local skynet = require "skynet"
local socket = require "skynet.socket"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"

local WATCHDOG
local host
local proto_pack
local client_fd

local CMD = {}
local REQUEST = {}

-- upload buffering per player: upload_buffer[player_id][art_id] = { name=, author=, total_chunks=, received=, chunks = {} }
local upload_buffer = {}

-- 保存当前玩家在这支笔中的角色 (1 or 2)
local player_id

-- 辅助函数
local function broadcast(pack, fd)
	local package = string.pack(">s2", pack)
	skynet.send(WATCHDOG, "lua", "broadcast", package, fd)
end

local function send_request(pack, fd)
	local package = string.pack(">s2", pack)
	socket.write(fd, package)
end

--------------------------------------------------------
-- 处理玩家输入
--------------------------------------------------------
function REQUEST:player_input()
	-- Forward input to PUBLIC_INFO (authoritative game/room state)
	-- Use server-side assigned player_id to prevent client spoofing
	local safe_args = {
		player_id = player_id,
		x = self.x,
		y = self.y,
		want_toggle = self.space,
	}

	-- call PUBLIC_INFO to merge state and return the event to broadcast
	local ok, res, detail = pcall(skynet.call, "PUBLIC_INFO", "lua", "player_input", safe_args)
	if not ok then
		skynet.error("agent: PUBLIC_INFO.player_input call failed:", res)
		return
	end
	-- res is boolean success, detail is event table when success
	if not res then
		skynet.error("agent: PUBLIC_INFO.player_input returned false")
		return
	end
	local evt = detail
	if not evt then
		return
	end
	if evt.event == "update_pencil" and evt.payload then
		local pack = proto_pack("update_pencil", evt.payload)
		broadcast(pack, nil)
	elseif evt.event == "clear_canvas" then
		local pack = proto_pack("clear_canvas", {})
		broadcast(pack, nil)
	end
end

--------------------------------------------------------
-- 处理玩家的颜色变更请求
--------------------------------------------------------
function REQUEST:color_change_req()
	-- broadcast color change to all clients (include player_id)
	local pack = proto_pack("color_change_broadcast", { color_id = self.color_id, player_id = player_id })
	broadcast(pack, nil)
end

--------------------------------------------------------
-- 处理分片上传的 artwork
-- 请求字段: id, name, author, chunk_index, total_chunks, data
--------------------------------------------------------
function REQUEST:art_upload_chunk()
	local id = self.id
	local name = self.name
	local author = self.author
	local idx = self.chunk_index or 1
	local total = self.total_chunks or 1
	local data = self.data or ""

	upload_buffer[player_id] = upload_buffer[player_id] or {}
	local u = upload_buffer[player_id][id]
	if not u then
		u = { name = name, author = author, total = total, received = 0, chunks = {} }
		upload_buffer[player_id][id] = u
	end
	if not u.chunks[idx] then
		u.chunks[idx] = data
		u.received = u.received + 1
	end

	skynet.error(string.format("agent: received artwork chunk %d/%d for id=%s", idx, total, id))
	-- if completed, assemble and store
	if u.received >= u.total then
		local parts = {}
		for i = 1, u.total do
			table.insert(parts, u.chunks[i] or "")
		end
		local bytes = table.concat(parts)
		-- store via ALBUM service
		local ok, res = pcall(skynet.call, "ALBUM", "lua", "store_artwork", id, u.name, u.author, bytes, os.time())
		if not ok or not res then
			skynet.error("agent: failed to store artwork", tostring(res))
			-- send ack failure to uploader
			local pack = proto_pack("art_upload_ack", { id = id, success = false, message = tostring(res) })
			send_request(pack, client_fd)
		else
			skynet.error("agent: artwork stored successfully, id=", id)
			-- cleanup
			upload_buffer[player_id][id] = nil
			-- send success ack to uploader
			local pack = proto_pack("art_upload_ack", { id = id, success = true, message = "stored" })
			send_request(pack, client_fd)
		end
	else
		-- optionally send intermediate ack for this chunk
		local pack = proto_pack("art_upload_ack", { id = id, success = true, message = string.format("received_chunk_%d", idx) })
		send_request(pack, client_fd)
	end
end

--------------------------------------------------------
-- handle art upload start: server assigns id and prepares buffer
--------------------------------------------------------
function REQUEST:art_upload_start()
	local name = self.name
	local author = self.author
	local total = self.total_chunks or 1
	local client_token = self.client_token
	-- generate server-side id
	local id = tostring(os.time()) .. "_" .. tostring(player_id) .. "_" .. tostring(math.random(100000,999999))
	upload_buffer[player_id] = upload_buffer[player_id] or {}
	upload_buffer[player_id][id] = { name = name, author = author, total = total, received = 0, chunks = {} }
	-- send ack with assigned id and echo client_token
	local pack = proto_pack("art_upload_ack", { id = id, success = true, message = "start", client_token = client_token })
	send_request(pack, client_fd)
end

--------------------------------------------------------
-- handle get_artwork_by_index request
--------------------------------------------------------
function REQUEST:get_artwork_by_index()
	local idx = self.index or 1
	-- ask ALBUM for artwork by index
	-- skynet.call to ALBUM returns (success_boolean, result_table) on success,
	-- so pcall(...) will return ok, success_boolean, result_table. Capture all.
	local ok, success, res = pcall(skynet.call, "ALBUM", "lua", "get_artwork_by_index", idx)
	if not ok or not success then
		-- notify client that requested index was not found
		local pack = proto_pack("artwork_not_found", { id = tostring(idx), reason = "not found" })
		send_request(pack, client_fd)
		return
	end
	local id = res.id
	-- reuse get_artwork flow to stream
	local ok2, success2, ret = pcall(skynet.call, "ALBUM", "lua", "get_artwork", id)
	if not ok2 or not success2 then
		-- artwork id resolved but fetching failed: inform client
		local pack = proto_pack("artwork_not_found", { id = id, reason = "not found" })
		send_request(pack, client_fd)
		return
	end
	local data = ret.data or ""
	local name = ret.name or ""
	local author = ret.author or ""
	local t = ret.time or 0
	local chunk_size = 60000
	local len = #data
	local total_chunks = math.ceil(len / chunk_size)
	if total_chunks < 1 then total_chunks = 1 end
	for i = 1, total_chunks do
		local s = (i - 1) * chunk_size + 1
		local e = math.min(i * chunk_size, len)
		local part = ""
		if len > 0 then
			part = string.sub(data, s, e)
		end
		local pack = proto_pack("artwork_chunk", { id = id, name = name, author = author, time = t, chunk_index = i, total_chunks = total_chunks, data = part })
		send_request(pack, client_fd)
	end
end

--------------------------------------------------------
-- 处理客户端查询 artwork
-- 请求字段: id
--------------------------------------------------------
function REQUEST:get_artwork()
	skynet.error("[[NOT IMPLEMENTED!!! ]]agent: get_artwork request for id=", tostring(self.id))
end

--------------------------------------------------------
-- 处理玩家的清除请求
--------------------------------------------------------
function REQUEST:clear_request()
	-- broadcast clear to all clients
	local pack = proto_pack("clear_canvas", {})
	broadcast(pack, nil)
end

--------------------------------------------------------
-- 请求调度
--------------------------------------------------------
local function request(name, args)
	local f = assert(REQUEST[name])
	return f(args)
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function(msg, sz)
		return host:dispatch(msg, sz)
	end,
	dispatch = function(fd, _, type, ...)
		skynet.ignoreret()
		if type == "REQUEST" then
			local ok, err = pcall(request, ...)
			if not ok then
				skynet.error(err)
			end
		end
	end
}

--------------------------------------------------------
-- 启动
--------------------------------------------------------
function CMD.start(conf)
	client_fd = conf.client
	WATCHDOG = conf.watchdog
	player_id = conf.player_id or 1 -- 由watchdog分配
	host = sprotoloader.load(1):host "package"
	proto_pack = host:attach(sprotoloader.load(2))
	skynet.call(conf.gate, "lua", "forward", client_fd)
	-- send connect_ok with assigned player_id
	send_request(proto_pack("connect_ok", { player_id = player_id }), client_fd)
end

function CMD.disconnect(fd)
	skynet.exit()
end


skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		local f = CMD[command]
		if f then
			-- call the command and return its results
			local ok, res = pcall(f, ...)
			if ok then
				skynet.ret(skynet.pack(res))
			else
				skynet.error("agent CMD error:", res)
				skynet.ret(skynet.pack(nil))
			end
		else
			-- unknown command: log and return false
			skynet.error("agent: unknown command ", tostring(command))
			skynet.ret(skynet.pack(nil))
		end
	end)
end)

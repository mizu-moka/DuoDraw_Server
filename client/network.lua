import "UnityEngine"

-- Coding Format : UTF-8

local socket = require "lsocket"
local proto = require "proto"
local sproto = require "sproto"

local host = sproto.new(proto.s2c):host "package"
local proto_pack = host:attach(sproto.new(proto.c2s))
-- local server_addr = {"127.0.0.1", 8888}
local server_addr = {"43.139.160.82", 8888}
local fd = nil

local class = {}

-- 注册C#层接口
local globalsObj = GameObject.Find("GlobalsObj")
local globals = globalsObj:GetComponent("Globals")
local network_for_lua = globals.NetworkForLua
local current_player_id = -1

-- 用于接收和组装画作数据
local recv_artwork = {}
local pending_uploads = {}
local pending_b64 = {}

-- 发送数据包
local function send_package(fd, pack)
	local len = #pack
	local byte1 = math.floor(len/256)
	local byte2 = len%256
	local char1 = string.char(byte1)
	local char2 = string.char(byte2)
	-- Jim, 202110041545. try for iOS build.
	local package = char1..char2..pack
	fd:send(package)
end
-- Jim, fix #202209291304. end

-- 解压数据包
local function unpack_package(text)
	local size = #text
	if size < 2 then
		return nil, text
	end
	local s = text:byte(1) * 256 + text:byte(2)
	if size < s + 2 then
		return nil, text
	end

	return text:sub(3, 2 + s), text:sub(3 + s)
end

-- 接收和处理数据包
local function recv_package(last)
	local result
	result, last = unpack_package(last)
	if result then
		return result, last
	end
	local r = fd:recv()
	if not r then
		return nil, last
	end
	if r == "" then
		error "Server closed"
	end
	return unpack_package(last .. r)
end

local session = 0
local last = ""

-- 发送请求
local function send_request(name, args)
	session = session + 1
	local str = proto_pack(name, args, session)
	send_package(fd, str)
end

-- lightweight base64 decode/encode (for client<->lua bridge)
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64_decode(data)
	data = string.gsub(data, "[^"..b.."=]", "")
	return (data:gsub('.', function(x)
		if (x == '=') then return '' end
		local r,f='',(b:find(x)-1)
		for i=6,1,-1 do r = r .. (f%2^i - f%2^(i-1) > 0 and '1' or '0') end
		return r
	end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
		if (#x ~= 8) then return '' end
		local c = 0
		for i = 1,8 do c = c + (x:sub(i,i) == '1' and 2^(8-i) or 0) end
		return string.char(c)
	end))
end

local function base64_encode(data)
	return ((data:gsub('.', function(x)
		local r = ''
		local c = string.byte(x)
		for i = 8,1,-1 do r = r .. (c%2^i - c%2^(i-1) > 0 and '1' or '0') end
		return r
	end) .. '0000'):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
		if (#x ~= 8) then return '' end
		local c = 0
		for i = 1,8 do c = c + (x:sub(i,i) == '1' and 2^(8-i) or 0) end
		return string.char(c)
	end):gsub('.', function(x)
		local v = string.byte(x)
		return b:sub(math.floor(v/4)+1, math.floor(v/4)+1) .. b:sub((v%4)*16+1, (v%4)*16+1)
	end) .. ({ '', '==', '=' })[#data%3+1])
end

-- 消息响应方法集
-- 当收到包后，会根据包的proto格式名，从server_rpc中找到对应的响应方法来执行
local server_rpc = {
	connect_ok = function(args)
		print("[network] connect_ok, assigned player_id:", args.player_id)
		if network_for_lua and network_for_lua.RecvConnectOK then
			network_for_lua:RecvConnectOK(args.player_id)
		end
		return true
	end,
	update_pencil = function(args)
		print(string.format("[network] update_pencil x=%.2f y=%.2f drawing=%s toggle1=%s toggle2=%s", args.x or 0, args.y or 0, tostring(args.drawing), tostring(args.toggle1), tostring(args.toggle2)))
		if network_for_lua and network_for_lua.UpdatePencil then
			pcall(function() network_for_lua:UpdatePencil(args.x, args.y, args.drawing, args.toggle1, args.toggle2) end)
		end
		return true
	end,
	start_game = function(args)
		print("[network] start_game, players:", args.players and table.concat(args.players, ",") or "nil")
		if network_for_lua and network_for_lua.StartGame then
			pcall(function() network_for_lua:StartGame(args.players) end)
		end
		return true
	end,
	color_change_broadcast = function(args)
		print(string.format("[network] color_change_broadcast color_id=%s player_id=%s", tostring(args.color_id), tostring(args.player_id)))
		if network_for_lua and network_for_lua.ColorChanged then
			pcall(function() network_for_lua:ColorChanged(args.player_id, args.color_id) end)
		end
		return true
	end,

	-- send chunkcs to server after receiving art_upload_ack with client_token
	art_upload_ack = function(args)
		print(string.format("[network] art_upload_ack id=%s success=%s msg=%s client_token=%s", tostring(args.id), tostring(args.success), tostring(args.message), tostring(args.client_token)))
		-- forward ack to C# listener (include client_token if present)
		if network_for_lua and network_for_lua.UploadAck then
			pcall(function() network_for_lua:UploadAck(args.id, args.success, args.message, args.client_token) end)
		end
		-- if this ack contains a client_token, it's the start ack: begin sending chunks
		if args.client_token and pending_uploads[args.client_token] then
			local p = pending_uploads[args.client_token]
			local id = args.id
			local bytes = p.bytes
			local chunk_size = p.chunk_size
			local total = p.total
			for i=1,total do
				local s = (i-1)*chunk_size + 1
				local e = math.min(i*chunk_size, #bytes)
				local part = ""
				if #bytes > 0 then part = string.sub(bytes, s, e) end
				send_request("art_upload_chunk", { id = id, name = p.name, author = p.author, chunk_index = i, total_chunks = total, data = part })
			end
			-- remove pending
			pending_uploads[args.client_token] = nil
		end
		return true
	end,

	-- receive requested artwork chunks from server and assemble
	artwork_chunk = function(args)
		-- assemble on client side
		local id = args.id
		recv_artwork[id] = recv_artwork[id] or { name = args.name, author = args.author, time = args.time, total = args.total_chunks, chunks = {}, received = 0 }
		local entry = recv_artwork[id]
		if not entry.chunks[args.chunk_index] then
			entry.chunks[args.chunk_index] = args.data
			entry.received = entry.received + 1
		end
		if entry.received >= entry.total then
			local parts = {}
			for i=1,entry.total do table.insert(parts, entry.chunks[i] or "") end
			local bytes = table.concat(parts)

			-- send to C# as base64 to avoid null-byte marshalling issues
			-- local b64 = base64_encode(bytes)
			-- print("[Lua] artwork_chunk b64 length:", #b64)
			-- print("[Lua] artwork_chunk b64 head:", string.sub(b64, 1, 100))
			if network_for_lua and network_for_lua.ArtworkReceived then
				pcall(function() network_for_lua:ArtworkReceived(id, entry.name, entry.author, bytes, entry.time) end)
			end
			recv_artwork[id] = nil
		end
		return true
	end,

	-- requested artwork was not found
	artwork_not_found = function(args)
		print(string.format("[network] artwork_not_found id=%s reason=%s", tostring(args.id), tostring(args.reason)))
		if network_for_lua and network_for_lua.ArtworkNotFound then
			pcall(function() network_for_lua:ArtworkNotFound(args.id or "", args.reason or "not found") end)
		end
		return true
	end,

	clear_canvas = function(args)
		print("[network] clear_canvas received")
		if network_for_lua and network_for_lua.ClearCanvas then
			pcall(function() network_for_lua:ClearCanvas() end)
		end
		return true
	end,
	game_pause = function(args)
		print("[network] game_pause, reason:", args.reason)
		if network_for_lua and network_for_lua.OnGamePause then
			pcall(function() network_for_lua:OnGamePause(args.reason) end)
		end
		return true
	end,
}

-- 处理协议操作，从server_rpc中选择相应的方法来处理
local function handle_action(requestName, args)
	if server_rpc[requestName] ~= nil then
		return server_rpc[requestName](args)
	end
	return true
end

-- 处理数据包
local function handle_package(t, ...)
	if t == "REQUEST" then
		return handle_action(...)
	else
		--assert(t == "RESPONSE")
		return handle_action(...)
	end
end

-- 发送数据包
local function dispatch_package()
	while true do
		local v
		v, last = recv_package(last)
		if not v then
			break
		end

		local result = handle_package(host:dispatch(v))
		if not result then
			return
		end
	end
end

function class:update(cmd)
	if fd == nil then
		return
	end
	dispatch_package()
	if cmd then

	end
end

------------------------------------
-----------发送调用区---------------
function class:connect_to_server()
	fd = assert(socket.connect(server_addr[1], server_addr[2]))
end

-- Send player input to server (matches server proto 'player_input')
function class:send_player_input(player_id, x, y, space)
	send_request("player_input", { player_id = player_id, x = x or 0, y = y or 0, space = (not not space) })
end

-- Send a clear request to the server (server will broadcast clear_canvas to all clients)
function class:send_clear_request(player_id)
	send_request("clear_request", { player_id = player_id })
end

-- Send color change request to server
function class:send_color_change_request(player_id, color_id)
	send_request("color_change_req", { player_id = player_id, color_id = color_id })
end

-- send artwork from lua (binary string) in chunks
function class:send_artwork(player_id, id, name, author, bytes)
	print("Use send_artwork_base64 instead of send_artwork!!!!!!!!")
end

-- receive artwork from C# (base64), decode and forward to server as chunks
function class:send_artwork_base64(player_id, name, author, b64)
	-- keep existing flow for callers that supply base64, but don't print large debug
	local bytes = base64_decode(b64)
	-- New flow: request server-assigned id, then send chunks when server replies with art_upload_ack containing client_token
	local chunk_size = 60000
	local len = #bytes
	local total = math.ceil(len / chunk_size)
	if total < 1 then total = 1 end
	-- generate client_token
	local client_token = tostring(os.time()) .. "_" .. tostring(math.random(100000,999999))
	pending_uploads[client_token] = { bytes = bytes, total = total, name = name, author = author, player_id = player_id, chunk_size = chunk_size }
	-- send start request, server will respond with art_upload_ack (including id and client_token)
	send_request("art_upload_start", { player_id = player_id, name = name, author = author, total_chunks = total, client_token = client_token })
	return true
end

-- -- receive base64 in chunks from C# to avoid passing a huge single string through SLua
-- function class:receive_artwork_b64_chunk(client_token, part, is_last, player_id, name, author)
-- 	pending_b64[client_token] = (pending_b64[client_token] or "") .. (part or "")
-- 	if is_last then
-- 		local b64 = pending_b64[client_token]
-- 		pending_b64[client_token] = nil
-- 		-- decode and reuse existing flow
-- 		local bytes = base64_decode(b64)
-- 		local chunk_size = 60000
-- 		local len = #bytes
-- 		local total = math.ceil(len / chunk_size)
-- 		if total < 1 then total = 1 end
-- 		pending_uploads[client_token] = { bytes = bytes, total = total, name = name, author = author, player_id = player_id, chunk_size = chunk_size }
-- 		send_request("art_upload_start", { player_id = player_id, name = name, author = author, total_chunks = total, client_token = client_token })
-- 	end
-- 	return true
-- end


-- -- read a temporary file written by C# and upload its bytes (avoids marshalling huge base64 strings through SLua)
-- function class:send_artwork_from_path(player_id, name, author, path)
-- 	local f, err = io.open(path, "rb")
-- 	if not f then
-- 		error("send_artwork_from_path: open failed: " .. tostring(err))
-- 	end
-- 	local bytes = f:read("*a")
-- 	f:close()
-- 	-- try to remove the file (best-effort)
-- 	pcall(function() os.remove(path) end)
-- 	-- reuse the same upload flow using the raw bytes we just read
-- 	local chunk_size = 60000
-- 	local len = #bytes
-- 	local total = math.ceil(len / chunk_size)
-- 	if total < 1 then total = 1 end
-- 	local client_token = tostring(os.time()) .. "_" .. tostring(math.random(100000,999999))
-- 	pending_uploads[client_token] = { bytes = bytes, total = total, name = name, author = author, player_id = player_id, chunk_size = chunk_size }
-- 	send_request("art_upload_start", { player_id = player_id, name = name, author = author, total_chunks = total, client_token = client_token })
-- 	return true
-- end

-- C# driven upload API: start from C# and then push per-chunk via upload_chunk_from_cs
function class:upload_start_from_cs(player_id, name, author, total_chunks, client_token)
    send_request("art_upload_start", { player_id = player_id, name = name, author = author, total_chunks = total_chunks, client_token = client_token })
    return true
end

function class:upload_chunk_from_cs(id, name, author, chunk_index, total_chunks, b64_part)
	-- decode the base64 part (C# sends base64 for safe string marshalling) and forward as binary chunk
	-- local bytes = base64_decode(b64_part or "")
	send_request("art_upload_chunk", { id = id, name = name, author = author, chunk_index = chunk_index, total_chunks = total_chunks, data = b64_part })
	return true
end

-- Request the i-th artwork by chronological order (1-based)
function class:request_artwork_by_index(i)
	send_request("get_artwork_by_index", { index = i })
end

-------------------------------------

function main()
	return class
end

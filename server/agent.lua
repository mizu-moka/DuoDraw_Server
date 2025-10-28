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

-- 保存当前玩家在这支笔中的角色 (1 or 2)
local player_id

-- 服务端全局状态
local pencil_state = {
    x = 0,
    y = 0,
    space1 = false,
    space2 = false,
    drawing = false
}

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
		clear = self.clear,
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

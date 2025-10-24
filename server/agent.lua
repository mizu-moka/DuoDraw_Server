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
	if self.player_id == 1 then
		pencil_state.x = pencil_state.x + self.x
		-- check, if self.y ~= 0 then print error("player 1 should not control y") end
		if self.space then
			pencil_state.space1 = not pencil_state.space1
		end
	elseif self.player_id == 2 then
		pencil_state.y = pencil_state.y + self.y
		if self.space then
			pencil_state.space2 = not pencil_state.space2
		end
	end

	-- 提笔判定：两人都按下时切换drawing状态
	if pencil_state.space1 and pencil_state.space2 then
		pencil_state.drawing = not pencil_state.drawing
		pencil_state.space1 = false
		pencil_state.space2 = false
	end

	-- 清空画布
	if self.clear then
		local pack = proto_pack("clear_canvas", {})
		broadcast(pack, nil)
		return
	end

	-- 广播当前铅笔状态
	local pack = proto_pack("update_pencil", {
		x = pencil_state.x,
		y = pencil_state.y,
		drawing = pencil_state.drawing
	})
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

-- forward a packed message (sproto pack) to this agent's client
function CMD.forward(pack)
	if client_fd then
		send_request(pack, client_fd)
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
end)

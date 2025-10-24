-- Coding Format : UTF-8

-- 「WatchDog.lua 脚本介绍」
-- WatchDog，正如其字面意思，扮演了“看门狗”的角色，负责蹲在大门口，看有没有新玩家过来
-- 玩家通过服务器IP地址+端口号，来接入服务器，而WatchDog就在服务器里一直盯着这个端口看，如果从端口收到请求，就进行处理


local skynet = require "skynet"
local socket = require "skynet.socket"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"

local host
local proto_pack
local CMD = {}
local SOCKET = {}
local gate
local agent = {}

-- player allocation is now handled by PUBLIC_INFO service


-- SOCKET.open是系统调用，在新客户端申请接入时自动调用
function SOCKET.open(fd, addr)
	skynet.error("New client from : " .. addr)
	
	-- ask PUBLIC_INFO to allocate a player id for this fd
	local pid = skynet.call("PUBLIC_INFO", "lua", "allocate_player", fd)
	if not pid then
		skynet.error("Room full, reject connection from " .. addr)
		skynet.call(gate, "lua", "kick", fd)
		return
	end

	-- 为新玩家分配一个agent (agent will be started with assigned player_id)
	agent[fd] = skynet.newservice("agent")
	-- 启动agent并传入分配的 player_id
	skynet.call(agent[fd], "lua", "start", { gate = gate, client = fd, watchdog = skynet.self(), player_id = pid })

	-- notify PUBLIC_INFO about the agent service so it can forward messages
	skynet.call("PUBLIC_INFO", "lua", "attach_agent", pid, agent[fd])
end

-- 关闭agent
local function close_agent(fd)
	local a = agent[fd]
	skynet.error(">>>>>close_agent>>>>" .. fd)

	-- tell PUBLIC_INFO to unregister this fd and let it notify remaining
	skynet.call("PUBLIC_INFO", "lua", "unregister_by_fd", fd)

	agent[fd] = nil
	if a then
		skynet.call(gate, "lua", "kick", fd)
		skynet.send(a, "lua", "disconnect", fd)
	end
end

-- 断开连接
function SOCKET.close(fd)
	print("socket close", fd)
	close_agent(fd)
end

function SOCKET.error(fd, msg)
	print("socket error", fd, msg)
	close_agent(fd)
end

function SOCKET.warning(fd, size)
	-- size K bytes havn't send out in fd
	print("socket warning", fd, size)
end

function CMD.start(conf)
	skynet.call(gate, "lua", "open", conf)
end

function CMD.close(fd)
	close_agent(fd)
end

-- 消息广播函数
-- package : 要发送的数据包
-- fd      : 要屏蔽的客户端
-- 如果输入fd，则fd会被广播过滤。如果fd==nil, 就是全员广播
function CMD.broadcast(package, fd)
	for k, v in pairs(agent) do
		if k and k ~= fd then
			--skynet.error("broadcast:"..k)
			socket.write(k, package)
		end
	end
end

function CMD.broadcastall(package)
	for k, v in pairs(agent) do
		socket.write(k, package)
	end
end

function CMD.login(id)
	print("login:" .. id)
	action_cache[id] = {}
end

function CMD.logout(id)
	if action_cache[id] == nil then
		return
	end

	if frame_actions[id] == nil then
		return
	end

	action_cache[id]  = nil
	frame_actions[id] = nil
end

skynet.start(function()
	-- 处理外部调用请求
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			f(...)
			-- socket api don't need return
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	-- 启动端口监视器
	gate = skynet.newservice("gate")
end)

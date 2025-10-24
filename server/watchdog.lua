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

local players = {}       -- map player_id -> fd
local fd2pid = {}       -- map fd -> player_id
local max_players = 2


-- SOCKET.open是系统调用，在新客户端申请接入时自动调用
function SOCKET.open(fd, addr)
	skynet.error("New client from : " .. addr)

	-- enforce max players per room (simple single-room implementation for now)
	local current_count = 0
	for _, v in pairs(players) do
		current_count = current_count + 1
	end
	if current_count >= max_players then
		skynet.error("Room full, reject connection from " .. addr)
		-- politely close the connection
		skynet.call(gate, "lua", "kick", fd)
		return
	end

	-- 为新玩家分配一个agent
	agent[fd] = skynet.newservice("agent")

	-- choose player_id (first free in 1..max_players)
	local pid
	for i = 1, max_players do
		if players[i] == nil then
			pid = i
			break
		end
	end
	if not pid then
		-- defensive fallback
		skynet.error("Failed to allocate player_id for fd=" .. fd)
		skynet.call(gate, "lua", "kick", fd)
		return
	end

	-- 启动新玩家的agent，传入分配的 player_id
	skynet.call(agent[fd], "lua", "start", { gate = gate, client = fd, watchdog = skynet.self(), player_id = pid })

	-- record mappings
	players[pid] = fd
	fd2pid[fd] = pid

	-- 如果现在刚好有两个玩家，广播 start_game
	current_count = 0
	local plist = {}
	for i = 1, max_players do
		if players[i] then
			current_count = current_count + 1
			table.insert(plist, i)
		end
	end
	if current_count == max_players then
		local pack = proto_pack("start_game", { players = plist })
		CMD.broadcastall(pack)
	end
end

-- 关闭agent
local function close_agent(fd)
	local a = agent[fd]
	skynet.error(">>>>>close_agent>>>>" .. fd)
	
	-- cleanup mappings
	local pid = fd2pid[fd]
	fd2pid[fd] = nil
	if pid then
		players[pid] = nil
	end

	agent[fd] = nil
	if a then
		skynet.call(gate, "lua", "kick", fd)
		skynet.send(a, "lua", "disconnect", fd)
	end

	-- if there's still one player left, notify them of pause
	local remaining_fd = nil
	for i = 1, max_players do
		if players[i] then
			remaining_fd = players[i]
			break
		end
	end
	if remaining_fd then
		local pack = proto_pack("game_pause", { reason = "other_disconnected" })
		local package = string.pack(">s2", pack)
		socket.write(remaining_fd, package)
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

-- Coding Format : UTF-8

-- 「agent.lua 脚本介绍」
-- 玩家需要服务，agent就是服务员，一个玩家对应一个agent
-- agent负责处理自己的玩家发来的消息，可以转发或广播消息，也可以修改数据库中的信息

-- 请注意，在一些特定场合，skynet会fork（复制）一个新的进程，来完成一些特殊操作（如定时）
-- 而不同进程拥有独立的的命名空间，一个进程中的local变量只能被这个进程所用，无法被其他进程所用
-- 由于agent脚本中包含多处fork，请尽量不要在agent中维护全局信息————如在线玩家列表等
-- 因为如果你在fork之后，修改了某个变量，这个修改将只对后一个进程生效，对原有的进程不生效，这可能造成难以排查的逻辑错误
-- 如果希望维护全局信息，建议在public_info.lua中编写，然后再在此脚本中调用

local skynet = require "skynet"
local socket = require "skynet.socket"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"

local WATCHDOG
local host
local proto_pack
local client_fd
local player_id

local CMD = {}
local REQUEST = {}
local clientReady = false


local function broadcast_request(pack, fd)
	local package = string.pack(">s2", pack)
	skynet.send(WATCHDOG, "lua", "broadcast", package, fd)
end

local function broadcastall_request(pack)
	local package = string.pack(">s2", pack)
	skynet.send(WATCHDOG, "lua", "broadcastall", package)
end

local function send_request(pack, fd)
	local package = string.pack(">s2", pack)
	socket.write(fd, package)
end

function REQUEST:dead()
	print("player dead", self.id)
	skynet.call("PUBLIC_INFO", "lua", "dead", self.id)
end

-- 处理玩家的登录请求
function REQUEST:login()

	-- 与后台数据库交互，获取玩家ID。如果是从未登录过的玩家，将会自动分配一个新的ID
	player_id = skynet.call("PUBLIC_INFO", "lua", "login", self.name, self.password, self.color)

	-- 向新玩家告知他被分配到的ID
	send_request(proto_pack("login", { id = player_id, name = self.name, color = self.color }), client_fd)
	skynet.error(">>>>> db return:" .. player_id)

	-- 如果 id == -1，说明密码错误或者已经在线，无法登陆
	if player_id < 0 then
		skynet.send(WATCHDOG, "lua", "close", client_fd)
		return
	end

	-- 让 新玩家 加载场景，并把自己加入场景
	local player = skynet.call("PUBLIC_INFO", "lua", "get_player", player_id)
	send_request(proto_pack("enter_scene", player), client_fd)
	skynet.send(WATCHDOG, "lua", "login", player_id)

	-- 由于加载场景可能耗费较长时间，为了防止玩家加载不完场景，这里需要先等待一段时间再发送后续消息
	-- skynet提供了休眠函数：skynet.sleep(time)。调用后，当前进程将休眠
	-- 但是，所有玩家是共用同一个agent的，如果这个agent休眠了，那其他玩家怎么办呢？
	-- 我们可以复制一个新的agent，只让新的agent休眠，让原来的agent继续服务其他玩家
	-- skynet提供了linux格式的fork函数，可以用来“复制”进程

	skynet.fork(function()
		-- fork：复制当前进程，然后让新进程执行括号里的代码，而旧进程将跳过这段代码
		-- 这里fork的括号里写的是一个function，所以就会执行这个function

		-- 等待一段时间（1s）
		skynet.sleep(100)

		-- 让 其他玩家 把 新玩家 加入场景
		local player = skynet.call("PUBLIC_INFO", "lua", "get_player", player_id)
		broadcast_request(proto_pack("enter_scene", player), client_fd)

		-- 让 新玩家 把 其他玩家 加入场景
		local players = skynet.call("PUBLIC_INFO", "lua", "get_players")
		for id, player in pairs(players) do
			if id ~= player_id then
				send_request(proto_pack("enter_scene", player), client_fd)
			end
		end
		-- skynet.send(WATCHDOG, "lua", "sync_actions", client_fd)
		broadcast_request(proto_pack("sync_info", { info = "All" }), nil)
	end)
end

function REQUEST:snapshoot()
	broadcast_request(proto_pack("snapshootBC", { id = self.id, frame = self.frame, info = self.info }), nil)
end

function REQUEST:action()
	broadcast_request(proto_pack("actionBC",
		{ id = self.id, frame = self.frame, input = self.input, facing = self.facing }), nil)
end

function REQUEST:add_coin_req()
	local coin = skynet.call("PUBLIC_INFO", "lua", "add_coin", self.posx, self.posy, self.posz, self.ownerPlayerId)
	broadcastall_request(proto_pack("add_coin_bc", coin))
end

function REQUEST:remove_coin_req()
	local success = skynet.call("PUBLIC_INFO", "lua", "remove_coin", self.id, self.pickerPlayerId)
	if success then
		broadcastall_request(proto_pack("remove_coin_bc", { id = self.id, pickerPlayerId = self.pickerPlayerId }))
	end
end


local function request(name, args, response)
	local f = assert(REQUEST[name])
	local r = f(args)
	-- if response then
	-- skynet.error(">>>>>>>>>>> response:"..name)
	-- return response(r)
	-- end
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function(msg, sz)
		return host:dispatch(msg, sz)
	end,
	dispatch = function(fd, _, type, ...)
		--assert(fd == client_fd)	-- You can use fd to reply message
		skynet.ignoreret() -- session is fd, don't call skynet.ret
		--skynet.trace()
		if type == "REQUEST" then
			args = ...

			local ok, result = pcall(request, ...)
			if ok then
				if result then
					send_request(result, fd)
				end
			else
				skynet.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "This example doesn't support request client"
		end
	end
}

function CMD.start(conf)
	local fd = conf.client
	local gate = conf.gate
	WATCHDOG = conf.watchdog
	client_fd = fd

	host = sprotoloader.load(1):host "package"
	proto_pack = host:attach(sprotoloader.load(2))
	skynet.call(gate, "lua", "forward", fd)
	print("new connect, fd is ------: ", fd)

	-- 发送连接成功包给客户端
	send_request(proto_pack("connect_ok"), client_fd)

end

function CMD.disconnect(fd)
	skynet.send(WATCHDOG, "lua", "logout", player_id)
	skynet.send("PUBLIC_INFO", "lua", "logout", player_id)
	local pack = proto_pack("logout", { id = player_id })
	broadcast_request(pack, fd)
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(_, _, command, ...)
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
end)

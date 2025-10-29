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

-- 消息响应方法集
-- 当收到包后，会根据包的proto格式名，从server_rpc中找到对应的响应方法来执行
local server_rpc = {
	-- enter_scene = function(args)
	-- 	if current_player_id == args["id"] then
	-- 		globals:LoadScene(args["scene"])
	-- 	end
	-- 	-- 多少毫秒后开始，每隔多少毫秒执行一次，执行的方法. 返回true表示持续回调，返回false表示执行一次
	-- 	LuaTimer.Add(100, 10, function()
	-- 		if globals:IsSceneLoaded(args["scene"]) then
	-- 			network_for_lua:CreatePlayerResponse(args["id"], args["name"], args["color"], args["pos"][1], args["pos"][2], args["pos"][3])
	-- 			return false
	-- 		end
	-- 		return true
	-- 	end)
	-- end,
	-- actionBC = function(args)
	-- 	network_for_lua:ActionResponse(args["id"], args["frame"], args["input"][1], args["input"][2], args["input"][3],
	-- 		args["input"][4], args["facing"][1], args["facing"][2])
	-- 	return true
	-- end,
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
		print(string.format("[network] color_change_broadcast color_id=%s", tostring(args.color_id)))
		if network_for_lua and network_for_lua.ColorChanged then
			pcall(function() network_for_lua:ColorChanged(args.color_id) end)
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

-------------------------------------

function main()
	return class
end

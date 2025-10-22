local skynet = require "skynet"
require "skynet.manager" -- import skynet.register
local playerName = {}

local command = {}

local players = {}
local name2id = {}

local max_actor_id = 10000

local coins = {}
local max_coin_id = 20000

--------------------------------------------------------------------------------
--以下是公共信息服逻辑（Public info server）
--------------------------------------------------------------------------------
-- 处理玩家的登录信息
function command.login(player_name, player_password, player_color)
	local player_id = name2id[player_name]

	if player_id then
		if players[player_id].online then
			return -1 --用户已经登陆
		elseif players[player_id].password ~= player_password then
			return -2 --密码错误
		end
	end

	-- 如果是从未登录过的新用户
	if player_id == nil then
		--产生一个新ID
		player_id = max_actor_id
		max_actor_id = max_actor_id + 1
		name2id[player_name] = player_id
		print(">>>>>>>>>>>>>>")
		print(player_id, max_actor_id)

		-- 构造一个player，存进后台数据库
		local player = {
			id       = player_id,
			name     = player_name,
			password = player_password,
			color    = player_color,
			scene    = 0,
			online   = true,
			pos      = { math.random(-10, 10), 0, math.random(-5, 15) },
			facing   = { 1.0, 0.0 },
		}

		for i, v in pairs(player) do
			print(i, v)
		end
		players[player_id] = player
	else
		players[player_id].online = true
	end

	return player_id
end

-- 处理玩家的登出信息
function command.logout(player_id)
	if player_id == nil then
		return
	end
	skynet.error("logout:" .. player_id)

	-- 修改数据库中的玩家状态
	if players[player_id] then
		skynet.error("online:" .. tostring(players[player_id].online))
		players[player_id].online = false
		skynet.error("online:" .. tostring(players[player_id].online))
	end

	for id, player in pairs(players) do
		skynet.error("player[" .. id .. "] online:" .. tostring(player.online))
	end

end

function command.remove(id)
	local name = playerName[id]
	playerName[id] = nil
	return name
end

function command.update_player(id, key, value)
	if players[id] then
		players[id][key] = value
	end
end

function command.get_players()
	local online_players = {}
	for i, player in pairs(players) do
		skynet.error("player[" .. i .. "] online:" .. tostring(player.online))
		if players[i].online then
			online_players[i] = player
		end
	end
	return online_players
end

function command.get_player(id)
	if players[id] then
		return players[id]
	end
	return nil
end

--------------------------------------------------------------------------------
--以下是场景逻辑（Scene server）
--------------------------------------------------------------------------------

function command.add_coin(x, y, z, ownerId)
	local coin_id = max_coin_id
	max_coin_id = max_coin_id + 1
	print("add coin" .. coin_id)
	local coin = {
		id = coin_id,
		posx = x,
		posy = y,
		posz = z,
		ownerPlayerId = ownerId,
		status = true
	}
	coins[coin_id] = coin
	return coin
end

function command.remove_coin(coin_id, pickerId)

	if coins[coin_id] then
		if coins[coin_id].status then
			-- 默认自己不能摘取自己放置的
			if coins[coin_id].ownerPlayerId ~= pickerId then
				coins[coin_id].status = false
				coins[coin_id].pickerPlayerId = pickerId
				print("remove coin:" .. coin_id .. " by:" .. pickerId)
				return true
			end
		end
	end

	return false

end

----------------------------------------------------------------------
--服务启动
----------------------------------------------------------------------
skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		if cmd == "ping" then
			-- 相应ping
			assert(session == 0)
			local str = (...)
			if #str > 20 then
				str = str:sub(1, 20) .. "...(" .. #str .. ")"
			end
			skynet.error(string.format("%s ping %s", skynet.address(address), str))
			return
		end
		local f = command[cmd]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	print("=====", skynet.register, skynet.name)
	skynet.register "PUBLIC_INFO"
end)

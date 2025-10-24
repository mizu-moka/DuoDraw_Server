local skynet = require "skynet"
require "skynet.manager"
local socket = require "skynet.socket"
local sprotoloader = require "sprotoloader"

-- load proto packer for server->client messages
local host = sprotoloader.load(1):host "package"
local proto_pack = host:attach(sprotoloader.load(2))

-- PUBLIC_INFO: minimal player/room manager and message-forwarding service.
-- Current responsibilities:
--  - register/unregister connected fds and assign player_id (1..max_players)
--  - broadcast messages to players in the (single) room
--  - notify when room is full -> start_game, and when a player leaves -> game_pause
-- This file is intentionally small and contains comments/psuedocode showing how to expand
-- to multiple rooms and richer room lifecycle management.

local command = {}

-- Single-room player management (simple). Keys:
-- players: player_id -> fd
-- fd2pid: fd -> player_id
local players = {}
local fd2pid = {}
local max_players = 2

-- Note: To support multiple rooms, replace `players`/`fd2pid` with a `rooms` table:
-- rooms = {
--   [room_id] = { players = { [player_id] = fd }, fd2pid = { [fd] = player_id }, max_players = N, state = "waiting" }
-- }
-- Provide APIs:
--   create_room(owner, capacity) -> room_id
--   join_room(room_id, fd) -> player_id / error
--   leave_room(room_id, fd)
--   list_rooms()
-- Keep room lifecycle logic here (start_game when room full, pause on disconnect, cleanup on timeout).

-- Register a new connected fd and assign a player_id (1..max_players).
-- Returns player_id on success, or nil,reason on failure (e.g. room full).
function command.register(fd)
	-- count current players
	local count = 0
	for _, v in pairs(players) do count = count + 1 end
	if count >= max_players then
		return nil, "room_full"
	end
	-- find first free id
	local pid
	for i = 1, max_players do
		if players[i] == nil then
			pid = i
			break
		end
	end
	if not pid then
		return nil, "no_free_id"
	end
	players[pid] = fd
	fd2pid[fd] = pid

	-- if room is now full, broadcast start_game to all players in the room
	count = 0
	local plist = {}
	for i = 1, max_players do
		if players[i] then
			count = count + 1
			table.insert(plist, i)
		end
	end
	if count == max_players then
		local pack = proto_pack("start_game", { players = plist })
		local package = string.pack(">s2", pack)
		for _, fdv in pairs(players) do
			socket.write(fdv, package)
		end
	end

	return pid
end

-- Unregister a disconnected fd, clean mappings and notify remaining player (game_pause).
function command.unregister(fd)
	local pid = fd2pid[fd]
	fd2pid[fd] = nil
	if pid then players[pid] = nil end

	-- notify remaining player if any
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
	return pid
end

-- Broadcast helpers used by watchdog/agents. package must be packed already (sproto raw string).
function command.broadcast(package, exclude_fd)
	for _, fd in pairs(players) do
		if fd and fd ~= exclude_fd then
			socket.write(fd, package)
		end
	end
end

function command.broadcastall(package)
	for _, fd in pairs(players) do
		if fd then socket.write(fd, package) end
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(session, address, cmd, ...)
		local f = command[cmd]
		if f then
			skynet.ret(skynet.pack(f(...)))
		else
			error(string.format("Unknown command %s", tostring(cmd)))
		end
	end)
	skynet.register "PUBLIC_INFO"
end)

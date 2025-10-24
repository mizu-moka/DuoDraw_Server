local skynet = require "skynet"
require "skynet.manager"

-- PUBLIC_INFO: central hub for player registration and message forwarding.
-- Responsibilities implemented here (minimal single-room example):
-- 1) Allocate player slots (player_id) when a client connects.
-- 2) Attach an agent service to a player slot after agent is started.
-- 3) Forward/broadcast messages between agents using agent's broadcast/send_request.
-- 4) Notify remaining players when one disconnects (game_pause).

local command = {}

-- player bookkeeping (single-room)
local players = {}   -- players[pid] = { fd = fd, agent = service }
local fd2pid = {}    -- fd -> pid
local max_players = 2

-- allocate a free player_id for a joining fd; returns pid or nil if full
function command.allocate_player(fd)
    for i = 1, max_players do
        if players[i] == nil then
            players[i] = { fd = fd, agent = nil }
            fd2pid[fd] = i
            return i
        end
    end
    return nil
end

-- attach an agent service to a previously allocated pid
-- when both players are present and attached, broadcast start_game
function command.attach_agent(pid, agent_service)
    if not players[pid] then
		skynet.error("[public_info] attach_agent failed: no such player slot", pid)
        return false, "no such player slot"
    end
    players[pid].agent = agent_service

    -- if all slots filled with agents, broadcast start_game
    local ready = true
    local plist = {}
    for i = 1, max_players do
        if not players[i] or not players[i].agent then
			print("[public_info] attach_agent: not ready, missing player", i)
            ready = false
            break
        end
        table.insert(plist, i)
    end
    if ready then
        local pack = skynet.call(agent_service, "lua", "proto_pack", "start_game", { players = plist })
        skynet.call(agent_service, "lua", "broadcast", pack, nil)
    end
    return true
end

-- unregister by fd (called when watchdog detects close/error)
-- notify remaining player with game_pause
function command.unregister_by_fd(fd)
    local pid = fd2pid[fd]
    if not pid then
        return false
    end
    fd2pid[fd] = nil
    if players[pid] then
        players[pid] = nil
    end

    -- notify remaining players
	local pack = skynet.call(players[i].agent, "lua", "proto_pack", "game_pause", { reason = "other_disconnected" })
	skynet.call(players[i].agent, "lua", "broadcast", pack, fd) -- notify except disconnected fd
    return true
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

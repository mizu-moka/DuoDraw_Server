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
local players = {}   -- players[pid] = { attached = true/false }
local fd2pid = {}    -- fd -> pid
local max_players = 2

-- Authoritative game state (shared between players)
local game_state = {
    x = 0,
    y = 0,
    space1 = false,
    space2 = false,
    drawing = false,
}

-- allocate a free player_id for a joining fd; returns pid or nil if full
function command.allocate_player(fd)
    for i = 1, max_players do
        if players[i] == nil then
            -- mark slot as allocated but not yet attached
            players[i] = { attached = false }
            fd2pid[fd] = i
            return i
        end
    end
    return nil
end

-- attach an agent service to a previously allocated pid
-- when both players are present and attached, broadcast start_game
function command.attach_agent(pid)
    if not players[pid] then
        skynet.error("[public_info] attach_agent failed: no such player slot", pid)
        return false, "no such player slot"
    end
    -- mark this slot as attached
    players[pid].attached = true

    -- if all slots present and attached, signal ready by returning player id list
    local ready = true
    local plist = {}
    for i = 1, max_players do
        if not players[i] or not players[i].attached then
            skynet.error("[public_info] attach_agent: not ready, missing player", i)
            ready = false
            break
        end
        table.insert(plist, i)
    end
    if ready then
        skynet.error("[public_info] all players ready")
        -- reset authoritative game state for a fresh game start
        game_state.x = 0
        game_state.y = 0
        game_state.space1 = false
        game_state.space2 = false
        game_state.drawing = false
        skynet.error("[public_info] game_state reset for new game")
        return true, plist
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
        -- free the slot
        players[pid] = nil
    end
    -- return remaining player fds so caller can notify them
    local plist = {}
    for f, p in pairs(fd2pid) do
        table.insert(plist, f)
    end
    return true, plist
end

-- handle player input centrally and broadcast authoritative state
function command.player_input(args)
    local pid = args.player_id
    if not pid or not players[pid] or not players[pid].attached then
        return false, "invalid player or not ready"
    end
    for i = 1, max_players do
        if not players[i] or not players[i].attached then
            return false, "not all players present"
        end
    end
    
    if (args.x ~= 0) or (args.y ~= 0) then
        skynet.error(string.format("[public_info] player_input from pid=%d x=%.2f y=%.2f space=%s clear=%s",
            pid, args.x or 0, args.y or 0, tostring(args.space), tostring(args.clear)))
    end

    -- merge input into central game_state
    local speed = 0.05
    if pid == 1 then
        game_state.x = game_state.x + (args.x or 0) * speed
        if args.space then
            game_state.space1 = not game_state.space1
        end
    elseif pid == 2 then
        game_state.y = game_state.y + (args.y or 0) * speed
        if args.space then
            game_state.space2 = not game_state.space2
        end
    end

    -- toggle drawing when both players pressed space
    if game_state.space1 and game_state.space2 then
        game_state.drawing = not game_state.drawing
        game_state.space1 = false
        game_state.space2 = false
    end

    -- do not broadcast here; return data needed for packing/sending
    if args.clear then
        return true, { event = "clear_canvas" }
    end

    -- return the authoritative pencil state for packing by caller
    return true, { event = "update_pencil", payload = { x = game_state.x, y = game_state.y, drawing = game_state.drawing } }
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

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
local ip2pid = {}    -- ip -> pid (prevent same IP occupying multiple slots)
local max_players = 2

-- Authoritative game state (shared between players)
local game_state = {
    x = 0,
    y = 0,
    toggle1 = false,
    toggle2 = false,
    is_drawing = true,
}

-- allocate a free player_id for a joining fd; returns pid or nil if full
function command.allocate_player(fd, addr)
    -- addr is like 'ip:port'; extract ip only
    local ip = nil
    if type(addr) == "string" then
        ip = addr:match("([^:]+)")
    end
    if ip and ip2pid[ip] then
        skynet.error(string.format("[public_info] allocate_player rejected: ip %s already has pid %s", ip, tostring(ip2pid[ip])))
        return nil
    end
    for i = 1, max_players do
        if players[i] == nil then
            -- mark slot as allocated but not yet attached; store ip for cleanup
            players[i] = { attached = false, ip = ip }
            fd2pid[fd] = i
            if ip then
                ip2pid[ip] = i
            end
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
        game_state.toggle1 = false
        game_state.toggle2 = false
        game_state.is_drawing = true
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
        -- free the slot and clear ip mapping
        local ip = players[pid].ip
        if ip then
            ip2pid[ip] = nil
        end
        players[pid] = nil
    end
    -- return remaining player fds so caller can notify them
    local plist = {}
    for f, p in pairs(fd2pid) do
        table.insert(plist, f)
    end
    return true, plist
end

-- Prepare pause: return list of remaining client fds without clearing mappings.
-- Caller should notify clients first, then call finish_pause to clear mappings and reset state.
function command.prepare_pause(fd)
    -- return remaining player fds except fd
    local plist = {}
    for f, p in pairs(fd2pid) do
        if f ~= fd then
            table.insert(plist, f)
        end
    end
    return true, plist
end

-- Finish pause: clear all player mappings and reset authoritative game state.
function command.finish_pause(fd)
    -- clear mappings
    fd2pid = {}
    players = {}
    ip2pid = {}

    -- reset game state
    game_state.x = 0
    game_state.y = 0
    game_state.toggle1 = false
    game_state.toggle2 = false
    game_state.is_drawing = true
    skynet.error(string.format("[public_info] finish_pause called, game_state reset by fd=%s", tostring(fd)))
    return true
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
    
    -- if (args.x ~= 0) or (args.y ~= 0) or args.want_toggle or args.clear then
    --     skynet.error(string.format("[public_info] player_input from pid=%d x=%.2f y=%.2f want_toggle=%s clear=%s",
    --         pid, args.x or 0, args.y or 0, tostring(args.want_toggle), tostring(args.clear)))
    -- end

    -- merge input into central game_state
    local speed = 0.02
    if pid == 1 then
        game_state.x = game_state.x + (args.x or 0) * speed
        game_state.toggle1 = args.want_toggle
        -- if args.want_toggle then
        --     game_state.toggle1 = not game_state.toggle1
        -- end
    elseif pid == 2 then
        game_state.y = game_state.y + (args.y or 0) * speed
        game_state.toggle2 = args.want_toggle
        -- if args.want_toggle then
        --     game_state.toggle2 = not game_state.toggle2
        --     game_state.toggle2 = game_state.toggle2
        -- end
    end

    -- toggle drawing when both players pressed space
    if game_state.toggle1 and game_state.toggle2 then
        game_state.is_drawing = not game_state.is_drawing
        game_state.toggle1 = false
        game_state.toggle2 = false
        skynet.error(string.format("[public_info] toggling drawing state to %s", tostring(game_state.is_drawing)))
    end

    -- do not broadcast here; return data needed for packing/sending

    -- return the authoritative pencil state for packing by caller
    return true, { event = "update_pencil", payload = { x = game_state.x, y = game_state.y, drawing = game_state.is_drawing, toggle1 = game_state.toggle1, toggle2 = game_state.toggle2 } }
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

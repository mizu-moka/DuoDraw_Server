local skynet = require "skynet"
local sqlite3 = require "lsqlite3"

local command = {}

local db

local function init_db()
    local path = "album.db"
    db = sqlite3.open(path)
    -- create table if not exists
    local sql = [[
    CREATE TABLE IF NOT EXISTS artworks (
        id TEXT PRIMARY KEY,
        name TEXT,
        author TEXT,
        data BLOB,
        t INTEGER
    );
    ]]
    db:exec(sql)
end

function command.store_artwork(id, name, author, data, t)
    skynet.error("[[[album]]]: storing artwork id=", id, " name=", name, " author=", author, " size=", #data, " time=", t)
    if not db then init_db() end
    local stmt = db:prepare("INSERT OR REPLACE INTO artworks(id,name,author,data,t) VALUES(?,?,?,?,?)")
    if not stmt then
        skynet.error("album: failed to prepare statement")
        return false
    end
    stmt:bind_values(id, name, author, data, t)
    local rc = stmt:step()
    stmt:finalize()
    if rc ~= sqlite3.DONE then
        skynet.error("album: failed to store artwork", rc)
        return false
    end
    skynet.error("[[[album]]]: artwork stored successfully, id=", id)
    return true
end

function command.get_artwork(id)
    if not db then init_db() end
    local stmt = db:prepare("SELECT name, author, data, t FROM artworks WHERE id = ? LIMIT 1")
    if not stmt then
        skynet.error("album: failed to prepare select")
        return false
    end
    stmt:bind_values(id)
    local rc = stmt:step()
    if rc == sqlite3.ROW then
        local name = stmt:get_value(0)
        local author = stmt:get_value(1)
        local data = stmt:get_value(2)
        local t = stmt:get_value(3)
        stmt:finalize()
        return true, { id = id, name = name, author = author, data = data, time = t }
    else
        stmt:finalize()
        return false
    end
end

function command.get_artwork_by_index(idx)
    if not db then init_db() end
    -- idx is 1-based; use OFFSET idx-1
    local stmt = db:prepare("SELECT id, name, author, data, t FROM artworks ORDER BY t DESC LIMIT 1 OFFSET ?")
    if not stmt then
        skynet.error("album: failed to prepare select by index")
        return false
    end
    stmt:bind_values(idx - 1)
    local rc = stmt:step()
    if rc == sqlite3.ROW then
        local id = stmt:get_value(0)
        local name = stmt:get_value(1)
        local author = stmt:get_value(2)
        local data = stmt:get_value(3)
        local t = stmt:get_value(4)
        stmt:finalize()
        return true, { id = id, name = name, author = author, data = data, time = t }
    else
        stmt:finalize()
        return false
    end
end

skynet.start(function()
    init_db()
    skynet.dispatch("lua", function(_,_, cmd, ...)
        local f = command[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            error("album: unknown cmd " .. tostring(cmd))
        end
    end)
    skynet.register "ALBUM"
end)

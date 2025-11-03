local skynet = require "skynet"
require "skynet.manager"
local sqlite3 = require "lsqlite3"

local command = {}
local db

------------------------------------------------------------
-- 初始化数据库
------------------------------------------------------------
local function init_db()
    local path = "album.db"
    db = sqlite3.open(path)
    if not db then
        skynet.error("[album] failed to open database")
        return
    end

    local sql = [[
    CREATE TABLE IF NOT EXISTS artworks (
        id TEXT PRIMARY KEY,
        name TEXT,
        author TEXT,
        data TEXT,   -- Base64 字符串存储
        t INTEGER
    );
    ]]
    local rc = db:exec(sql)
    if rc ~= sqlite3.OK then
        skynet.error("[album] failed to create table, code=", rc)
    else
        skynet.error("[album] database initialized successfully")
    end
end

------------------------------------------------------------
-- 存储艺术品 (Base64 存为 TEXT)
------------------------------------------------------------
function command.store_artwork(id, name, author, data, t)
    if not db then init_db() end
    if not data then
        skynet.error("[album] store_artwork: data is nil, id=", id)
        return false
    end

    skynet.error("[album] store_artwork called for id=", id)
    -- 输出 base64 数据前 50 字符用于调试
    local preview = string.sub(data, 1, 50)
    skynet.error(string.format(
        "[album] storing artwork id=%s, name=%s, author=%s, size=%d, time=%d, data_head=%s...",
        tostring(id), tostring(name), tostring(author), #data, t, preview
    ))

    local stmt = db:prepare("INSERT OR REPLACE INTO artworks(id,name,author,data,t) VALUES(?,?,?,?,?)")
    if not stmt then
        skynet.error("[album] failed to prepare insert statement")
        return false
    end

    skynet.error("[album] store_artwork called for id=", id)
    stmt:bind_values(id, name, author, data, t)
    local rc = stmt:step()
    stmt:finalize()

    if rc ~= sqlite3.DONE then
        skynet.error("[album] failed to store artwork, code=", rc)
        return false
    end

    skynet.error("[album] artwork stored successfully, id=", id)
    return true
end

------------------------------------------------------------
-- 按 id 获取艺术品
------------------------------------------------------------
function command.get_artwork(id)
    if not db then init_db() end
    local stmt = db:prepare("SELECT name, author, data, t FROM artworks WHERE id = ? LIMIT 1")
    if not stmt then
        skynet.error("[album] failed to prepare select statement")
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

        -- 输出 base64 数据前 50 字符用于调试
        skynet.error(string.format(
            "[album] retrieved artwork id=%s, data_head=%s...",
            tostring(id), string.sub(data or "", 1, 50)
        ))

        return true, {
            id = id,
            name = name,
            author = author,
            data = data,
            time = t
        }
    else
        stmt:finalize()
        skynet.error("[album] no artwork found for id=", id)
        return false
    end
end

------------------------------------------------------------
-- 按索引获取 (时间倒序)
------------------------------------------------------------
function command.get_artwork_by_index(idx)
    if not db then init_db() end
    local stmt = db:prepare("SELECT id, name, author, data, t FROM artworks ORDER BY t DESC LIMIT 1 OFFSET ?")
    if not stmt then
        skynet.error("[album] failed to prepare select by index")
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

        skynet.error(string.format(
            "[album] get_artwork_by_index idx=%d -> id=%s, data_head=%s...",
            idx, tostring(id), string.sub(data or "", 1, 50)
        ))

        return true, {
            id = id,
            name = name,
            author = author,
            data = data,
            time = t
        }
    else
        stmt:finalize()
        return false
    end
end

------------------------------------------------------------
-- 启动服务
------------------------------------------------------------
skynet.start(function()
    init_db()
    skynet.dispatch("lua", function(_, _, cmd, ...)
        local f = command[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            error("[album] unknown cmd " .. tostring(cmd))
        end
    end)
    skynet.register "ALBUM"
end)

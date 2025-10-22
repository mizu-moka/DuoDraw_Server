local skynet = require "skynet"
local sprotoloader = require "sprotoloader"

local max_client = 64

-- Coding Format : UTF-8

-- 「main.lua 脚本介绍」
-- 我们从命令行窗口执行./skynet gameserver/config 命令后，将从start入口启动main.lua，这是skynet在服务器上运行的第一个脚本

skynet.start(function()
	skynet.error("Server start")
	skynet.uniqueservice("protoloader")
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end

	-- 启动调试控制台
	skynet.newservice("debug_console", 8000)

	-- 启动数据库
	skynet.newservice("public_info")

	-- 启动WatchDog
	local watchdog = skynet.newservice("watchdog")

	skynet.call(watchdog, "lua", "start", {
		port = 8888,
		maxclient = max_client,
		nodelay = true,
	})
	skynet.error("Watchdog listen on", 8888)
	skynet.exit()
end)

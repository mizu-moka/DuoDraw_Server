local sprotoparser = require "sprotoparser"

local proto = {}

proto.c2s = sprotoparser.parse [[
.package {
	type 0 : integer
	session 1 : integer
}

-- 玩家输入
player_input 1 {
	request {
		player_id 0 : integer  # 1或2
		x         1 : double   # 若非控制x方向则填0(player 1控制x方向)
		y         2 : double   # 若非控制y方向则填0(player 2控制y方向)
		space     3 : boolean  # 按下Space切换提笔状态
		clear     4 : boolean  # 按下清空画布
	}
}

]]

proto.s2c = sprotoparser.parse [[
.package {
	type 0 : integer
	session 1 : integer
}

-- 服务端合并后的同步结果
update_pencil 1 {
	request {
		x        0 : double
		y        1 : double
		drawing  2 : boolean
	}
}

-- 清空画布
clear_canvas 2 {
	request {
	}
}

-- 客户端连接确认，包含分配的 player_id
connect_ok 3 {
    request {
        player_id 0 : integer
    }
}

-- 游戏开始通知（当两个玩家都加入时）
start_game 4 {
    request {
        players 0 : *integer
    }
}

-- 游戏暂停通知（另一玩家掉线）
game_pause 5 {
    request {
        reason 0 : string
    }
}
]]

return proto

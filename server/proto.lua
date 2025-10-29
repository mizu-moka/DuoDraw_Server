local sprotoparser = require "sprotoparser"

local proto = {}

proto.c2s = sprotoparser.parse [[
.package {
	type 0 : integer
	session 1 : integer
}

player_input 1 {
	request {
		player_id 0 : integer
		x         1 : double
		y         2 : double
		space     3 : boolean
	}
}

clear_request 2 {
	request {
		player_id 0 : integer
	}
}

color_change_req 3 {
	request {
		player_id 0 : integer
		color_id  1 : integer
	}
}

]]

proto.s2c = sprotoparser.parse [[
.package {
	type 0 : integer
	session 1 : integer
}

update_pencil 1 {
	request {
	x        0 : double
	y        1 : double
	drawing  2 : boolean
	toggle1  3 : boolean
	toggle2  4 : boolean
	}
}

color_change_broadcast 6 {
	request {
		color_id 0 : integer
		player_id 1 : integer
	}
}

clear_canvas 2 {
	request {
	}
}

connect_ok 3 {
    request {
        player_id 0 : integer
    }
}

start_game 4 {
    request {
        players 0 : *integer
    }
}

game_pause 5 {
    request {
        reason 0 : string
    }
}
]]

return proto

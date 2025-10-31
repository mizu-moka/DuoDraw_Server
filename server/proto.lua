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

art_upload_chunk 10 {
	request {
		id         0 : string
		name       1 : string
		author     2 : string
		chunk_index 3 : integer
		total_chunks 4 : integer
		data       5 : string
	}
}

get_artwork 11 {
	request {
		id 0 : string
	}
}

art_upload_start 12 {
	request {
		player_id 0 : integer
		name      1 : string
		author    2 : string
		total_chunks 3 : integer
		client_token 4 : string
	}
}

get_artwork_by_index 13 {
	request {
		index 0 : integer
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

art_upload_ack 7 {
	request {
		id 0 : string
		success 1 : boolean
		message 2 : string
		client_token 3 : string
	}
}

artwork_chunk 8 {
	request {
		id 0 : string
		name 1 : string
		author 2 : string
		time 3 : integer
		chunk_index 4 : integer
		total_chunks 5 : integer
		data 6 : string
	}
}

artwork_not_found 9 {
	request {
		id 0 : string
		reason 1 : string
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

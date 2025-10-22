local sprotoparser = require "sprotoparser"

local proto = {}

proto.c2s = sprotoparser.parse [[
.package {
	type 		0 : integer
	session 	1 : integer
}

login 		2 {
	request {
		name 		0 : string
		password 	1 : string
		color       2 : integer
	}
}

logout 		3 {
	request {
		id 	0  : integer
	}	
}

action		 4 {
	request {
		id 		0 : integer
		frame	1 : integer
		input	2 : *integer 
		facing	3 : *double
	}
}

snapshoot	5 {
	request {
		id 		0 : integer
		frame 	1 : integer
		info	2 : *double 
	}
}

dead		6 {
	request {
		id 		0 : integer
	}
}

add_coin_req    7 {
	request {
		posx 	         0 : double
		posy 	         1 : double
		posz             2 : double
		ownerPlayerId    3 : integer
	}
}

remove_coin_req  8 {
	request {
		id               0 : integer
		pickerPlayerId   1 : integer
	}
}


]]

proto.s2c = sprotoparser.parse [[
.package {
	type 		0 : integer
	session 	1 : integer
}

.action {
		id 		0 : integer
		frame	1 : integer
		input	2 : *integer 
		facing	3 : *double
}

connect_ok 		1 {
	request {
	}
}

login 		2 {
	request {
		id 		0 : integer
		name	1 : string
		color   2 : integer
	}
}


logout 		3 {
	request {
		id 	0  : integer
	}	
}

enter_scene 	4 {
	request {	
		id 		0 : integer
		name	1 : string
		color   2 : integer
		scene	3 : integer
		pos 	4 : *double
		facing	5 : *double
	}
}

exit_scene 		5 {
	request {
		id 		0 : integer
	}
}

actions 		6 {
	request {
		actions 0 : *action
	}
}

sync_info 	7 {
	request {	
		
	}
}

actionBC 8 {
	request {
		id 		0 : integer
		frame	1 : integer
		input	2 : *integer 
		facing	3 : *double
	}
}

snapshootBC 9 {
	request {
		id 		0 : integer
		frame 	1 : integer
		info	2 : *double 
	}
}

add_coin_bc    10 {
	request {
		id               0 : integer
		posx 	         1 : double
		posy 	         2 : double
		posz             3 : double
		ownerPlayerId    4 : integer
	}
}

remove_coin_bc    11 {
	request {
		id               0 : integer
		pickerPlayerId   1 : integer
	}
}


]]

return proto

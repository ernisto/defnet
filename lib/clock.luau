local Players = game:GetService 'Players'

-- vars
local local_player = Players.LocalPlayer
local server_time = workspace:GetServerTimeNow()
local received_at = os.clock()

-- functions
local function ping(player: Player?): number
	return (player or local_player or error 'ping needs a player on server'):GetNetworkPing()
end
local function clock(): number
	return if local_player then server_time + os.clock() - received_at else workspace:GetServerTimeNow()
end
local function server_clock(player: Player?): number
	return clock() + ping(player)
end
local function sync(time: number)
	server_time = time
	received_at = os.clock()
end

-- module
return table.freeze {
	sync = sync,
	ping = ping,
	clock = clock,
	server_clock = server_clock,
}

local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'

local codec = require './utils/codec'
local diff = require './utils/diff'
local diff_codec = require './utils/diff_codec'
local remote_index = require './remote_index'
local sync = require './utils/sync'

-- defs
export type remote_desc<T> = { rbxclass: 'RemoteEvent', default: T?, id: number, single: true }
export type state_type<T> = {
	changed: (() -> ()) -> (),
	codec: codec.codec_impl<T>?,
	step: (Player?) -> (),
	server: { [Player]: T },
	client: T,
}

-- vars
local is_client = RunService:IsClient()
local server_pools: { [Player]: codec.pool } = {}
local registry: { sync.syncer<Player> } = {}

-- definition
local function wrap<T>(event: BindableEvent, desc: remote_desc<T>): state_type<T>
	local function listen_changed(callback)
		return event.Event:Connect(callback)
	end

	if is_client then
		local self = { changed = listen_changed, client = desc.default or {} }
		remote_index.on(desc.id, function(buf: buffer, unknowns: { any })
			sync.apply(self.client, buf, remote_index.client_pool, unknowns)
			event:Fire()
		end)
		return self :: any
	end

	local function send(player: Player, packet)
		remote_index.fire(desc.id, player, packet.buf, packet.unknowns)
		event:Fire()
	end
	local syncer = sync.create {
		default = diff.snapshot(desc.default),
		pools = server_pools,
		send = send,
	}
	local function step(player: Player?)
		sync.step(syncer, player)
	end

	table.insert(registry, syncer)
	return table.freeze { changed = listen_changed, step = step, server = syncer.targets } :: any
end
local function define<T>(default: T?): state_type<T>
	return { rbxclass = 'BindableEvent', wrap = wrap, codec = diff_codec.impl, default = default, single = true } :: any
end

-- functions
local function step_sync(player: Player?)
	for _, s in registry do
		sync.step(s, player)
	end
end

-- @server init
if not is_client then
	Players.PlayerAdded:Connect(function(player: Player)
		server_pools[player] = codec.create_pool()
	end)
	for _, player in Players:GetPlayers() do
		server_pools[player] = codec.create_pool()
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		server_pools[player] = nil
		for _, s in registry do
			sync.remove(s, player)
		end
	end)
	RunService.Heartbeat:Connect(function()
		step_sync()
	end)
end

-- module
return table.freeze {
	step_sync = step_sync,
	define = define,
	wrap = wrap,
}

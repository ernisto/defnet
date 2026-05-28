local Players = game:GetService "Players"
local RunService = game:GetService "RunService"

local codec = require "./utils/codec"
local diff = require "./utils/diff"
local diff_codec = require "./utils/diff_codec"
local remote_index = require "./remote_index"
local sync = require "./utils/sync"

local is_client = RunService:IsClient()

local server_pools: { [Player]: codec.pool } = {}
local registry: { sync.syncer } = {}

export type client_state<T> = {
	value: T,
	get: () -> T,
	changed: ((T, T?) -> ()) -> RBXScriptConnection,
}

export type state_type<T> = {
	client: client_state<T>,

	changed: (() -> ()) -> RBXScriptConnection,
	step: (Player?) -> (),

	server: { [Player]: T },

	codec: codec.codec_impl<T>?,
}

export type remote_desc<T> = {
	id: number,
	rbxclass: "RemoteEvent",
	codec: codec.codec_impl<T>?,
	wrap: (RemoteEvent, remote_desc<T>) -> state_type<T>,
	single: true,
	default: T?,
}

local function wrap<T>(remote: RemoteEvent, desc: remote_desc<T>): state_type<T>
	local changed_event = Instance.new("BindableEvent")

	local function changed(callback: () -> ()): RBXScriptConnection
		return changed_event.Event:Connect(callback)
	end

	if is_client then
		local value = if desc.default ~= nil then diff.snapshot(desc.default) else {} :: any

		local client = {
			value = value,

			get = function(): T
				return value
			end,

			changed = function(callback: (T, T?) -> ()): RBXScriptConnection
				return changed_event.Event:Connect(callback)
			end,
		}

		remote_index.on(desc.id, function(buf: buffer, unknowns: { any }?)
			local patch = sync.apply(value, buf, remote_index.client_pool, unknowns)

			changed_event:Fire(patch, value)
		end)

		return table.freeze({
			client = table.freeze(client),

			changed = changed,
			step = function(_player: Player?) end,

			server = {} :: { [Player]: T },

			codec = desc.codec,
		}) :: any
	end

	local function send(player: Player, packet)
		remote_index.fire(desc.id, player, packet.buf, packet.unknowns)
		changed_event:Fire()
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

	return table.freeze {
		client = table.freeze({
			value = if desc.default ~= nil then diff.snapshot(desc.default) else {} :: any,

			get = function(): T
				return if desc.default ~= nil then diff.snapshot(desc.default) else {} :: any
			end,

			changed = function(callback: (T, T?) -> ()): RBXScriptConnection
				return changed_event.Event:Connect(callback)
			end,
		}),

		changed = changed,
		step = step,

		server = syncer.targets,

		codec = desc.codec,
	} :: any
end

local function define<T>(default: T?): state_type<T>
	return {
		rbxclass = "RemoteEvent",
		wrap = wrap,
		codec = diff_codec.impl,
		default = default,
		single = true,
	} :: any
end

local function step_sync(player: Player?)
	for _, syncer in registry do
		sync.step(syncer, player)
	end
end

if not is_client then
	Players.PlayerAdded:Connect(function(player: Player)
		server_pools[player] = codec.create_pool()
	end)

	for _, player in Players:GetPlayers() do
		server_pools[player] = codec.create_pool()
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		server_pools[player] = nil

		for _, syncer in registry do
			sync.remove(syncer, player)
		end
	end)

	RunService.Heartbeat:Connect(function()
		step_sync()
	end)
end

return table.freeze {
	step_sync = step_sync,
	define = define,
	wrap = wrap,
}
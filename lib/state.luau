local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'

local clock = require './clock'
local codec = require './utils/codec'
local diff = require './utils/diff'
local diff_codec = require './utils/diff_codec'
local pool = require './utils/pool'
local prediction = require './utils/prediction'
local remote_index = require './remote_index'
local sync = require './utils/sync'

-- defs
export type remote_desc<T> = { rbxclass: 'RemoteEvent', default: T?, id: number, unified: true }
export type op = { time: number, id: number }
export type state_type<T> = {
	changed: (() -> ()) -> (),
	codec: codec.codec_impl<T>?,
	step: (Player?) -> (),
	predict: ((T) -> ()) -> op,
	settle: (id: number) -> (),
	cancel: (id: number) -> (),
	server: { [Player]: T },
	client: T,
}

-- vars
local is_client = RunService:IsClient()
local server_pools: { [Player]: pool.pool } = {}
local registry: { sync.syncer<Player> } = {}
local next_op_id = 0

-- definition
local function wrap_client<T>(event: BindableEvent, desc: remote_desc<T>): state_type<T>
	local p = prediction.create(desc.default or {})

	local function predict(fn: (any) -> ()): op
		next_op_id += 1
		local op = { time = math.huge, id = next_op_id, fn = fn }

		prediction.predict(p, op)
		event:Fire()
		return op
	end

	local function settle(id: number)
		prediction.settle(p, id, clock.clock())
	end
	local function cancel(id: number)
		if prediction.cancel(p, id) then event:Fire() end
	end
	local function changed(callback)
		return event.Event:Connect(callback)
	end

	remote_index.on(desc.id, function(server_time: number, buf: buffer, unknowns: { any })
		local node = diff_codec.impl.decode(buf, remote_index.client_pool, unknowns)
		prediction.receive(p, node, server_time)
		event:Fire()
	end)

	return table.freeze {
		changed = changed,
		predict = predict,
		settle = settle,
		cancel = cancel,
		server = { [Players.LocalPlayer] = p.server },
		client = p.client,
	} :: any
end
local function wrap<T>(event: BindableEvent, desc: remote_desc<T>): state_type<T>
	if is_client then return wrap_client(event, desc) end

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
	local function changed(callback)
		return event.Event:Connect(callback)
	end

	table.insert(registry, syncer)
	return table.freeze {
		changed = changed,
		step = step,
		server = syncer.targets,
	} :: any
end
local function define<T>(default: T?): state_type<T>
	return {
		rbxclass = 'BindableEvent',
		wrap = wrap,
		codec = diff_codec.impl,
		default = default,
		unified = true,
	} :: any
end

-- functions
local function step_sync(player: Player?)
	for _, s in registry do
		sync.step(s, player)
	end
end

-- @server init
if not is_client then
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, s in registry do
			sync.remove(s, player)
		end
		server_pools[player] = nil
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

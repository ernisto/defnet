local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'

local codec = require './utils/codec'
local diff = require './utils/diff'
local diff_codec = require './utils/diff_codec'
local event = require './event'
local sync = require './utils/sync'

local is_client = RunService:IsClient()

-- defs
type remote_desc<T> = { class: string, default: T? }
export type state_type<T> = {
	changed: (() -> ()) -> (),
	codec: codec.codec_impl<T>?,
	step: (Player?) -> (),
	server: { [Player]: T },
	client: T,
}

local registry: { sync.syncer<Player> } = {}

-- definition
local function define<T>(default: T?): state_type<T>
	return { class = 'state', codec = codec, default = default } :: any
end

local function wrap<T>(remote: RemoteEvent, desc: remote_desc<T>): state_type<T>
	event.codecs[remote] = diff_codec.impl :: any

	if is_client then
		local function listen_changed(listener)
			remote.OnClientEvent:Connect(listener)
		end

		local self = { changed = listen_changed, client = desc.default or {} }
		remote.OnClientEvent:Connect(function(buf: buffer, unknowns: { any })
			sync.apply(self.client, buf, unknowns)
		end)
		return self :: any
	end

	local listeners = {}
	local function send(player: Player, packet)
		remote:FireClient(player, packet.buf, packet.unknowns)
		for _, listener in listeners do
			task.spawn(listener :: any)
		end
	end

	local syncer = sync.create { send = send, default = diff.snapshot(desc.default) }
	local function step(player: Player?)
		sync.step(syncer, player)
	end
	local function listen_changed(listener)
		table.insert(listeners, listener)
	end

	table.insert(registry, syncer)
	return table.freeze { changed = listen_changed, step = step, server = syncer.targets } :: any
end

local function step_sync(player: Player?)
	for _, s in registry do
		sync.step(s, player)
	end
end

if not is_client then
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, s in registry do
			sync.remove(s, player)
		end
	end)
	RunService.Heartbeat:Connect(function()
		step_sync()
	end)
end

-- module
return table.freeze { define = define, wrap = wrap, step_sync = step_sync }

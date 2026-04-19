local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'

local codec = require '../utils/codec'
local diff_codec = require '../utils/diff_codec'
local sync = require '../utils/sync'

local is_client = RunService:IsClient()

-- defs
type remote_desc<T> = { class: string, default: T? }
export type state_type<T> = {
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
	local idx = diff_codec.build_index(desc.default)
	if is_client then
		local self = { client = desc.default or {} }
		remote.OnClientEvent:Connect(function(buf: buffer, unknowns: { any })
			sync.apply(idx, self.client, buf, unknowns)
		end)
		return self :: any
	end

	local function send(player: Player, packet)
		remote:FireClient(player, packet.buf, packet.unknowns)
	end

	local syncer = sync.create { idx = idx, send = send }
	local function step(player: Player?)
		sync.step(syncer, player)
	end

	table.insert(registry, syncer)
	return table.freeze { step = step, server = syncer.targets } :: any
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

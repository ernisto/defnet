local RunService = game:GetService 'RunService'

local clock = require './clock'
local codec = require './utils/codec'
local diff_codec = require './utils/diff_codec'
local pool = require './utils/pool'

-- defs
export type codec_impl = codec.codec_impl<any>
type dispatcher = (...any) -> ()
type packet = { id: number, server_time: number, buf: buffer, unknowns: { any }?, paths: { string }? }

-- vars
local is_plugin = not RunService:IsRunning()
local is_client = RunService:IsClient()
local is_studio = RunService:IsStudio()
local client_pool = pool.create()

local unified_remote: RemoteEvent?
local codecs: { [Instance]: codec_impl } = {}

local HANDLE_TIMEOUT = 5

local queue: { packet } = {}
local draining = false

local dispatchers: { [number]: dispatcher } = {}
local names: { [number]: string } = {}
local next_id = 0

-- functions
local function reserve_id(name: string): number
	local id = next_id
	next_id += 1
	names[id] = name
	return id
end
local function get_name(id: number): string?
	return names[id]
end

local function get_unified(): RemoteEvent?
	return unified_remote
end
local function is_unified(rbx: Instance): boolean
	return rbx == unified_remote
end

local function set_codec(rbx: Instance, impl: codec_impl)
	codecs[rbx] = impl
end
local function get_codec(rbx: Instance, args): codec_impl?
	-- TODO: support unified events with custom codec
	return if is_unified(rbx) then diff_codec.impl else codecs[rbx]
end

-- instance handles
-- paths only ship in studio, to name handles that never sync on the client
local function to_handles(unknowns: { any }?): ({ any }?, { string }?)
	if not unknowns then return nil, nil end

	local paths: { string }? = if is_studio then {} else nil
	for index, value in unknowns do
		if paths then paths[index] = '' end -- remotes mangle sparse arrays
		if typeof(value) ~= 'Instance' then continue end
		if not value:IsDescendantOf(game) then
			warn(debug.traceback(`[defnet] syncing instance outside the DataModel: {value:GetFullName()}`))
		end
		if paths then paths[index] = value:GetFullName() end
		unknowns[index] = InstanceHandle.new(value)
	end
	return unknowns, paths
end
local function resolve_handles(unknowns: { any }?, paths: { string }?)
	if not unknowns then return end

	for index, value in unknowns do
		if typeof(value) ~= 'InstanceHandle' then continue end
		local instance = value:Get() or value:Wait(HANDLE_TIMEOUT)
		if not instance then
			local name = paths and paths[index] or `#{index}`
			warn(`[defnet] instance handle {name} not synced after {HANDLE_TIMEOUT}s, decoding as nil`)
		end
		unknowns[index] = instance
	end
end

-- client dispatch
local function warn_traceback(err: any)
	warn(debug.traceback(tostring(err)))
end
local function dispatch(packet: packet)
	local id, unknowns = packet.id, packet.unknowns
	local fn = dispatchers[id] or error(`unknown remote id {id}`)

	resolve_handles(unknowns, packet.paths)
	fn(packet.server_time, packet.buf, unknowns)
end
local function receive(id: number, server_time: number, buf: buffer, unknowns: { any }?, paths: { string }?)
	clock.sync(server_time)
	table.insert(queue, { id = id, server_time = server_time, buf = buf, unknowns = unknowns, paths = paths })
	if draining then return end

	-- packets are diffs: one waiting on handles must hold back the later ones
	draining = true
	local packet = table.remove(queue, 1)
	while packet do
		xpcall(dispatch, warn_traceback, packet)
		packet = table.remove(queue, 1)
	end
	draining = false
end

local function ensure_unified(parent: Instance): RemoteEvent
	if unified_remote then return unified_remote end

	local remote: RemoteEvent
	if is_client and not is_plugin then
		remote = parent:WaitForChild '__main__' :: RemoteEvent
	else
		remote = Instance.new 'RemoteEvent'
		remote.Name = '__main__'
		remote.Parent = parent
	end
	unified_remote = remote

	if is_client then remote.OnClientEvent:Connect(receive) end
	return remote
end

local function on(id: number, fn: dispatcher)
	dispatchers[id] = fn
end
local function fire(id: number, target: Player, buf: buffer, unknowns: { any }?)
	local remote = unified_remote or error 'unified remote not initialized'
	local handles, paths = to_handles(unknowns)
	remote:FireClient(target, id, clock.clock(), buf, handles, paths)
end

-- module
return table.freeze {
	reserve_id = reserve_id,
	get_name = get_name,

	set_codec = set_codec,
	get_codec = get_codec,

	ensure_unified = ensure_unified,
	get_unified = get_unified,
	is_unified = is_unified,

	on = on,
	fire = fire,

	client_pool = client_pool,
}

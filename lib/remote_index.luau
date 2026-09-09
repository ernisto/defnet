local RunService = game:GetService 'RunService'

local codec = require './utils/codec'

-- defs
export type codec_impl = codec.codec_impl<any>
type dispatcher = (...any) -> ()

-- vars
local is_plugin = not RunService:IsRunning()
local is_client = RunService:IsClient()
local client_pool = codec.create_pool()

local unified_remote: RemoteEvent?
local codecs: { [Instance]: codec_impl } = {}

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
local function get_codec(rbx: Instance): codec_impl?
	return codecs[rbx]
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

	if is_client then
		remote.OnClientEvent:Connect(function(id: number, ...)
			local fn = dispatchers[id] or error(`unknown remote id {id}`)
			fn(...)
		end)
	end
	return remote
end

local function on(id: number, fn: dispatcher)
	dispatchers[id] = fn
end
local function fire(id: number, ...: any)
	local remote = unified_remote or error 'unified remote not initialized'
	if is_client then
		remote:FireServer(id, ...)
	else
		local target = ... :: Player
		remote:FireClient(target, id, select(2, ...))
	end
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

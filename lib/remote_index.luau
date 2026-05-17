local RunService = game:GetService 'RunService'

local codec = require './utils/codec'

-- defs
export type codec_impl = codec.codec_impl<any>
type dispatcher = (...any) -> ()

-- vars
local is_client = RunService:IsClient()
local client_pool = codec.create_pool()

local single_remote: RemoteEvent?
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

local function set_codec(rbx: Instance, impl: codec_impl)
	codecs[rbx] = impl
end
local function get_codec(rbx: Instance): codec_impl?
	return codecs[rbx]
end

local function ensure_single(parent: Instance): RemoteEvent
	if single_remote then return single_remote end

	local remote: RemoteEvent
	if is_client then
		remote = parent:WaitForChild '__main__' :: RemoteEvent
	else
		remote = Instance.new 'RemoteEvent'
		remote.Name = '__main__'
		remote.Parent = parent
	end
	single_remote = remote

	if is_client then
		remote.OnClientEvent:Connect(function(id: number, ...)
			local fn = dispatchers[id] or error(`unknown remote id {id}`)
			fn(...)
		end)
	end
	return remote
end

local function get_single(): RemoteEvent?
	return single_remote
end
local function is_single(rbx: Instance): boolean
	return rbx == single_remote
end

local function on(id: number, fn: dispatcher)
	dispatchers[id] = fn
end
local function fire(id: number, ...: any)
	local remote = single_remote or error 'single remote not initialized'
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

	ensure_single = ensure_single,
	get_single = get_single,
	is_single = is_single,
	on = on,
	fire = fire,

	client_pool = client_pool,
}

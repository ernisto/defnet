local RunService = game:GetService 'RunService'
local is_client = RunService:IsClient()

local codec = require '@self/utils/codec'
local event = require '@self/event'
local func = require '@self/func'
local remote_index = require '@self/remote_index'
local state = require '@self/state'

-- defs
type remote_desc = {
	id: number,
	rbxclass: string?,
	codec: remote_index.codec_impl?,
	wrap: (Instance, any) -> any,
	single: boolean?,
}

-- helpers
local function sorted_keys(tab: { [string]: any }): { string }
	local keys = {}
	for k in tab do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end
local function deterministic_iter<V>(tabl: { string: V }): () -> (string, V)
	local keys = sorted_keys(tabl)
	local count = 0
	return function()
		count += 1
		local key = keys[count]
		return key, key and tabl[key]
	end
end
local function ensure_instance(parent: Instance, class: string, name: string)
	if is_client then return parent:WaitForChild(name) end
	local instance = Instance.new(class)

	instance.Name = name
	instance.Parent = parent
	return instance
end

-- functions
local function define_remotes<T>(remotes_def: T, root: Instance?): T
	assert(type(remotes_def) == 'table', 'refine type')
	local parent: Instance = root or ensure_instance(script, 'Folder', 'rbx')

	for name, desc in deterministic_iter<<remote_desc>>(remotes_def) do
		if type(desc.rbxclass) == 'string' then
			desc.id = remote_index.reserve_id(name)
			local rbx = if desc.single
				then remote_index.ensure_single(parent)
				else ensure_instance(parent, desc.rbxclass, name)

			if desc.codec then remote_index.set_codec(rbx, desc.codec) end

			remotes_def[name] = desc.wrap(rbx, desc)
		else
			local folder = ensure_instance(parent, 'Folder', name)
			remotes_def[name] = define_remotes(desc, folder)
		end
	end

	return table.freeze(remotes_def) :: any
end

-- module
return table.freeze {
	codec = codec,

	remotes = define_remotes,
	step_sync = state.step_sync,
	state = state.define,
	event = event.define,
	func = func.define,
}

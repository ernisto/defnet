local RunService = game:GetService 'RunService'
local is_client = RunService:IsClient()

local codec = require '@self/utils/codec'
local event = require '@self/event'
local func = require '@self/func'
local state = require '@self/state'

type remote_desc<T> = { class: string }

-- functions
local function ensure_instance(parent: Instance, class: string, name: string)
	if is_client then return parent:WaitForChild(name) end
	local instance = Instance.new(class)

	instance.Name = name
	instance.Parent = script
	return instance
end
local function define_remotes<T>(remotes_def: T, root: Instance?): T
	assert(type(remotes_def) == 'table', 'refine type')
	local parent: Instance = root or ensure_instance(script, 'Folder', 'rbx')

	for name, desc: any in remotes_def do
		if type(desc.rbxclass) == 'string' then
			local rbx = ensure_instance(parent, desc.rbxclass, name)
			remotes_def[name] = desc.wrap(rbx)
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
	event = event.define,
	func = func.define,
	state = state.define,
	step_sync = state.step_sync,
}

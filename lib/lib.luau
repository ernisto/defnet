local RunService = game:GetService 'RunService'
local is_client = RunService:IsClient()

local codec = require './codec'
local event = require './event'
local func = require './func'
local state = require './state'

type remote_desc<T> = { class: string, codec: codec.codec_impl<T, ...any>? }

-- functions
local function remotes<T>(remotes_def: T, root: Instance?): T
	assert(type(remotes_def) == 'table', 'refine type')
	local parent: Instance = root or script

	for name, desc in remotes_def do
		local class = type(desc) == 'table' and (desc :: remote_desc<any>).class
		if class == 'state' then
			local remote = if is_client then parent:WaitForChild(name) else Instance.new 'RemoteEvent'
			remote.Name = name
			remote.Parent = parent
			remotes_def[name] = state.wrap(remote :: RemoteEvent, desc :: any)
		elseif class then
			local remote = if is_client then parent:WaitForChild(name) else Instance.new(class :: any)
			remote.Name = name
			remote.Parent = parent

			remotes_def[name] = if class == 'RemoteFunction'
				then func.wrap(remote :: RemoteFunction, desc)
				else event.wrap(remote :: RemoteEvent, desc)
		else
			local folder: Instance = if is_client then parent:WaitForChild(name) else Instance.new('Folder', parent)
			folder.Name = name
			remotes_def[name] = remotes(desc, folder)
		end
	end

	return table.freeze(remotes_def) :: any
end

-- module
return table.freeze {
	preserved = codec :: codec.codec_impl<any, ...any>,
	remotes = remotes,
	event = event.define,
	func = func.define,
	state = state.define,
	step_sync = state.step_sync,
}

local RunService = game:GetService "RunService"
local is_client = RunService:IsClient()

local codec = require "@self/utils/codec"
local event = require "@self/event"
local func = require "@self/func"
local remote_index = require "@self/remote_index"
local state = require "@self/state"

export type state_type<T> = state.state_type<T>
export type event_type<T...> = event.event_type<T...>
export type func_type<T..., R...> = func.func_type<T..., R...>

type remote_desc = {
	id: number?,
	rbxclass: string?,
	codec: remote_index.codec_impl?,
	wrap: (Instance, any) -> any,
	single: boolean?,
}

export type defnet = {
	codec: typeof(codec),

	remotes: <T>(T, Instance?) -> T,

	step_sync: (Player?) -> (),
	state: <T>(T?) -> state.state_type<T>,
	event: typeof(event.define),
	func: typeof(func.define),
}

local function sorted_keys(tab: { [string]: any }): { string }
	local keys = {}

	for k in tab do
		table.insert(keys, k)
	end

	table.sort(keys)

	return keys
end

local function deterministic_iter(tabl: { [string]: any })
	local keys = sorted_keys(tabl)
	local count = 0

	return function()
		count += 1

		local key = keys[count]

		if key == nil then
			return nil
		end

		return key, tabl[key]
	end
end

local function ensure_instance(parent: Instance, class: string, name: string): Instance
	if is_client then
		return parent:WaitForChild(name)
	end

	local instance = Instance.new(class)

	instance.Name = name
	instance.Parent = parent

	return instance
end

local function define_remotes<T>(remotes_def: T, root: Instance?): T
	assert(type(remotes_def) == "table", "refine type")

	local remotes_table = remotes_def :: any
	local parent: Instance = root or ensure_instance(script, "Folder", "rbx")

	for name, desc in deterministic_iter(remotes_table) do
		if type(desc.rbxclass) ~= "string" then
			local folder = ensure_instance(parent, "Folder", name)

			remotes_table[name] = define_remotes(desc, folder)

			continue
		end

		desc.id = remote_index.reserve_id(name)

		local rbx = ensure_instance(parent, desc.rbxclass, name)

		if desc.single then
			remote_index.ensure_single(parent)
		end

		if desc.codec then
			remote_index.set_codec(rbx, desc.codec)
		end

		remotes_table[name] = desc.wrap(rbx, desc)
	end

	return table.freeze(remotes_table) :: T
end

local defnet: defnet = table.freeze {
	codec = codec,

	remotes = define_remotes,
	step_sync = state.step_sync,
	state = state.define,
	event = event.define,
	func = func.define,
}

return defnet
local Players = game:GetService 'Players'
local RunService = game:GetService 'RunService'

local serde = require './serde'

local is_client = RunService:IsClient()
local remote_func_debug_event = script:FindFirstChild 'RemoteFunctionEvent.profiler' :: BindableEvent
	or Instance.new('BindableEvent', script)

remote_func_debug_event.Name = 'RemoteFunctionEvent.profiler'

-- defs
type serde_impl<Data, Encoded...> = { encode: (Data) -> Encoded..., decode: (Encoded...) -> Data }
type remote_desc<T> = { class: string, serde: serde_impl<T, ...any>? }

export type event_type<T...> = {
	fire_server: (T...) -> (),
	fire_client: (Player, T...) -> (),
	fire_all: (T...) -> (),
	fire_list: ({ Player }, T...) -> (),
	fire_except: (Player, T...) -> (),
	on_client: ((T...) -> ()) -> RBXScriptConnection,
	on_server: ((Player, T...) -> ()) -> RBXScriptConnection,
}
export type func_type<T..., R...> = {
	invoke_server: (T...) -> R...,
	invoke_client: (Player, T...) -> R...,
	on_server_invoke: (Player, T...) -> R...,
	on_client_invoke: (T...) -> R...,
}

local function event<T...>(serde: serde_impl<any, ...any>?): event_type<T...>
	return { class = 'RemoteEvent', serde = serde } :: any
end
local function func<T..., R...>(): func_type<T..., R...>
	return { class = 'RemoteFunction' } :: any
end

-- functions

local function wrap_event<T...>(remote: RemoteEvent, desc: remote_desc<any>)
	local impl = desc.serde
	if impl == serde then remote:AddTag 'preserved' end

	return table.freeze {
		fire_server = function(...: T...)
			if impl then
				remote:FireServer(impl.encode(...))
			else
				remote:FireServer(...)
			end
		end,
		fire_client = function(player: Player, ...: T...)
			if impl then
				remote:FireClient(player, impl.encode(...))
			else
				remote:FireClient(player, ...)
			end
		end,
		fire_all = function(...: T...)
			if impl then
				remote:FireAllClients(impl.encode(...))
			else
				remote:FireAllClients(...)
			end
		end,
		fire_list = function(list: { Player }, ...)
			if impl then
				local encoded = { impl.encode(...) }
				for _, player in list do
					remote:FireClient(player, unpack(encoded))
				end
			else
				local args: { any } = { ... }
				for _, player in list do
					remote:FireClient(player, unpack(args))
				end
			end
		end,
		fire_except = function(except: Player, ...)
			if impl then
				local encoded = { impl.encode(...) }
				for _, player in Players:GetPlayers() do
					if player ~= except then remote:FireClient(player, unpack(encoded)) end
				end
			else
				local args: { any } = { ... }
				for _, player in Players:GetPlayers() do
					if player ~= except then remote:FireClient(player, unpack(args)) end
				end
			end
		end,
		on_client = function(handler: (T...) -> ())
			if impl then
				return remote.OnClientEvent:Connect(function(...)
					(handler :: any)(impl.decode(...))
				end)
			else
				return remote.OnClientEvent:Connect(handler :: any)
			end
		end,
		on_server = function(handler: (Player, T...) -> ())
			if impl then
				return remote.OnServerEvent:Connect(function(player: Player, ...)
					(handler :: any)(player, impl.decode(...))
				end)
			else
				return remote.OnServerEvent:Connect(handler :: any)
			end
		end,
	}
end
local function wrap_func<T>(remote: RemoteFunction, desc: remote_desc<T>)
	return setmetatable({
		invoke_server = function(...)
			remote_func_debug_event:Fire(remote, ...)
			local reply = { remote:InvokeServer(...) }

			remote_func_debug_event:Fire(remote, unpack(reply))
			return unpack(reply)
		end,
		invoke_client = function(player: Player, ...)
			remote_func_debug_event:Fire(remote, ...)
			local reply = { remote:InvokeClient(player, ...) }

			remote_func_debug_event:Fire(remote, unpack(reply))
			return unpack(reply)
		end,
	}, {
		__newindex = function(self, key, value)
			if key == 'on_server_invoke' then
				remote.OnServerInvoke = value
			elseif key == 'on_client_invoke' then
				remote.OnClientInvoke = value
			else
				rawset(self, key, value)
			end
		end,
		__index = function(_, key)
			if key == 'on_server_invoke' then return remote.OnServerInvoke end
			if key == 'on_client_invoke' then return remote.OnClientInvoke end
			return nil :: any
		end,
	})
end

local function remotes<T>(remotes_def: T, root: Instance?): T
	assert(type(remotes_def) == 'table', 'refine type')
	local parent: Instance = root or script

	for name, desc in remotes_def do
		local class = type(desc) == 'table' and (desc :: remote_desc<any>).class
		if class then
			local remote = if is_client then parent:WaitForChild(name) else Instance.new(class :: any)
			remote.Name = name
			remote.Parent = parent

			remotes_def[name] = if class == 'RemoteFunction'
				then wrap_func(remote :: RemoteFunction, desc)
				else wrap_event(remote :: RemoteEvent, desc)
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
	preserved = serde :: serde_impl<any, ...any>,
	remotes = remotes,
	event = event,
	preserved_event = event,
	func = func,
}

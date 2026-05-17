local scanner = require './utils/nan_scanner'

local remote_func_debug_event = script:FindFirstChild 'RemoteFunctionEvent.profiler' :: BindableEvent
	or Instance.new('BindableEvent', script)

remote_func_debug_event.Name = 'RemoteFunctionEvent.profiler'

-- defs
type codec_impl<Data, Encoded...> = { encode: (Data) -> Encoded..., decode: (Encoded...) -> Data }
type remote_desc<T> = { rbxclass: string, codec: codec_impl<T, ...any>? }

export type func_type<T..., R...> = {
	invoke_server: (T...) -> R...,
	invoke_client: (Player, T...) -> R...,
	on_server_invoke: (Player, T...) -> R...,
	on_client_invoke: (T...) -> R...,
}

-- functions
local function wrap<T>(remote: RemoteFunction, desc: remote_desc<T>)
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

			scanner.assert_valid_tuple(unpack(reply))
			remote_func_debug_event:Fire(remote, unpack(reply))
			return unpack(reply)
		end,
	}, {
		__newindex = function(self, key, callback)
			if key == 'on_server_invoke' then
				remote.OnServerInvoke = function(player: Player, ...)
					scanner.assert_valid_tuple(...)
					return callback(player, ...)
				end
			elseif key == 'on_client_invoke' then
				remote.OnClientInvoke = function(...)
					return callback(...)
				end
			else
				rawset(self, key, callback)
			end
		end,
	})
end
local function define<T..., R...>(): func_type<T..., R...>
	return { rbxclass = 'RemoteFunction', wrap = wrap } :: any
end

-- module
return table.freeze { define = define, wrap = wrap }

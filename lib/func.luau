local remote_func_debug_event = script:FindFirstChild 'RemoteFunctionEvent.profiler' :: BindableEvent
	or Instance.new('BindableEvent', script)

remote_func_debug_event.Name = 'RemoteFunctionEvent.profiler'

-- defs
type codec_impl<Data, Encoded...> = { encode: (Data) -> Encoded..., decode: (Encoded...) -> Data }
type remote_desc<T> = { class: string, codec: codec_impl<T, ...any>? }

export type func_type<T..., R...> = {
	invoke_server: (T...) -> R...,
	invoke_client: (Player, T...) -> R...,
	on_server_invoke: (Player, T...) -> R...,
	on_client_invoke: (T...) -> R...,
}

-- functions
local function define<T..., R...>(): func_type<T..., R...>
	return { class = 'RemoteFunction' } :: any
end
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
	})
end

-- module
return table.freeze { define = define, wrap = wrap }

local Players = game:GetService 'Players'

local codec = require '../utils/codec'

-- defs
type remote_desc<T> = { class: string, codec: codec.codec_impl<T, ...any>? }

export type event_type<T...> = {
	fire_server: (T...) -> (),
	fire_client: (Player, T...) -> (),
	fire_all: (T...) -> (),
	fire_list: ({ Player }, T...) -> (),
	fire_except: (Player, T...) -> (),
	on_client: ((T...) -> ()) -> RBXScriptConnection,
	on_server: ((Player, T...) -> ()) -> RBXScriptConnection,
}

-- functions
local function define<T...>(codec: codec.codec_impl<any, ...any>?): event_type<T...>
	return { class = 'RemoteEvent', codec = codec } :: any
end
local function wrap_codec<T>(remote: RemoteEvent, codec_impl: codec.codec_impl<T>): event_type<(T)>
	if codec_impl == codec then remote:AddTag 'preserved' end

	return table.freeze {
		fire_server = function(t: T)
			remote:FireServer(codec_impl.encode(t))
		end,
		fire_client = function(player: Player, t: T)
			remote:FireClient(player, codec_impl.encode(t))
		end,
		fire_all = function(t: T)
			remote:FireAllClients(codec_impl.encode(t))
		end,
		fire_list = function(list: { Player }, t: T)
			local encoded = { codec_impl.encode(t) }
			for _, player in list do
				remote:FireClient(player, unpack(encoded))
			end
		end,
		fire_except = function(except: Player, t: T)
			local encoded = { codec_impl.encode(t) }
			for _, player in Players:GetPlayers() do
				if player ~= except then remote:FireClient(player, unpack(encoded)) end
			end
		end,
		on_client = function(handler: (T) -> ())
			return remote.OnClientEvent:Connect(function(...)
				handler(codec_impl.decode(...))
			end)
		end,
		on_server = function(handler: (Player, T) -> ())
			return remote.OnServerEvent:Connect(function(player: Player, ...)
				handler(player, codec_impl.decode(...))
			end)
		end,
	}
end
local function wrap<T...>(remote: RemoteEvent, desc: remote_desc<any>): event_type<T...>
	local codec_impl = desc.codec
	if codec_impl then return wrap_codec(remote, codec_impl) :: any end

	return table.freeze {
		fire_server = function(...: T...)
			remote:FireServer(...)
		end,
		fire_client = function(player: Player, ...: T...)
			remote:FireClient(player, ...)
		end,
		fire_all = function(...: T...)
			remote:FireAllClients(...)
		end,
		fire_list = function(list: { Player }, ...: T...)
			for _, player in list do
				remote:FireClient(player, ...)
			end
		end,
		fire_except = function(except: Player, ...: T...)
			for _, player in Players:GetPlayers() do
				if player ~= except then remote:FireClient(player, ...) end
			end
		end,
		on_client = function(handler: (T...) -> ())
			return remote.OnClientEvent:Connect(handler :: any)
		end,
		on_server = function(handler: (Player, T...) -> ())
			return remote.OnServerEvent:Connect(handler :: any)
		end,
	}
end

-- module
return table.freeze { define = define, wrap = wrap }

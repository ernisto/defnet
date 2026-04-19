local Players = game:GetService 'Players'

local codec = require './codec'

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
local function wrap<T...>(remote: RemoteEvent, desc: remote_desc<any>): event_type<T...>
	local codec_impl = desc.codec
	if codec_impl == codec then remote:AddTag 'preserved' end

	return table.freeze {
		fire_server = function(...: T...)
			if codec_impl then
				remote:FireServer(codec_impl.encode(...))
			else
				remote:FireServer(...)
			end
		end,
		fire_client = function(player: Player, ...: T...)
			if codec_impl then
				remote:FireClient(player, codec_impl.encode(...))
			else
				remote:FireClient(player, ...)
			end
		end,
		fire_all = function(...: T...)
			if codec_impl then
				remote:FireAllClients(codec_impl.encode(...))
			else
				remote:FireAllClients(...)
			end
		end,
		fire_list = function(list: { Player }, ...)
			if codec_impl then
				local encoded = { codec_impl.encode(...) }
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
			if codec_impl then
				local encoded = { codec_impl.encode(...) }
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
			if codec_impl then
				return remote.OnClientEvent:Connect(function(...)
					(handler :: any)(codec_impl.decode(...))
				end)
			else
				return remote.OnClientEvent:Connect(handler :: any)
			end
		end,
		on_server = function(handler: (Player, T...) -> ())
			if codec_impl then
				return remote.OnServerEvent:Connect(function(player: Player, ...)
					(handler :: any)(player, codec_impl.decode(...))
				end)
			else
				return remote.OnServerEvent:Connect(handler :: any)
			end
		end,
	}
end

return table.freeze { define = define, wrap = wrap }

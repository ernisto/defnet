local Players = game:GetService "Players"

local codec = require "./utils/codec"
local scanner = require "./utils/nan_scanner"
local guard = require "./utils/guard"
local codec_guard = require "./utils/codec_guard"

type schema = guard.schema

type event_options = {
	codec: codec.codec_impl?,
	schema: schema?,
	rate_limit: number?,
	rate_window: number?,
}

type remote_desc = {
	rbxclass: string,
	codec: codec.codec_impl?,
	schema: schema?,
	rate_limit: number?,
	rate_window: number?,
}

export type event_type<T... = ...any> = {
	fire_server: (T...) -> (),
	fire_client: (Player, T...) -> (),
	fire_all: (T...) -> (),
	fire_list: ({ Player }, T...) -> (),
	fire_except: (Player, T...) -> (),
	on_client: ((T...) -> ()) -> RBXScriptConnection,
	on_server: ((Player, T...) -> ()) -> RBXScriptConnection,
}

local function validate_server(desc: remote_desc, remote: RemoteEvent, player: Player, ...): boolean
	if not guard.rate_limit(player, remote.Name, desc.rate_limit, desc.rate_window) then
		warn("[defnet] rate limit:", player.Name, remote.Name)
		return false
	end

	local valid, index = guard.validate_tuple(desc.schema, ...)

	if not valid then
		warn("[defnet] invalid payload:", player.Name, remote.Name, "arg", index)
		return false
	end

	return true
end

local function wrap_codec<T>(remote: RemoteEvent, desc: remote_desc): event_type<T>
	local codec_impl = codec_guard.wrap(desc.codec :: codec.codec_impl, desc.schema)

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
				if player ~= except then
					remote:FireClient(player, unpack(encoded))
				end
			end
		end,

		on_client = function(handler: (T) -> ())
			return remote.OnClientEvent:Connect(function(buf: buffer, unknowns: { any }?)
				local data = codec_impl.decode(buf, nil, unknowns)

				scanner.assert_valid(data)

				guard.safe_call(handler, data)
			end)
		end,

		on_server = function(handler: (Player, T) -> ())
			return remote.OnServerEvent:Connect(function(player: Player, buf: buffer, unknowns: { any }?)
				if not guard.rate_limit(player, remote.Name, desc.rate_limit, desc.rate_window) then
					warn("[defnet] rate limit:", player.Name, remote.Name)
					return
				end

				local data = codec_impl.decode(buf, nil, unknowns)

				scanner.assert_valid(data)

				guard.safe_call(handler, player, data)
			end)
		end,
	}
end

local function wrap<T...>(remote: RemoteEvent, desc: remote_desc): event_type<T...>
	if desc.codec then
		return wrap_codec(remote, desc) :: any
	end

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
				if player ~= except then
					remote:FireClient(player, ...)
				end
			end
		end,

		on_client = function(handler: (T...) -> ())
			return remote.OnClientEvent:Connect(function(...)
				scanner.assert_valid_tuple(...)

				guard.safe_call(handler, ...)
			end :: any)
		end,

		on_server = function(handler: (Player, T...) -> ())
			return remote.OnServerEvent:Connect(function(player: Player, ...)
				scanner.assert_valid_tuple(...)

				if not validate_server(desc, remote, player, ...) then
					return
				end

				guard.safe_call(handler, player, ...)
			end :: any)
		end,
	}
end

local function normalize_options(options: codec.codec_impl? | event_options?): event_options
	if options == nil then
		return {}
	end

	if typeof(options) == "table" and (options :: any).encode and (options :: any).decode then
		return {
			codec = options :: codec.codec_impl,
		}
	end

	return options :: event_options
end

local function define<T...>(options: codec.codec_impl? | event_options?): event_type<T...>
	local opts = normalize_options(options)

	return {
		rbxclass = "RemoteEvent",
		wrap = wrap,
		codec = opts.codec,
		schema = opts.schema,
		rate_limit = opts.rate_limit,
		rate_window = opts.rate_window,
	} :: any
end

return table.freeze {
	define = define,
	wrap = wrap,
}
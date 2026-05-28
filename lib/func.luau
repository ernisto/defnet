local scanner = require "./utils/nan_scanner"
local guard = require "./utils/guard"

local remote_func_debug_event =
	script:FindFirstChild "RemoteFunctionEvent.profiler" :: BindableEvent
	or Instance.new("BindableEvent", script)

remote_func_debug_event.Name = "RemoteFunctionEvent.profiler"

type schema = guard.schema

type func_options = {
	schema: schema?,
	rate_limit: number?,
	rate_window: number?,
	timeout: number?,
}

type remote_desc = {
	rbxclass: string,
	schema: schema?,
	rate_limit: number?,
	rate_window: number?,
	timeout: number?,
}

export type func_type<T... = ...any, R... = ...any> = {
	invoke_server: (T...) -> R...,
	invoke_client: (Player, T...) -> R...,
	on_server_invoke: (Player, T...) -> R...,
	on_client_invoke: (T...) -> R...,
}

local function invoke_client_with_timeout<T..., R...>(
	remote: RemoteFunction,
	player: Player,
	timeout: number,
	...: T...
): R...
	local done = false
	local ok = false
	local result = nil

	local args = { ... }

	task.spawn(function()
		ok, result = pcall(function()
			return table.pack(remote:InvokeClient(player, unpack(args)))
		end)

		done = true
	end)

	local started_at = os.clock()

	while not done do
		if os.clock() - started_at >= timeout then
			warn("[defnet] invoke_client timeout:", player.Name, remote.Name)
			return nil :: any
		end

		task.wait()
	end

	if not ok then
		warn("[defnet] invoke_client error:", result)
		return nil :: any
	end

	local packed = result :: any

	scanner.assert_valid_tuple(unpack(packed, 1, packed.n))

	return unpack(packed, 1, packed.n)
end

local function wrap<T..., R...>(remote: RemoteFunction, desc: remote_desc): func_type<T..., R...>
	return setmetatable({
		invoke_server = function(...: T...): R...
			remote_func_debug_event:Fire(remote, ...)

			local reply = table.pack(remote:InvokeServer(...))

			remote_func_debug_event:Fire(remote, unpack(reply, 1, reply.n))

			return unpack(reply, 1, reply.n)
		end,

		invoke_client = function(player: Player, ...: T...): R...
			remote_func_debug_event:Fire(remote, ...)

			local timeout = desc.timeout or 8
			local reply = table.pack(invoke_client_with_timeout(remote, player, timeout, ...))

			remote_func_debug_event:Fire(remote, unpack(reply, 1, reply.n))

			return unpack(reply, 1, reply.n)
		end,
	}, {
		__newindex = function(self, key, callback)
			if key == "on_server_invoke" then
				remote.OnServerInvoke = function(player: Player, ...: T...): R...
					if not guard.rate_limit(player, remote.Name, desc.rate_limit, desc.rate_window) then
						warn("[defnet] rate limit:", player.Name, remote.Name)
						return nil :: any
					end

					scanner.assert_valid_tuple(...)

					local valid, index = guard.validate_tuple(desc.schema, ...)

					if not valid then
						warn("[defnet] invalid invoke:", player.Name, remote.Name, "arg", index)
						return nil :: any
					end

					return guard.safe_call(callback, player, ...)
				end
			elseif key == "on_client_invoke" then
				remote.OnClientInvoke = function(...: T...): R...
					scanner.assert_valid_tuple(...)

					return guard.safe_call(callback, ...)
				end
			else
				rawset(self, key, callback)
			end
		end,
	}) :: any
end

local function define<T..., R...>(options: func_options?): func_type<T..., R...>
	options = options or {}

	return {
		rbxclass = "RemoteFunction",
		wrap = wrap,
		schema = options.schema,
		rate_limit = options.rate_limit,
		rate_window = options.rate_window,
		timeout = options.timeout,
	} :: any
end

return table.freeze {
	define = define,
	wrap = wrap,
}
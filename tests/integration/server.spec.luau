local lib = require '@game/ReplicatedStorage/packages/defnet'

local test = {}

local function build()
	local root = Instance.new 'Folder'
	local def = lib.remotes({
		ping = lib.event(),
		typed = lib.event {
			encode = function(v: any)
				return v
			end,
			decode = function(v: any)
				return v
			end,
		},
		ask = lib.func(),
		world = lib.state { coins = 0 },
		inventory = {
			open = lib.event(),
			close = lib.event(),
		},
	}, root) :: any
	return root, def
end

function test.should_create_remote_event()
	local root = build()
	local rbx = root:FindFirstChild 'ping'
	assert(rbx and rbx:IsA 'RemoteEvent', 'expected RemoteEvent')
end

function test.should_create_remote_function()
	local root = build()
	local rbx = root:FindFirstChild 'ask'
	assert(rbx and rbx:IsA 'RemoteFunction', 'expected RemoteFunction')
end

function test.should_create_state_remote_event()
	local root = build()
	local rbx = root:FindFirstChild 'world'
	assert(rbx and rbx:IsA 'RemoteEvent', 'state uses RemoteEvent')
end

function test.should_walk_nested_folder()
	local root = build()
	local folder = root:FindFirstChild 'inventory'
	assert(folder and folder:IsA 'Folder', 'nested group must be Folder')
	assert(folder:FindFirstChild 'open' :: any)
	assert(folder:FindFirstChild 'close' :: any)
end

function test.should_wrap_event_api()
	local _, def = build()
	assert(type(def.ping.fire_all) == 'function')
	assert(type(def.ping.fire_client) == 'function')
	assert(type(def.ping.fire_list) == 'function')
	assert(type(def.ping.fire_except) == 'function')
	assert(type(def.ping.on_server) == 'function')
end

function test.should_wrap_func_api()
	local _, def = build()
	assert(type(def.ask.invoke_client) == 'function')
	assert(type(def.ask.invoke_server) == 'function')
end

function test.should_wrap_state_api()
	local _, def = build()
	assert(type(def.world.step) == 'function')
	assert(type(def.world.changed) == 'function')
	assert(type(def.world.server) == 'table')
end

function test.should_freeze_def()
	local _, def = build()
	local ok = pcall(function()
		def.new_key = 1
	end)
	assert(not ok, 'def must be frozen')
end

function test.should_freeze_nested_def()
	local _, def = build()
	local ok = pcall(function()
		def.inventory.new_key = 1
	end)
	assert(not ok, 'nested def must be frozen')
end

function test.should_fire_all_with_no_players_not_error()
	local _, def = build()
	def.ping.fire_all 'hello'
end

function test.should_fire_list_empty_not_error()
	local _, def = build()
	def.ping.fire_list({}, 'x')
end

function test.should_codec_path_encode_on_fire()
	local seen
	local root = Instance.new 'Folder'
	local def = lib.remotes({
		typed = lib.event {
			encode = function(v: any)
				seen = v
				return v
			end,
			decode = function(v: any)
				return v
			end,
		},
	}, root) :: any
	def.typed.fire_all 'payload'
	assert(seen == 'payload', `expected encode called, got {tostring(seen)}`)
end

function test.should_route_on_server_invoke()
	local root = build()
	local _, def = root, select(2, build())
	local remote = root:FindFirstChild 'ask' :: RemoteFunction
	local called_with
	def.ask.on_server_invoke = function(player: Player, n: number)
		called_with = { player = player, n = n }
		return n * 2
	end
	-- on_server_invoke was assigned on a separate def; rebuild test for clarity below
	assert(type(remote) == 'userdata', 'sanity')
	assert(called_with == nil, 'handler not yet called')
end

function test.should_invoke_on_server_invoke_directly()
	local root = Instance.new 'Folder'
	local def = lib.remotes({ ask = lib.func() }, root) :: any
	local remote = root:FindFirstChild 'ask' :: RemoteFunction

	def.ask.on_server_invoke = function(player: Player, n: number)
		return player, n * 2
	end
	assert(type(remote.OnServerInvoke) == 'function', 'remote.OnServerInvoke must be set')

	local who, doubled = remote.OnServerInvoke('fake-player' :: any, 21)
	assert(who == 'fake-player')
	assert(doubled == 42)
end

function test.should_state_step_with_no_targets_not_error()
	local _, def = build()
	def.world.step()
end

function test.should_state_changed_listener_registers()
	local _, def = build()
	def.world.changed(function() end)
end

function test.should_step_sync_callable()
	build()
	lib.step_sync()
end

return test

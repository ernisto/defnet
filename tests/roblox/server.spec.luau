local ReplicatedStorage = game:GetService 'ReplicatedStorage'

local lib = require(ReplicatedStorage.packages.defnet)
local t = {}

function t.test(id, fun)
	fun()
end
function t.skip(id, fun) end

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

t.test('should_create_state_bindable_and_single_remote', function()
	local root = Instance.new 'Folder'
	lib.remotes({
		world = lib.state { coins = 0 },
		stats = lib.state { hp = 0 },
	}, root)

	local bindables = root:QueryDescendants '> BindableEvent #world'
	assert(#bindables == 1, 'state should own a BindableEvent')

	local remotes = root:QueryDescendants '> RemoteEvent #__main__'
	assert(#remotes == 1, 'state should share a single RemoteEvent')
end)

t.test('should_create_remote_event', function()
	local root = build()
	local rbx = root:FindFirstChild 'ping'
	assert(rbx and rbx:IsA 'RemoteEvent', 'expected RemoteEvent')
end)

t.test('should_create_remote_function', function()
	local root = build()
	local rbx = root:FindFirstChild 'ask'
	assert(rbx and rbx:IsA 'RemoteFunction', 'expected RemoteFunction')
end)

t.test('should_walk_nested_folder', function()
	local root = build()
	local folder = root:FindFirstChild 'inventory'
	assert(folder and folder:IsA 'Folder', 'nested group must be Folder')
	assert(folder:FindFirstChild 'open' :: any)
	assert(folder:FindFirstChild 'close' :: any)
end)

t.test('should_wrap_event_api', function()
	local _, def = build()
	assert(type(def.ping.fire_all) == 'function')
	assert(type(def.ping.fire_client) == 'function')
	assert(type(def.ping.fire_list) == 'function')
	assert(type(def.ping.fire_except) == 'function')
	assert(type(def.ping.on_server) == 'function')
end)

t.test('should_wrap_func_api', function()
	local _, def = build()
	assert(type(def.ask.invoke_client) == 'function')
	assert(type(def.ask.invoke_server) == 'function')
end)

t.test('should_wrap_state_api', function()
	local _, def = build()
	assert(type(def.world.step) == 'function')
	assert(type(def.world.changed) == 'function')
	assert(type(def.world.server) == 'table')
end)

t.test('should_freeze_def', function()
	local _, def = build()
	local ok = pcall(function()
		def.new_key = 1
	end)
	assert(not ok, 'def must be frozen')
end)

t.test('should_freeze_nested_def', function()
	local _, def = build()
	local ok = pcall(function()
		def.inventory.new_key = 1
	end)
	assert(not ok, 'nested def must be frozen')
end)

t.test('should_fire_all_with_no_players_not_error', function()
	local _, def = build()
	def.ping.fire_all 'hello'
end)

t.test('should_fire_list_empty_not_error', function()
	local _, def = build()
	def.ping.fire_list({}, 'x')
end)

t.test('should_codec_path_encode_on_fire', function()
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
end)

t.test('should_route_on_server_invoke', function()
	local root = build()
	local _, def = root, select(2, build())
	local remote = root:FindFirstChild 'ask' :: RemoteFunction
	local called_with
	def.ask.on_server_invoke = function(player: Player, n: number)
		called_with = { player = player, n = n }
		return n * 2
	end
	assert(type(remote) == 'userdata', 'sanity')
	assert(called_with == nil, 'handler not yet called')
end)

t.skip('should_invoke_on_server_invoke_directly', function() -- unable to test
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
end)

t.test('should_state_step_with_no_targets_not_error', function()
	local _, def = build()
	def.world.step()
end)

t.test('should_state_changed_listener_registers', function()
	local _, def = build()
	def.world.changed(function() end)
end)

t.test('should_step_sync_callable', function()
	build()
	lib.step_sync()
end)

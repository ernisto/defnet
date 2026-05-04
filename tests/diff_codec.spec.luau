local diff_codec = require('../lib/utils/diff_codec').impl

local test = {}

-- helpers
local function empty_node(): any
	return { children = {}, shift_inserts = {}, shift_removes = {}, changes = {}, removes = {} }
end

local function deep_equal(left: any, right: any): boolean
	if left == right then return true end
	if type(left) ~= 'table' or type(right) ~= 'table' then return false end
	for key, value in left do
		if not deep_equal(value, right[key]) then return false end
	end
	for key in right do
		if left[key] == nil then return false end
	end
	return true
end

local function assert_equal(actual: any, expected: any, msg: string?)
	assert(deep_equal(actual, expected), msg or `not equal`)
end

local function roundtrip(node: any)
	local buf, unknowns = diff_codec.encode(node)
	return diff_codec.decode(buf, unknowns), unknowns
end

local function count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- empty
function test.should_roundtrip_empty_node()
	local decoded = roundtrip(empty_node())
	assert(next(decoded.changes) == nil)
	assert(#decoded.removes == 0)
	assert(#decoded.shift_inserts == 0)
	assert(#decoded.shift_removes == 0)
	assert(next(decoded.children) == nil)
end

-- changes
function test.should_roundtrip_scalar_change()
	local node = empty_node()
	node.changes.coins = 42

	local decoded = roundtrip(node)
	assert(decoded.changes.coins == 42)
end

function test.should_roundtrip_multiple_changes()
	local node = empty_node()
	node.changes.a = 1
	node.changes.b = 'two'
	node.changes.c = true

	local decoded = roundtrip(node)
	assert(decoded.changes.a == 1)
	assert(decoded.changes.b == 'two')
	assert(decoded.changes.c == true)
end

function test.should_roundtrip_change_with_table_value()
	local node = empty_node()
	node.changes.stats = { hp = 10, mp = 5 }

	local decoded = roundtrip(node)
	assert_equal(decoded.changes.stats, { hp = 10, mp = 5 })
end

function test.should_preserve_numeric_vs_string_key()
	local node = empty_node()
	node.changes[1] = 'numeric'
	node.changes['1'] = 'string_one'

	local decoded = roundtrip(node)
	assert(decoded.changes[1] == 'numeric')
	assert(decoded.changes['1'] == 'string_one')
end

-- removes
function test.should_roundtrip_removes()
	local node = empty_node()
	node.removes = { 'coins', 'level' }

	local decoded = roundtrip(node)
	assert(#decoded.removes == 2)
	assert(decoded.removes[1] == 'coins')
	assert(decoded.removes[2] == 'level')
end

-- shifts
function test.should_roundtrip_shift_inserts()
	local node = empty_node()
	node.shift_inserts = { { index = 1, value = 'first' }, { index = 3, value = 'third' } }

	local decoded = roundtrip(node)
	assert(#decoded.shift_inserts == 2)
	assert(decoded.shift_inserts[1].index == 1 and decoded.shift_inserts[1].value == 'first')
	assert(decoded.shift_inserts[2].index == 3 and decoded.shift_inserts[2].value == 'third')
end

function test.should_roundtrip_shift_removes()
	local node = empty_node()
	node.shift_removes = { 5, 3 }

	local decoded = roundtrip(node)
	assert(#decoded.shift_removes == 2)
	assert(decoded.shift_removes[1] == 5)
	assert(decoded.shift_removes[2] == 3)
end

-- children (recursion)
function test.should_roundtrip_nested_children()
	local node = empty_node()
	local stats = empty_node()
	stats.changes.hp = 99
	node.children.stats = stats

	local decoded = roundtrip(node)
	assert(decoded.children.stats)
	assert(decoded.children.stats.changes.hp == 99)
end

function test.should_roundtrip_deep_nested_children()
	local node = empty_node()
	local lvl1 = empty_node()
	local lvl2 = empty_node()
	lvl2.changes.deep = true
	lvl1.children.b = lvl2
	node.children.a = lvl1

	local decoded = roundtrip(node)
	assert(decoded.children.a.children.b.changes.deep == true)
end

-- combined
function test.should_roundtrip_combined()
	local node = empty_node()
	node.changes = { coins = 50 }
	node.removes = { 'scratch' }
	node.shift_inserts = { { index = 2, value = 'bow' } }
	node.shift_removes = { 5 }
	local child = empty_node()
	child.changes.hp = 80
	node.children.stats = child

	local decoded = roundtrip(node)
	assert(decoded.changes.coins == 50)
	assert(decoded.removes[1] == 'scratch')
	assert(decoded.shift_inserts[1].value == 'bow')
	assert(decoded.shift_removes[1] == 5)
	assert(decoded.children.stats.changes.hp == 80)
end

-- value types
function test.should_preserve_value_types_in_changes()
	local node = empty_node()
	node.changes.bool = true
	node.changes.vec = vector.create(1, 2, 3)
	node.changes.tab = { nested = 'ok' }
	node.changes.num = 3.14
	node.changes.str = 'hello'
	node.changes.buf = buffer.fromstring 'data'

	local decoded = roundtrip(node)
	assert(decoded.changes.bool == true)
	assert(decoded.changes.vec.x == 1 and decoded.changes.vec.y == 2 and decoded.changes.vec.z == 3)
	assert(decoded.changes.tab.nested == 'ok')
	assert(decoded.changes.num == 3.14)
	assert(decoded.changes.str == 'hello')
	assert(buffer.tostring(decoded.changes.buf) == 'data')
end

-- unknowns side-channel
function test.should_track_unknowns_in_change_value()
	local thread = coroutine.create(function() end)
	local node = empty_node()
	node.changes.ref = thread

	local buf, unknowns = diff_codec.encode(node)
	assert(unknowns and #unknowns == 1 and unknowns[1] == thread)

	local decoded = diff_codec.decode(buf, unknowns)
	assert(decoded.changes.ref == thread)
end

-- identity dedup (cache reuse)
function test.should_dedup_shared_child_node()
	local shared = empty_node()
	shared.changes.x = 1

	local node = empty_node()
	node.children.a = shared
	node.children.b = shared

	local decoded = roundtrip(node)
	assert(decoded.children.a.changes.x == 1)
	assert(decoded.children.b.changes.x == 1)
	assert(decoded.children.a == decoded.children.b, 'shared ref must roundtrip as same instance')
end

function test.should_handle_self_referential_node()
	local node = empty_node()
	node.children.self = node

	local decoded = roundtrip(node)
	assert(decoded.children.self == decoded, 'self-ref must roundtrip as same instance')
end

function test.should_handle_mutually_recursive_nodes()
	local a = empty_node()
	local b = empty_node()
	a.children.b = b
	b.children.a = a

	local decoded = roundtrip(a)
	assert(decoded.children.b.children.a == decoded)
end

-- bitmask sparseness — partial fields skip absent ones
function test.should_roundtrip_only_changes()
	local node = empty_node()
	node.changes.a = 1

	local decoded = roundtrip(node)
	assert(count(decoded.changes) == 1)
	assert(#decoded.removes == 0)
	assert(#decoded.shift_inserts == 0)
	assert(#decoded.shift_removes == 0)
	assert(count(decoded.children) == 0)
end

function test.should_roundtrip_only_removes()
	local node = empty_node()
	node.removes = { 'k' }

	local decoded = roundtrip(node)
	assert(#decoded.removes == 1)
	assert(count(decoded.changes) == 0)
end

function test.should_roundtrip_only_children()
	local node = empty_node()
	local sub = empty_node()
	sub.changes.x = 1
	node.children.k = sub

	local decoded = roundtrip(node)
	assert(decoded.children.k.changes.x == 1)
	assert(count(decoded.changes) == 0)
	assert(#decoded.removes == 0)
end

return test

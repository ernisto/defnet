local test = require '@std/test'

local diff_codec = require '../../lib/utils/diff_codec'

-- helpers
local function empty_node(): any
	return { children = {}, shift_inserts = {}, shift_removes = {}, changes = {}, removes = {} }
end

local function roundtrip(node: any)
	local buf, unknowns = diff_codec.impl.encode(node)
	return diff_codec.impl.decode(buf, nil, unknowns), unknowns
end

local function count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- empty
test.case('should_roundtrip_empty_node', function(t)
	local decoded = roundtrip(empty_node())
	t.eq(next(decoded.changes), nil)
	t.eq(#decoded.removes, 0)
	t.eq(#decoded.shift_inserts, 0)
	t.eq(#decoded.shift_removes, 0)
	t.eq(next(decoded.children), nil)
end)

-- changes
test.case('should_roundtrip_scalar_change', function(t)
	local node = empty_node()
	node.changes.coins = 42

	t.eq(roundtrip(node).changes.coins, 42)
end)

test.case('should_roundtrip_multiple_changes', function(t)
	local node = empty_node()
	node.changes.a = 1
	node.changes.b = 'two'
	node.changes.c = true

	local decoded = roundtrip(node)
	t.eq(decoded.changes.a, 1)
	t.eq(decoded.changes.b, 'two')
	t.eq(decoded.changes.c, true)
end)

test.case('should_roundtrip_change_with_table_value', function(t)
	local node = empty_node()
	node.changes.stats = { hp = 10, mp = 5 }

	t.eq(roundtrip(node).changes.stats, { hp = 10, mp = 5 })
end)

test.case('should_preserve_numeric_vs_string_key', function(t)
	local node = empty_node()
	node.changes[1] = 'numeric'
	node.changes['1'] = 'string_one'

	local decoded = roundtrip(node)
	t.eq(decoded.changes[1], 'numeric')
	t.eq(decoded.changes['1'], 'string_one')
end)

-- removes
test.case('should_roundtrip_removes', function(t)
	local node = empty_node()
	node.removes = { 'coins', 'level' }

	local decoded = roundtrip(node)
	t.eq(#decoded.removes, 2)
	t.eq(decoded.removes[1], 'coins')
	t.eq(decoded.removes[2], 'level')
end)

-- shifts
test.case('should_roundtrip_shift_inserts', function(t)
	local node = empty_node()
	node.shift_inserts = { { index = 1, value = 'first' }, { index = 3, value = 'third' } }

	local decoded = roundtrip(node)
	t.eq(#decoded.shift_inserts, 2)
	t.eq(decoded.shift_inserts[1].index == 1 and decoded.shift_inserts[1].value == 'first', true)
	t.eq(decoded.shift_inserts[2].index == 3 and decoded.shift_inserts[2].value == 'third', true)
end)

test.case('should_roundtrip_shift_removes', function(t)
	local node = empty_node()
	node.shift_removes = { 5, 3 }

	local decoded = roundtrip(node)
	t.eq(#decoded.shift_removes, 2)
	t.eq(decoded.shift_removes[1], 5)
	t.eq(decoded.shift_removes[2], 3)
end)

-- children (recursion)
test.case('should_roundtrip_nested_children', function(t)
	local node = empty_node()
	local stats = empty_node()
	stats.changes.hp = 99
	node.children.stats = stats

	local decoded = roundtrip(node)
	t.that(decoded.children.stats)
	t.eq(decoded.children.stats.changes.hp, 99)
end)

test.case('should_roundtrip_deep_nested_children', function(t)
	local node = empty_node()
	local lvl1 = empty_node()
	local lvl2 = empty_node()
	lvl2.changes.deep = true
	lvl1.children.b = lvl2
	node.children.a = lvl1

	t.eq(roundtrip(node).children.a.children.b.changes.deep, true)
end)

-- combined
test.case('should_roundtrip_combined', function(t)
	local node = empty_node()
	node.changes = { coins = 50 }
	node.removes = { 'scratch' }
	node.shift_inserts = { { index = 2, value = 'bow' } }
	node.shift_removes = { 5 }
	local child = empty_node()
	child.changes.hp = 80
	node.children.stats = child

	local decoded = roundtrip(node)
	t.eq(decoded.changes.coins, 50)
	t.eq(decoded.removes[1], 'scratch')
	t.eq(decoded.shift_inserts[1].value, 'bow')
	t.eq(decoded.shift_removes[1], 5)
	t.eq(decoded.children.stats.changes.hp, 80)
end)

-- value types
test.case('should_preserve_value_types_in_changes', function(t)
	local node = empty_node()
	node.changes.bool = true
	node.changes.vec = vector.create(1, 2, 3)
	node.changes.tab = { nested = 'ok' }
	node.changes.num = 3.14
	node.changes.str = 'hello'
	node.changes.buf = buffer.fromstring 'data'

	local decoded = roundtrip(node)
	t.eq(decoded.changes.bool, true)
	t.eq(decoded.changes.vec.x == 1 and decoded.changes.vec.y == 2 and decoded.changes.vec.z == 3, true)
	t.eq(decoded.changes.tab.nested, 'ok')
	t.eq(decoded.changes.num, 3.14)
	t.eq(decoded.changes.str, 'hello')
	t.eq(buffer.tostring(decoded.changes.buf), 'data')
end)

-- unknowns side-channel
test.case('should_track_unknowns_in_change_value', function(t)
	local thread = coroutine.create(function() end)
	local node = empty_node()
	node.changes.ref = thread

	local buf, unknowns = diff_codec.impl.encode(node)
	t.eq(unknowns and #unknowns, 1)
	t.eq(unknowns[1], thread)

	t.eq(diff_codec.impl.decode(buf, nil, unknowns).changes.ref, thread)
end)

-- identity dedup (cache reuse)
test.case('should_dedup_shared_child_node', function(t)
	local shared = empty_node()
	shared.changes.x = 1

	local node = empty_node()
	node.children.a = shared
	node.children.b = shared

	local decoded = roundtrip(node)
	t.eq(decoded.children.a.changes.x, 1)
	t.eq(decoded.children.b.changes.x, 1)
	t.eq(decoded.children.a, decoded.children.b, 'shared ref must roundtrip as same instance')
end)

test.case('should_handle_self_referential_node', function(t)
	local node = empty_node()
	node.children.self = node

	local decoded = roundtrip(node)
	t.eq(decoded.children.self, decoded, 'self-ref must roundtrip as same instance')
end)

test.case('should_handle_mutually_recursive_nodes', function(t)
	local a = empty_node()
	local b = empty_node()
	a.children.b = b
	b.children.a = a

	local decoded = roundtrip(a)
	t.eq(decoded.children.b.children.a, decoded)
end)

-- bitmask sparseness — partial fields skip absent ones
test.case('should_roundtrip_only_changes', function(t)
	local node = empty_node()
	node.changes.a = 1

	local decoded = roundtrip(node)
	t.eq(count(decoded.changes), 1)
	t.eq(#decoded.removes, 0)
	t.eq(#decoded.shift_inserts, 0)
	t.eq(#decoded.shift_removes, 0)
	t.eq(count(decoded.children), 0)
end)

test.case('should_roundtrip_only_removes', function(t)
	local node = empty_node()
	node.removes = { 'k' }

	local decoded = roundtrip(node)
	t.eq(#decoded.removes, 1)
	t.eq(count(decoded.changes), 0)
end)

test.case('should_roundtrip_only_children', function(t)
	local node = empty_node()
	local sub = empty_node()
	sub.changes.x = 1
	node.children.k = sub

	local decoded = roundtrip(node)
	t.eq(decoded.children.k.changes.x, 1)
	t.eq(count(decoded.changes), 0)
	t.eq(#decoded.removes, 0)
end)

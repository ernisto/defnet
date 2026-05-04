local diff = require '../lib/utils/diff'

local test = {}

-- helpers
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
	assert(deep_equal(actual, expected), msg or `not equal: {tostring(actual)} vs {tostring(expected)}`)
end

local function count(map: { [any]: any }): number
	local total = 0
	for _ in map do
		total += 1
	end
	return total
end

local function is_empty(node: any): boolean
	return next(node.changes) == nil
		and #node.removes == 0
		and #node.shift_inserts == 0
		and #node.shift_removes == 0
		and next(node.children) == nil
end

local function roundtrip(prev: any, curr: any)
	local node = diff.from(prev, curr)
	local applied = diff.snapshot(prev)
	diff.apply(applied, node)
	assert_equal(applied, curr, 'roundtrip mismatch')
	return node
end

-- snapshot
function test.should_snapshot_independent()
	local source = { coins = 10, stats = { hp = 5 }, items = { 1, 2, 3 } }
	local copy = diff.snapshot(source)

	assert_equal(copy, source)

	copy.stats.hp = 99
	copy.items[1] = 99

	assert(source.stats.hp == 5 and source.items[1] == 1, 'snapshot mutation leaked into source')
end

function test.should_snapshot_frozen_root_into_mutable()
	local source = table.freeze { a = 1, b = 2 }
	local copy = diff.snapshot(source)

	assert_equal(copy, source)
	assert(not table.isfrozen(copy), 'snapshot must be mutable')

	copy.a = 99
	assert(source.a == 1, 'snapshot mutation leaked into frozen source')
end

function test.should_snapshot_frozen_subtables_into_mutable()
	local source = table.freeze {
		stats = table.freeze { hp = 1 },
		items = table.freeze { 1, 2 },
	}
	local copy = diff.snapshot(source)

	assert(not table.isfrozen(copy.stats))
	assert(not table.isfrozen(copy.items))

	copy.stats.hp = 99
	copy.items[1] = 99

	assert(source.stats.hp == 1 and source.items[1] == 1)
end

-- from: empty / equal
function test.should_emit_empty_node_when_equal()
	local node = diff.from({ a = 1, b = 2 }, { a = 1, b = 2 })
	assert(is_empty(node), 'expected empty node')
end

function test.should_emit_empty_node_for_two_empties()
	local node = diff.from({}, {})
	assert(is_empty(node))
end

-- from: hash
function test.should_emit_change_on_scalar_differ()
	local node = diff.from({ a = 1 }, { a = 2 })
	assert(count(node.changes) == 1)
	assert(node.changes.a == 2)
end

function test.should_emit_change_on_new_key()
	local node = diff.from({}, { coins = 10 })
	assert(count(node.changes) == 1)
	assert(node.changes.coins == 10)
end

function test.should_emit_remove_on_missing_key()
	local node = diff.from({ a = 1, b = 2 }, { a = 1 })
	assert(#node.removes == 1)
	assert(node.removes[1] == 'b')
end

-- from: nested via children
function test.should_recurse_via_children_on_nested_table()
	local node = diff.from({ stats = { hp = 10, mp = 5 } }, { stats = { hp = 10, mp = 8 } })

	local stats = node.children.stats
	assert(stats, 'expected children.stats')
	assert(count(stats.changes) == 1)
	assert(stats.changes.mp == 8)
end

function test.should_emit_nested_remove_via_children()
	local node = diff.from({ inv = { sword = 1, shield = 1 } }, { inv = { sword = 1 } })

	local inv = node.children.inv
	assert(inv, 'expected children.inv')
	assert(#inv.removes == 1)
	assert(inv.removes[1] == 'shield')
end

function test.should_skip_children_entry_when_subtree_equal()
	local node = diff.from({ stats = { hp = 1 } }, { stats = { hp = 1 } })
	assert(next(node.children) == nil, 'equal subtrees must not create child entries')
end

-- from: arrays
function test.should_emit_change_for_same_length_array()
	local node = diff.from({ 1, 2, 3 }, { 1, 9, 3 })
	assert(count(node.changes) == 1)
	assert(node.changes[2] == 9)
end

function test.should_recurse_into_array_element_via_children()
	local node = diff.from({ { hp = 10 }, { hp = 20 } }, { { hp = 10 }, { hp = 30 } })

	local element = node.children[2]
	assert(element, 'expected children[2]')
	assert(count(element.changes) == 1)
	assert(element.changes.hp == 30)
end

function test.should_emit_shift_insertion_middle()
	local node = diff.from({ 'a', 'b', 'c' }, { 'a', 'x', 'b', 'c' })
	assert(#node.shift_inserts == 1)
	assert(node.shift_inserts[1].index == 2 and node.shift_inserts[1].value == 'x')
end

function test.should_emit_shift_insertion_end_in_ascending_order()
	local node = diff.from({ 1, 2 }, { 1, 2, 3, 4 })
	assert(#node.shift_inserts == 2)
	assert(node.shift_inserts[1].index == 3 and node.shift_inserts[1].value == 3)
	assert(node.shift_inserts[2].index == 4 and node.shift_inserts[2].value == 4)
end

function test.should_emit_shift_removal_middle_in_descending_order()
	local node = diff.from({ 'a', 'b', 'c', 'd' }, { 'a', 'd' })
	assert(#node.shift_removes == 2)
	assert(node.shift_removes[1] == 3)
	assert(node.shift_removes[2] == 2)
end

function test.should_emit_shift_removal_tail()
	local node = diff.from({ 1, 2, 3 }, { 1 })
	assert(#node.shift_removes == 2)
	assert(node.shift_removes[1] == 3)
	assert(node.shift_removes[2] == 2)
end

-- apply: changes / removes
function test.should_apply_change_to_root_key()
	local state = { coins = 10 }
	diff.apply(state, {
		children = {},
		changes = { coins = 42 },
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})
	assert(state.coins == 42)
end

function test.should_apply_remove_at_root()
	local state = { a = 1, b = 2 }
	diff.apply(state, {
		children = {},
		changes = {},
		removes = { 'b' },
		shift_inserts = {},
		shift_removes = {},
	})
	assert(state.a == 1 and state.b == nil)
end

function test.should_apply_change_with_table_value_replacing_scalar()
	local state = { x = 1 }
	diff.apply(state, {
		children = {},
		changes = { x = { nested = true } },
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})
	assert(type(state.x) == 'table' and state.x.nested == true)
end

-- apply: nested via children
function test.should_apply_nested_via_children()
	local state = { stats = { hp = 10, mp = 5 } }
	diff.apply(state, {
		children = {
			stats = {
				children = {},
				changes = { mp = 99 },
				removes = {},
				shift_inserts = {},
				shift_removes = {},
			},
		},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})
	assert(state.stats.hp == 10 and state.stats.mp == 99)
end

function test.should_apply_nested_creating_missing_parent()
	local state: any = {}
	diff.apply(state, {
		children = {
			stats = {
				children = {},
				changes = { hp = 100 },
				removes = {},
				shift_inserts = {},
				shift_removes = {},
			},
		},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})
	assert(state.stats.hp == 100)
end

-- apply: shifts
function test.should_apply_shift_insertion_at_root()
	local state = { 'a', 'b', 'c' }
	diff.apply(state, {
		children = {},
		changes = {},
		removes = {},
		shift_inserts = { { index = 2, value = 'x' } },
		shift_removes = {},
	})
	assert_equal(state, { 'a', 'x', 'b', 'c' })
end

function test.should_apply_multiple_shift_insertions_in_order()
	local state = { 'a', 'b' }
	diff.apply(state, {
		children = {},
		changes = {},
		removes = {},
		shift_inserts = { { index = 3, value = 'c' }, { index = 4, value = 'd' } },
		shift_removes = {},
	})
	assert_equal(state, { 'a', 'b', 'c', 'd' })
end

function test.should_apply_shift_removal_at_root()
	local state = { 'a', 'b', 'c', 'd' }
	diff.apply(state, {
		children = {},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = { 3, 2 },
	})
	assert_equal(state, { 'a', 'd' })
end

function test.should_apply_shift_via_children_path()
	local state = { items = { 'a', 'c' } }
	diff.apply(state, {
		children = {
			items = {
				children = {},
				changes = {},
				removes = {},
				shift_inserts = { { index = 2, value = 'b' } },
				shift_removes = {},
			},
		},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})
	assert_equal(state.items, { 'a', 'b', 'c' })
end

-- apply: combined / no-op
function test.should_apply_combined_diff()
	local state = { coins = 10, inv = { 'sword', 'shield' }, scratch = 1 }
	diff.apply(state, {
		children = {
			inv = {
				children = {},
				changes = {},
				removes = {},
				shift_inserts = { { index = 2, value = 'bow' } },
				shift_removes = { 3 },
			},
		},
		changes = { coins = 50 },
		removes = { 'scratch' },
		shift_inserts = {},
		shift_removes = {},
	})

	assert(state.coins == 50)
	assert(state.scratch == nil)
	assert_equal(state.inv, { 'sword', 'bow' })
end

function test.should_apply_no_op_on_empty_node()
	local state = { a = 1, b = { c = 2 }, arr = { 1, 2, 3 } }
	local before = diff.snapshot(state)

	diff.apply(state, {
		children = {},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})

	assert_equal(state, before)
end

-- apply: frozen subtables (copy-on-write)
function test.should_apply_change_on_frozen_subtable()
	local original = table.freeze { hp = 10, mp = 5 }
	local state = { stats = original }

	diff.apply(state, {
		children = {
			stats = {
				children = {},
				changes = { hp = 99 },
				removes = {},
				shift_inserts = {},
				shift_removes = {},
			},
		},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})

	assert(state.stats.hp == 99 and state.stats.mp == 5)
	assert(original.hp == 10, 'frozen original must be untouched')
	assert(state.stats ~= original, 'frozen subtable must be replaced with mutable clone')
end

function test.should_apply_shift_on_frozen_nested_array()
	local original = table.freeze { 'a', 'c' }
	local state = { items = original }

	diff.apply(state, {
		children = {
			items = {
				children = {},
				changes = {},
				removes = {},
				shift_inserts = { { index = 2, value = 'b' } },
				shift_removes = {},
			},
		},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})

	assert_equal(state.items, { 'a', 'b', 'c' })
	assert_equal(original, { 'a', 'c' })
end

function test.should_error_on_frozen_root()
	local state = table.freeze { coins = 10 }

	local ok = pcall(diff.apply, state, {
		children = {},
		changes = { coins = 42 },
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})

	assert(not ok, 'apply must error on frozen root')
end

-- roundtrip integration
function test.should_roundtrip_scalar_change()
	roundtrip({ a = 1, b = 2 }, { a = 1, b = 99 })
end

function test.should_roundtrip_add_and_remove_keys()
	roundtrip({ a = 1, b = 2 }, { a = 1, c = 3 })
end

function test.should_roundtrip_nested_hash()
	roundtrip({ stats = { hp = 10, mp = 5 }, coins = 3 }, { stats = { hp = 15 }, coins = 3 })
end

function test.should_roundtrip_array_insert_middle()
	roundtrip({ 'a', 'b', 'c' }, { 'a', 'x', 'b', 'c' })
end

function test.should_roundtrip_array_insert_end()
	roundtrip({ 1, 2 }, { 1, 2, 3, 4 })
end

function test.should_roundtrip_array_remove_middle()
	roundtrip({ 1, 2, 3, 4, 5 }, { 1, 5 })
end

function test.should_roundtrip_array_remove_tail()
	roundtrip({ 1, 2, 3 }, { 1 })
end

function test.should_roundtrip_array_replace_same_length()
	roundtrip({ 1, 2, 3 }, { 1, 9, 3 })
end

function test.should_roundtrip_array_of_tables()
	roundtrip(
		{ { name = 'a', lvl = 1 }, { name = 'b', lvl = 2 } },
		{ { name = 'a', lvl = 1 }, { name = 'c', lvl = 3 } }
	)
end

function test.should_roundtrip_empty_to_populated()
	roundtrip({}, { coins = 10, items = { 'sword' } })
end

function test.should_roundtrip_populated_to_empty_hash()
	roundtrip({ a = 1, b = 2 }, {})
end

function test.should_roundtrip_mixed_deep()
	roundtrip(
		{ coins = 100, stats = { hp = 10 }, items = { 'a', 'b' } },
		{ coins = 50, stats = { hp = 20, mp = 5 }, items = { 'a', 'x', 'b' } }
	)
end

function test.should_roundtrip_nested_array_mutation()
	roundtrip({ teams = { { 1, 2 }, { 3, 4 } } }, { teams = { { 1, 2 }, { 3, 4, 5 } } })
end

return test

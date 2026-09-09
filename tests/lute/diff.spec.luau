local test = require '@std/test'

local diff = require '../../lib/utils/diff'

-- helpers
local function count(map: { [any]: any }): number
	local total = 0
	for _ in map do
		total += 1
	end
	return total
end

local function roundtrip(t, prev: any, curr: any)
	local node = diff.from(prev, curr)

	local applied = diff.snapshot(prev)
	diff.apply(applied, node)
	t.eq(applied, curr, 'roundtrip mismatch')
	return node
end

-- snapshot
test.case('should_snapshot_independent', function(t)
	local source = { coins = 10, stats = { hp = 5 }, items = { 1, 2, 3 } }
	local copy = diff.snapshot(source)

	t.eq(copy, source)

	copy.stats.hp = 99
	copy.items[1] = 99

	t.eq(source.stats.hp == 5 and source.items[1] == 1, true, 'snapshot mutation leaked into source')
end)

test.case('should_snapshot_frozen_root_into_mutable', function(t)
	local source = table.freeze { a = 1, b = 2 }
	local copy = diff.snapshot(source)

	t.eq(copy, source)
	t.eq(table.isfrozen(copy), true, 'snapshot preserves frozen root')
	t.eq(source.a, 1)
end)

test.case('should_snapshot_frozen_subtables_into_mutable', function(t)
	local source = table.freeze {
		stats = table.freeze { hp = 1 },
		items = table.freeze { 1, 2 },
	}
	local copy = diff.snapshot(source)

	t.eq(table.isfrozen(copy.stats), true, 'snapshot preserves frozen subtables')
	t.eq(table.isfrozen(copy.items), true)
	t.eq(copy.stats, { hp = 1 })
	t.eq(copy.items, { 1, 2 })
	t.eq(source.stats.hp == 1 and source.items[1] == 1, true)
end)

-- from: empty / equal
test.case('should_return_nil_node_when_equal', function(t)
	t.eq(diff.from({ a = 1, b = 2 }, { a = 1, b = 2 }), nil)
end)

test.case('should_return_nil_node_for_two_empties', function(t)
	t.eq(diff.from({}, {}), nil)
end)

-- from: hash
test.case('should_emit_change_on_scalar_differ', function(t)
	local node = diff.from({ a = 1 }, { a = 2 })
	t.that(node)
	t.eq(count(node.changes), 1)
	t.eq(node.changes.a, 2)
end)

test.case('should_emit_change_on_new_key', function(t)
	local node = diff.from({}, { coins = 10 })
	t.that(node)
	t.eq(count(node.changes), 1)
	t.eq(node.changes.coins, 10)
end)

test.case('should_emit_remove_on_missing_key', function(t)
	local node = diff.from({ a = 1, b = 2 }, { a = 1 })
	t.that(node)
	t.eq(#node.removes, 1)
	t.eq(node.removes[1], 'b')
end)

-- from: nested via children
test.case('should_recurse_via_children_on_nested_table', function(t)
	local node = diff.from({ stats = { hp = 10, mp = 5 } }, { stats = { hp = 10, mp = 8 } })
	t.that(node)

	local stats = node.children.stats
	t.that(stats, 'expected children.stats')
	t.eq(count(stats.changes), 1)
	t.eq(stats.changes.mp, 8)
end)

test.case('should_emit_nested_remove_via_children', function(t)
	local node = diff.from({ inv = { sword = 1, shield = 1 } }, { inv = { sword = 1 } })
	t.that(node)

	local inv = node.children.inv
	t.that(inv, 'expected children.inv')
	t.eq(#inv.removes, 1)
	t.eq(inv.removes[1], 'shield')
end)

test.case('should_skip_children_entry_when_subtree_equal', function(t)
	t.eq(diff.from({ stats = { hp = 1 } }, { stats = { hp = 1 } }), nil, 'equal subtrees yield nil node')
end)

-- from: arrays
test.case('should_emit_change_for_same_length_array', function(t)
	local node = diff.from({ 1, 2, 3 }, { 1, 9, 3 })
	t.that(node)
	t.eq(count(node.changes), 1)
	t.eq(node.changes[2], 9)
end)

test.case('should_recurse_into_array_element_via_children', function(t)
	local node = diff.from({ { hp = 10 }, { hp = 20 } }, { { hp = 10 }, { hp = 30 } })
	t.that(node)

	local element = node.children[2]
	t.that(element, 'expected children[2]')
	t.eq(count(element.changes), 1)
	t.eq(element.changes.hp, 30)
end)

test.case('should_emit_shift_insertion_middle', function(t)
	local node = diff.from({ 'a', 'b', 'c' }, { 'a', 'x', 'b', 'c' })
	t.that(node)
	t.eq(#node.shift_inserts, 1)
	t.eq(node.shift_inserts[1].index == 2 and node.shift_inserts[1].value == 'x', true)
end)

test.case('should_emit_shift_insertion_end_in_ascending_order', function(t)
	local node = diff.from({ 1, 2 }, { 1, 2, 3, 4 })
	t.that(node)
	t.eq(#node.shift_inserts, 2)
	t.eq(node.shift_inserts[1].index == 3 and node.shift_inserts[1].value == 3, true)
	t.eq(node.shift_inserts[2].index == 4 and node.shift_inserts[2].value == 4, true)
end)

test.case('should_emit_shift_removal_middle_in_descending_order', function(t)
	local node = diff.from({ 'a', 'b', 'c', 'd' }, { 'a', 'd' })
	t.that(node)
	t.eq(#node.shift_removes, 2)
	t.eq(node.shift_removes[1], 3)
	t.eq(node.shift_removes[2], 2)
end)

test.case('should_emit_shift_removal_tail', function(t)
	local node = diff.from({ 1, 2, 3 }, { 1 })
	t.that(node)
	t.eq(#node.shift_removes, 2)
	t.eq(node.shift_removes[1], 3)
	t.eq(node.shift_removes[2], 2)
end)

-- apply: changes / removes
test.case('should_apply_change_to_root_key', function(t)
	local state = { coins = 10 }
	diff.apply(state, {
		children = {},
		changes = { coins = 42 },
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})
	t.eq(state.coins, 42)
end)

test.case('should_apply_remove_at_root', function(t)
	local state = { a = 1, b = 2 }
	diff.apply(state, {
		children = {},
		changes = {},
		removes = { 'b' },
		shift_inserts = {},
		shift_removes = {},
	})
	t.eq(state.a == 1 and state.b == nil, true)
end)

test.case('should_apply_change_with_table_value_replacing_scalar', function(t)
	local state = { x = 1 }
	diff.apply(state, {
		children = {},
		changes = { x = { nested = true } },
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})
	t.eq(type(state.x) == 'table' and state.x.nested == true, true)
end)

-- apply: nested via children
test.case('should_apply_nested_via_children', function(t)
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
	t.eq(state.stats.hp == 10 and state.stats.mp == 99, true)
end)

test.case('should_apply_nested_creating_missing_parent', function(t)
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
	t.eq(state.stats.hp, 100)
end)

-- apply: shifts
test.case('should_apply_shift_insertion_at_root', function(t)
	local state = { 'a', 'b', 'c' }
	diff.apply(state, {
		children = {},
		changes = {},
		removes = {},
		shift_inserts = { { index = 2, value = 'x' } },
		shift_removes = {},
	})
	t.eq(state, { 'a', 'x', 'b', 'c' })
end)

test.case('should_apply_multiple_shift_insertions_in_order', function(t)
	local state = { 'a', 'b' }
	diff.apply(state, {
		children = {},
		changes = {},
		removes = {},
		shift_inserts = { { index = 3, value = 'c' }, { index = 4, value = 'd' } },
		shift_removes = {},
	})
	t.eq(state, { 'a', 'b', 'c', 'd' })
end)

test.case('should_apply_shift_removal_at_root', function(t)
	local state = { 'a', 'b', 'c', 'd' }
	diff.apply(state, {
		children = {},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = { 3, 2 },
	})
	t.eq(state, { 'a', 'd' })
end)

test.case('should_apply_shift_via_children_path', function(t)
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
	t.eq(state.items, { 'a', 'b', 'c' })
end)

-- apply: combined / no-op
test.case('should_apply_combined_diff', function(t)
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

	t.eq(state.coins, 50)
	t.eq(state.scratch, nil)
	t.eq(state.inv, { 'sword', 'bow' })
end)

test.case('should_apply_no_op_on_empty_node', function(t)
	local state = { a = 1, b = { c = 2 }, arr = { 1, 2, 3 } }
	local before = diff.snapshot(state)

	diff.apply(state, {
		children = {},
		changes = {},
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})

	t.eq(state, before)
end)

-- apply: frozen subtables (copy-on-write)
test.case('should_apply_change_on_frozen_subtable', function(t)
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

	t.eq(state.stats.hp == 99 and state.stats.mp == 5, true)
	t.eq(original.hp, 10, 'frozen original must be untouched')
	t.eq(state.stats ~= original, true, 'frozen subtable must be replaced with mutable clone')
end)

test.case('should_apply_shift_on_frozen_nested_array', function(t)
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

	t.eq(state.items, { 'a', 'b', 'c' })
	t.eq(original, { 'a', 'c' })
end)

test.case('should_error_on_frozen_root', function(t)
	local state = table.freeze { coins = 10 }

	t.throws(diff.apply, state, {
		children = {},
		changes = { coins = 42 },
		removes = {},
		shift_inserts = {},
		shift_removes = {},
	})
end)

-- roundtrip integration
test.case('should_roundtrip_scalar_change', function(t)
	roundtrip(t, { a = 1, b = 2 }, { a = 1, b = 99 })
end)

test.case('should_roundtrip_add_and_remove_keys', function(t)
	roundtrip(t, { a = 1, b = 2 }, { a = 1, c = 3 })
end)

test.case('should_roundtrip_nested_hash', function(t)
	roundtrip(t, { stats = { hp = 10, mp = 5 }, coins = 3 }, { stats = { hp = 15 }, coins = 3 })
end)

test.case('should_roundtrip_array_insert_middle', function(t)
	roundtrip(t, { 'a', 'b', 'c' }, { 'a', 'x', 'b', 'c' })
end)

test.case('should_roundtrip_array_insert_end', function(t)
	roundtrip(t, { 1, 2 }, { 1, 2, 3, 4 })
end)

test.case('should_roundtrip_array_remove_middle', function(t)
	roundtrip(t, { 1, 2, 3, 4, 5 }, { 1, 5 })
end)

test.case('should_roundtrip_array_remove_tail', function(t)
	roundtrip(t, { 1, 2, 3 }, { 1 })
end)

test.case('should_roundtrip_array_replace_same_length', function(t)
	roundtrip(t, { 1, 2, 3 }, { 1, 9, 3 })
end)

test.case('should_roundtrip_array_of_tables', function(t)
	roundtrip(
		t,
		{ { name = 'a', lvl = 1 }, { name = 'b', lvl = 2 } },
		{ { name = 'a', lvl = 1 }, { name = 'c', lvl = 3 } }
	)
end)

test.case('should_roundtrip_empty_to_populated', function(t)
	roundtrip(t, {}, { coins = 10, items = { 'sword' } })
end)

test.case('should_roundtrip_populated_to_empty_hash', function(t)
	roundtrip(t, { a = 1, b = 2 }, {})
end)

test.case('should_roundtrip_mixed_deep', function(t)
	roundtrip(
		t,
		{ coins = 100, stats = { hp = 10 }, items = { 'a', 'b' } },
		{ coins = 50, stats = { hp = 20, mp = 5 }, items = { 'a', 'x', 'b' } }
	)
end)

test.case('should_roundtrip_nested_array_mutation', function(t)
	roundtrip(t, { teams = { { 1, 2 }, { 3, 4 } } }, { teams = { { 1, 2 }, { 3, 4, 5 } } })
end)

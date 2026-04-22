local diff = require '../lib/utils/diff'

local test = {}

local function assert_equal(a: any, b: any, msg: string?)
	assert(diff.equal(a, b), msg or `not equal: {tostring(a)} vs {tostring(b)}`)
end

local empty = { changes = {}, removes = {}, shift_insertions = {}, shift_removes = {} }
local function make(partial: any): any
	local d = table.clone(empty)
	for k, v in partial do
		d[k] = v
	end
	return d
end

local function roundtrip(prev: any, curr: any)
	local d = diff.compute(prev, curr)
	local applied = diff.clone(prev)
	diff.apply(applied, d)
	assert_equal(applied, curr, 'roundtrip mismatch')
	return d
end

-- equal
function test.should_equal_primitives()
	assert(diff.equal(1, 1))
	assert(diff.equal('x', 'x'))
	assert(not diff.equal(1, 2))
	assert(not diff.equal(1, '1'))
end

function test.should_equal_nested_tables()
	assert(diff.equal({ a = { b = 1 } }, { a = { b = 1 } }))
	assert(not diff.equal({ a = { b = 1 } }, { a = { b = 2 } }))
end

function test.should_detect_extra_key()
	assert(not diff.equal({ a = 1 }, { a = 1, b = 2 }))
	assert(not diff.equal({ a = 1, b = 2 }, { a = 1 }))
end

-- clone
function test.should_clone_independent()
	local src = { a = { b = 1 }, list = { 1, 2, 3 } }
	local dst = diff.clone(src)
	assert(diff.equal(src, dst))
	dst.a.b = 99
	dst.list[1] = 99
	assert(src.a.b == 1 and src.list[1] == 1, 'mutation leaked')
end

function test.should_clone_frozen_root()
	local src = table.freeze { a = 1, b = 2 }
	local dst = diff.clone(src)
	assert(diff.equal(src, dst))
	assert(not table.isfrozen(dst), 'clone must be mutable')
	dst.a = 99
	assert(src.a == 1, 'mutation leaked to frozen src')
end

function test.should_clone_frozen_nested()
	local src = table.freeze {
		a = table.freeze { b = 1 },
		list = table.freeze { 1, 2, 3 },
	}
	local dst = diff.clone(src)
	assert(diff.equal(src, dst))
	assert(not table.isfrozen(dst))
	assert(not table.isfrozen(dst.a))
	assert(not table.isfrozen(dst.list))
	dst.a.b = 99
	dst.list[1] = 99
	assert(src.a.b == 1 and src.list[1] == 1, 'mutation leaked')
end

-- compute: empty / equal
function test.should_emit_empty_diff_when_equal()
	local d = diff.compute({ a = 1, b = 2 }, { a = 1, b = 2 })
	assert(not diff.has_any(d), 'expected empty diff')
end

function test.should_treat_empty_as_hash()
	local d = diff.compute({}, {})
	assert(not diff.has_any(d))
end

-- compute: hash basics
function test.should_emit_change_on_scalar_differ()
	local d = diff.compute({ a = 1 }, { a = 2 })
	assert(#d.changes == 1)
	assert(d.changes[1].path[1] == 'a')
	assert(d.changes[1].value == 2)
end

function test.should_emit_change_on_new_key()
	local d = diff.compute({}, { coins = 10 })
	assert(#d.changes == 1)
	assert(d.changes[1].path[1] == 'coins')
	assert(d.changes[1].value == 10)
end

function test.should_emit_remove_on_missing_key()
	local d = diff.compute({ a = 1, b = 2 }, { a = 1 })
	assert(#d.removes == 1)
	assert(d.removes[1].path[1] == 'b')
end

-- compute: nested
function test.should_recurse_into_nested_tables()
	local d = diff.compute({ stats = { hp = 10, mp = 5 } }, { stats = { hp = 10, mp = 8 } })
	assert(#d.changes == 1)
	assert(d.changes[1].path[1] == 'stats' and d.changes[1].path[2] == 'mp')
	assert(d.changes[1].value == 8)
end

function test.should_emit_nested_remove()
	local d = diff.compute({ inv = { sword = 1, shield = 1 } }, { inv = { sword = 1 } })
	assert(#d.removes == 1)
	assert(d.removes[1].path[1] == 'inv' and d.removes[1].path[2] == 'shield')
end

-- compute: arrays
function test.should_emit_change_for_same_length_array()
	local d = diff.compute({ 1, 2, 3 }, { 1, 9, 3 })
	assert(#d.changes == 1)
	assert(d.changes[1].path[1] == 2 and d.changes[1].value == 9)
end

function test.should_recurse_into_array_elements()
	local d = diff.compute({ { hp = 10 }, { hp = 20 } }, { { hp = 10 }, { hp = 30 } })
	assert(#d.changes == 1)
	assert(d.changes[1].path[1] == 2 and d.changes[1].path[2] == 'hp')
	assert(d.changes[1].value == 30)
end

function test.should_emit_shift_insertion_middle()
	local d = diff.compute({ 'a', 'b', 'c' }, { 'a', 'x', 'b', 'c' })
	assert(#d.shift_insertions == 1)
	assert(d.shift_insertions[1].index == 2 and d.shift_insertions[1].value == 'x')
end

function test.should_emit_shift_insertion_end()
	local d = diff.compute({ 1, 2 }, { 1, 2, 3, 4 })
	assert(#d.shift_insertions == 2)
	assert(d.shift_insertions[1].index == 3 and d.shift_insertions[1].value == 3)
	assert(d.shift_insertions[2].index == 4 and d.shift_insertions[2].value == 4)
end

function test.should_emit_shift_removal_middle()
	local d = diff.compute({ 'a', 'b', 'c', 'd' }, { 'a', 'd' })
	assert(#d.shift_removes == 2)
	assert(d.shift_removes[1].index == 3)
	assert(d.shift_removes[2].index == 2)
end

function test.should_emit_shift_removal_tail()
	local d = diff.compute({ 1, 2, 3 }, { 1 })
	assert(#d.shift_removes == 2)
	assert(d.shift_removes[1].index == 3)
	assert(d.shift_removes[2].index == 2)
end

-- apply: changes
function test.should_apply_change_to_root_key()
	local t = { coins = 10 }
	diff.apply(t, make { changes = { { path = { 'coins' }, value = 42 } } })
	assert(t.coins == 42)
end

function test.should_apply_change_to_nested_key()
	local t = { stats = { hp = 10, mp = 5 } }
	diff.apply(t, make { changes = { { path = { 'stats', 'mp' }, value = 99 } } })
	assert(t.stats.hp == 10 and t.stats.mp == 99)
end

function test.should_apply_change_creating_missing_parents()
	local t: any = {}
	diff.apply(t, make { changes = { { path = { 'stats', 'hp' }, value = 100 } } })
	assert(t.stats.hp == 100)
end

function test.should_apply_change_with_table_value_replacing_scalar()
	local t = { x = 1 }
	diff.apply(t, make { changes = { { path = { 'x' }, value = { nested = true } } } })
	assert(type(t.x) == 'table' and t.x.nested == true)
end

-- apply: removes
function test.should_apply_remove()
	local t = { a = 1, b = 2 }
	diff.apply(t, make { removes = { { path = { 'b' } } } })
	assert(t.a == 1 and t.b == nil)
end

function test.should_apply_nested_remove()
	local t = { inv = { sword = 1, shield = 1 } }
	diff.apply(t, make { removes = { { path = { 'inv', 'shield' } } } })
	assert(t.inv.sword == 1 and t.inv.shield == nil)
end

-- apply: shifts
function test.should_apply_shift_insertion_middle()
	local t = { 'a', 'b', 'c' }
	diff.apply(t, make { shift_insertions = { { path = {}, index = 2, value = 'x' } } })
	assert_equal(t, { 'a', 'x', 'b', 'c' })
end

function test.should_apply_shift_insertion_nested_path()
	local t = { items = { 'a', 'c' } }
	diff.apply(t, make { shift_insertions = { { path = { 'items' }, index = 2, value = 'b' } } })
	assert_equal(t.items, { 'a', 'b', 'c' })
end

function test.should_apply_multiple_shift_insertions_in_order()
	local t = { 'a', 'b' }
	diff.apply(
		t,
		make {
			shift_insertions = {
				{ path = {}, index = 3, value = 'c' },
				{ path = {}, index = 4, value = 'd' },
			},
		}
	)
	assert_equal(t, { 'a', 'b', 'c', 'd' })
end

function test.should_apply_shift_removal()
	local t = { 'a', 'b', 'c', 'd' }
	diff.apply(
		t,
		make {
			shift_removes = {
				{ path = {}, index = 3 },
				{ path = {}, index = 2 },
			},
		}
	)
	assert_equal(t, { 'a', 'd' })
end

function test.should_apply_shift_removal_nested_path()
	local t = { items = { 'a', 'b', 'c' } }
	diff.apply(t, make { shift_removes = { { path = { 'items' }, index = 2 } } })
	assert_equal(t.items, { 'a', 'c' })
end

-- apply: combined / edge
function test.should_apply_combined_diff_in_defined_order()
	local t = { coins = 10, inv = { 'sword', 'shield' }, scratch = 1 }
	diff.apply(
		t,
		make {
			changes = { { path = { 'coins' }, value = 50 } },
			removes = { { path = { 'scratch' } } },
			shift_insertions = { { path = { 'inv' }, index = 2, value = 'bow' } },
			shift_removes = { { path = { 'inv' }, index = 3 } },
		}
	)
	assert(t.coins == 50)
	assert(t.scratch == nil)
	assert_equal(t.inv, { 'sword', 'bow' })
end

function test.should_apply_no_op_on_empty_diff()
	local t = { a = 1, b = { c = 2 }, arr = { 1, 2, 3 } }
	local snapshot = diff.clone(t)
	diff.apply(t, empty)
	assert_equal(t, snapshot)
end

-- apply: frozen descendants (root must stay mutable)
function test.should_apply_change_to_frozen_subtable()
	local original = table.freeze { hp = 10, mp = 5 }
	local t = { stats = original }
	diff.apply(t, make { changes = { { path = { 'stats', 'hp' }, value = 99 } } })
	assert(t.stats.hp == 99 and t.stats.mp == 5)
	assert(original.hp == 10, 'original frozen subtable unchanged')
	assert(t.stats ~= original, 'subtable replaced with mutable clone')
end

function test.should_apply_remove_on_frozen_subtable()
	local original = table.freeze { sword = 1, shield = 1 }
	local t = { inv = original }
	diff.apply(t, make { removes = { { path = { 'inv', 'shield' } } } })
	assert(t.inv.sword == 1 and t.inv.shield == nil)
	assert(original.shield == 1, 'original frozen subtable unchanged')
end

function test.should_apply_shift_on_frozen_nested_array()
	local original = table.freeze { 'a', 'c' }
	local t = { items = original }
	diff.apply(t, make { shift_insertions = { { path = { 'items' }, index = 2, value = 'b' } } })
	assert_equal(t.items, { 'a', 'b', 'c' })
	assert_equal(original, { 'a', 'c' })
end

function test.should_apply_combined_diff_on_frozen_subtables()
	local frozen_inv = table.freeze { 'sword', 'shield' }
	local t = { coins = 10, inv = frozen_inv, scratch = 1 }
	diff.apply(
		t,
		make {
			changes = { { path = { 'coins' }, value = 50 } },
			removes = { { path = { 'scratch' } } },
			shift_insertions = { { path = { 'inv' }, index = 2, value = 'bow' } },
			shift_removes = { { path = { 'inv' }, index = 3 } },
		}
	)
	assert(t.coins == 50 and t.scratch == nil)
	assert_equal(t.inv, { 'sword', 'bow' })
	assert_equal(frozen_inv, { 'sword', 'shield' })
end

function test.should_error_on_frozen_root()
	local t = table.freeze { coins = 10 }
	local ok = pcall(diff.apply, t, make { changes = { { path = { 'coins' }, value = 42 } } })
	assert(not ok, 'apply must error on frozen root')
end

-- roundtrip (compute + apply integration)
function test.should_roundtrip_scalar_change()
	roundtrip({ a = 1, b = 2 }, { a = 1, b = 99 })
end

function test.should_roundtrip_add_and_remove()
	roundtrip({ a = 1, b = 2 }, { a = 1, c = 3 })
end

function test.should_roundtrip_nested()
	roundtrip({ stats = { hp = 10, mp = 5 }, coins = 3 }, { stats = { hp = 15 }, coins = 3 })
end

function test.should_roundtrip_array_insert()
	roundtrip({ 'a', 'b', 'c' }, { 'a', 'x', 'b', 'c' })
end

function test.should_roundtrip_array_remove()
	roundtrip({ 1, 2, 3, 4, 5 }, { 1, 5 })
end

function test.should_roundtrip_array_replace()
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

local codec = require '../utils/codec'
local diff = require '../utils/diff'
local diff_codec = require '../utils/diff_codec'

local ITERATIONS = 1000

local function bench(name: string, fn: () -> ())
	local start = os.clock()
	for _ = 1, ITERATIONS do
		fn()
	end
	local elapsed = os.clock() - start

	local avg_us = elapsed / ITERATIONS * 1e6
	local ops = ITERATIONS / elapsed
	print(string.format('%-60s avg %8.3f us  (%d ops/s)', name, avg_us, math.floor(ops)))
end

local function section(title: string)
	print()
	print(`== {title} ==`)
end

-- fixtures
local small_table = {
	id = 'player_42',
	coins = 1234,
	level = 12,
	position = vector.create(10, 5, 3),
	alive = true,
}

local function make_large_table(n: number)
	local t = { items = {}, stats = {} }
	for i = 1, n do
		t.items[i] = { name = `item_{i}`, count = i, rarity = i % 5 }
	end
	for i = 1, n do
		t.stats[`stat_{i}`] = i * 1.5
	end
	return t
end

local large_table = make_large_table(1024)

local schema = {
	coins = 0,
	level = 0,
	items = {}, --{ [1] = { name = '', count = 0 } },
	stats = { hp = 0, mp = 0 },
}
local idx = diff_codec.build_index(schema)
local empty_idx = diff_codec.build_index(nil)

local diff_small = {
	changes = {
		{ path = { 'coins' }, value = 200 },
		{ path = { 'stats', 'hp' }, value = 95 },
	},
	removes = {},
	shift_insertions = {},
	shift_removes = {},
}

local function make_diff_large(n: number)
	local diff = { changes = {}, removes = {}, shift_insertions = {}, shift_removes = {} }
	for i = 1, n do
		table.insert(diff.changes, { path = { 'items', i :: any, 'count' }, value = i })
	end
	return diff
end

local diff_large = make_diff_large(1024)

-- sizes
local small_buf = codec.encode(small_table)
local large_buf = codec.encode(large_table)
local diff_small_buf = diff_codec.encode(diff_small, idx)
local diff_small_no_schema_buf = diff_codec.encode(diff_small, empty_idx)
local diff_large_buf = diff_codec.encode(diff_large, idx)

print 'payload sizes:'
print(string.format('  small table          : %d bytes', buffer.len(small_buf)))
print(string.format('  large table (n=1024)  : %d bytes', buffer.len(large_buf)))
print(string.format('  diff small w/ schema : %d bytes', buffer.len(diff_small_buf)))
print(string.format('  diff small no schema : %d bytes', buffer.len(diff_small_no_schema_buf)))
print(string.format('  diff large w/ schema : %d bytes', buffer.len(diff_large_buf)))
print()
print(`iterations per bench: {ITERATIONS}`)

section 'codec'
bench('encode small table', function()
	codec.encode(small_table)
end)
bench('decode small table', function()
	codec.decode(small_buf)
end)
bench('encode large table (n=1024)', function()
	codec.encode(large_table)
end)
bench('decode large table (n=1024)', function()
	codec.decode(large_buf)
end)

section 'varint'
bench('push_varint 127 (1 byte)', function()
	codec.reset_workspace()
	codec.push_varint(127)
	codec.free_workspace()
end)
bench('push_varint 16383 (2 byte)', function()
	codec.reset_workspace()
	codec.push_varint(16383)
	codec.free_workspace()
end)
bench('push_varint 2097151 (3 byte)', function()
	codec.reset_workspace()
	codec.push_varint(2097151)
	codec.free_workspace()
end)

section 'diff_codec'
bench('encode diff (small, w/ schema)', function()
	diff_codec.encode(diff_small, idx)
end)
bench('encode diff (small, no schema)', function()
	diff_codec.encode(diff_small, empty_idx)
end)
bench('decode diff (small, w/ schema)', function()
	diff_codec.decode(diff_small_buf, nil, idx)
end)
bench('encode diff (large, n=1024)', function()
	diff_codec.encode(diff_large, idx)
end)
bench('decode diff (large, n=1024)', function()
	diff_codec.decode(diff_large_buf, nil, idx)
end)

-- diff fixtures
local large_prev = make_large_table(1024)
local large_curr_unchanged = make_large_table(1024)

local large_curr_scalar = make_large_table(1024)
for i = 1, 1024 do
	large_curr_scalar.items[i].count = i + 1
end

local large_curr_array_insert = make_large_table(1024)
table.insert(large_curr_array_insert.items, 512, { name = 'new_item', count = 0, rarity = 0 })

local large_curr_array_remove = make_large_table(1024)
table.remove(large_curr_array_remove.items, 512)

local nested_prev = { a = { b = { c = { d = { e = { f = 1 } } } } } }
local nested_curr = { a = { b = { c = { d = { e = { f = 2 } } } } } }

local diff_full_large = diff.compute({}, large_prev)
local diff_scalar_large = diff.compute(large_prev, large_curr_scalar)
local diff_insert_large = diff.compute(large_prev, large_curr_array_insert)

section 'diff compute'
bench('compute equal (small)', function()
	diff.compute(small_table, small_table)
end)
bench('compute nested 6-deep change', function()
	diff.compute(nested_prev, nested_curr)
end)
bench('compute equal (large, n=1024)', function()
	diff.compute(large_prev, large_curr_unchanged)
end)
bench('compute scalar change all rows (large, n=1024)', function()
	diff.compute(large_prev, large_curr_scalar)
end)
bench('compute array insert middle (large, n=1024)', function()
	diff.compute(large_prev, large_curr_array_insert)
end)
bench('compute array remove middle (large, n=1024)', function()
	diff.compute(large_prev, large_curr_array_remove)
end)
bench('compute from empty (large, n=1024)', function()
	diff.compute({}, large_prev)
end)

section 'diff apply'
bench('apply scalar change all rows (large, n=1024)', function()
	local root = diff.clone(large_prev)
	diff.apply(root, diff_scalar_large)
end)
bench('apply array insert middle (large, n=1024)', function()
	local root = diff.clone(large_prev)
	diff.apply(root, diff_insert_large)
end)
bench('apply full populate (large, n=1024)', function()
	local root = {}
	diff.apply(root, diff_full_large)
end)

section 'diff helpers'
bench('clone large table (n=1024)', function()
	diff.clone(large_prev)
end)
bench('equal large equal (n=1024)', function()
	diff.equal(large_prev, large_curr_unchanged)
end)

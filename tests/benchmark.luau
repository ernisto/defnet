local codec = require '../lib/utils/codec'
local encode = codec.impl.encode
local decode = codec.impl.decode

local diff_codec = require '../lib/utils/diff_codec'
local encode_diff = diff_codec.impl.encode
local decode_diff = diff_codec.impl.decode

local diff_algo = require '../lib/utils/diff'
local diff_from = diff_algo.from
local apply_diff = diff_algo.apply
local snapshot = diff_algo.snapshot

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

local diff_small = {
	children = {
		stats = {
			children = {},
			removes = {},
			shift_inserts = {},
			shift_removes = {},
			changes = {
				hp = 49,
			},
		},
	},
	changes = {
		coins = 200,
	},
	removes = {},
	shift_inserts = {},
	shift_removes = {},
}

local function make_diff_large(n: number)
	local diff = diff_algo.from({}, {})
	diff.changes.items = diff_algo.from({}, {})

	for i = 1, n do
		diff.children[i] = diff_algo.from({}, {})
		diff.children[i].changes.count = i
	end
	return diff
end

local diff_large = make_diff_large(1024)

-- sizes
local small_buf = encode(small_table)
local large_buf = encode(large_table)
local diff_small_buf = diff_codec.impl.encode(diff_small)
local diff_large_buf = diff_codec.impl.encode(diff_large)

print 'payload sizes:'
print(string.format('  small table          : %d bytes', buffer.len(small_buf)))
print(string.format('  large table (n=1024)  : %d bytes', buffer.len(large_buf)))
print(string.format('  diff small          : %d bytes', buffer.len(diff_small_buf)))
print(string.format('  diff large          : %d bytes', buffer.len(diff_large_buf)))
print()
print(`iterations per bench: {ITERATIONS}`)

section 'codec'
bench('encode small table', function()
	encode(small_table)
end)
bench('decode small table', function()
	decode(small_buf)
end)
bench('encode large table (n=1024)', function()
	encode(large_table)
end)
bench('decode large table (n=1024)', function()
	decode(large_buf)
end)

section 'varint'
bench('push_varint 127 (1 byte)', function()
	codec.reset_workspace()
	codec.push_varint(127)
	codec.save_workspace()
end)
bench('push_varint 16383 (2 byte)', function()
	codec.reset_workspace()
	codec.push_varint(16383)
	codec.save_workspace()
end)
bench('push_varint 2097151 (3 byte)', function()
	codec.reset_workspace()
	codec.push_varint(2097151)
	codec.save_workspace()
end)

section 'diff_codec'
bench('encode diff (small)', function()
	encode_diff(diff_small)
end)
bench('decode diff (small)', function()
	decode_diff(diff_small_buf)
end)
bench('encode diff (large, n=1024)', function()
	encode_diff(diff_large)
end)
bench('decode diff (large, n=1024)', function()
	decode_diff(diff_large_buf)
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

local diff_full_large = diff_from({}, large_prev)
local diff_scalar_large = diff_from(large_prev, large_curr_scalar)
local diff_insert_large = diff_from(large_prev, large_curr_array_insert)

section 'diff compute'
bench('compute equal (small)', function()
	diff_from(small_table, small_table)
end)
bench('compute nested 6-deep change', function()
	diff_from(nested_prev, nested_curr)
end)
bench('compute equal (large, n=1024)', function()
	diff_from(large_prev, large_curr_unchanged)
end)
bench('compute scalar change all rows (large, n=1024)', function()
	diff_from(large_prev, large_curr_scalar)
end)
bench('compute array insert middle (large, n=1024)', function()
	diff_from(large_prev, large_curr_array_insert)
end)
bench('compute array remove middle (large, n=1024)', function()
	diff_from(large_prev, large_curr_array_remove)
end)
bench('compute from empty (large, n=1024)', function()
	diff_from({}, large_prev)
end)

section 'diff apply'
bench('apply scalar change all rows (large, n=1024)', function()
	local root = snapshot(large_prev)
	apply_diff(root, diff_scalar_large)
end)
bench('apply array insert middle (large, n=1024)', function()
	local root = snapshot(large_prev)
	apply_diff(root, diff_insert_large)
end)
bench('apply full populate (large, n=1024)', function()
	local root = {}
	apply_diff(root, diff_full_large)
end)

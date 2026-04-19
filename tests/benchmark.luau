local codec = require '../lib/codec'

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

-- sizes
local small_buf = codec.encode(small_table)
local large_buf = codec.encode(large_table)

print 'payload sizes:'
print(string.format('  small table          : %d bytes', buffer.len(small_buf)))
print(string.format('  large table (n=1024)  : %d bytes', buffer.len(large_buf)))
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
	codec.begin_encode()
	codec.push_varint(127)
	codec.finish_encode()
end)
bench('push_varint 16383 (2 byte)', function()
	codec.begin_encode()
	codec.push_varint(16383)
	codec.finish_encode()
end)
bench('push_varint 2097151 (3 byte)', function()
	codec.begin_encode()
	codec.push_varint(2097151)
	codec.finish_encode()
end)

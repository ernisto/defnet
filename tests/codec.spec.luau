local codec = require '../utils/codec'

local test = {}

-- helpers
local function encode(v)
	codec.reset_workspace()
	codec.push_value(v)
	return codec.free_workspace()
end
local function decode(buff, unk)
	codec.load_workspace(buff, unk)
	return codec.pop_value()
end

local function assert_buffer_equal(a: buffer, b: buffer)
	assert(buffer.len(a) == buffer.len(b), 'buffer lengths differ')

	for i = 0, buffer.len(a) - 1 do
		local byte_a = buffer.readu8(a, i)
		local byte_b = buffer.readu8(b, i)
		assert(byte_a == byte_b, `buffer mismatch at index {i}`)
	end
end

-- primitives
function test.should_roundtrip_nil()
	local encoded, unknowns = encode(nil)
	local decoded = decode(encoded, unknowns)

	assert(decoded == nil)
	assert(unknowns == nil)
end

function test.should_roundtrip_booleans()
	local encoded_true, unknowns_true = encode(true)
	local encoded_false, unknowns_false = encode(false)

	assert(decode(encoded_true, unknowns_true) == true)
	assert(decode(encoded_false, unknowns_false) == false)
end

function test.should_roundtrip_number()
	local input = -123.456
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert(decoded == input)
end

function test.should_roundtrip_ascii_string()
	local input = 'hello serializer'
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert(decoded == input)
end

function test.should_roundtrip_empty_string()
	local input = ''
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert(decoded == input)
end

function test.should_roundtrip_long_string_with_varint_length()
	local input = string.rep('x', 200) -- forces 2-byte varint length prefix
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert(decoded == input)
end

function test.should_roundtrip_vector()
	local input = vector.create(1.5, -2.25, 300.125)
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert(decoded.x == input.x)
	assert(decoded.y == input.y)
	assert(decoded.z == input.z)
end

function test.should_roundtrip_buffer()
	local input = buffer.create(4)
	buffer.writeu8(input, 0, 12)
	buffer.writeu8(input, 1, 34)
	buffer.writeu8(input, 2, 56)
	buffer.writeu8(input, 3, 78)

	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert_buffer_equal(decoded, input)
end

function test.should_roundtrip_empty_buffer()
	local input = buffer.create(0)
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert_buffer_equal(decoded, input)
end

-- tables
function test.should_roundtrip_empty_table()
	local input = {}
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert(type(decoded) == 'table')
	assert(next(decoded) == nil)
end

function test.should_roundtrip_table_with_array_and_hash_parts()
	local input = {
		1,
		2,
		3,
		key = 'value',
		enabled = true,
		nested = {
			11,
			name = 'nested',
		},
	}
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert(decoded[1] == 1)
	assert(decoded[2] == 2)
	assert(decoded[3] == 3)
	assert(decoded.key == 'value')
	assert(decoded.enabled == true)
	assert(decoded.nested[1] == 11)
	assert(decoded.nested.name == 'nested')
end

-- unknowns side-channel
function test.should_roundtrip_unknown_values_with_unknown_list()
	local unknown = coroutine.create(function() end)
	local encoded, unknowns = encode(unknown)

	local decoded = decode(encoded, unknowns)
	assert(decoded == unknown)
end

function test.should_track_unknown_values_once()
	local unknown = coroutine.create(function() end)
	local input = { first = unknown, second = unknown }

	local _, unknowns = encode(input)

	assert(unknowns and #unknowns == 1)
	assert(unknowns[1] == unknown)
end

function test.should_serialize_duplicated_table_values()
	local shared = { x = 1, y = 2 }
	local input = { first = shared, second = shared }
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	assert(decoded.first.x == 1 and decoded.first.y == 2)
	assert(decoded.second.x == 1 and decoded.second.y == 2)
	assert(decoded.first ~= decoded.second)
end

-- varint primitives (internal building block)
function test.should_roundtrip_varint_boundaries()
	local cases = {
		0,
		1,
		127, -- 1 byte max
		128, -- 2 byte min
		16383, -- 2 byte max
		16384, -- 3 byte min
		2097151, -- 3 byte max
		2097152, -- 4 byte min
		268435455, -- 4 byte max (2^28 - 1)
	}
	for _, n in cases do
		codec.reset_workspace()
		codec.push_varint(n)
		local encoded = codec.free_workspace()

		codec.load_workspace(encoded)
		local decoded = codec.pop_varint()
		assert(decoded == n, `varint roundtrip failed for {n}: got {decoded}`)
	end
end

function test.should_use_expected_byte_count_for_varints()
	local cases = {
		{ value = 0, bytes = 1 },
		{ value = 127, bytes = 1 },
		{ value = 128, bytes = 2 },
		{ value = 16383, bytes = 2 },
		{ value = 16384, bytes = 3 },
		{ value = 2097151, bytes = 3 },
		{ value = 2097152, bytes = 4 },
	}
	for _, case in cases do
		codec.reset_workspace()
		codec.push_varint(case.value)
		local encoded = codec.free_workspace()

		assert(
			buffer.len(encoded) == case.bytes,
			`varint {case.value} expected {case.bytes} bytes, got {buffer.len(encoded)}`
		)
	end
end

-- errors / edge cases
function test.should_error_when_encoding_nan()
	local ok, _ = pcall(function()
		encode(0 / 0)
	end)

	assert(ok == false)
end

function test.should_error_when_encoding_non_ascii_string()
	local non_ascii = 'cafe com acento: caf' .. utf8.char(0xE9)
	local ok, _ = pcall(function()
		codec.encode 'cafe com acento: cafe'
		encode(non_ascii)
	end)

	assert(ok == false)
end

function test.should_error_when_encoding_recursive_table()
	local input = {}
	input.self = input

	local ok, _ = pcall(function()
		encode(input)
	end)
	assert(ok == false)
end

return test

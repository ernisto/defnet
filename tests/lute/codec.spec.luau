local test = require '@std/test'

local codec = require '../../lib/utils/codec'

-- helpers
local function encode(v)
	codec.reset_workspace()
	codec.load_pool()
	codec.push_value(v)
	return codec.save_workspace()
end
local function decode(buff, unk)
	codec.load_workspace(buff, unk)
	local out = codec.pop_value()

	codec.save_pool()
	return out
end

local function assert_buffer_equal(t, a: buffer, b: buffer)
	t.eq(buffer.len(a), buffer.len(b), 'buffer lengths differ')

	for i = 0, buffer.len(a) - 1 do
		t.eq(buffer.readu8(a, i), buffer.readu8(b, i), `buffer mismatch at index {i}`)
	end
end

-- primitives
test.case('should_roundtrip_nil', function(t)
	local encoded, unknowns = encode(nil)
	local decoded = decode(encoded, unknowns)

	t.eq(decoded, nil)
	t.eq(unknowns, nil)
end)

test.case('should_roundtrip_booleans', function(t)
	local encoded_true, unknowns_true = encode(true)
	local encoded_false, unknowns_false = encode(false)

	t.eq(decode(encoded_true, unknowns_true), true)
	t.eq(decode(encoded_false, unknowns_false), false)
end)

test.case('should_roundtrip_number', function(t)
	local input = -123.456
	local encoded, unknowns = encode(input)

	t.eq(decode(encoded, unknowns), input)
end)

test.case('should_roundtrip_ascii_string', function(t)
	local input = 'hello serializer'
	local encoded, unknowns = encode(input)

	t.eq(decode(encoded, unknowns), input)
end)

test.case('should_roundtrip_empty_string', function(t)
	local input = ''
	local encoded, unknowns = encode(input)

	t.eq(decode(encoded, unknowns), input)
end)

test.case('should_roundtrip_long_string_with_varint_length', function(t)
	local input = string.rep('x', 200) -- forces 2-byte varint length prefix
	local encoded, unknowns = encode(input)

	t.eq(decode(encoded, unknowns), input)
end)

test.case('should_roundtrip_vector', function(t)
	local input = vector.create(1.5, -2.25, 300.125)
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	t.eq(decoded.x, input.X)
	t.eq(decoded.y, input.Y)
	t.eq(decoded.z, input.Z)
end)

test.case('should_roundtrip_buffer', function(t)
	local input = buffer.create(4)
	buffer.writeu8(input, 0, 12)
	buffer.writeu8(input, 1, 34)
	buffer.writeu8(input, 2, 56)
	buffer.writeu8(input, 3, 78)

	local encoded, unknowns = encode(input)

	assert_buffer_equal(t, decode(encoded, unknowns), input)
end)

test.case('should_roundtrip_empty_buffer', function(t)
	local input = buffer.create(0)
	local encoded, unknowns = encode(input)

	assert_buffer_equal(t, decode(encoded, unknowns), input)
end)

-- tables
test.case('should_roundtrip_empty_table', function(t)
	local input = {}
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	t.eq(type(decoded), 'table')
	t.eq(next(decoded), nil)
end)

test.case('should_roundtrip_table_with_array_and_hash_parts', function(t)
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

	t.eq(decoded[1], 1)
	t.eq(decoded[2], 2)
	t.eq(decoded[3], 3)
	t.eq(decoded.key, 'value')
	t.eq(decoded.enabled, true)
	t.eq(decoded.nested[1], 11)
	t.eq(decoded.nested.name, 'nested')
end)

test.case('should_roundtrip_table_with_zero_index', function(t)
	local input = { [0] = 'zero', [1] = 'one', [2] = 'two' }
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	t.eq(decoded[0], 'zero')
	t.eq(decoded[1], 'one')
	t.eq(decoded[2], 'two')
end)

test.case('should_roundtrip_table_with_only_zero_index', function(t)
	local input = { [0] = 'zero' }
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	t.eq(decoded[0], 'zero')
	t.eq(next(decoded, 0), nil)
end)

test.case('should_roundtrip_mix_table_with_zero_index', function(t)
	local input = { [0] = 'zero', [1] = 'cavalo', cavalo = 'esperto' }
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	t.eq(decoded[0], 'zero')
	t.eq(decoded.cavalo, 'esperto')
end)

-- unknowns side-channel
test.case('should_roundtrip_unknown_values_with_unknown_list', function(t)
	local unknown = coroutine.create(function() end)
	local encoded, unknowns = encode(unknown)

	t.eq(decode(encoded, unknowns), unknown)
end)

test.case('should_track_unknown_values_once', function(t)
	local unknown = coroutine.create(function() end)
	local input = { first = unknown, second = unknown }

	local _, unknowns = encode(input)

	t.eq(unknowns and #unknowns, 1)
	t.eq(unknowns[1], unknown)
end)

test.case('should_preserve_identity_of_duplicated_table_values', function(t)
	local shared = { x = 1, y = 2 }
	local input = { first = shared, second = shared }
	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	t.eq(decoded.first.x == 1 and decoded.first.y == 2, true)
	t.eq(decoded.second.x == 1 and decoded.second.y == 2, true)
	t.eq(decoded.first, decoded.second)
end)

-- varint primitives (internal building block)
test.case('should_roundtrip_varint_boundaries', function(t)
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
		local encoded = codec.save_workspace()

		codec.load_workspace(encoded)
		t.eq(codec.pop_varint(), n, `varint roundtrip failed for {n}`)
	end
end)

test.case('should_use_expected_byte_count_for_varints', function(t)
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
		local encoded = codec.save_workspace()

		t.eq(buffer.len(encoded), case.bytes, `varint {case.value} expected {case.bytes} bytes`)
	end
end)

-- errors / edge cases
test.case('should_error_when_encoding_nan', function(t)
	t.throws(function()
		encode(0 / 0)
	end)
end)

test.case('should_error_when_encoding_non_ascii_string', function(t)
	local non_ascii = 'cafe com acento: caf' .. utf8.char(0xE9)
	t.throws(function()
		encode(non_ascii)
	end)
end)

test.case('should_roundtrip_recursive_table', function(t)
	local input = {}
	input.self = input

	local encoded, unknowns = encode(input)
	local decoded = decode(encoded, unknowns)

	t.eq(decoded.self, decoded)
end)

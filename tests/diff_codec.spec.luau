local diff_codec = require '../lib/utils/diff_codec'

local test = {}

local empty_diff = {
	changes = {},
	removes = {},
	shift_insertions = {},
	shift_removes = {},
}

local function make_diff(partial: any)
	local d = table.clone(empty_diff)
	for k, v in partial do
		d[k] = v
	end
	return d
end

local function assert_path_equal(a: { any }, b: { any })
	assert(#a == #b, `path length mismatch: {#a} vs {#b}`)
	for i = 1, #a do
		assert(a[i] == b[i], `path[{i}] mismatch: {tostring(a[i])} vs {tostring(b[i])}`)
	end
end

-- empty
function test.should_roundtrip_empty_diff()
	local encoded, unknowns = diff_codec.encode(empty_diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert(#decoded.changes == 0)
	assert(#decoded.removes == 0)
	assert(#decoded.shift_insertions == 0)
	assert(#decoded.shift_removes == 0)
end

-- changes
function test.should_roundtrip_change()
	local diff = make_diff {
		changes = { { path = { 'coins' }, value = 42 } },
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert(#decoded.changes == 1)
	assert_path_equal(decoded.changes[1].path, { 'coins' })
	assert(decoded.changes[1].value == 42)
end

function test.should_roundtrip_nested_path()
	local diff = make_diff {
		changes = { { path = { 'pets', 1 :: any, 'name' }, value = 'rex' } },
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert_path_equal(decoded.changes[1].path, { 'pets', 1, 'name' })
	assert(decoded.changes[1].value == 'rex')
end

function test.should_roundtrip_deep_path()
	local diff = make_diff {
		changes = { { path = { 'anything', 'nested' }, value = 1 } },
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert_path_equal(decoded.changes[1].path, { 'anything', 'nested' })
	assert(decoded.changes[1].value == 1)
end

-- diff parts
function test.should_roundtrip_removes()
	local diff = make_diff {
		removes = { { path = { 'coins' } }, { path = { 'level' } } },
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert(#decoded.removes == 2)
	assert_path_equal(decoded.removes[1].path, { 'coins' })
	assert_path_equal(decoded.removes[2].path, { 'level' })
end

function test.should_roundtrip_shift_insertions()
	local diff = make_diff {
		shift_insertions = {
			{ path = { 'items' }, index = 1, value = 'first' },
			{ path = { 'items' }, index = 3, value = 'third' },
		},
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert(#decoded.shift_insertions == 2)
	assert(decoded.shift_insertions[1].index == 1)
	assert(decoded.shift_insertions[1].value == 'first')
	assert(decoded.shift_insertions[2].index == 3)
	assert(decoded.shift_insertions[2].value == 'third')
end

function test.should_roundtrip_shift_removes()
	local diff = make_diff {
		shift_removes = {
			{ path = { 'items' }, index = 2 },
		},
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert(decoded.shift_removes[1].index == 2)
	assert_path_equal(decoded.shift_removes[1].path, { 'items' })
end

function test.should_roundtrip_combined_diff()
	local diff = make_diff {
		changes = {
			{ path = { 'coins' }, value = 100 },
			{ path = { 'stats', 'hp' }, value = 80 },
		},
		removes = { { path = { 'items', 'old' } } },
		shift_insertions = { { path = { 'items' }, index = 1, value = 'new' } },
		shift_removes = { { path = { 'items' }, index = 5 } },
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert(#decoded.changes == 2)
	assert(decoded.changes[1].value == 100)
	assert(decoded.changes[2].value == 80)
	assert_path_equal(decoded.changes[2].path, { 'stats', 'hp' })
	assert(#decoded.removes == 1)
	assert_path_equal(decoded.removes[1].path, { 'items', 'old' })
	assert(decoded.shift_insertions[1].value == 'new')
	assert(decoded.shift_removes[1].index == 5)
end

-- value preservation
function test.should_preserve_value_types_in_changes()
	local diff = make_diff {
		changes = {
			{ path = { 'a' }, value = true } :: any,
			{ path = { 'b' }, value = vector.create(1, 2, 3) },
			{ path = { 'c' }, value = { nested = 'ok' } },
			{ path = { 'd' }, value = nil },
		},
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert(decoded.changes[1].value == true)
	assert(decoded.changes[2].value.x == 1)
	assert(decoded.changes[3].value.nested == 'ok')
	assert(decoded.changes[4].value == nil)
end

function test.should_track_unknowns_in_diff_values()
	local unknown = coroutine.create(function() end)
	local diff = make_diff {
		changes = { { path = { 'ref' }, value = unknown } },
	}

	local encoded, unknowns = diff_codec.encode(diff)
	assert(unknowns and #unknowns == 1 and unknowns[1] == unknown)

	local decoded = diff_codec.decode(encoded, unknowns)
	assert(decoded.changes[1].value == unknown)
end

function test.should_preserve_number_key_vs_string_key()
	local diff = make_diff {
		changes = {
			{ path = { 'pets', 1 :: any }, value = 'numeric' },
			{ path = { 'pets', '1' }, value = 'string_one' },
		},
	}

	local encoded, unknowns = diff_codec.encode(diff)
	local decoded = diff_codec.decode(encoded, unknowns)

	assert(decoded.changes[1].path[2] == 1 and type(decoded.changes[1].path[2]) == 'number')
	assert(decoded.changes[2].path[2] == '1' and type(decoded.changes[2].path[2]) == 'string')
end

return test

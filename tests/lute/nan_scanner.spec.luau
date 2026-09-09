local test = require '@std/test'

local scan_nan = require '../../lib/utils/nan_scanner'

local nan = math.nan

-- primitives
test.case('should_pass_finite_number', function(t)
	scan_nan.assert_valid(0)
	scan_nan.assert_valid(1.5)
	scan_nan.assert_valid(-1e9)
	scan_nan.assert_valid(math.huge)
	scan_nan.assert_valid(-math.huge)
end)

test.case('should_error_on_nan_number', function(t)
	t.throws(scan_nan.assert_valid, nan)
end)

test.case('should_pass_finite_vector', function(t)
	scan_nan.assert_valid(vector.create(1, 2, 3))
end)

test.case('should_error_on_nan_vector_x', function(t)
	t.throws(scan_nan.assert_valid, vector.create(nan, 0, 0))
end)

test.case('should_error_on_nan_vector_y', function(t)
	t.throws(scan_nan.assert_valid, vector.create(0, nan, 0))
end)

test.case('should_error_on_nan_vector_z', function(t)
	t.throws(scan_nan.assert_valid, vector.create(0, 0, nan))
end)

test.case('should_pass_non_numeric_primitives', function(t)
	scan_nan.assert_valid(nil)
	scan_nan.assert_valid(true)
	scan_nan.assert_valid(false)
	scan_nan.assert_valid 'hello'
	scan_nan.assert_valid(buffer.create(4))
end)

-- tables
test.case('should_pass_empty_table', function(t)
	scan_nan.assert_valid {}
end)

test.case('should_pass_finite_table', function(t)
	scan_nan.assert_valid { 1, 2, 3, key = 'val', nested = { 4, 5 } }
end)

test.case('should_error_on_nan_in_array', function(t)
	t.throws(scan_nan.assert_valid, { 1, nan, 3 })
end)

test.case('should_error_on_nan_in_hash_value', function(t)
	t.throws(scan_nan.assert_valid, { key = nan })
end)

test.case('should_error_on_nan_in_nested_table', function(t)
	t.throws(scan_nan.assert_valid, { a = { b = { c = nan } } })
end)

test.case('should_error_on_nan_in_vector_inside_table', function(t)
	t.throws(scan_nan.assert_valid, { pos = vector.create(0, nan, 0) })
end)

-- variadic
test.case('should_pass_finite_args', function(t)
	scan_nan.assert_valid_tuple(1, 'foo', { 2, 3 }, vector.create(1, 2, 3))
end)

test.case('should_error_on_nan_in_args', function(t)
	t.throws(scan_nan.assert_valid_tuple, 1, nan, 3)
end)

test.case('should_error_on_nan_in_args_table', function(t)
	t.throws(scan_nan.assert_valid_tuple, 'ok', { bad = nan })
end)

test.case('should_pass_no_args', function(t)
	scan_nan.assert_valid_tuple()
end)

test.case('should_pass_nil_args', function(t)
	scan_nan.assert_valid_tuple(nil, nil, nil)
end)

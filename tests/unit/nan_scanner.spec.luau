local scan_nan = require '../../lib/utils/nan_scanner'

local test = {}

local nan = math.nan

-- helpers
local function expect_error(fn, ...)
	local ok = pcall(fn, ...)
	assert(not ok, 'expected error, got success')
end

-- primitives
function test.should_pass_finite_number()
	scan_nan.assert_valid(0)
	scan_nan.assert_valid(1.5)
	scan_nan.assert_valid(-1e9)
	scan_nan.assert_valid(math.huge)
	scan_nan.assert_valid(-math.huge)
end

function test.should_error_on_nan_number()
	expect_error(scan_nan.assert_valid, nan)
end

function test.should_pass_finite_vector()
	scan_nan.assert_valid(vector.create(1, 2, 3))
end

function test.should_error_on_nan_vector_x()
	expect_error(scan_nan.assert_valid, vector.create(nan, 0, 0))
end

function test.should_error_on_nan_vector_y()
	expect_error(scan_nan.assert_valid, vector.create(0, nan, 0))
end

function test.should_error_on_nan_vector_z()
	expect_error(scan_nan.assert_valid, vector.create(0, 0, nan))
end

function test.should_pass_non_numeric_primitives()
	scan_nan.assert_valid(nil)
	scan_nan.assert_valid(true)
	scan_nan.assert_valid(false)
	scan_nan.assert_valid 'hello'
	scan_nan.assert_valid(buffer.create(4))
end

-- tables
function test.should_pass_empty_table()
	scan_nan.assert_valid {}
end

function test.should_pass_finite_table()
	scan_nan.assert_valid { 1, 2, 3, key = 'val', nested = { 4, 5 } }
end

function test.should_error_on_nan_in_array()
	expect_error(scan_nan.assert_valid, { 1, nan, 3 })
end

function test.should_error_on_nan_in_hash_value()
	expect_error(scan_nan.assert_valid, { key = nan })
end

function test.should_error_on_nan_in_nested_table()
	expect_error(scan_nan.assert_valid, { a = { b = { c = nan } } })
end

function test.should_error_on_nan_in_vector_inside_table()
	expect_error(scan_nan.assert_valid, { pos = vector.create(0, nan, 0) })
end

-- variadic
function test.should_pass_finite_args()
	scan_nan.assert_valid_tuple(1, 'foo', { 2, 3 }, vector.create(1, 2, 3))
end

function test.should_error_on_nan_in_args()
	expect_error(scan_nan.assert_valid_tuple, 1, nan, 3)
end

function test.should_error_on_nan_in_args_table()
	expect_error(scan_nan.assert_valid_tuple, 'ok', { bad = nan })
end

function test.should_pass_no_args()
	scan_nan.assert_valid_tuple()
end

function test.should_pass_nil_args()
	scan_nan.assert_valid_tuple(nil, nil, nil)
end

return test

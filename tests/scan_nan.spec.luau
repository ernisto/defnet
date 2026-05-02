local scan_nan = require '../lib/utils/scan_nan'

local test = {}

local nan = math.nan

-- helpers
local function expect_error(fn, ...)
	local ok = pcall(fn, ...)
	assert(not ok, 'expected error, got success')
end

-- primitives
function test.should_pass_finite_number()
	scan_nan.scan(0)
	scan_nan.scan(1.5)
	scan_nan.scan(-1e9)
	scan_nan.scan(math.huge)
	scan_nan.scan(-math.huge)
end

function test.should_error_on_nan_number()
	expect_error(scan_nan.scan, nan)
end

function test.should_pass_finite_vector()
	scan_nan.scan(vector.create(1, 2, 3))
end

function test.should_error_on_nan_vector_x()
	expect_error(scan_nan.scan, vector.create(nan, 0, 0))
end

function test.should_error_on_nan_vector_y()
	expect_error(scan_nan.scan, vector.create(0, nan, 0))
end

function test.should_error_on_nan_vector_z()
	expect_error(scan_nan.scan, vector.create(0, 0, nan))
end

function test.should_pass_non_numeric_primitives()
	scan_nan.scan(nil)
	scan_nan.scan(true)
	scan_nan.scan(false)
	scan_nan.scan 'hello'
	scan_nan.scan(buffer.create(4))
end

-- tables
function test.should_pass_empty_table()
	scan_nan.scan {}
end

function test.should_pass_finite_table()
	scan_nan.scan { 1, 2, 3, key = 'val', nested = { 4, 5 } }
end

function test.should_error_on_nan_in_array()
	expect_error(scan_nan.scan, { 1, nan, 3 })
end

function test.should_error_on_nan_in_hash_value()
	expect_error(scan_nan.scan, { key = nan })
end

function test.should_error_on_nan_in_nested_table()
	expect_error(scan_nan.scan, { a = { b = { c = nan } } })
end

function test.should_error_on_nan_in_vector_inside_table()
	expect_error(scan_nan.scan, { pos = vector.create(0, nan, 0) })
end

-- variadic
function test.should_pass_finite_args()
	scan_nan.scan_args(1, 'foo', { 2, 3 }, vector.create(1, 2, 3))
end

function test.should_error_on_nan_in_args()
	expect_error(scan_nan.scan_args, 1, nan, 3)
end

function test.should_error_on_nan_in_args_table()
	expect_error(scan_nan.scan_args, 'ok', { bad = nan })
end

function test.should_pass_no_args()
	scan_nan.scan_args()
end

function test.should_pass_nil_args()
	scan_nan.scan_args(nil, nil, nil)
end

return test

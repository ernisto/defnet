local function assert_valid(value: any)
	local kind = type(value)
	if kind == 'number' then
		assert(not math.isnan(value), 'NaN received')
	elseif kind == 'vector' then
		assert(not math.isnan(value.x + value.y + value.z), 'NaN received')
	elseif kind == 'table' then
		for key, val in value do
			assert_valid(key)
			assert_valid(val)
		end
	end
end

local function assert_valid_tuple(...: any)
	for index = 1, select('#', ...) do
		assert_valid(select(index, ...))
	end
end

return table.freeze { assert_valid = assert_valid, assert_valid_tuple = assert_valid_tuple }

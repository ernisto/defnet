local function scan(value: any)
	local kind = type(value)
	if kind == 'number' then
		assert(not math.isnan(value), 'NaN received')
	elseif kind == 'vector' then
		assert(not math.isnan(value.x + value.y + value.z), 'NaN received')
	elseif kind == 'table' then
		for key, val in value do
			scan(key)
			scan(val)
		end
	end
end

local function scan_args(...: any)
	for index = 1, select('#', ...) do
		scan(select(index, ...))
	end
end

return table.freeze { scan = scan, scan_args = scan_args }

local visited = {}

local function sum(tab: { [any]: any })
	local v = vector.zero
	local n = 0

	if visited[tab] then return n, v end
	visited[tab] = true

	for key, value in tab do
		if type(value) == 'number' then
			n += value
		elseif type(value) == 'vector' then
			v += value
		elseif type(value) == 'table' then
			local an, av = sum(value)
			n += an
			v += av
		end

		if type(key) == 'number' then
			n += key
		elseif type(key) == 'vector' then
			v += key
		elseif type(key) == 'table' then
			local an, av = sum(key)
			n += an
			v += av
		end
	end
	return n, v
end

local function fast_check(tab)
	local a, v = sum(tab)
	table.clear(visited)
	return math.isnan(a + v.X + v.Y + v.Z)
end

local has_nan: (tab: { [any]: any }) -> boolean

local function is_nan(value: any): boolean
	return if type(value) == 'number'
		then value ~= value
		elseif type(value) == 'vector' then value.X ~= value.X or value.Y ~= value.Y or value.Z ~= value.Z
		elseif type(value) == 'table' then has_nan(value)
		else false
end

function has_nan(tab)
	if visited[tab] then return false end
	visited[tab] = true

	for key, value in tab do
		if is_nan(key) or is_nan(value) then return true end
	end
	return false
end

local function assert_valid_tuple(...: any)
	local args = { ... }
	if not fast_check(args) then return end

	local found = has_nan(args)
	table.clear(visited)

	assert(not found, 'NaN detected')
end

return table.freeze { assert_valid = assert_valid_tuple }

--!native

type diff_node = {
	children: { [any]: diff_node },
	shift_inserts: { { index: number, value: any } },
	shift_removes: { number },
	changes: { [any]: any },
	removes: { any },
}

-- workspace
local cache: { [any]: { [any]: diff_node } } = setmetatable({}, { __mode = 'k' }) :: any

-- helpers
local function reset_cache()
	table.clear(cache)
end

local function deep_clone(value: any): any
	if type(value) ~= 'table' then return value end
	local out = {}
	for key, sub in value do
		out[key] = deep_clone(sub)
	end
	return out
end

local function empty_node(): diff_node
	return { children = {}, shift_inserts = {}, shift_removes = {}, changes = {}, removes = {} }
end

local function is_empty(node: diff_node): boolean
	return next(node.changes) == nil
		and #node.removes == 0
		and #node.shift_inserts == 0
		and #node.shift_removes == 0
		and next(node.children) == nil
end

local function is_array_index(key: any, max_len: number): boolean
	return type(key) == 'number' and key % 1 == 0 and key >= 1 and key <= max_len
end

local function from<T>(prev: any, curr: any): diff_node
	prev = prev or {}
	curr = curr or {}

	local by_curr = cache[prev]
	if by_curr then
		local hit = by_curr[curr]
		if hit then return hit end
	else
		by_curr = {}
		cache[prev] = by_curr
	end

	local node = empty_node()
	by_curr[curr] = node

	local count_prev = #prev
	local count_curr = #curr
	local array_len = math.max(count_prev, count_curr)

	if array_len > 0 then
		local index_curr = count_curr
		local index_prev = count_prev
		local delta = count_curr - count_prev

		while index_curr >= 1 or index_prev >= 1 do
			local matched = false
			local sub: diff_node?

			if index_curr >= 1 and index_prev >= 1 then
				local prev_value = prev[index_prev]
				local curr_value = curr[index_curr]
				if prev_value == curr_value then
					matched = true
				elseif type(prev_value) == 'table' and type(curr_value) == 'table' then
					sub = from(prev_value, curr_value)
					matched = is_empty(sub :: any)
				end
			end

			if matched then
				index_curr -= 1
				index_prev -= 1
			elseif delta > 0 then
				table.insert(node.shift_inserts, 1, { index = index_curr, value = curr[index_curr] })
				index_curr -= 1
				delta -= 1
			elseif delta < 0 then
				table.insert(node.shift_removes, index_prev)
				index_prev -= 1
				delta += 1
			else
				if sub then
					node.children[index_prev] = sub
				else
					node.changes[index_prev] = curr[index_curr]
				end
				index_curr -= 1
				index_prev -= 1
			end
		end
	end

	for key, value in curr do
		if is_array_index(key, array_len) then continue end

		local prev_value = prev[key]
		if prev_value == value then continue end

		if type(prev_value) == 'table' and type(value) == 'table' then
			local sub = from(prev_value, value)
			if not is_empty(sub) then node.children[key] = sub end
		else
			node.changes[key] = value
		end
	end
	for key in prev do
		if is_array_index(key, array_len) then continue end

		if curr[key] ~= nil then continue end
		table.insert(node.removes, key)
	end

	return node
end

local function apply(state: any, node: diff_node)
	for index, value in node.changes do
		state[index] = value
	end
	for _, key in node.removes do
		state[key] = nil
	end
	for _, insertion in node.shift_inserts do
		table.insert(state, insertion.index, insertion.value)
	end
	for _, index in node.shift_removes do
		table.remove(state, index)
	end

	for key, child in node.children do
		local nested = state[key]
		if type(nested) ~= 'table' then
			nested = {}
			state[key] = nested
		elseif table.isfrozen(nested) then
			nested = table.clone(nested)
			state[key] = nested
		end
		apply(nested, child)
	end
end

-- module
return table.freeze {
	reset_cache = reset_cache,
	snapshot = deep_clone,
	is_empty = is_empty,
	apply = apply,
	from = from,
}

local diff_codec = require './diff_codec'

type diff = diff_codec.diff

-- helpers
local function deep_clone(v: any): any
	if type(v) ~= 'table' then return v end
	local out = {}
	for k, value in v do
		out[k] = deep_clone(value)
	end
	return out
end
local function deep_equal(a: any, b: any): boolean
	if a == b then return true end
	if type(a) ~= 'table' or type(b) ~= 'table' then return false end

	for k, v in a do
		if not deep_equal(v, b[k]) then return false end
	end
	for k in b do
		if a[k] == nil then return false end
	end
	return true
end
local function is_array(t: { [any]: any }): boolean
	local n = #t
	if n == 0 then return false end

	local count = 0
	for _ in t do
		count += 1
	end
	return count == n
end
local function sub_path(path: { any }, key: any): { any }
	local out = table.clone(path)
	table.insert(out, key)
	return out
end
local function has_any(diff: diff): boolean
	return #diff.changes > 0 or #diff.removes > 0 or #diff.shift_insertions > 0 or #diff.shift_removes > 0
end

-- compute diff
local write_diff
local function write_array_diff(prev: { any }, curr: { any }, path: { any }, diff: diff)
	local plen, clen = #prev, #curr
	local max_pref = math.min(plen, clen)

	local prefix = 0
	while prefix < max_pref and deep_equal(prev[prefix + 1], curr[prefix + 1]) do
		prefix += 1
	end

	local suffix = 0
	while suffix < max_pref - prefix and deep_equal(prev[plen - suffix], curr[clen - suffix]) do
		suffix += 1
	end

	local prev_mid = plen - prefix - suffix
	local curr_mid = clen - prefix - suffix
	local overlap = math.min(prev_mid, curr_mid)

	for k = 1, overlap do
		local idx = prefix + k
		local pv, cv = prev[idx], curr[idx]
		if type(pv) == 'table' and type(cv) == 'table' then
			write_diff(pv, cv, sub_path(path, idx), diff)
		elseif pv ~= cv then
			table.insert(diff.changes, { path = sub_path(path, idx), value = cv })
		end
	end

	if curr_mid > prev_mid then
		for k = overlap + 1, curr_mid do
			local idx = prefix + k
			table.insert(diff.shift_insertions, { path = path, index = idx, value = curr[idx] })
		end
	elseif prev_mid > curr_mid then
		for k = prev_mid, overlap + 1, -1 do
			local idx = prefix + k
			table.insert(diff.shift_removes, { path = path, index = idx })
		end
	end
end
function write_diff(prev: any, curr: any, path: { any }, diff: diff)
	if is_array(prev) and is_array(curr) then
		write_array_diff(prev, curr, path, diff)
		return
	end

	for k, v in prev do
		local cv = curr[k]
		if cv == nil then
			table.insert(diff.removes, { path = sub_path(path, k) })
		elseif type(v) == 'table' and type(cv) == 'table' then
			write_diff(v, cv, sub_path(path, k), diff)
		elseif v ~= cv then
			table.insert(diff.changes, { path = sub_path(path, k), value = cv })
		end
	end
	for k, v in curr do
		if prev[k] == nil then table.insert(diff.changes, { path = sub_path(path, k), value = v }) end
	end
end

local function compute(prev: any, curr: any): diff
	local diff: diff = { changes = {}, removes = {}, shift_insertions = {}, shift_removes = {} }
	write_diff(prev, curr, {}, diff)
	return diff
end

-- apply diff
local function walk_parent(root: any, path: { any }): (any, any)
	local t = root
	for i = 1, #path - 1 do
		local key = path[i]
		local child = t[key]
		if child == nil then
			child = {}
		elseif type(child) == 'table' and table.isfrozen(child) then
			child = table.clone(child)
		else
			t = child
			continue
		end
		t[key] = child
		t = child
	end
	return t, path[#path]
end
local function walk(root: any, path: { any }): any
	local t = root
	for _, k in path do
		local child = t[k]
		if type(child) == 'table' and table.isfrozen(child) then
			child = table.clone(child)
			t[k] = child
		end
		t = child
	end
	return t
end
local function apply(root: any, diff: diff)
	for _, c in diff.changes do
		local parent, key = walk_parent(root, c.path)
		parent[key] = c.value
	end
	for _, r in diff.removes do
		local parent, key = walk_parent(root, r.path)
		parent[key] = nil
	end
	for _, s in diff.shift_insertions do
		table.insert(walk(root, s.path), s.index, s.value)
	end
	for _, s in diff.shift_removes do
		table.remove(walk(root, s.path), s.index)
	end
end

return table.freeze {
	compute = compute,
	apply = apply,
	clone = deep_clone,
	equal = deep_equal,
	has_any = has_any,
}

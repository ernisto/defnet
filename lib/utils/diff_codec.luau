local codec = require './codec'
local push_value = codec.push_value
local push_size = codec.push_varint
local pop_value = codec.pop_value
local pop_size = codec.pop_varint

-- format (uses codec's shared buffer/cursor/unknowns):
--   diff { varint changes_len, changes[], varint removes_len, removes[],
--          varint shift_insertions_len, shift_insertions[], varint shift_removes_len, shift_removes[] }
--   change        { path, value(push_value) }
--   remove        { path }
--   shift_insert  { path, varint index, value(push_value) }
--   shift_remove  { path, varint index }
--   path          { varint len, len * push_value(key) }

export type path = { any }
export type change = { path: path, value: any }
export type removal = { path: path }
export type shift_insertion = { path: path, index: number, value: any }
export type shift_removal = { path: path, index: number }
export type diff = {
	changes: { change },
	removes: { removal },
	shift_insertions: { shift_insertion },
	shift_removes: { shift_removal },
}

-- functions
local function push_path(path: path)
	push_size(#path)
	for _, key in path do
		push_value(key)
	end
end
local function pop_path(): path
	local len = pop_size()
	local path = table.create(len)
	for i = 1, len do
		path[i] = pop_value()
	end
	return path
end

local function encode(diff: diff): (buffer, { any }?)
	codec.reset_workspace()

	local changes = diff.changes
	push_size(#changes)
	for _, c in changes :: any do
		push_path(c.path)
		push_value(c.value)
	end

	local removes = diff.removes
	push_size(#removes)
	for _, r in removes :: any do
		push_path(r.path)
	end

	local shift_insertions = diff.shift_insertions
	push_size(#shift_insertions)
	for _, s in shift_insertions :: any do
		push_path(s.path)
		push_size(s.index)
		push_value(s.value)
	end

	local shift_removes = diff.shift_removes
	push_size(#shift_removes)
	for _, s in shift_removes :: any do
		push_path(s.path)
		push_size(s.index)
	end

	return codec.free_workspace()
end
local function decode(input: buffer, input_unknowns: { any }?): diff
	codec.load_workspace(input, input_unknowns)

	local changes_len = pop_size()
	local changes = table.create(changes_len)
	for i = 1, changes_len do
		changes[i] = { path = pop_path(), value = pop_value() }
	end

	local removes_len = pop_size()
	local removes = table.create(removes_len)
	for i = 1, removes_len do
		removes[i] = { path = pop_path() }
	end

	local shift_insertions_len = pop_size()
	local shift_insertions = table.create(shift_insertions_len)
	for i = 1, shift_insertions_len do
		shift_insertions[i] = { path = pop_path(), index = pop_size(), value = pop_value() }
	end

	local shift_removes_len = pop_size()
	local shift_removes = table.create(shift_removes_len)
	for i = 1, shift_removes_len do
		shift_removes[i] = { path = pop_path(), index = pop_size() }
	end

	return { changes = changes, removes = removes, shift_insertions = shift_insertions, shift_removes = shift_removes }
end

-- module
return table.freeze { encode = encode, decode = decode }

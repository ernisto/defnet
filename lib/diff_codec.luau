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
--   path          { varint schema_node_id, varint unknown_len, unknown_len * push_value(key) }
--     schema_node_id refers to an id produced by build_index; the id marks the deepest
--     schema-known prefix of the path, then the remaining keys follow as push_value

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
type node = { id: number, prefix: path, children: { [any]: node } }
export type schema_index = { nodes: { node }, root: node }

-- helpers
local function compare_keys(a: any, b: any): boolean
	local ta, tb = type(a), type(b)
	if ta ~= tb then return ta < tb end

	if ta == 'number' then return a < b end
	return tostring(a) < tostring(b)
end

-- functions
local function build_index(schema: any): schema_index
	local nodes: { node } = {}

	local function visit(sub: any, prefix: path): node
		local self_node: node = { id = #nodes + 1, prefix = prefix, children = {} }
		table.insert(nodes, self_node)

		if type(sub) ~= 'table' then return self_node end

		local keys = {}
		for key in sub do
			table.insert(keys, key)
		end
		table.sort(keys, compare_keys)

		for _, key in keys do
			local child_prefix = table.clone(prefix)
			table.insert(child_prefix, key)
			self_node.children[key] = visit(sub[key], child_prefix)
		end
		return self_node
	end

	local root = visit(schema, {})
	return { nodes = nodes, root = root }
end
local function push_path(path: path, idx: schema_index)
	local node = idx.root
	local depth = 0

	for i, key in path do
		local child = node.children[key]
		if not child then break end
		node = child
		depth = i
	end

	push_size(node.id)
	push_size(#path - depth)
	for i = depth + 1, #path do
		push_value(path[i])
	end
end
local function pop_path(idx: schema_index): path
	local id = pop_size()
	local prefix = idx.nodes[id] and idx.nodes[id].prefix or error(`unknown schema node id {id}`)
	local path = table.clone(prefix)

	local unknown_len = pop_size()
	for _ = 1, unknown_len do
		table.insert(path, pop_value())
	end
	return path
end

local function encode(diff: diff, idx: schema_index): (buffer, { any })
	codec.begin_encode()

	local changes = diff.changes
	push_size(#changes)
	for _, c in changes :: any do
		push_path(c.path, idx)
		push_value(c.value)
	end

	local removes = diff.removes
	push_size(#removes)
	for _, r in removes :: any do
		push_path(r.path, idx)
	end

	local shift_insertions = diff.shift_insertions
	push_size(#shift_insertions)
	for _, s in shift_insertions :: any do
		push_path(s.path, idx)
		push_size(s.index)
		push_value(s.value)
	end

	local shift_removes = diff.shift_removes
	push_size(#shift_removes)
	for _, s in shift_removes :: any do
		push_path(s.path, idx)
		push_size(s.index)
	end

	return codec.finish_encode()
end
local function decode(input: buffer, input_unknowns: { any }?, idx: schema_index): diff
	codec.begin_decode(input, input_unknowns)

	local changes_len = pop_size()
	local changes = table.create(changes_len)
	for i = 1, changes_len do
		changes[i] = { path = pop_path(idx), value = pop_value() }
	end

	local removes_len = pop_size()
	local removes = table.create(removes_len)
	for i = 1, removes_len do
		removes[i] = { path = pop_path(idx) }
	end

	local shift_insertions_len = pop_size()
	local shift_insertions = table.create(shift_insertions_len)
	for i = 1, shift_insertions_len do
		shift_insertions[i] = { path = pop_path(idx), index = pop_size(), value = pop_value() }
	end

	local shift_removes_len = pop_size()
	local shift_removes = table.create(shift_removes_len)
	for i = 1, shift_removes_len do
		shift_removes[i] = { path = pop_path(idx), index = pop_size() }
	end

	return { changes = changes, removes = removes, shift_insertions = shift_insertions, shift_removes = shift_removes }
end

-- module
return table.freeze { encode = encode, decode = decode, build_index = build_index }

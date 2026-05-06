--!native

local codec = require './codec'
local register_push_identity = codec.register_push_identity
local register_pop_identity = codec.register_pop_identity
local get_identity = codec.get_identity
local pop_identity = codec.pop_identity
local push_value = codec.push_value
local push_size = codec.push_varint
local pop_value = codec.pop_value
local pop_size = codec.pop_varint
local push_u8 = codec.push_u8
local pop_u8 = codec.pop_u8

type diff_node = {
	children: { [any]: diff_node },
	shift_inserts: { { index: number, value: any } },
	shift_removes: { number },
	changes: { [any]: any },
	removes: { any },
}

-- format (uses codec's shared buffer/cursor/unknowns + identity_pool):
--   u8 tag: 0 = new (registered in identity_pool), 1 = ref
--   if ref: varint id
--   if new:
--     u8 mask: bit 0 = changes, bit 1 = removes, bit 2 = shift_inserts,
--              bit 3 = shift_removes, bit 4 = children
--     if bit 0: varint len, [ push_value(key), push_value(value) ]
--     if bit 1: varint len, [ push_value(key) ]
--     if bit 2: varint len, [ varint(index), push_value(value) ]
--     if bit 3: varint len, [ varint(index) ]
--     if bit 4: varint len, [ push_value(key), push_diff(child) ]

-- helpers
local function count(map: { [any]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- functions
local function push_diff(node: diff_node)
	local id = get_identity(node)
	if id then
		push_u8(9)
		push_size(id)
		return
	end

	push_u8(0)
	register_push_identity(node)

	local changes = node.changes
	local removes = node.removes
	local shift_inserts = node.shift_inserts
	local shift_removes = node.shift_removes
	local children = node.children

	local changes_len = count(changes)
	local children_len = count(children)
	local mask = 0
		+ 2 ^ 0 * math.sign(changes_len)
		+ 2 ^ 1 * math.sign(#removes)
		+ 2 ^ 2 * math.sign(#shift_inserts)
		+ 2 ^ 3 * math.sign(#shift_removes)
		+ 2 ^ 4 * math.sign(children_len)
	push_u8(mask)

	if changes_len > 0 then
		push_size(changes_len)
		for key, value in changes do
			push_value(key)
			push_value(value)
		end
	end
	if #removes > 0 then
		push_size(#removes)
		for _, key in removes do
			push_value(key)
		end
	end
	if #shift_inserts > 0 then
		push_size(#shift_inserts)
		for _, ins in shift_inserts do
			push_size(ins.index)
			push_value(ins.value)
		end
	end
	if #shift_removes > 0 then
		push_size(#shift_removes)
		for _, index in shift_removes do
			push_size(index)
		end
	end
	if children_len > 0 then
		push_size(children_len)
		for key, child in children do
			push_value(key)
			push_diff(child)
		end
	end
end

local function pop_diff(): diff_node
	local tag = pop_u8()
	if tag == 9 then return pop_identity() end

	local node: diff_node = { children = {}, shift_inserts = {}, shift_removes = {}, changes = {}, removes = {} }
	register_pop_identity(node)

	local mask = pop_u8()

	if mask % 2 >= 1 then
		local len = pop_size()
		for _ = 1, len do
			local key = pop_value()
			node.changes[key] = pop_value()
		end
	end
	if (mask // 2) % 2 >= 1 then
		local len = pop_size()
		for index = 1, len do
			node.removes[index] = pop_value()
		end
	end
	if (mask // 4) % 2 >= 1 then
		local len = pop_size()
		for index = 1, len do
			node.shift_inserts[index] = { index = pop_size(), value = pop_value() }
		end
	end
	if (mask // 8) % 2 >= 1 then
		local len = pop_size()
		for index = 1, len do
			node.shift_removes[index] = pop_size()
		end
	end
	if (mask // 16) % 2 >= 1 then
		local len = pop_size()
		for _ = 1, len do
			local key = pop_value()
			node.children[key] = pop_diff()
		end
	end

	return node
end

-- module
local function encode(diff: diff_node, pool: codec.pool?): (buffer, { any }?)
	codec.reset_workspace()
	codec.load_pool(pool)
	push_diff(diff)
	return codec.save_workspace()
end
local function decode(input: buffer, pool: codec.pool?, input_unknowns: { any }?): diff_node
	codec.load_workspace(input, input_unknowns, pool)
	local diff = pop_diff()
	codec.save_pool()
	return diff
end

-- module
return table.freeze {
	impl = { encode = encode, decode = decode },
	push = push_diff,
	pop = pop_diff,
}

--!native

local WORST_MISSING_BYTES_CASE = 3 -- check `peek_u32` hack comment

-- defs
local type_to_tags = {
	-- [anything else] = 1	-- unknown
	['nil'] = 2,
	['boolean'] = 3,
	['number'] = 4,
	['string'] = 5,
	['vector'] = 6,
	['table'] = 7,
	['buffer'] = 8,
}

type table = { [any]: any }
export type pool = {
	val_to_id: { [any]: number },
	id_to_val: { [number]: any },
	next_id: number,
}
export type codec_impl<Data> = {
	encode: (Data, pool?) -> (buffer, { any }?),
	decode: (buffer, pool?, { any }?) -> Data,
}

-- workspace
-- based on global states for speed
-- not stables for concurrency work
-- but we arent doing it here anyway
local limit = 1024 -- expandable
local working_buf = buffer.create(limit)
local unknowns: { any } = {}
local cursor = 0
local fail = false

local current_pool: pool?
local next_identity = 1
local val_to_id: { [any]: number } = {}
local id_to_val: { [number]: any } = {}

local function warn_not_available()
	print(`unknown values not available, pls check the 2nd argument of 'decode' and 2nd return of 'encode'`)
end
local function not_available_unknowns(): { any }
	return setmetatable({}, { __index = warn_not_available }) :: any
end

local function create_pool(): pool
	return { val_to_id = {}, id_to_val = {}, next_id = 1 }
end
local function load_pool(pool: pool?)
	current_pool = pool
	val_to_id = if pool then pool.val_to_id else {}
	id_to_val = if pool then pool.id_to_val else {}
	next_identity = if pool then pool.next_id else 1
end
local function save_pool()
	if current_pool then current_pool.next_id = next_identity end
end

local function load_workspace(input: buffer, input_unknowns: { any }?, pool: pool?)
	local input_len = buffer.len(input) + WORST_MISSING_BYTES_CASE
	working_buf = if input_len < limit then working_buf else buffer.create(input_len)

	buffer.copy(working_buf, 0, input)
	load_pool(pool)

	unknowns = input_unknowns or not_available_unknowns()
	cursor = 0
end
local function save_workspace(): (buffer, { any }?)
	if current_pool then current_pool.next_id = next_identity end

	local copy = buffer.create(cursor)
	buffer.copy(copy, 0, working_buf, 0, cursor)

	if fail then error 'some values couldnt be serialized' end
	return copy, if #unknowns > 0 then unknowns else nil
end
local function reset_workspace()
	cursor = 0
	fail = false
	unknowns = {}
end

local function realloc()
	local old = working_buf

	limit = math.max(cursor, limit * 2)
	working_buf = buffer.create(limit)
	buffer.copy(working_buf, 0, old)
end
local function ensure_size(bytes: number): number
	local prev = cursor
	cursor += bytes

	if cursor > limit then realloc() end
	return prev
end
local function advance(bytes: number): number
	local prev = cursor
	cursor += bytes
	return prev
end
local function peek_u32(): number
	-- HACK: if we are reading the last byte, it still misses 3 bytes
	-- so we are alway allocating +3 bytes for `working_buf`
	-- instead of waste time handling edge cases
	return buffer.readu32(working_buf, cursor)
end

local function get_identity(value: any): number?
	return val_to_id[value]
end
local function register_push_identity(value: any): number
	local id = next_identity
	val_to_id[value] = id
	next_identity += 1
	return id
end
local function register_pop_identity(value: any): number
	local id = next_identity
	id_to_val[id] = value
	next_identity += 1
	return id
end

-- primitives
local function push_u8(n: number)
	local offset = ensure_size(1)
	buffer.writeu8(working_buf, offset, n)
end
local function push_u16(n: number)
	local offset = ensure_size(2)
	buffer.writeu16(working_buf, offset, n)
end
local function push_u32(n: number)
	local offset = ensure_size(4)
	buffer.writeu32(working_buf, offset, n)
	fail = fail or math.isnan(n)
end
local function pop_u8(): number
	return buffer.readu8(working_buf, advance(1))
end
local function pop_u16(): number
	return buffer.readu16(working_buf, advance(2))
end
local function pop_u32(): number
	return buffer.readu32(working_buf, advance(4))
end

-- unrolled varint up to u32 implementation for speed
local function push_varint(num: number)
	if num < 0x80 then
		push_u8(num)
	elseif num < 0x4000 then
		push_u8((num % 0x80) + 0x80)
		push_u8(num // 0x80)
	elseif num < 0x200000 then
		push_u8((num % 0x80) + 0x80)
		num //= 0x80
		push_u8((num % 0x80) + 0x80)
		push_u8(num // 0x80)
	elseif num < 0x10000000 then
		push_u8((num % 0x80) + 0x80)
		num //= 0x80
		push_u8((num % 0x80) + 0x80)
		num //= 0x80
		push_u8((num % 0x80) + 0x80)
		push_u8(num // 0x80)
	end
end
local function pop_varint(): number
	local bytes = peek_u32()

	local byte1 = bytes % 256
	if byte1 < 0x80 then
		advance(1)
		return byte1
	end

	local byte2 = (bytes // 256) % 256
	local num = (byte1 - 0x80) + (byte2 % 0x80) * 0x80
	if byte2 < 0x80 then
		advance(2)
		return num
	end

	local byte3 = (bytes // 0x10000) % 256
	num += (byte3 % 0x80) * 0x4000
	if byte3 < 0x80 then
		advance(3)
		return num
	end

	local byte4 = (bytes // 0x1000000) % 256
	num += (byte4 % 0x80) * 0x200000

	advance(4)
	return num
end

local push_size, pop_size = push_varint, pop_varint

-- functions
local push_tab, pop_tab

local function push_unknown(value: any)
	local existing_index = table.find(unknowns, value)
	local index = existing_index or #unknowns + 1

	if existing_index == nil then unknowns[index] = value end
	push_size(index)
end
local function pop_unknown(): any
	return unknowns[pop_size()]
end

local function push_nil(_: nil)
	return
end
local function pop_nil(): nil
	return
end

local function push_bool(bool: boolean)
	push_u8(bool and 1 or 0)
end
local function pop_bool(): boolean
	return pop_u8() > 0
end

local function push_num(num: number)
	local offset = ensure_size(64 / 8)
	buffer.writef64(working_buf, offset, num)
	fail = fail or math.isnan(num)
end
local function pop_num(): number
	return buffer.readf64(working_buf, advance(64 / 8))
end

local function push_str(str: string)
	register_push_identity(str)

	local len = string.len(str)
	push_size(len)

	local offset = ensure_size(len)
	buffer.writestring(working_buf, offset, str)
	fail = fail or utf8.len(str) ~= len
end
local function pop_str(): string
	local len = pop_size()
	local str = buffer.readstring(working_buf, advance(len), len)

	register_pop_identity(str)
	return str
end

local function push_vec(vec: vector)
	local offset = ensure_size(3 * 32 / 8)

	buffer.writef32(working_buf, offset + 0, vec.x)
	buffer.writef32(working_buf, offset + 4, vec.y)
	buffer.writef32(working_buf, offset + 8, vec.z)
	fail = fail or math.isnan(vec.x + vec.y + vec.z)
end
local function pop_vec(): vector
	return vector.create(
		buffer.readf32(working_buf, advance(32 / 8)),
		buffer.readf32(working_buf, advance(32 / 8)),
		buffer.readf32(working_buf, advance(32 / 8))
	)
end

local function push_buf(buf: buffer)
	local len = buffer.len(buf)
	push_size(len)

	local offset = ensure_size(len)
	buffer.copy(working_buf, offset, buf, 0, len)
end
local function pop_buf(): buffer
	local len = pop_size()
	local output_buf = buffer.create(len)

	buffer.copy(output_buf, 0, working_buf, advance(len), len)
	return output_buf
end

local function push_identity(tab: table)
	push_size(val_to_id[tab])
end
local function pop_identity(): table
	return id_to_val[pop_size()]
end

local function push_value(value: any)
	local type = type(value)
	local tag = if val_to_id[value] then 9 else type_to_tags[type] or 1

	push_u8(tag)
	return if tag == 1
		then push_unknown(value)
		elseif tag == 2 then push_nil(value)
		elseif tag == 3 then push_bool(value)
		elseif tag == 4 then push_num(value)
		elseif tag == 5 then push_str(value)
		elseif tag == 6 then push_vec(value)
		elseif tag == 7 then push_tab(value)
		elseif tag == 8 then push_buf(value)
		else push_identity(value)
end
local function pop_value(): any
	local tag = pop_u8()
	return if tag == 1
		then pop_unknown()
		elseif tag == 2 then pop_nil()
		elseif tag == 3 then pop_bool()
		elseif tag == 4 then pop_num()
		elseif tag == 5 then pop_str()
		elseif tag == 6 then pop_vec()
		elseif tag == 7 then pop_tab()
		elseif tag == 8 then pop_buf()
		else pop_identity()
end

function push_tab(tab: table): ()
	register_push_identity(tab)

	local hash_len = 0
	local seq_len = 0

	local next = 1
	for index in tab do
		if next == index then
			seq_len += 1
			next += 1
		else
			hash_len += 1
		end
	end

	push_size(seq_len)
	push_size(hash_len)

	for k, v in tab do
		if type(k) ~= 'number' or k > next then push_value(k) end
		push_value(v)
	end
end
function pop_tab(): table
	local arr_len = pop_size()
	local hash_len = pop_size()

	local out = table.create(arr_len)
	register_pop_identity(out)

	for i = 1, arr_len do
		out[i] = pop_value()
	end
	for i = 1, hash_len do
		out[pop_value()] = pop_value()
	end
	return out
end

-- module
local function encode(value: any, pool: pool?): (buffer, { any }?)
	reset_workspace()
	load_pool(pool)

	push_value(value)
	return save_workspace()
end
local function decode(input: buffer, pool: pool?, input_unknowns: { any }?): any
	load_workspace(input, input_unknowns, pool)
	local value = pop_value()

	save_pool()
	return value
end

-- module
return table.freeze {
	-- user api
	impl = { encode = encode, decode = decode },
	create_pool = create_pool,

	-- internal workspace
	reset_workspace = reset_workspace,
	save_workspace = save_workspace,
	load_workspace = load_workspace,
	save_pool = save_pool,
	load_pool = load_pool,

	-- internal datatypes
	push_u8 = push_u8,
	push_u16 = push_u16,
	push_u32 = push_u32,
	push_value = push_value,
	push_varint = push_varint,
	push_identity = push_identity,

	pop_u8 = pop_u8,
	pop_u16 = pop_u16,
	pop_u32 = pop_u32,
	pop_value = pop_value,
	pop_varint = pop_varint,
	pop_identity = pop_identity,

	-- identity pool
	get_identity = get_identity,
	register_push_identity = register_push_identity,
	register_pop_identity = register_pop_identity,
}

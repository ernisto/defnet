--!native

local working_buf = buffer.create(1024)
local unknowns: { any } = {}
local cursor = 0
local fail = false

local WORST_MISSING_BYTES_CASE = 3 -- check `peek_u32` hack comment

-- utils
local pop, push
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

-- helpers
export type codec_impl<Data, Encoded...> = { encode: (Data) -> Encoded..., decode: (Encoded...) -> Data }
type table = { [any]: any }

local function warn_not_available()
	warn(`unknown values not available, pls check the 2nd argument of 'decode' and 2nd return of 'encode'`)
end
local function not_available_unknowns(): { any }
	return setmetatable({}, { __index = warn_not_available }) :: any
end

local function realloc(prev)
	local old = working_buf

	working_buf = buffer.create(math.max(cursor, buffer.len(old) * 2))
	buffer.copy(working_buf, 0, old)

	return prev
end
local function ensure_size(bytes: number): number
	local prev = cursor
	cursor += bytes

	return if cursor > buffer.len(working_buf) then realloc(prev) else prev
end
local function advance(bytes: number): number
	local prev = cursor
	cursor += bytes
	return prev
end
local function peek_u32(): number
	-- HACK: if we are reading the last byte, it still misses 3 bytes
	-- so we are alway allocating +3 bytes for `next_output` instead
	-- of waste time handling edge cases
	return buffer.readu32(working_buf, cursor)
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
local function push_value(value: any)
	local type = typeof(value)
	local tag = type_to_tags[type] or 1

	push_u8(tag)
	push[tag](value)
end
local function pop_value(): any
	local tag = pop_u8()
	return pop[tag]()
end

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
	local len = string.len(str)
	push_size(len)

	local offset = ensure_size(len)
	buffer.writestring(working_buf, offset, str)
	fail = fail or utf8.len(str) ~= len
end
local function pop_str(): string
	local len = pop_size()
	return buffer.readstring(working_buf, advance(len), len)
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

local function push_tab(tab: table)
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
local function pop_tab(): table
	local arr_len = pop_size()
	local hash_len = pop_size()

	local out = table.create(arr_len)
	for i = 1, arr_len do
		out[i] = pop_value()
	end
	for i = 1, hash_len do
		out[pop_value()] = pop_value()
	end
	return out
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

push = { push_unknown, push_nil, push_bool, push_num, push_str, push_vec, push_tab, push_buf }
pop = { pop_unknown, pop_nil, pop_bool, pop_num, pop_str, pop_vec, pop_tab, pop_buf }

-- lifecycle
local function begin_encode()
	cursor = 0
	fail = false
	unknowns = {}
	if buffer.len(working_buf) < 256 then working_buf = buffer.create(1024) end
end
local function finish_encode(): (buffer, { any })
	local copy = buffer.create(cursor)
	buffer.copy(copy, 0, working_buf, 0, cursor)

	if fail then error 'some values couldnt be serialized' end
	return copy, unknowns
end
local function begin_decode(input: buffer, input_unknowns: { any }?)
	working_buf = buffer.create(buffer.len(input) + WORST_MISSING_BYTES_CASE)
	buffer.copy(working_buf, 0, input)

	unknowns = input_unknowns or not_available_unknowns()
	cursor = 0
end

-- module
local function encode(value: any): (buffer, { any })
	begin_encode()
	push_value(value)
	return finish_encode()
end
local function decode(input: buffer, input_unknowns: { any }?): any
	local prev = working_buf
	begin_decode(input, input_unknowns)
	local value = pop_value()

	working_buf = prev
	return value
end

-- module
return table.freeze {
	encode = encode,
	decode = decode,

	-- lifecycle
	begin_encode = begin_encode,
	finish_encode = finish_encode,
	begin_decode = begin_decode,

	-- value codec
	push_value = push_value,
	pop_value = pop_value,

	-- primitives
	push_u8 = push_u8,
	push_u16 = push_u16,
	push_u32 = push_u32,
	push_varint = push_varint,
	pop_u8 = pop_u8,
	pop_u16 = pop_u16,
	pop_u32 = pop_u32,
	pop_varint = pop_varint,
}

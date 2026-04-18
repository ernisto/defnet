local next_output = buffer.create(1024)
local unknowns: { any } = {}
local cursor = 0
local fail = false

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
type table = { [any]: any }

local function warn_not_available()
	warn(`unknown values not available, pls check the 2nd argument of 'decode' and 2nd return of 'encode'`)
end
local function not_available_unknowns(): { any }
	return setmetatable({}, { __index = warn_not_available }) :: any
end

local function ensure_size(bytes: number): number
	local prev = cursor
	cursor += bytes

	if cursor <= buffer.len(next_output) then return prev end
	local old = next_output

	next_output = buffer.create(math.max(cursor, buffer.len(old) * 2))
	buffer.copy(next_output, 0, old)

	return prev
end
local function advance(bytes: number): number
	local prev = cursor
	cursor += bytes
	return prev
end
local function push_size(n: number)
	local offset = ensure_size(32 / 8)
	buffer.writeu32(next_output, offset, n)
	fail = fail or math.isnan(n)
end

-- functions
local function push_value(value: any)
	local type = typeof(value)
	local tag = type_to_tags[type] or 1

	local offset = ensure_size(1)
	buffer.writeu8(next_output, offset, tag)

	push[tag](value)
end
local function pop_value(): any
	local tag = buffer.readu8(next_output, advance(1))
	return pop[tag]()
end

local function push_unknown(value: any)
	local existing_index = table.find(unknowns, value)
	local index = existing_index or #unknowns + 1

	if existing_index == nil then unknowns[index] = value end
	push_size(index)
end
local function pop_unknown(): any
	return unknowns[buffer.readu32(next_output, advance(32 / 8))]
end

local function push_nil(_: nil)
	return
end
local function pop_nil(): nil
	return
end

local function push_bool(bool: boolean)
	local offset = ensure_size(1)
	buffer.writeu8(next_output, offset, bool and 1 or 0)
end
local function pop_bool(): boolean
	return buffer.readu8(next_output, advance(1)) > 0
end

local function push_num(num: number)
	local offset = ensure_size(64 / 8)
	buffer.writef64(next_output, offset, num)
	fail = fail or math.isnan(num)
end
local function pop_num(): number
	return buffer.readf64(next_output, advance(64 / 8))
end

local function push_str(str: string)
	local len = string.len(str)
	push_size(len)

	local offset = ensure_size(len)
	buffer.writestring(next_output, offset, str)
	fail = fail or utf8.len(str) ~= len
end
local function pop_str(): string
	local len = buffer.readu32(next_output, advance(32 / 8))
	return buffer.readstring(next_output, advance(len), len)
end

local function push_vec(vec: vector)
	local offset = ensure_size(3 * 32 / 8)

	buffer.writef32(next_output, offset + 0, vec.x)
	buffer.writef32(next_output, offset + 4, vec.y)
	buffer.writef32(next_output, offset + 8, vec.z)
	fail = fail or math.isnan(vec.x + vec.y + vec.z)
end
local function pop_vec(): vector
	return vector.create(
		buffer.readf32(next_output, advance(32 / 8)),
		buffer.readf32(next_output, advance(32 / 8)),
		buffer.readf32(next_output, advance(32 / 8))
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
	local arr_len = buffer.readu32(next_output, advance(32 / 8))
	local hash_len = buffer.readu32(next_output, advance(32 / 8))

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
	buffer.copy(next_output, offset, buf, 0, len)
end
local function pop_buf(): buffer
	local len = buffer.readu32(next_output, advance(32 / 8))
	local output = buffer.create(len)

	buffer.copy(output, 0, next_output, advance(len), len)
	return output
end

push = { push_unknown, push_nil, push_bool, push_num, push_str, push_vec, push_tab, push_buf }
pop = { pop_unknown, pop_nil, pop_bool, pop_num, pop_str, pop_vec, pop_tab, pop_buf }

-- module
local function handle_push_value(value: any): (buffer, { any })
	cursor = 0
	fail = false
	unknowns = {}
	push_value(value)

	local copy = buffer.create(cursor)
	buffer.copy(copy, 0, next_output, 0, cursor)

	if fail then error 'some values couldnt be serialized' end
	return copy, unknowns
end
local function handle_pop_value(input: buffer, input_unknowns: { any }?): any
	local temp = next_output

	next_output = input
	unknowns = input_unknowns or not_available_unknowns()
	cursor = 0
	local value = pop_value()

	next_output = temp
	return value
end

return table.freeze { encode = handle_push_value, decode = handle_pop_value }

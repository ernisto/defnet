local guard = {}

export type checker = (any) -> boolean
export type schema = { checker }

local calls: { [string]: { started_at: number, count: number } } = {}

function guard.rate_limit(player: Player, key: string, limit: number?, window: number?): boolean
	if not limit then
		return true
	end

	window = window or 1

	local now = os.clock()
	local id = tostring(player.UserId) .. ":" .. key

	local bucket = calls[id]

	if not bucket or now - bucket.started_at > window then
		calls[id] = {
			started_at = now,
			count = 1,
		}

		return true
	end

	bucket.count += 1

	return bucket.count <= limit
end

function guard.validate_tuple(schema_def: schema?, ...): (boolean, number?)
	if not schema_def then
		return true
	end

	local args = { ... }

	for index, check in schema_def do
		if not check(args[index]) then
			return false, index
		end
	end

	return true
end

function guard.safe_call(callback: (...any) -> ...any, ...): ...any
	local packed = table.pack(pcall(callback, ...))

	if not packed[1] then
		warn("[defnet] callback error:", packed[2])
		return nil
	end

	return unpack(packed, 2, packed.n)
end

return table.freeze(guard)
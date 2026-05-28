local guard = require "./guard"

local codec_guard = {}

export type codec_impl = {
	encode: (any) -> ...any,
	decode: (...any) -> any,
}

function codec_guard.wrap(codec_impl: codec_impl, schema: guard.schema?)
	if not schema then
		return codec_impl
	end

	return table.freeze {
		encode = function(value: any)
			local valid, index = guard.validate_tuple(schema, value)

			if not valid then
				error("[defnet] invalid encoded payload at arg " .. tostring(index), 2)
			end

			return codec_impl.encode(value)
		end,

		decode = function(...)
			local value = codec_impl.decode(...)

			local valid, index = guard.validate_tuple(schema, value)

			if not valid then
				error("[defnet] invalid decoded payload at arg " .. tostring(index), 2)
			end

			return value
		end,
	}
end

return table.freeze(codec_guard)
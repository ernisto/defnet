local types = {}

export type checker = (any) -> boolean

function types.any(_: any): boolean
	return true
end

function types.string(value: any): boolean
	return typeof(value) == "string"
end

function types.number(value: any): boolean
	return typeof(value) == "number" and value == value
end

function types.boolean(value: any): boolean
	return typeof(value) == "boolean"
end

function types.table(value: any): boolean
	return typeof(value) == "table"
end

function types.vector3(value: any): boolean
	return typeof(value) == "Vector3"
end

function types.instance(value: any): boolean
	return typeof(value) == "Instance"
end

function types.player(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

function types.optional(check: checker): checker
	return function(value: any): boolean
		if value == nil then
			return true
		end

		return check(value)
	end
end

function types.array(check: checker): checker
	return function(value: any): boolean
		if typeof(value) ~= "table" then
			return false
		end

		for _, item in value do
			if not check(item) then
				return false
			end
		end

		return true
	end
end

function types.shape(schema: { [any]: checker }): checker
	return function(value: any): boolean
		if typeof(value) ~= "table" then
			return false
		end

		for key, check in schema do
			if not check(value[key]) then
				return false
			end
		end

		return true
	end
end

return table.freeze(types)
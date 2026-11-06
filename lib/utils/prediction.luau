local diff = require './diff'

-- defs
export type op<T> = { time: number, id: number, fn: (T) -> () }
export type predictor<T> = { server: T, client: T, ops: { op<T> } }

-- functions
local function create<T>(client: T): predictor<T>
	return { server = diff.snapshot(client), client = client, ops = {} }
end

-- copies source into target reusing target's nested tables, so references held to them stay valid
-- seen maps source tables to their target, so cycles resolve to the target side
local function assign(target: any, source: any, seen: { [any]: any })
	seen[source] = target
	for key in target do
		if source[key] == nil then target[key] = nil end
	end
	for key, value in source do
		local current = target[key]
		local mapped = seen[value]
		if mapped then
			target[key] = mapped
		elseif type(value) ~= 'table' then
			target[key] = value
		elseif type(current) == 'table' and not table.isfrozen(current) then
			assign(current, value, seen)
		else
			target[key] = diff.snapshot(value, seen)
		end
	end
end

local function rebuild(p: predictor<any>)
	assign(p.client, p.server, {})
	for _, op in p.ops do
		op.fn(p.client)
	end
end

-- applies a server diff stamped at server_time, dropping the ops it settles
local function receive(p: predictor<any>, node: any, server_time: number)
	diff.apply(p.server, node)

	if #p.ops == 0 then
		diff.apply(p.client, diff.snapshot(node))
		return
	end

	local ops = p.ops
	for index = #ops, 1, -1 do
		if server_time > ops[index].time then table.remove(ops, index) end
	end

	rebuild(p)
end

local function predict<T>(p: predictor<T>, op: op<T>)
	table.insert(p.ops, op)
	op.fn(p.client)
end

local function cancel(p: predictor<any>, id: number): boolean
	for index, op in p.ops do
		if op.id ~= id then continue end
		table.remove(p.ops, index)

		rebuild(p)
		return true
	end
	return false
end
local function settle(p: predictor<any>, id: number, time: number): boolean
	for _, op in p.ops do
		if op.id ~= id then continue end
		op.time = time
		return true
	end
	return false
end

-- module
return table.freeze {
	create = create,
	receive = receive,
	predict = predict,
	cancel = cancel,
	settle = settle,
}

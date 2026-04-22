local diff_algo = require './diff'
local diff_codec = require './diff_codec'

local EMPTY = table.freeze {} :: any

-- defs
type packet = { buf: buffer, unknowns: { any } }
export type syncer<Receiver> = {
	idx: diff_codec.schema_index,
	send: (target: Receiver, packet) -> (),
	targets: { [Receiver]: any },
	snapshots: { [Receiver]: any },
}

-- functions
local function create<Receiver>(
	params: { idx: diff_codec.schema_index, send: (target: Receiver, packet) -> () }
): syncer<Receiver>
	return { idx = params.idx, send = params.send, targets = {}, snapshots = {} }
end
local function remove<Receiver>(syncer: syncer<Receiver>, target: Receiver)
	syncer.targets[target] = nil
	syncer.snapshots[target] = nil
end

local function step<Receiver>(syncer: syncer<Receiver>, target: Receiver?)
	local snapshots: { [any]: any } = {}
	local packets: { [any]: packet } = {}

	local function ensure_snapshot<T>(curr: T): T
		local snapshot = snapshots[curr]
		if snapshot then return snapshot end

		snapshot = diff_algo.clone(curr)
		snapshots[curr] = snapshot
		return snapshot
	end

	local function ensure_encoded<T>(prev: T?, curr: T): packet | false
		local packet = packets[curr]
		if packet ~= nil then return packet end

		local diff = diff_algo.compute(prev, curr)
		if diff_algo.has_any(diff) then
			local buf, unknowns = diff_codec.encode(diff, syncer.idx)
			packet = { buf = buf, unknowns = unknowns } :: any
		else
			packet = false :: any
		end

		packets[curr] = packet
		return packet
	end

	local function send_one(target: Receiver)
		local curr = syncer.targets[target]
		local prev = syncer.snapshots[target] or EMPTY

		local packet = ensure_encoded(prev, curr)
		if packet then syncer.send(target, packet :: any) end

		syncer.snapshots[target] = ensure_snapshot(curr)
	end

	if target ~= nil then return send_one(target) end
	for t in syncer.targets do
		send_one(t)
	end

	-- remove snapshots
	for receiver in syncer.snapshots do
		if syncer.targets[receiver] == nil then syncer.snapshots[receiver] = nil end
	end
end

local function apply<T>(idx: diff_codec.schema_index, state: T, buf: buffer, unknowns: { any }?)
	diff_algo.apply(state, diff_codec.decode(buf, unknowns, idx))
end

return table.freeze { create = create, remove = remove, step = step, apply = apply }

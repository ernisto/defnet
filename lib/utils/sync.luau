local codec = require './codec'
local diff_algo = require './diff'
local diff_codec = require './diff_codec'

-- defs
type packet = { buf: buffer, unknowns: { any }? }
export type syncer<Receiver> = {
	send: (target: Receiver, packet) -> (),
	targets: { [Receiver]: any },
	snapshots: { [Receiver]: any },
	pools: { [Receiver]: codec.pool }?,
	default: any,
}

-- functions
local function create<Receiver>(params: {
	default: any,
	send: (target: Receiver, packet) -> (),
	pools: { [Receiver]: codec.pool }?,
}): syncer<Receiver>
	return {
		default = params.default,
		send = params.send,
		pools = params.pools,
		targets = {},
		snapshots = {},
	}
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

		snapshot = diff_algo.snapshot(curr)
		snapshots[curr] = snapshot
		return snapshot
	end

	local function ensure_encoded<T>(prev: T?, curr: T): packet | false
		local packet = packets[curr]
		if packet ~= nil then return packet end

		local diff = diff_algo.from(prev, curr)
		if not diff_algo.is_empty(diff) then
			local buf, unknowns = diff_codec.impl.encode(diff)
			packet = { buf = buf, unknowns = unknowns } :: any
		else
			packet = false :: any
		end

		packets[curr] = packet
		return packet
	end

	local pools = syncer.pools
	local function send_one(target: Receiver)
		local curr = syncer.targets[target]
		local prev = syncer.snapshots[target] or syncer.default
		local pool = if pools then pools[target] else nil

		if pool then
			local diff = diff_algo.from(prev, curr)
			if not diff_algo.is_empty(diff) then
				local buf, unknowns = diff_codec.impl.encode(diff, pool)
				syncer.send(target, { buf = buf, unknowns = unknowns })
			end
		else
			local packet = ensure_encoded(prev, curr)
			if packet then syncer.send(target, packet :: any) end
		end

		syncer.snapshots[target] = ensure_snapshot(curr)
	end

	if target then
		send_one(target)
	else
		for receiver in syncer.targets do
			send_one(receiver)
		end
	end

	-- remove snapshots
	for receiver in syncer.snapshots do
		if syncer.targets[receiver] == nil then syncer.snapshots[receiver] = nil end
	end

	diff_algo.reset_cache()
end

local function apply<T>(state: T, buf: buffer, pool: codec.pool?, unknowns: { any }?)
	diff_algo.apply(state, diff_codec.impl.decode(buf, pool, unknowns))
end

return table.freeze { create = create, remove = remove, step = step, apply = apply }

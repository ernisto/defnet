local codec = require './codec'
local diff_algo = require './diff'
local diff_codec = require './diff_codec'

-- defs
export type packet = { buf: buffer, unknowns: { any }? }
export type syncer<Receiver> = {
	send: (target: Receiver, packet) -> (),
	targets: { [Receiver]: any },
	snapshots: { [Receiver]: any },
	pools: { [Receiver]: codec.pool },
	default: any,
}

-- functions
local function create<Receiver>(params: {
	default: any,
	send: (target: Receiver, packet) -> (),
	pools: { [Receiver]: codec.pool },
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
	local pools = syncer.pools

	local function ensurepool(target: Receiver)
		if pools[target] then return pools[target] end
		local pool = codec.create_pool()

		pools[target] = pool
		return pool
	end

	local function send_one(target: Receiver)
		local curr = syncer.targets[target]
		local prev = syncer.snapshots[target] or syncer.default

		local diff = diff_algo.from(prev, curr)
		if not diff then return end

		local buf, unknowns = diff_codec.impl.encode(diff, ensurepool(target))
		syncer.send(target, { buf = buf, unknowns = unknowns })

		syncer.snapshots[target] = diff_algo.snapshot(curr)
	end

	if target then
		send_one(target)
	else
		for receiver in syncer.targets do
			send_one(receiver)
		end
	end

	-- remove snapshots of removed targets
	for receiver in syncer.snapshots do
		if syncer.targets[receiver] == nil then syncer.snapshots[receiver] = nil end
	end

	diff_algo.reset_cache()
end

local function apply<T>(state: T, buf: buffer, pool: codec.pool?, unknowns: { any }?)
	diff_algo.apply(state, diff_codec.impl.decode(buf, pool, unknowns))
end

-- module
return table.freeze { create = create, remove = remove, step = step, apply = apply }

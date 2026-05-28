local codec = require "./codec"
local diff_algo = require "./diff"
local diff_codec = require "./diff_codec"

export type packet = {
	buf: buffer,
	unknowns: { any }?,
}

export type syncer = {
	send: (Player, packet) -> (),
	targets: { [Player]: any },
	snapshots: { [Player]: any },
	pools: { [Player]: codec.pool },
	default: any,
}

local function create(params: {
	default: any,
	send: (Player, packet) -> (),
	pools: { [Player]: codec.pool },
	}): syncer
	return {
		default = params.default,
		send = params.send,
		pools = params.pools,
		targets = {},
		snapshots = {},
	}
end

local function remove(syncer: syncer, player: Player)
	syncer.targets[player] = nil
	syncer.snapshots[player] = nil
end

local function step(syncer: syncer, player: Player?)
	local snapshots_cache: { [any]: any } = {}

	local function ensure_snapshot(current: any): any
		local snapshot = snapshots_cache[current]

		if snapshot then
			return snapshot
		end

		snapshot = diff_algo.snapshot(current)
		snapshots_cache[current] = snapshot

		return snapshot
	end

	local function send_one(target_player: Player)
		local current = syncer.targets[target_player]

		if current == nil then
			return
		end

		local previous = syncer.snapshots[target_player] or syncer.default
		local diff_node = diff_algo.from(previous, current)

		if diff_algo.is_empty(diff_node) then
			return
		end

		local buf, unknowns = diff_codec.impl.encode(diff_node, syncer.pools[target_player])

		syncer.send(target_player, {
			buf = buf,
			unknowns = unknowns,
		})

		syncer.snapshots[target_player] = ensure_snapshot(current)
	end

	if player then
		send_one(player)
	else
		for target_player in syncer.targets do
			send_one(target_player)
		end
	end

	for target_player in syncer.snapshots do
		if syncer.targets[target_player] == nil then
			syncer.snapshots[target_player] = nil
		end
	end

	diff_algo.reset_cache()
end

local function diff_to_patch(node)
	local patch = {
		changed = {},
		removed = {},
		children = {},
	}

	if not node then
		return patch
	end

	for key, value in node.changes do
		patch.changed[key] = value
	end

	for _, key in node.removes do
		table.insert(patch.removed, key)
	end

	for key, child in node.children do
		patch.children[key] = diff_to_patch(child)
	end

	return patch
end

local function apply(state: any, buf: buffer, pool: codec.pool?, unknowns: { any }?)
	local diff_node = diff_codec.impl.decode(buf, pool, unknowns)

	diff_algo.apply(state, diff_node)

	return diff_to_patch(diff_node)
end

return table.freeze {
	create = create,
	remove = remove,
	step = step,
	apply = apply,
}
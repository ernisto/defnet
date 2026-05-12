local diff_codec = require '../../lib/utils/diff_codec'
local sync = require '../../lib/utils/sync'

local test = {}

type msg = { target: string, buf: buffer, unknowns: { any }? }

local function make_syncer(schema: any?): (sync.syncer<string>, { msg })
	local sent: { msg } = {}
	local s = sync.create {
		default = schema,
		pools = {},
		send = function(target: string, p: sync.packet)
			table.insert(sent, { target = target, buf = p.buf, unknowns = p.unknowns })
		end,
	}
	return s, sent
end

local function apply_msg(state: any, m: msg)
	sync.apply(state, m.buf, nil, m.unknowns)
end

function test.should_step_only_specific_target()
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }
	s.targets.p1 = world
	s.targets.p2 = world
	sync.step(s, 'p1')

	assert(#sent == 1)
	assert(sent[1].target == 'p1')
end

-- receiver-side apply
function test.should_roundtrip_full_state_through_apply()
	local schema = { coins = 0, items = {}, stats = { hp = 0 } }
	local s, sent = make_syncer(schema)
	local world = { coins = 50, items = { 'a', 'b' }, stats = { hp = 80 } }
	s.targets.p1 = world
	sync.step(s)

	local client: any = {}
	apply_msg(client, sent[1])
	assert(client.coins == 50)
	assert(client.stats.hp == 80)
	assert(client.items[1] == 'a' and client.items[2] == 'b')
end

-- late join / catch-up
function test.should_catch_up_new_joiner_via_targeted_step()
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }
	s.targets.p1 = world
	sync.step(s)
	s.targets.p2 = world
	sync.step(s, 'p2')

	assert(#sent == 2, 'p1 first tick + p2 catch-up')
	assert(sent[1].target == 'p1')
	assert(sent[2].target == 'p2')

	local p2_state: any = {}
	apply_msg(p2_state, sent[2])
	assert(p2_state.coins == 10, 'p2 caught up to current state')
end

-- target switches reference
function test.should_send_resync_when_target_switches_curr()
	local s, sent = make_syncer { coins = 0 }
	local world_a = { coins = 1 }
	local world_b = { coins = 99 }
	s.targets.p1 = world_a
	sync.step(s)
	s.targets.p1 = world_b
	sync.step(s)

	assert(#sent == 2)
	local client: any = {}
	apply_msg(client, sent[1])
	apply_msg(client, sent[2])
	assert(client.coins == 99)
end

-- cleanup / no-op edges
function test.should_stop_sending_after_remove()
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }
	s.targets.p1 = world
	sync.step(s)
	sync.remove(s, 'p1')
	world.coins = 99
	sync.step(s)

	assert(#sent == 1, 'no messages after remove')
	assert(s.snapshots.p1 == nil)
end

-- diff against default
function test.should_send_only_changed_field_against_default_for_new_target()
	local s, sent = make_syncer { persistent = 0, mutable = 0 }
	local world = { persistent = 0, mutable = 100 }
	s.targets.p1 = world
	sync.step(s)

	assert(#sent == 1)
	local d = diff_codec.impl.decode(sent[1].buf, nil, sent[1].unknowns)
	assert(#d.removes == 0 and #d.shift_inserts == 0 and #d.shift_removes == 0)
	assert(next(d.children) == nil, 'expected no nested children')

	local changes_count = 0
	for _ in d.changes do
		changes_count += 1
	end
	assert(changes_count == 1, `expected 1 change, got {changes_count}`)
	assert(d.changes.mutable == 100, `expected mutable=100, got {d.changes.mutable}`)

	local client: any = { persistent = 0, mutable = 0 }
	apply_msg(client, sent[1])
	assert(client.persistent == 0 and client.mutable == 100)
end

function test.should_emit_nothing_when_no_change()
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }
	s.targets.p1 = world
	s.targets.p2 = world
	sync.step(s)
	local count = #sent
	sync.step(s)
	assert(#sent == count, 'no new messages without mutation')
end

return test

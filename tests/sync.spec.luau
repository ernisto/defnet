local diff_codec = require '../lib/utils/diff_codec'
local sync = require '../lib/utils/sync'

local test = {}

type packet = { buf: buffer, unknowns: { any } }
type msg = { target: string, buf: buffer, unknowns: { any } }

local function make_syncer(schema: any?): (sync.syncer<string>, { msg })
	local sent: { msg } = {}
	local s = sync.create {
		idx = diff_codec.build_index(schema),
		send = function(target: string, p: packet)
			table.insert(sent, { target = target, buf = p.buf, unknowns = p.unknowns })
		end,
	}
	return s, sent
end

local function apply_msg(state: any, idx: diff_codec.schema_index, m: msg)
	sync.apply(idx, state, m.buf, m.unknowns)
end

-- basic flow: register, step, mutate
function test.should_send_diff_on_mutation()
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }
	s.targets.p1 = world
	s.targets.p2 = world
	sync.step(s)
	world.coins = 20
	sync.step(s)

	assert(#sent == 4)
	assert(sent[3].buf == sent[4].buf, 'mutation diff must be shared across group')
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
	apply_msg(client, s.idx, sent[1])
	assert(client.coins == 50)
	assert(client.stats.hp == 80)
	assert(client.items[1] == 'a' and client.items[2] == 'b')
end

-- group send / buffer sharing
function test.should_share_buffer_for_targets_with_same_curr()
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }
	s.targets.p1 = world
	s.targets.p2 = world
	sync.step(s)

	assert(#sent == 2, `expected 2 messages, got {#sent}`)
	assert(sent[1].buf == sent[2].buf, 'both targets should receive same buffer ref')
	assert(sent[1].unknowns == sent[2].unknowns, 'both targets should receive same unknowns ref')
end

function test.should_send_one_encode_per_unique_curr()
	local s, sent = make_syncer { coins = 0 }
	local world_a = { coins = 1 }
	local world_b = { coins = 2 }
	s.targets.p1 = world_a
	s.targets.p2 = world_a
	s.targets.p3 = world_b
	sync.step(s)

	assert(#sent == 3)
	local by_target: { [string]: msg } = {}
	for _, m in sent do
		by_target[m.target] = m
	end
	assert(by_target.p1.buf == by_target.p2.buf, 'p1 and p2 share buf')
	assert(by_target.p1.buf ~= by_target.p3.buf, 'p3 gets different buf')
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
	apply_msg(p2_state, s.idx, sent[2])
	assert(p2_state.coins == 10, 'p2 caught up to current state')
end

function test.should_rejoin_group_after_catchup()
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }
	s.targets.p1 = world
	sync.step(s)
	s.targets.p2 = world
	sync.step(s, 'p2')
	world.coins = 20
	sync.step(s)

	local last_two = { sent[#sent - 1], sent[#sent] }
	assert(last_two[1].buf == last_two[2].buf, 'p1 and p2 share group buffer after p2 catch-up')
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
	apply_msg(client, s.idx, sent[1])
	apply_msg(client, s.idx, sent[2])
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

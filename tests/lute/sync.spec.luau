local test = require '@std/test'

local codec = require '../../lib/utils/codec'
local diff_codec = require '../../lib/utils/diff_codec'
local sync = require '../../lib/utils/sync'

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

local function apply_msg(state: any, m: msg, pool)
	sync.apply(state, m.buf, pool, m.unknowns)
end

test.case('should_step_only_specific_target', function(t)
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }

	s.targets.p1 = world
	s.targets.p2 = world
	sync.step(s, 'p1')

	t.eq(#sent, 1)
	t.eq(sent[1].target, 'p1')
end)

-- receiver-side apply
test.case('should_roundtrip_full_state_through_apply', function(t)
	local schema = { coins = 0, items = {}, stats = { hp = 0 } }
	local s, sent = make_syncer(schema)

	s.targets.p1 = { coins = 50, items = { 'a', 'b' }, stats = { hp = 80 } }
	sync.step(s)

	local client: any = {}
	apply_msg(client, sent[1])
	t.eq(client.coins, 50)
	t.eq(client.stats.hp, 80)
	t.eq(client.items[1] == 'a' and client.items[2] == 'b', true)
end)

-- late join / catch-up
test.case('should_catch_up_new_joiner_via_targeted_step', function(t)
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }

	s.targets.p1 = world
	sync.step(s)

	s.targets.p2 = world
	sync.step(s, 'p2')

	t.eq(#sent, 2, 'p1 first tick + p2 catch-up')
	t.eq(sent[1].target, 'p1')
	t.eq(sent[2].target, 'p2')

	local p2_state: any = {}
	apply_msg(p2_state, sent[2])
	t.eq(p2_state.coins, 10, 'p2 caught up to current state')
end)

-- target switches reference
test.case('should_send_resync_when_target_switches_curr', function(t)
	local s, sent = make_syncer { coins = 0 }

	s.targets.p1 = { coins = 1 }
	sync.step(s)

	s.targets.p1 = { coins = 99 }
	sync.step(s)

	t.eq(#sent, 2)
	local client: any = {}
	local client_pool = codec.create_pool()

	apply_msg(client, sent[1], client_pool)
	apply_msg(client, sent[2], client_pool)
	t.eq(client.coins, 99)
end)

-- cleanup / no-op edges
test.case('should_stop_sending_after_remove', function(t)
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }

	s.targets.p1 = world
	sync.step(s)

	sync.remove(s, 'p1')
	world.coins = 99
	sync.step(s)

	t.eq(#sent, 1, 'no messages after remove')
	t.eq(s.snapshots.p1, nil)
end)

-- diff against default
test.case('should_send_only_changed_field_against_default_for_new_target', function(t)
	local s, sent = make_syncer { persistent = 0, mutable = 0 }
	local world = { persistent = 0, mutable = 100 }
	s.targets.p1 = world
	sync.step(s)

	t.eq(#sent, 1)
	local d = diff_codec.impl.decode(sent[1].buf, nil, sent[1].unknowns)
	t.eq(#d.removes == 0 and #d.shift_inserts == 0 and #d.shift_removes == 0, true)
	t.eq(next(d.children), nil, 'expected no nested children')

	local changes_count = 0
	for _ in d.changes do
		changes_count += 1
	end
	t.eq(changes_count, 1, `expected 1 change, got {changes_count}`)
	t.eq(d.changes.mutable, 100, `expected mutable=100, got {d.changes.mutable}`)

	local client: any = { persistent = 0, mutable = 0 }
	apply_msg(client, sent[1])
	t.eq(client.persistent == 0 and client.mutable == 100, true)
end)

test.case('should_emit_nothing_when_no_change', function(t)
	local s, sent = make_syncer { coins = 0 }
	local world = { coins = 10 }

	s.targets.p1 = world
	s.targets.p2 = world
	sync.step(s)

	local count = #sent
	sync.step(s)
	t.eq(#sent, count, 'no new messages without mutation')
end)

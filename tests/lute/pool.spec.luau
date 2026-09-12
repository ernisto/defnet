local test = require '@std/test'

local codec = require '../../lib/utils/codec'
local diff_codec = require '../../lib/utils/diff_codec'
local pool = require '../../lib/utils/pool'
local sync = require '../../lib/utils/sync'

-- helpers
type msg = { target: string, buf: buffer, unknowns: { any }? }

local function make_syncer_with_pools(schema: any?, pools: { [string]: pool.pool }): (sync.syncer<string>, { msg })
	local sent: { msg } = {}
	local s = sync.create {
		default = schema,
		pools = pools,
		send = function(target: string, p: sync.packet)
			table.insert(sent, { target = target, buf = p.buf, unknowns = p.unknowns })
		end,
	}
	return s, sent
end

-- pool factory
test.case('should_create_pool_with_empty_maps', function(t)
	local pool = pool.create()

	t.eq(next(pool.val_to_id), nil)
	t.eq(next(pool.id_to_val), nil)
	t.eq(pool.next_id, 1)
end)

test.case('should_fork_copies_base_entries_and_next_id', function(t)
	local base = pool.create()
	pool.add_value(base, 'seed')
	base.next_id += 5

	local child = pool.fork(base)
	t.eq(child.val_to_id.seed, base.val_to_id.seed)
	t.eq(child.next_id, base.next_id)
end)

-- codec encode/decode: pool is a read-only seed, each call works on a fork
test.case('should_not_mutate_pool_during_encode', function(t)
	local seeded = pool.create()
	pool.add_value(seeded, 'hello')
	local before = seeded.next_id

	codec.impl.encode('world', seeded)

	t.eq(seeded.next_id, before, 'encode works on a fork, base untouched')
	t.eq(seeded.val_to_id.world, nil)
end)

test.case('should_not_mutate_pool_during_decode', function(t)
	local buf = codec.impl.encode 'hello'
	local seeded = pool.create()
	local before = seeded.next_id

	codec.impl.decode(buf, seeded)

	t.eq(seeded.next_id, before, 'decode works on a fork, base untouched')
	t.eq(next(seeded.val_to_id), nil)
end)

test.case('should_dedup_preseeded_value_on_encode', function(t)
	local seeded = pool.create()
	pool.add_value(seeded, 'hello')

	local plain = codec.impl.encode 'hello'
	local pooled = codec.impl.encode('hello', seeded)

	t.that(buffer.len(pooled) < buffer.len(plain), 'seeded value encodes as ref')

	-- refs decode against a paired receiver pool seeded with the same values
	local receiver = pool.create()
	pool.add_value(receiver, 'hello')
	t.eq(codec.impl.decode(pooled, receiver), 'hello')
end)

test.case('should_dedup_preseeded_unknown_on_encode', function(t)
	local seeded = pool.create()
	local inst = function() end
	pool.add_value(seeded, inst)

	local plain, unk_plain = codec.impl.encode(inst)
	local pooled, unk_pooled = codec.impl.encode(inst, seeded)

	t.eq(unk_plain, { inst })
	t.eq(unk_pooled, nil, 'seeded unknown encodes as pool ref, no unknown emitted')
end)

test.case('should_dedup_repeated_value_within_single_encode', function(t)
	local long = 'a_very_long_repeated_string_value'

	local distinct = codec.impl.encode { a = long, b = long .. '_other' }
	local shared = codec.impl.encode { a = long, b = long }

	t.that(buffer.len(shared) < buffer.len(distinct), 'second occurrence in one payload is a ref')
end)

test.case('should_dedup_repeated_table_within_single_encode', function(t)
	local shared = { x = 1, y = 2 }

	local distinct = codec.impl.encode { { x = 1, y = 2 }, { x = 1, y = 2 } }
	local pooled = codec.impl.encode { shared, shared }

	t.that(buffer.len(pooled) < buffer.len(distinct), 'shared subtable encodes as ref')
end)

test.case('should_resolve_pooled_refs_to_same_table_in_one_decode', function(t)
	local shared = { x = 1 }

	local buf, unk = codec.impl.encode { shared, shared }
	local decoded = codec.impl.decode(buf, nil, unk)

	t.eq(decoded[1], decoded[2], 'identity preserved within one decode')
end)

test.case('should_keep_pool_independent_when_not_passed', function(t)
	local seeded = pool.create()
	pool.add_value(seeded, 'hello')
	local before = seeded.next_id

	codec.impl.encode 'hello' -- no pool
	t.eq(seeded.next_id, before, 'unrelated encode must not mutate pool')
end)

test.case('should_isolate_distinct_pools', function(t)
	local pool_a = pool.create()
	local pool_b = pool.create()
	pool.add_value(pool_a, 'hello')

	local pooled = codec.impl.encode('hello', pool_a)
	local bare = codec.impl.encode('hello', pool_b)

	t.that(buffer.len(pooled) < buffer.len(bare), 'only pool_a has the seed')
	t.eq(pool_b.next_id, 1, 'pool_b untouched')
end)

test.case('should_roundtrip_recursive_table_with_pool', function(t)
	local pool_enc = pool.create()
	local pool_dec = pool.create()

	local input = {}
	input.self = input

	local buf, unk = codec.impl.encode(input, pool_enc)
	local decoded = codec.impl.decode(buf, pool_dec, unk)
	t.eq(decoded.self, decoded)
end)

-- diff_codec with pool
test.case('should_roundtrip_diff_with_pool', function(t)
	local pool_enc = pool.create()
	local pool_dec = pool.create()

	local node: any = { children = {}, shift_inserts = {}, shift_removes = {}, changes = { coins = 50 }, removes = {} }

	local buf, unk = diff_codec.impl.encode(node, pool_enc)
	t.eq(diff_codec.impl.decode(buf, pool_dec, unk).changes.coins, 50)
end)

test.case('should_dedup_preseeded_diff_value_via_pool', function(t)
	local seeded = pool.create()
	pool.add_value(seeded, 'alice')

	local node: any =
		{ children = {}, shift_inserts = {}, shift_removes = {}, changes = { name = 'alice' }, removes = {} }

	local bare = diff_codec.impl.encode(node)
	local pooled = diff_codec.impl.encode(node, seeded)
	t.that(buffer.len(pooled) < buffer.len(bare), 'seeded key/value dedup')
end)

-- sync with pools map (pools act as read-only seeds per target)
test.case('should_create_pool_on_demand_per_target', function(t)
	local pools: { [string]: pool.pool } = {}
	local s, sent = make_syncer_with_pools({ coins = 0 }, pools)
	s.targets.p1 = { coins = 10 }

	sync.step(s)
	t.eq(#sent, 1)
	t.that(pools.p1 ~= nil, 'target pool created lazily')
	t.eq(pools.p1.next_id, 1, 'seed pool not mutated by encode')
end)

test.case('should_share_seed_pool_across_multiple_states_for_same_target', function(t)
	local pools: { [string]: pool.pool } = { p1 = pool.create() }
	local s_a, sent_a = make_syncer_with_pools({ name = '' }, pools)
	local s_b, sent_b = make_syncer_with_pools({ label = '' }, pools)

	s_a.targets.p1 = { name = 'shared_string' }
	s_b.targets.p1 = { label = 'shared_string' }

	sync.step(s_a)
	sync.step(s_b)
	t.eq(pools.p1.next_id, 1, 'seed pool stays pristine')

	local client = { name = '', label = '' }
	sync.apply(client, sent_a[1].buf, nil, sent_a[1].unknowns)
	sync.apply(client, sent_b[1].buf, nil, sent_b[1].unknowns)
	t.eq(client.name, 'shared_string')
	t.eq(client.label, 'shared_string')
end)

test.case('should_emit_smaller_packet_with_preseeded_pool', function(t)
	local plain_pools: { [string]: pool.pool } = { p1 = pool.create() }
	local seeded_pools: { [string]: pool.pool } = { p1 = pool.create() }
	pool.add_value(seeded_pools.p1, 'long_unique_name_alpha')

	local s_plain, sent_plain = make_syncer_with_pools({ name = '' }, plain_pools)
	local s_seeded, sent_seeded = make_syncer_with_pools({ name = '' }, seeded_pools)

	s_plain.targets.p1 = { name = 'long_unique_name_alpha' }
	s_seeded.targets.p1 = { name = 'long_unique_name_alpha' }
	sync.step(s_plain)
	sync.step(s_seeded)

	local plain_size = buffer.len(sent_plain[1].buf)
	local seeded_size = buffer.len(sent_seeded[1].buf)
	t.that(
		seeded_size < plain_size,
		`expected seeded pool ref packet smaller, got plain={plain_size} seeded={seeded_size}`
	)
end)

test.case('should_roundtrip_through_paired_sync_pools', function(t)
	local server_pools: { [string]: pool.pool } = { p1 = pool.create() }
	local client_pool = pool.create()

	local s, sent = make_syncer_with_pools({ items = {} }, server_pools)
	local world = { items = { 'sword', 'shield' } }
	s.targets.p1 = world
	sync.step(s)

	local client: any = {}
	sync.apply(client, sent[1].buf, pool.fork(client_pool), sent[1].unknowns)
	t.eq(client.items[1] == 'sword' and client.items[2] == 'shield', true)

	world.items = { 'sword', 'shield', 'bow' }
	sync.step(s)
	sync.apply(client, sent[2].buf, pool.fork(client_pool), sent[2].unknowns)
	t.eq(client.items[3], 'bow', 'second packet applied via paired pool')
end)

test.case('should_isolate_pools_per_target', function(t)
	local pools: { [string]: pool.pool } = {
		p1 = pool.create(),
		p2 = pool.create(),
	}
	pool.add_value(pools.p1, 'seed')
	local s, sent = make_syncer_with_pools({ name = '' }, pools)

	s.targets.p1 = { name = 'seed' }
	s.targets.p2 = { name = 'seed' }
	sync.step(s)

	local sizes = {}
	for _, m in sent do
		sizes[m.target] = buffer.len(m.buf)
	end
	t.that(sizes.p1 < sizes.p2, `only p1 seed applies, got p1={sizes.p1} p2={sizes.p2}`)
end)

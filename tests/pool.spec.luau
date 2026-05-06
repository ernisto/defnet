local codec = require '../lib/utils/codec'
local diff_codec = require '../lib/utils/diff_codec'
local sync = require '../lib/utils/sync'

local test = {}

-- helpers
type packet = { buf: buffer, unknowns: { any } }
type msg = { target: string, buf: buffer, unknowns: { any } }

local function make_syncer_with_pools(schema: any?, pools: { [string]: codec.pool }): (sync.syncer<string>, { msg })
	local sent: { msg } = {}
	local s = sync.create {
		default = schema,
		pools = pools,
		send = function(target: string, p: packet)
			table.insert(sent, { target = target, buf = p.buf, unknowns = p.unknowns })
		end,
	}
	return s, sent
end

-- pool factory
function test.should_create_pool_with_empty_maps()
	local pool = codec.create_pool()

	assert(next(pool.val_to_id) == nil)
	assert(next(pool.id_to_val) == nil)
	assert(pool.next_id == 1)
end

-- codec encode/decode with pool dedup across calls
function test.should_dedup_string_across_encode_calls_with_same_pool()
	local pool_enc = codec.create_pool()
	local pool_dec = codec.create_pool()

	local buf1, unk1 = codec.impl.encode('hello', pool_enc)
	local buf2, unk2 = codec.impl.encode('hello', pool_enc)

	assert(buffer.len(buf2) < buffer.len(buf1), 'second encode must be smaller (ref tag)')

	assert(codec.impl.decode(buf1, pool_dec, unk1) == 'hello')
	assert(codec.impl.decode(buf2, pool_dec, unk2) == 'hello')
end

function test.should_dedup_table_across_encode_calls_with_same_pool()
	local pool_enc = codec.create_pool()
	local pool_dec = codec.create_pool()

	local shared = { x = 1, y = 2 }
	local buf1 = codec.impl.encode(shared, pool_enc)
	local buf2 = codec.impl.encode(shared, pool_enc)

	assert(buffer.len(buf2) < buffer.len(buf1), 'second encode of same table must be smaller')

	local decoded1 = codec.impl.decode(buf1, pool_dec)
	local decoded2 = codec.impl.decode(buf2, pool_dec)
	assert(decoded1 == decoded2, 'pool preserves identity across decode calls')
end

function test.should_grow_pool_next_id_across_encodes()
	local pool = codec.create_pool()
	codec.impl.encode('a', pool)
	local first = pool.next_id

	codec.impl.encode('b', pool)
	assert(pool.next_id > first, 'next_id increments per new value')
end

function test.should_grow_pool_next_id_across_decodes()
	local pool_enc = codec.create_pool()
	local pool_dec = codec.create_pool()

	local b1 = codec.impl.encode('a', pool_enc)
	codec.impl.decode(b1, pool_dec)
	local first = pool_dec.next_id

	local b2 = codec.impl.encode('b', pool_enc)
	codec.impl.decode(b2, pool_dec)
	assert(pool_dec.next_id > first, 'decode side commits next_id')
end

function test.should_keep_pool_independent_when_not_passed()
	local pool = codec.create_pool()
	codec.impl.encode('hello', pool)
	local before = pool.next_id

	codec.impl.encode 'hello' -- no pool
	assert(pool.next_id == before, 'unrelated encode must not mutate pool')
end

function test.should_isolate_distinct_pools()
	local pool_a = codec.create_pool()
	local pool_b = codec.create_pool()

	codec.impl.encode('hello', pool_a)
	assert(pool_b.next_id == 1, 'pool_b untouched')
	assert(pool_a.val_to_id.hello ~= nil)
	assert(pool_b.val_to_id.hello == nil)
end

function test.should_roundtrip_recursive_table_with_pool()
	local pool_enc = codec.create_pool()
	local pool_dec = codec.create_pool()

	local input = {}
	input.self = input

	local buf, unk = codec.impl.encode(input, pool_enc)
	local decoded = codec.impl.decode(buf, pool_dec, unk)
	assert(decoded.self == decoded)
end

-- diff_codec with pool
function test.should_roundtrip_diff_with_pool()
	local pool_enc = codec.create_pool()
	local pool_dec = codec.create_pool()

	local node: any = { children = {}, shift_inserts = {}, shift_removes = {}, changes = { coins = 50 }, removes = {} }

	local buf, unk = diff_codec.impl.encode(node, pool_enc)
	local decoded = diff_codec.impl.decode(buf, pool_dec, unk)
	assert(decoded.changes.coins == 50)
end

function test.should_dedup_repeated_diff_payload_via_pool()
	local pool_enc = codec.create_pool()

	local node1: any =
		{ children = {}, shift_inserts = {}, shift_removes = {}, changes = { name = 'alice' }, removes = {} }
	local node2: any =
		{ children = {}, shift_inserts = {}, shift_removes = {}, changes = { name = 'alice' }, removes = {} }

	local buf1 = diff_codec.impl.encode(node1, pool_enc)
	local buf2 = diff_codec.impl.encode(node2, pool_enc)
	assert(buffer.len(buf2) < buffer.len(buf1), 'repeated key+value dedup')
end

-- sync with pools map
function test.should_use_per_target_pool_in_sync()
	local pools: { [string]: codec.pool } = { p1 = codec.create_pool() }
	local s, sent = make_syncer_with_pools({ coins = 0 }, pools)
	local world = { coins = 10 }
	s.targets.p1 = world

	sync.step(s)
	assert(#sent == 1)
	assert(pools.p1.next_id > 1, 'pool grew during encode')
end

function test.should_share_pool_across_multiple_states_for_same_target()
	local pools: { [string]: codec.pool } = { p1 = codec.create_pool() }
	local s_a, _ = make_syncer_with_pools({ name = '' }, pools)
	local s_b, _ = make_syncer_with_pools({ label = '' }, pools)

	s_a.targets.p1 = { name = 'shared_string' }
	s_b.targets.p1 = { label = 'shared_string' }

	sync.step(s_a)
	local id_after_a = pools.p1.val_to_id.shared_string
	assert(id_after_a ~= nil, 'string registered after first sync')

	sync.step(s_b)
	assert(pools.p1.val_to_id.shared_string == id_after_a, 'second state reuses same id')
end

function test.should_emit_smaller_packet_on_repeated_string_with_persistent_pool()
	local pools: { [string]: codec.pool } = { p1 = codec.create_pool() }
	local s, sent = make_syncer_with_pools({ name = '' }, pools)
	local world = { name = 'long_unique_name_alpha' }
	s.targets.p1 = world
	sync.step(s)
	local first_size = buffer.len(sent[1].buf)

	world.name = 'long_unique_name_alpha_other'
	sync.step(s)
	world.name = 'long_unique_name_alpha' -- already in pool from first packet
	sync.step(s)

	local last_size = buffer.len(sent[#sent].buf)
	assert(last_size < first_size, `expected last packet smaller via ref, got first={first_size} last={last_size}`)
end

function test.should_roundtrip_through_paired_sync_pools()
	local server_pools: { [string]: codec.pool } = { p1 = codec.create_pool() }
	local client_pool = codec.create_pool()

	local s, sent = make_syncer_with_pools({ items = {} }, server_pools)
	local world = { items = { 'sword', 'shield' } }
	s.targets.p1 = world
	sync.step(s)

	local client: any = {}
	sync.apply(client, sent[1].buf, client_pool, sent[1].unknowns)
	assert(client.items[1] == 'sword' and client.items[2] == 'shield')

	world.items = { 'sword', 'shield', 'bow' }
	sync.step(s)
	sync.apply(client, sent[2].buf, client_pool, sent[2].unknowns)
	assert(client.items[3] == 'bow', 'second packet applied via paired pool')
end

function test.should_isolate_pools_per_target()
	local pools: { [string]: codec.pool } = {
		p1 = codec.create_pool(),
		p2 = codec.create_pool(),
	}
	local s, _ = make_syncer_with_pools({ name = '' }, pools)

	s.targets.p1 = { name = 'only_p1' }
	s.targets.p2 = { name = 'only_p2' }
	sync.step(s)

	assert(pools.p1.val_to_id.only_p1 ~= nil)
	assert(pools.p1.val_to_id.only_p2 == nil)
	assert(pools.p2.val_to_id.only_p2 ~= nil)
	assert(pools.p2.val_to_id.only_p1 == nil)
end

return test

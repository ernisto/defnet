local test = require '@std/test'

local diff = require '../../lib/utils/diff'
local prediction = require '../../lib/utils/prediction'

local function cyclic(coins: number): any
	local data = { coins = coins } :: any
	data.self = data
	return data
end

local function add(n: number)
	return function(data: any)
		data.coins += n
	end
end

test.case('should_apply_server_diff_to_both_without_ops', function(t)
	local p = prediction.create { coins = 0, items = {} }
	prediction.receive(p, diff.from(p.server, { coins = 5, items = { 'a' } }))

	assert(p.server.coins == 5 and p.client.coins == 5)
	assert(p.client.items ~= p.server.items, 'client must not share tables with server')
end)

test.case('should_keep_client_identity_and_replay_ops', function(t)
	local client = { coins = 0 }
	local p = prediction.create(client)
	prediction.predict(p, { id = 10, fn = add(1) })
	assert(client.coins == 1 and p.server.coins == 0)

	prediction.receive(p, diff.from(p.server, { coins = 100 }))
	assert(p.client == client and client.coins == 101, 'server diff + replayed op')
end)

test.case('should_hold_ops_across_server_diffs_until_dropped', function(t)
	local p = prediction.create { coins = 0 }
	prediction.predict(p, { id = 1, fn = add(1) })

	prediction.receive(p, diff.from(p.server, { coins = 0 }))
	assert(#p.ops == 1 and p.client.coins == 1, 'op survives server diffs')

	prediction.receive(p, diff.from(p.server, { coins = 1 }))
	assert(prediction.drop(p, 1))
	assert(#p.ops == 0 and p.client.coins == 1, 'settled op leaves the server state that already holds it')
end)

test.case('should_drop_settled_op_without_a_later_diff', function(t)
	local p = prediction.create { coins = 0 }
	prediction.predict(p, { id = 1, fn = add(1) })

	assert(prediction.drop(p, 1))
	assert(p.client.coins == 0, 'server never changed: no diff needed to clear the prediction')
end)

test.case('should_drop_by_id', function(t)
	local p = prediction.create { coins = 0 }
	prediction.predict(p, { id = 1, fn = add(1) })
	prediction.predict(p, { id = 2, fn = add(10) })

	assert(prediction.drop(p, 1))
	assert(p.client.coins == 10)
	assert(not prediction.drop(p, 1))
end)

test.case('should_keep_nested_identity_on_rebuild', function(t)
	local p = prediction.create({ shot = {}, state = {} } :: any)
	local shot = p.client.shot
	prediction.predict(p, {
		id = 1,
		fn = function(data: any)
			data.shot.me = { kind = 'jumpshot' }
		end,
	})
	prediction.receive(p, diff.from(p.server, { shot = { other = { kind = 'dunk' } }, state = {} }))

	assert(p.client.shot == shot, 'nested table identity kept')
	local me, other = shot.me, shot.other
	assert(me.kind == 'jumpshot' and other.kind == 'dunk')
	assert(p.server.shot.me == nil)

	prediction.drop(p, 1)
	assert(shot.me == nil and shot.other.kind == 'dunk')
end)

test.case('should_create_predictor_from_cyclic_client', function(t)
	local client = cyclic(0)
	local p = prediction.create(client)

	t.that(p.server ~= client, 'server must not share tables with client')
	t.that(p.server.self == p.server, 'server cycle points to server')
	t.that(client.self == client, 'client cycle untouched')
end)

test.case('should_replay_ops_over_cyclic_server_diff', function(t)
	local client = cyclic(0)
	local p = prediction.create(client)

	prediction.predict(p, { id = 1, fn = add(1) })
	t.eq(client.coins, 1)

	prediction.receive(p, diff.from(p.server, cyclic(100)))
	t.eq(p.server.coins, 100)
	t.eq(client.coins, 101)
	t.that(p.client == client and client.self == client, 'client identity and cycle kept on rebuild')
	t.that(p.server.self == p.server, 'server cycle kept')
end)

test.case('should_apply_cyclic_server_diff_without_ops', function(t)
	local client = cyclic(0)
	local p = prediction.create(client)

	prediction.receive(p, diff.from(p.server, cyclic(7)))
	t.eq(p.server.coins, 7)
	t.eq(client.coins, 7)
	t.that(client.self == client, 'client cycle kept')
	t.that(p.server.self ~= client, 'server must not point into client')
end)

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
	prediction.receive(p, diff.from(p.server, { coins = 5, items = { 'a' } }), 0)

	assert(p.server.coins == 5 and p.client.coins == 5)
	assert(p.client.items ~= p.server.items, 'client must not share tables with server')
end)

test.case('should_keep_client_identity_and_replay_ops', function(t)
	local client = { coins = 0 }
	local p = prediction.create(client)
	prediction.predict(p, { time = 10, id = 10, fn = add(1) })
	assert(client.coins == 1 and p.server.coins == 0)

	prediction.receive(p, diff.from(p.server, { coins = 100 }), 5)
	assert(p.client == client and client.coins == 101, 'server diff + replayed op')
end)

test.case('should_prune_ops_older_than_server_time', function(t)
	local p = prediction.create { coins = 0 }
	prediction.predict(p, { time = 1, id = 1, fn = add(1) })
	prediction.predict(p, { time = 3, id = 3, fn = add(10) })

	prediction.receive(p, diff.from(p.server, { coins = 0 }), 1)
	assert(#p.ops == 2, 'server_time must be strictly greater')
	prediction.receive(p, diff.from(p.server, { coins = 0 }), 2)
	assert(#p.ops == 1 and p.client.coins == 10)
end)

test.case('should_hold_unsettled_ops_until_settled_time', function(t)
	local p = prediction.create { coins = 0 }
	prediction.predict(p, { time = math.huge, id = 1, fn = add(1) })

	prediction.receive(p, diff.from(p.server, { coins = 0 }), 1000)
	assert(#p.ops == 1 and p.client.coins == 1, 'unsettled op survives any server time')

	assert(prediction.settle(p, 1, 5))
	prediction.receive(p, diff.from(p.server, { coins = 0 }), 5)
	assert(#p.ops == 1)
	prediction.receive(p, diff.from(p.server, { coins = 0 }), 6)
	assert(#p.ops == 0 and p.client.coins == 0)
	assert(not prediction.settle(p, 1, 7))
end)

test.case('should_cancel_by_id', function(t)
	local p = prediction.create { coins = 0 }
	prediction.predict(p, { time = 1, id = 1, fn = add(1) })
	prediction.predict(p, { time = 2, id = 2, fn = add(10) })

	assert(prediction.cancel(p, 1))
	assert(p.client.coins == 10)
	assert(not prediction.cancel(p, 1))
end)

test.case('should_keep_nested_identity_on_rebuild', function(t)
	local p = prediction.create({ shot = {}, state = {} } :: any)
	local shot = p.client.shot
	prediction.predict(p, {
		time = 1,
		id = 1,
		fn = function(data: any)
			data.shot.me = { kind = 'jumpshot' }
		end,
	})
	prediction.receive(p, diff.from(p.server, { shot = { other = { kind = 'dunk' } }, state = {} }), 0)

	assert(p.client.shot == shot, 'nested table identity kept')
	local me, other = shot.me, shot.other
	assert(me.kind == 'jumpshot' and other.kind == 'dunk')
	assert(p.server.shot.me == nil)

	prediction.receive(p, diff.from(p.server, { shot = { other = { kind = 'dunk' } }, state = {} }), 2)
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

	prediction.predict(p, { time = 10, id = 1, fn = add(1) })
	t.eq(client.coins, 1)

	prediction.receive(p, diff.from(p.server, cyclic(100)), 5)
	t.eq(p.server.coins, 100)
	t.eq(client.coins, 101)
	t.that(p.client == client and client.self == client, 'client identity and cycle kept on rebuild')
	t.that(p.server.self == p.server, 'server cycle kept')
end)

test.case('should_apply_cyclic_server_diff_without_ops', function(t)
	local client = cyclic(0)
	local p = prediction.create(client)

	prediction.receive(p, diff.from(p.server, cyclic(7)), 0)
	t.eq(p.server.coins, 7)
	t.eq(client.coins, 7)
	t.that(client.self == client, 'client cycle kept')
	t.that(p.server.self ~= client, 'server must not point into client')
end)

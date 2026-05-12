local ReplicatedStorage = game:GetService 'ReplicatedStorage'

local motion = require(ReplicatedStorage.shared.motion)
local player_data = require(ReplicatedStorage.shared.player_data)
local world = require(ReplicatedStorage.shared.world)

local defnet = require '../lib'
local event, func = defnet.event, defnet.func

return defnet.remotes {
	defnet.batch {
		defnet.ratelimit(5),
		defnet.bandwidth(1024),
	},

	player_data = defnet.state(player_data.default),
	world = defnet.state(world),
	ping = func(),

	spawn_ball = func(),
	pick_ball = func<<(ball_id), ()>>(),
	launch_ball = func<<(ball_id, number, motion.motion), ()>>(),
	motion_changed = event<<(ball_id, motion.motion?)>>(),
	throw_ball = event<<(ball_id, motion.motion & {
		direction: Vector3,
		target: Model,
	})>>(),

	set_guard_state = func<<(boolean)>>(),
}

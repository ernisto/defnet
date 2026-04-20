local diff_codec = require '../utils/diff_codec'

local event = require './event'
local state = require './state'

type request_info = { { Name: string, Data: { any } } }
return function(
	rbxevent: UnreliableRemoteEvent | RemoteEvent | RemoteFunction,
	player: Player,
	args: { any }
): request_info?
	if not args then args = player :: any end

	local event_codec = event.codecs[rbxevent :: any]
	if event_codec then
		return {
			{
				Name = rbxevent:GetFullName():gsub(assert(script.Parent):GetFullName() .. '.', ''),
				Data = { event_codec.decode(args[1], args[2]) },
			},
		}
	end

	local state_idx = state.idxs[rbxevent :: any]
	if state_idx then
		return {
			{
				Name = rbxevent:GetFullName():gsub(assert(script.Parent):GetFullName() .. '.', ''),
				Data = { diff_codec.decode(args[1], args[2], state_idx) },
			},
		}
	end
	return
end

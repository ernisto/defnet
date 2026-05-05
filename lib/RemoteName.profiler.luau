local event = require './event'
type request_info = { { Name: string, Data: { any } } }

return function(
	rbxevent: UnreliableRemoteEvent | RemoteEvent | RemoteFunction,
	player: Player,
	args: { any }
): request_info?
	if not args then args = player :: any end

	local codec = event.codecs[rbxevent :: any]
	if not codec then return end

	return {
		{
			Name = rbxevent:GetFullName():gsub(assert(script.Parent):GetFullName() .. '.', ''),
			Data = { codec.decode(args[1], args[2]) },
		},
	}
end

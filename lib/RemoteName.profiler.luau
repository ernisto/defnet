local codec = require './codec'

return function(event: UnreliableRemoteEvent | RemoteEvent | RemoteFunction, player: Player, args: { any })
	if not event:HasTag 'preserved' then return end
	if not args then args = player :: any end

	return {
		{
			Name = event:GetFullName():gsub(script.Parent:GetFullName() .. '.', ''),
			Data = { codec.decode(args[1], args[2]) },
		},
	}
end

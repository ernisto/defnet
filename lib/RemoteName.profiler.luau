local remote_index = require './remote_index'

-- defs
type request_info = { { Name: string, Data: { any } } }

-- module
return function(
	rbxevent: UnreliableRemoteEvent | RemoteEvent | RemoteFunction | BindableEvent,
	player: Player,
	args: { any }
): request_info?
	if not args then args = player :: any end

	local codec = remote_index.get_codec(rbxevent, args)
	if not codec then return end

	local name, buf, unknowns
	if remote_index.is_unified(rbxevent) then
		local id = args[1] :: number
		name = remote_index.get_name(id) or `unified#{id}`
		buf, unknowns = args[2], args[3]
	else
		name = rbxevent:GetFullName():gsub(assert(script.Parent):GetFullName() .. '.', '')
		buf, unknowns = args[1], args[2]
	end

	return {
		{
			Name = name,
			Data = { codec.decode(buf, table.clone(remote_index.client_pool), unknowns) },
		},
	}
end

export type pool = {
	val_to_id: { [any]: number },
	id_to_val: { [number]: any },
	next_id: number,
}

-- functions
local function create_pool(): pool
	return { val_to_id = {}, id_to_val = {}, next_id = 1 }
end

local function fork(base: pool): pool
	return {
		val_to_id = table.clone(base.val_to_id),
		id_to_val = table.clone(base.id_to_val),
		next_id = base.next_id,
	}
end

local function add_value(pool: pool, value: any): number
	local curid = pool.val_to_id[value]
	if curid then return curid end

	local id = pool.next_id
	pool.next_id += 1

	pool.val_to_id[value] = id
	pool.id_to_val[id] = value
	return id
end

-- module
return table.freeze {
	fork = fork,
	create = create_pool,
	add_value = add_value,
}

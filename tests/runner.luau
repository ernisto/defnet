local suites = {
	require './serde.spec',
}

local function is_test(name: string, value: any): boolean
	return type(value) == 'function' and string.sub(name, 1, 7) == 'should_'
end

local function sorted_keys(t: { [string]: any }): { string }
	local keys = {}
	for key, value in t do
		if is_test(key, value) then table.insert(keys, key) end
	end
	table.sort(keys)
	return keys
end

local total = 0
local failed = 0

for _, suite in suites do
	local keys = sorted_keys(suite)
	for _, name in keys do
		total += 1

		local ok, err = pcall(suite[name])
		if ok then
			print(`ok - {name}`)
		else
			failed += 1
			print(`not ok - {name}`)
			print(err)
		end
	end
end

if failed > 0 then error(`{failed}/{total} tests failed`) end

print(`all tests passed ({total}/{total})`)

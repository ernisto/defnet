local fs = require '@lute/fs'
local process = require '@lute/process'

local result = process.run {
	'git',
	'for-each-ref',
	'--sort=-creatordate',
	'--format=%(refname:short)',
	'--count=1',
	'refs/tags',
}
assert(result.ok, `git for-each-ref failed: {result.stderr}`)

local tag = result.stdout:match '^%s*(.-)%s*$'
if tag == '' then
	print 'no tag found'
	return
end

local version = tag:match '^v?(.+)$' or error(`invalid tag: {tag}`)

local path = 'wally.toml'
local handle = fs.open(path, 'r')
local contents = fs.read(handle)
fs.close(handle)

local updated, n = contents:gsub('version%s*=%s*"[^"]*"', `version = "{version}"`, 1)
assert(n == 1, 'no version field found in wally.toml')

handle = fs.open(path, 'w')
fs.write(handle, updated)
fs.close(handle)

print(`wally.toml version -> {version}`)

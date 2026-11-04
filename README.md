# defnet [![Tests](https://github.com/ernisto/defnet/actions/workflows/check.yml/badge.svg)](https://github.com/ernisto/defnet/actions/workflows/check.yml)

Small Roblox networking library. Declare remotes once, share the module between server and client. Optional binary codec and server-authoritative replicated state.

## Installation

- Download (`defnet.rbxm`) from [latest release](https://github.com/ernisto/defnet/releases/latest)

- Wally (`wally.toml`): add under `[dependencies]`
```toml
defnet = "ernisto/defnet@0.1.0-alpha.10"
```

- Pesde in roblox (terminal):
```sh
pesde add wally#ernisto/defnet
```

## Declare remotes

```lua
-- shared/net.luau
local net = require(ReplicatedStorage.Packages.net)

return net.remotes {
    chat = {
        send = net.event<<(string)>>(),
        history = net.func<<(), ({ string })>>(),
    },
    world = net.state { players = {} :: { [string]: Vector3 } },
}
```

Call `net.remotes(def, root?)` once at module load. Server instantiates the `RemoteEvent`/`RemoteFunction`/`Folder` tree; client `WaitForChild`s it. The def table is mutated in-place and frozen.

## Event

```lua
-- server
net.chat.send.on_server(function(player, message)
    print(player.Name, message)
end)
net.chat.send.fire_all 'hello'
net.chat.send.fire_list({ p1, p2 }, 'hi')
net.chat.send.fire_except(p1, 'not you')

-- client
net.chat.send.on_client(function(message) ... end)
net.chat.send.fire_server 'ping'
```

Pass a codec to `net.event(codec)` to binary-encode payloads. Built-in `net.codec` covers nil, bool, number, string (ASCII), vector, table, buffer. Unknowns (instances, etc.) flow through a side-channel.

## Func

```lua
-- server
function net.chat.history.on_server_invoke(player)
    return {...}
end

-- client
local msgs = net.chat.history.invoke_server()
```

## State

Server-authoritative replicated state. Diffed every `Heartbeat`, only the delta goes on the wire.

```lua
local world = { players = {} }

-- server: write into targets[player]
net.world.server[player1] = world
table.insert(world.players, 'alice')

net.world.server[player2] = world
table.insert(world.players, 'bob')

-- client: read current snapshot
print(net.world.client.players)
```

Call `net.step_sync()` to flush all syncers manually; otherwise it runs on `Heartbeat`.

### Clock

- `defnet.clock()` — server time on client, unlike `Workspace:GetServerTimeNow()` theres no prediction of current server clock, its just last received server clock
- `defnet.server_clock(player?)` — `clock() + ping()`, server's clock() when receive this.
- `defnet.ping(player?)` — round-trip time (`Player:GetNetworkPing`).

### Prediction (client)

`state.server[localplayer]` holds the last received server data, `state.client` is `server` + pending predictions.

```lua
local op = net.world.predict(function(world)
    table.insert(world.players, 'me')
end)

local ok = pcall(net.join.invoke_server)
if ok then
    net.world.settle(op.id) -- server replied: drop once a snapshot sent after now arrives
else
    net.world.cancel(op.id) -- drop it immediately (e.g. server refused)
end
```

Operations stay pending until settled. `settle` stamps them with `defnet.clock()`; they're dropped once a snapshot stamped with server clock `> op.time` arrives (every unified packet carries the server clock). Until then they replay over every new server snapshot, so keep them idempotent and side-effect free. Always settle or cancel, even if the request errors, or the op lives forever.

## License

MIT

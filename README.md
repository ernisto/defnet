# defnet

Small Roblox networking library. Declare remotes once, share the module between server and client. Optional binary codec and server-authoritative replicated state.

## Install

Insert in your wally.toml
```toml
[dependencies]
net = "ernisto/defnet@0.1.0-alpha.2"
```
Or install with pesde
```bash
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

## License

MIT

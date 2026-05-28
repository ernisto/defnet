# 🚀 DefNet

> Fast, typed, secure and lightweight networking framework for Roblox.

DefNet is a networking library focused on:

* ⚡ performance
* 🧠 strong typing
* 🔒 exploit protection
* 🧬 codec support
* 🔄 state replication
* 📦 automatic remote generation

Built for modern Roblox networking.

---

# ✨ Features

## ⚡ Fast Networking

* optimized remote wrappers
* minimal overhead
* delta replication support
* codec pipeline integration
* automatic remote indexing

---

## 🧠 Typed APIs

DefNet supports Luau generics out of the box.

```lua
local event = net.event<number, string>()
local func = net.func<string, boolean>()
```

---

## 🔒 Built-in Security

DefNet now includes:

* schema validation
* rate limiting
* safe callbacks
* invoke timeout protection
* codec validation pipeline

---

## 📦 Automatic Remote Creation

Server automatically creates:

* `RemoteEvent`
* `RemoteFunction`
* folders

Clients automatically fetch and wrap them.

---

## 🧬 Codec Support

Supports custom codecs:

```lua
net.event(my_codec)
```

or:

```lua
net.event({
	codec = my_codec
})
```

Validation is automatically integrated into:

* `encode`
* `decode`

through the codec pipeline.

---

## 🔄 State Replication

Built-in replicated state system with:

* diff replication
* delta syncing
* heartbeat sync
* manual sync support

---

# 📁 Structure

```text
defnet
├─ utils
│  ├─ codec
│  ├─ diff
│  ├─ diff_codec
│  ├─ nan_scanner
│  ├─ sync
│  ├─ guard
│  ├─ types
│  └─ codec_guard
├─ event
├─ func
├─ state
└─ remote_index
```

---

# 📥 Installation

## Wally

```toml
[dependencies]
defnet = "ernisto/defnet@latest"
```

---

# 🚀 Usage

## Shared

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local net = require(ReplicatedStorage.Shared.defnet)
local types = require(ReplicatedStorage.Shared.defnet.utils.types)

return net.remotes({
	damage = net.event({
		schema = {
			types.number,
		},

		rate_limit = 10,
		rate_window = 1,
	}),

	get_coins = net.func({
		timeout = 5,
	}),
})
```

---

## Server

```lua
local remotes = require(path.to.shared_remotes)

remotes.damage:on_server(function(player, amount)
	print(player.Name, amount)
end)

remotes.get_coins.on_server_invoke = function(player)
	return 100
end
```

---

## Client

```lua
local remotes = require(path.to.shared_remotes)

remotes.damage:fire_server(25)

local coins = remotes.get_coins:invoke_server()

print(coins)
```

---

# 🔒 Security

## ✅ Schema Validation

Validate payloads automatically.

```lua
net.event({
	schema = {
		types.number,
		types.string,
	}
})
```

---

## ✅ Rate Limit

Prevent remote spam and flooding.

```lua
net.event({
	rate_limit = 10,
	rate_window = 1,
})
```

---

## ✅ Invoke Timeout

Prevent `InvokeClient()` server hangs.

```lua
net.func({
	timeout = 5
})
```

---

## ✅ Safe Callback Protection

All callbacks are protected using `pcall`.

---

## ✅ Codec Validation Pipeline

Payload validation is integrated directly into:

* `encode`
* `decode`

when using codecs.

---

# 📚 Added Utilities

## `utils/types`

Payload validation utilities.

### Included

* `types.number`
* `types.string`
* `types.boolean`
* `types.table`
* `types.vector3`
* `types.player`
* `types.optional`
* `types.array`
* `types.shape`

---

## `utils/guard`

Central networking protection system.

### Includes

* rate limiting
* payload validation
* safe callback execution
* abuse prevention

---

## `utils/codec_guard`

Codec wrapper for validation-aware encode/decode pipelines.

---

# 🧩 API Compatibility

DefNet keeps full compatibility with:

* existing codecs
* existing descriptors
* existing wrappers
* generic typing
* original API structure

Supported:

```lua
net.event(codec)
net.func()
```

---

# 🧬 Typing Support

DefNet preserves the original Luau generic architecture.

```lua
event_type<T...>
func_type<T..., R...>
```

---

# 🎯 Goals

DefNet aims to be:

* lightweight
* fast
* typed
* secure
* production-ready

while keeping the API minimal and clean.

---

# 🛣️ Planned Features

* player scoped replication
* unreliable remotes
* middleware system
* replication filters
* advanced compression
* ECS integration
* profiling tools
* prediction utilities
* state visibility filtering

---

# ❤️ Credits

Created by Ernisto.
Security and networking improvements contributed by the community.

---

# 📜 License

MIT License.

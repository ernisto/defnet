# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
luau tests/runner.luau

# Benchmarks (always with -O2 --codegen)
luau -O2 --codegen tests/benchmark.luau

# Format
stylua lib/ utils/ tests/

# Check formatting
stylua --check lib/ utils/ tests/
```

### `lib/` — API glue

- `lib/lib.luau` — public entry. Re-exports `event`, `func`, `state`, `step_sync`, and `remotes(def, root?)`. `remotes` walks the definition tree, instantiates or `WaitForChild`s the actual `RemoteEvent`/`RemoteFunction`/`Folder` instances, wraps them, mutates the def in-place, and freezes it. Server creates; client waits. Call once at module load.
- `lib/event.luau` — `event<T...>(codec?)` declaration + `wrap` for `RemoteEvent`. Exposes `fire_server`, `fire_client`, `fire_all`, `fire_list`, `fire_except`, `on_client`, `on_server`. With a codec, payloads go through `encode`/`decode` and the remote gets tagged `'preserved'`.
- `lib/func.luau` — `func<T..., R...>()` declaration + `wrap` for `RemoteFunction`. Exposes `invoke_server`, `invoke_client`, and `on_server_invoke` / `on_client_invoke` (assigned via `__newindex` so they route to the real `OnServerInvoke` / `OnClientInvoke`). Fires a `BindableEvent` (`RemoteFunctionEvent.profiler`) on both call and reply for the profiler.
- `lib/state.luau` — `state<T>(default?)` declaration + `wrap`. Server side owns a `syncer` (from `utils/sync`) with a `targets` map keyed by `Player`. On `Heartbeat`, every registered syncer diffs each target's current state against its last snapshot and fires only the diff. Client side receives `(buf, unknowns)` and applies via `sync.apply`. Exposes `step(player?)` for manual sync and `step_sync()` to flush all registered syncers.
- `lib/RemoteName.profiler.luau` — Roblox Studio profiler hook. Decodes `preserved`-tagged remote payloads for the network profiler panel.

### `utils/` — algorithms

- `utils/codec.luau` — binary buffer serializer. `encode(value) -> (buffer, unknowns)` / `decode(buffer, unknowns?) -> value`. Handles nil, bool, number (f64), string (ASCII only), vector (3×f32), table (seq+hash), buffer. Non-serializable values (instances, coroutines, etc.) go into the `unknowns` side-channel array by reference — they don't cross the wire. Exports `push_value` / `pop_value` / `push_varint` / `pop_varint` for other encoders built on the shared buffer/cursor. `--!native`. Errors on NaN, non-ASCII strings, recursive tables.
- `utils/diff.luau` — pure diff algorithm over nested tables. `compute(prev, curr) -> diff`, `apply(state, diff)`, `clone`, `has_any`. Diff is `{ changes, removes, shift_insertions, shift_removes }` so array shifts encode as a single op instead of N changes.
- `utils/diff_codec.luau` — encode/decode a `diff` into the codec's shared buffer. `build_index(default) -> schema_index` precomputes ids for every path in the schema so paths encode as `(varint schema_node_id, varint unknown_len, unknown keys...)` instead of full path traversal. `encode(diff, idx)` / `decode(buf, unknowns, idx)` require the prebuilt index — no fallback rebuild.
- `utils/sync.luau` — per-receiver diff/send loop. `create { idx, send }` returns a `syncer<Receiver>` with `targets` and `snapshots`. `step(syncer, target?)` diffs each target's current value against its snapshot, encodes once per `curr` (memoized by reference), sends, and updates the snapshot. `remove(syncer, target)` drops both. `apply(idx, state, buf, unknowns)` decodes and applies on the receiver.

### `tests/`

- `tests/runner.luau` — test runner. Tests named `should_*`.
- `tests/codec.spec.luau`, `tests/diff.spec.luau`, `tests/diff_codec.spec.luau`, `tests/sync.spec.luau` — unit tests per util.
- `tests/benchmark.luau` — perf bench. Run with `-O2 --codegen`.

## Key Behaviors

- `event(codec)` — enable binary encoding; remote tagged `'preserved'` so profiler can decode.
- `event()` no arg — raw Roblox values, no encoding.
- `state<T>(default)` — server-authoritative replicated state, diffed on `Heartbeat`, applied on client.
- `codec.encode` errors on NaN, non-ASCII strings, recursive tables.
- Unknowns (instances, coroutines, etc.) flow through the `unknowns` side-channel — never serialized.
- `remotes()` mutates the def table in-place and freezes it. Call once at module load.
- `diff_codec.encode` / `decode` require a prebuilt `schema_index` from `build_index(default)` — no optional fallback.

## Code Style

Enforced by stylua (`stylua.toml`): single quotes, no call parentheses for single args, Unix line endings, sorted requires, Luau syntax. Tests named `should_*`.

- Keep algorithms (`utils/`) decoupled from remote/API glue (`lib/`). Don't import `lib/` from `utils/`.
- Single quotes preferred (`AutoPreferSingle`)
- No parentheses around single-argument calls (`call_parentheses = 'None'`)
- Requires are sorted (`sort_requires.enabled = true`)
- Prefer early returns and `if` expressions over `if` statements
- Use general iterator (`for i, v in tab do`) instead of `pairs()` / `ipairs()` for arrays
- Define all functions as `local`, return them in a `table.freeze {}`
- Avoid closures where possible — e.g. `pcall(net.remote.invoke, data)` not `pcall(function() net.remote.invoke(data) end)`. If a closure just calls a function with the same arguments as its parameters, pass the function directly: `event:Connect(handler)` not `event:Connect(function(x) handler(x) end)`
- Do not `task.spawn` inside event listeners — Roblox already runs each listener in its own thread
- Minimize nesting — reorganize or extract functions to keep tab depth in max 2
- Use the `or error` idiom for inline assertions: `local x = find(player) or error 'not found'`
- Use template strings for error messages: `` error(`{player.Name} has no match`) ``
- Use `assert(condition, message)` over `if not condition then error(message) end` for guard clauses
- Only comments for hacks and sections, do not repeat code with verbose comments
- Avoid redundant type conversions — don't wrap a value in `tostring()`, `tonumber()`, or similar if it is already the correct type
- Use a table for functions with 3 or more data parameters instead of positional arguments: `await_create(request, { experience_id = ..., name = ..., price = ... })` not `await_create(request, experience_id, name, price)`

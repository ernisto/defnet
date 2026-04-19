# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
luau tests/runner.luau

# Format
stylua lib/ tests/

# Check formatting
stylua --check lib/ tests/
```

## Architecture

`vendor/net` is a small Roblox networking library. Three files:

- `lib/lib.luau` — public API. `event<T...>()` and `func<T..., R...>()` are declaration helpers used in `shared/net.luau`. `remotes(def, root?)` instantiates or waits for the actual `RemoteEvent`/`RemoteFunction` instances and wraps them. Server creates; client `WaitForChild`.
- `lib/codec.luau` — binary buffer serializer. `encode(value) -> (buffer, unknowns)` / `decode(buffer, unknowns?) -> value`. Handles nil, bool, number (f64), string (ASCII only), vector (3×f32), table (seq+hash), buffer. Non-serializable values go into the `unknowns` side-channel array by reference.
- `lib/RemoteName.profiler.luau` — Roblox Studio profiler hook. Decodes `preserved`-tagged remote payloads for the network profiler panel.

## Key Behaviors

- `event(codec)` — pass `codec` module as argument to enable binary encoding on that remote. The remote gets tagged `'preserved'` so the profiler can decode it.
- `event()` with no argument — raw Roblox values, no encoding.
- `codec.encode` errors on NaN, non-ASCII strings, and recursive tables.
- Unknown/non-serializable values (instances, coroutines, etc.) are passed through the `unknowns` side-channel — they don't cross the network wire.
- `remotes()` mutates the definition table in-place and freezes it. Call once at module load.

## Code Style

Enforced by stylua (`stylua.toml`): single quotes, no call parentheses for single args, Unix line endings, sorted requires, Luau syntax. Tests named `should_*`.

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


---
name: lute-test
description: Write and run unit tests with lute's built-in @std/test library. Use when adding/editing Luau tests in a lute project, running `lute test`, debugging test discovery/failures, or setting up test conventions (spec files, suites, assertions, lifecycle hooks). Triggers on *.test.luau / *.spec.luau files, `lute test`, `@std/test`, or "write a lute test".
---

# lute-test

Unit testing with lute's first-party `@std/test`. No external runner needed.

## Run

```sh
lute test                  # discover + run all specs in cwd (recursive)
lute test --list           # list discovered cases, don't run
lute test --suite <name>   # only that suite
lute test --case <name>    # only cases matching name
lute test --update         # accept snapshot changes (-u)
lute test --interactive    # accept/reject snapshots one by one (-i)
```

Exit code: `0` all pass, `1` any fail.

## Discovery

Only files named `*.test.luau` or `*.spec.luau` are discovered. Plain `*.luau` and `*_test.luau` are **not**. A spec registers cases at module load — no `return` needed; the runner collects globally registered cases.

## API

```luau
local test = require("@std/test")
```

`@std/test` resolves natively in the lute runtime. For editor/luau-lsp type-checking, add aliases to a `.luaurc` near the tests:
```json
{ "aliases": { "std": "~/.lute/typedefs/1.0.0/std", "lute": "~/.lute/typedefs/1.0.0/lute" } }
```

### Cases

```luau
test.case("descriptive_name", function(t)
    t.eq(1 + 1, 2)
end)
```

The case fn receives `t` — the assertion table. Do **not** use raw `assert`; use `t.*` so failures report file:line + message cleanly.

### Suites + lifecycle hooks

```luau
test.suite("parser", function(s)
    local subject

    s:beforeAll(function() --[[ once before all cases ]] end)
    s:beforeEach(function() subject = make() end)
    s:afterEach(function() subject = nil end)
    s:afterAll(function() --[[ once after all ]] end)

    s:case("parses_empty", function(t)
        t.eq(subject:parse(""), {})
    end)
end)
```

Failures report as `suite.case`. A failing `beforeAll` skips (and fails) every case in the suite.

### Assertions (`t`)

| Call | Passes when |
|------|-------------|
| `t.eq(lhs, rhs, msg?)` | equal — deep for tables, byte-wise for buffers |
| `t.neq(lhs, rhs, msg?)` | not equal |
| `t.that(value, msg?)` | value truthy |
| `t.throws(fn, ...args)` | `fn(...)` errors |
| `t.throwsWith(expected, fn, ...args)` | errors; string `expected` matched as suffix, else deep-equal |
| `t.strContains(haystack, needle, instances?, msg?)` | substring present (exactly `instances` times if given) |
| `t.strNotContains(haystack, needle, msg?)` | substring absent |

Each assertion stops the case on failure. No matcher chaining (`.toBe`) — flat `t.fn(...)` only. Last arg is an optional custom message; prefer it for loop assertions: `t.eq(got, want, `seed {i}`)`.

## Conventions

- **Layout:** tests in `tests/`, one spec per unit/concern (`tests/parser.spec.luau`). Mirror the lib file it covers.
- **Suffix:** prefer `.spec.luau` for behavior specs; `.test.luau` is equivalent.
- **Naming:** snake_case case names that read as a sentence after the unit — `should_return_empty`, `is_deterministic`, `rejects_negative`.
- **Assertions:** always `t.*`, never bare `assert`. Always pass a message on assertions inside loops.
- **Suites:** group with `test.suite` when cases share setup; use hooks instead of copy-pasted setup. Parametrize by generating cases in a loop (`for _, c in cases do s:case(c.name, ...) end`).
- **One tutorial spec:** keep a single `tests/_guide.spec.luau` (see below) — real, passing tests that double as the how-to and a problem→solution cookbook. New contributors read one file; CI keeps it honest.

## The tutorial/cookbook spec

Convention: a single self-documenting spec file is the team's living tutorial. Each common problem becomes a named case showing the solution. Template:

```luau
-- tests/_guide.spec.luau
-- Living tutorial for this project's lute tests. Every case is a runnable
-- example. Add a case here when a testing question/problem recurs.
local test = require("@std/test")

-- ── Basics ──────────────────────────────────────────────
test.case("eq_compares_tables_deeply", function(t)
    t.eq({ a = 1, b = { 2 } }, { a = 1, b = { 2 } })
end)

test.case("assert_errors_with_throws", function(t)
    t.throws(function() error("boom") end)
    t.throwsWith("boom", function() error("boom") end) -- suffix match
end)

-- ── Problem → solution ──────────────────────────────────

-- Problem: a randomized/statistical fn — can't assert one exact value.
-- Solution: assert invariants over many samples; message carries the sample.
test.suite("randomness", function(s)
    local N = 2 ^ 16
    s:case("stays_in_range", function(t)
        for i = 1, N do
            local n = rng.range(1, 10)
            t.that(n >= 1 and n <= 10, `out of range: {n}`)
        end
    end)
end)

-- Problem: shared, expensive setup across cases.
-- Solution: test.suite + beforeAll/beforeEach.
test.suite("with_fixture", function(s)
    local db
    s:beforeAll(function() db = open_db() end)
    s:afterAll(function() db:close() end)
    s:case("reads_back", function(t)
        db:put("k", "v")
        t.eq(db:get("k"), "v")
    end)
end)

-- Problem: many near-identical cases.
-- Solution: generate cases in a loop.
test.suite("table_driven", function(s)
    for _, c in { { 2, 3, 5 }, { -1, 1, 0 } } do
        s:case(`adds_{c[1]}_{c[2]}`, function(t)
            t.eq(add(c[1], c[2]), c[3])
        end)
    end
end)
```

## Gotchas

- Spec must be named `*.spec.luau` / `*.test.luau` or it's silently skipped — verify with `lute test --list`.
- Bare `assert` works but reports a raw runtime error with stacktrace instead of a clean `file:line` assertion entry. Use `t.*`.
- `t.throws`/`t.throwsWith` take the function then its args separately — `t.throws(fn, a, b)`, not `t.throws(function() fn(a,b) end)` (though the closure form also works).
- Snapshot flags (`--update`, `--interactive`) exist in the CLI but aren't in the v1.0.0 typedef assert surface; only `t.*` above are type-checked.
- `@std/test` needs no `.luaurc` alias to *run*, only to type-check in the editor.

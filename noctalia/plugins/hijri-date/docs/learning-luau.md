# Learning Luau — Hijri Date

> **The goal:** in six weeks, you can read every file in this plugin, explain any
> diff line by line, and write a small change without an agent.
>
> **The method:** you do not learn Luau from a tutorial and then apply it. You
> learn it by reading this codebase in slices, retyping its pure functions in a
> scratch file, and using the agent as a reviewer — not as the author.
>
> **The budget:** 30–45 minutes a day, four or five days a week. At least two
> sessions a week have no agent at all.
>
> **The scope:** the Lua/Luau subset this plugin actually uses. Not Roblox, not
> metatables, not the type system, not the whole standard library.

## 1. The honest starting point

This plugin is about 2,500 lines of Luau across four entries. The agent wrote
most of it. That is a real risk, and it is the risk this document exists to fix.

The danger is not that the code is bad. The danger is that the code is
*plausible*: it runs, it looks tidy, and it has comments. You can use it for
months without ever building the mental model that would let you repair it at
3 AM.

The good news is that the plugin is small and has clean seams:

- one entry owns HTTP;
- one entry owns the month cache;
- two entries only render;
- the domain rules are ordinary Lua functions, not a framework.

These notes were written by the same agent that wrote most of the code. Treat
them as a map, not scripture. Pick three claims from the codebase map or the
network map and verify them against the source before you trust the rest.

You do not need to become a Luau expert. You need to become the person who can
answer: **what does this file decide, what breaks if it is wrong, and how would
I know?**

## 2. The AI-independence contract

Copy this into your notes. Tick it honestly. It is the definition of done for
this learning path.

- [ ] I can name the four entries and say which one owns HTTP.
- [ ] I can explain the difference between the civil-day rollover and the
      Maghrib rollover.
- [ ] I can predict the request count for the eight scenarios in
      [network-map.md](network-map.md).
- [ ] I can name the two cache files, their TTL, and their version.
- [ ] I can write `pad2`, `timeToMinutes`, `shiftMonthParts`, and
      `daysInMonth` from scratch.
- [ ] I can make a small panel or widget change, run the checks, and explain
      every line of the diff.
- [ ] I can debug a missing date from the status notification, the log, and the
      cache files.
- [ ] I can ask the agent for a review without asking it for the answer first.

### The rules

1. **No agent-written code is merged until I can explain it.** Not “explain it
   vaguely” — explain what each function decides and what happens if it is
   wrong.
2. **My draft comes first.** For every exercise, write your version before
   asking for the agent's. The difference between the two is the lesson.
3. **Ask “why”, not “write it”.** “Why does `refresh` check `timezone` after
   `tomorrow`?” is a good question. “Fix my refresh function” is not.
4. **One learning-log entry per session.** Four lines are enough: what you
   read, what you predicted, what was actually true, what you still cannot
   explain.
5. **The agent may review, but it may not be your first reader.** Read the
   code once yourself, even badly, before asking.

### Red flags

| Signal | What it means |
| --- | --- |
| You can describe a function's *purpose* but not its *branches* | You have read the comment, not the code. |
| You cannot predict whether a change costs a request | You do not own the network model yet. |
| You would not know which file to open for a bug | You do not own the map yet. |
| You accept a diff because “the agent said it works” | The learning did not happen. |
| You have no commits in this plugin | The strongest proof is still missing. |

## 3. Why this plugin is a good classroom

| Quality | Why it helps |
| --- | --- |
| Small | Four entries, one module, no build system. You can hold the whole topology in your head. |
| Real async | `noctalia.http` callbacks and shared state are the hard part of plugin code, and they are here. |
| Real persistence | Two JSON caches, a TTL, a version, and a plain-text preference file. |
| Real UI | Declarative `ui.*` trees, RTL, language switching, and a panel lifecycle. |
| Real failure paths | Retry backoff, a fallback that can hide failures, and a cache that works offline. |
| No tests | A downside, but it makes you write your own small harness — which is how you learn. |
| Clear risk zones | The service and the panel's cache/fetch code are the dangerous parts; the rest is presentation. |

The lack of tests is the main weakness. You will compensate with three things:
`luac -p` for syntax, the live plugin for behaviour, and a scratch Lua file for
pure functions. The [network map](network-map.md) is the specification for the
request behaviour; use it as your test oracle.

## 4. The Lua/Luau you need

This is not a complete language course. It is the subset that appears in this
plugin, in the order you will meet it.

### 4.1 The shape of a file

A plugin entry is a Lua script that runs when the entry loads. It can define
functions, require modules, and call the host API at the top level.

```lua
--!nonstrict
-- A comment. The `--!nonstrict` line is a Luau type-checking directive; it does
-- not change how the code runs. This plugin uses no type annotations.

local i18n = require("./i18n.luau")   -- a module; returns a table

local RETRY_SECONDS = 5 * 60          -- a file-local constant

local function pad2(n)                -- a file-local function
  return (n < 10 and "0" or "") .. n
end

local function update()               -- a host lifecycle hook
  -- ...
end
```

Things to notice:

- `local` means “visible in this file (or block) only”. Without it, you create a
  global, which is almost always a bug in a plugin.
- The top level runs **once** when the entry loads. `update()` runs later, on
  the interval set by `noctalia.setUpdateInterval`.
- `require("./i18n.luau")` returns whatever `i18n.luau` returns. The relative
  `.luau` form is a Noctalia extension; standard Lua uses module names and
  `package.path`.
- Each entry has its own module cache. The bar widget and the panel each get
  their own `i18n` instance, even though they require the same file.

### 4.2 Values and truthiness

Lua has nil, booleans, numbers, strings, tables, and functions. That is enough
for this entire plugin.

```lua
local name = nil          -- absent
local enabled = false
local count = 42
local label = "Hijri"
local parts = { y = 2026, m = 11, d = 6 }
```

Only `nil` and `false` are falsy. `0` and `""` are **true**:

```lua
if 0 then print("this runs") end
if "" then print("this runs too") end
```

That is why the code is careful with strings:

```lua
local value = noctalia.state.get(key)
if type(value) ~= "string" or value == "" then
  value = noctalia.state.get("hijri.display")
end
```

`and` and `or` return their operands, not a boolean. The `value or fallback`
idiom is everywhere:

```lua
local base = noctalia.getenv("XDG_STATE_HOME")
if base == nil or base == "" then
  base = (noctalia.getenv("HOME") or "") .. "/.local/state"
end
```

`tonumber` converts a string to a number or returns `nil`; `tostring` converts
anything to a string. The API sends numbers as numbers and some fields as
strings, so the code uses both defensively.

### 4.3 Tables

Tables are the only data structure. They are both arrays and maps.

```lua
local weekdays = { "Sunday", "Monday", "Tuesday" }  -- array, 1-based
print(weekdays[1])                                  -- Sunday

local hijri = { y = 1448, m = 5, d = 18 }           -- map
print(hijri.y)                                      -- 1448
print(hijri["m"])                                   -- 5
```

Important details:

- Indexing starts at **1**, not 0.
- `#t` is the length of an array. On a table with holes, the result is
  undefined; do not rely on it.
- `ipairs(t)` walks `1, 2, 3…` and stops at the first `nil`.
- `pairs(t)` walks every key, in an unspecified order.
- `table.insert(t, value)` appends; `table.sort(t, compare)` sorts in place.
- A missing key reads as `nil`; assigning `nil` removes the key.

The caches use both shapes. The Gregorian cache is a map keyed by day number;
the Hijri cache is an array in Hijri day order:

```lua
-- Gregorian cache: days[1] is the first day of the Gregorian month.
-- The key is the Gregorian day number.
days[day] = {
  hy = 1448, hm = 5, hd = 18,
  hn = "Jumada al-Ula", hn_en = "Jumada al-Ula",
}

-- Hijri cache: days[1] is the first day of the Hijri month.
-- The array is in Hijri day order and also carries the Gregorian date.
table.insert(days, {
  hy = 1448, hm = 5, hd = 1,
  gy = 2026, gm = 10, gd = 12,
})
```

When JSON is decoded, objects become string-keyed tables and arrays become
1-based tables. JSON `null` becomes `nil`, which means the key disappears from
the table. That is why `hijri.timezone == nil` is a meaningful check.

### 4.4 Functions, closures, and callbacks

Functions are values. You can pass them to other functions, return them, and
store them in tables.

```lua
local function add(a, b)
  return a + b
end

local function apply(fn, value)
  return fn(value)          -- call the function passed in
end
```

A **closure** is a function that remembers the local variables around it. This
is the most important idea in the service:

```lua
local function fetchBoth(todayDMY)
  fetchDay(todayDMY, function(data)
    -- `data` is captured here and is still available when the second
    -- request finishes, even though fetchBoth has already returned.
    local tomorrowDMY = os.date("%d-%m-%Y", os.time() + 86400)
    fetchDay(tomorrowDMY, function(tomorrowData)
      applyDay(data, tomorrowData)
    end)
  end)
end
```

That is why the first response is not lost while the second request runs. The
callback holds it.

`noctalia.http` is asynchronous:

```lua
noctalia.http({ url = url, method = "GET" }, function(response)
  -- runs later, on this entry's runtime
  if not response.ok or response.status ~= 200 then
    -- handle failure
  end
end)
```

There is no `await`, no promise, and no coroutine in this code. The callback is
the continuation. If you need to keep state between the call and the callback,
use a local upvalue (`pendingG`, `inFlight`) or `noctalia.state`.

`pcall` is the protected-call helper. It returns a boolean and the result or the
error:

```lua
local ok, decoded = pcall(noctalia.json.decode, raw)
if not ok or type(decoded) ~= "table" then
  return nil
end
```

The panel uses `pcall` around JSON decoding. The service does not need it
because `noctalia.json.decode` returns `nil, err` instead of throwing, but
`pcall` is still the general pattern to recognize.

### 4.5 Strings and patterns

Strings are immutable. Concatenate with `..`; format with `string.format`.

```lua
local url = string.format(
  "https://api.aladhan.com/v1/gToHCalendar/%d/%d",
  month,
  year
)

local key = string.format("%04d-%02d", year, month)  -- 2026-11
```

Lua patterns are not regular expressions. The common pieces in this plugin:

| Pattern | Meaning | Example |
| --- | --- | --- |
| `%d` | a digit | `"(%d+):(%d+)"` |
| `%W` | a non-word character | `text:gsub("(%W)", "%%%1")` |
| `^` / `$` | start / end | `value:match("^(%d%d%d%d)%-(%d%d)$")` |
| `( )` | capture | `local hh, mm = text:match("(%d+):(%d+)")` |
| `*`, `+`, `-` | repetition | `"%s+"` |

`string.match` returns the captures; `string.gsub` returns the new string and
the number of substitutions; `string.find` returns the position. The code uses
these for time parsing, URL building, and escaping English month names before
replacing them with translations.

### 4.6 Control flow

```lua
if value == nil then
  return fallback
elseif value == "" then
  return fallback
else
  return value
end

for i = 1, 7 do
  -- numeric for, inclusive
end

for key, entry in pairs(months) do
  -- map iteration, order unspecified
end

for index, day in ipairs(days) do
  -- array iteration, stops at the first nil
end

while not done do
  -- ...
  break
end
```

This plugin does not use `continue` (Luau has it; Lua 5.1 does not), and it
does not use `goto`. Early `return` is the main control-flow tool: most
functions check for `nil`, return, and keep the happy path unindented.

### 4.7 Modules and shared state

`i18n.luau` returns a table:

```lua
local i18n = require("./i18n.luau")
local text = i18n.tr("settings.latitude.label", "Latitude")
```

The module is loaded once per entry. Its file-local variables are private; the
returned table is the public API.

`noctalia.state` is different: it is **shared across entries** of the same
plugin. That is how the service publishes a date and the bar reads it without
sharing Lua memory.

```lua
noctalia.state.set("hijri.display", "Tuesday 18 Jumada al-Ula 1448")

noctalia.state.watch("hijri.display", function(value)
  render()                 -- called when the key changes
end)
```

State is in memory. It survives an entry reload, but not a shell restart. The
panel's month cache is also written to disk, which is why it survives a restart
while the service's day state does not.

### 4.8 The host API

You do not need to memorize the Noctalia API. You need to recognize the handful
of calls this plugin uses:

| Call | What it does |
| --- | --- |
| `noctalia.getConfig(key)` | Reads this plugin entry's declared setting |
| `noctalia.state.get/set/watch` | Reads, writes, and subscribes to shared state |
| `noctalia.http(request, cb)` | Starts an async HTTP request; `cb(response)` runs later |
| `noctalia.json.decode/encode` | JSON ↔ Lua tables |
| `noctalia.formatTime(fmt, nil, zone)` | Formats time in a specific IANA zone |
| `noctalia.getenv`, `readFile`, `writeFile`, `fileExists`, `mkdirAll` | Environment and files |
| `noctalia.pluginDataDir()` | The plugin's writable data directory |
| `noctalia.log`, `noctalia.notify` | Diagnostic log and user notification |
| `noctalia.setUpdateInterval(ms)` | How often `update()` runs |
| `noctalia.togglePanel(id)` | Opens/closes a panel |
| `barWidget.render`, `barWidget.setTooltip`, `barWidget.isVertical` | Bar widget output |
| `desktopWidget.render`, `desktopWidget.setWantsSecondTicks` | Desktop/lock output |
| `ui.row`, `ui.column`, `ui.label`, `ui.box`, `ui.button` | Declarative UI tree |

The entry lifecycle is just functions with known names:

| Entry type | Hooks |
| --- | --- |
| Bar widget | top level, `update()`, `onClick()`, `onRightClick()`, `onIpc(event, payload)` |
| Panel | top level, `onOpen(context)`, `onClose()`, `onIpc(event, payload)` |
| Service | top level, `update()` |
| Desktop widget | top level, `update()` |

If you remember only one thing: **the top level runs once; `update()` is the
recurring tick; callbacks run later.** Most confusion in this plugin comes from
forgetting which of those three is executing.

### 4.9 Time

Lua's time functions are small and sharp:

```lua
os.time()                       -- seconds since the epoch
os.date("%d-%m-%Y")             -- host-local date string
os.date("*t", os.time())        -- table: year, month, day, hour, min, sec, wday
os.time({ year = 2026, month = 11, day = 6 })  -- epoch for a local date
```

`os.date` and `os.time` use the **host's** timezone, not the configured
location's. The plugin uses them for the civil-day cache key and for weekday
lookups. It uses `noctalia.formatTime(..., zone)` for the location's local time:

```lua
local text = noctalia.formatTime("{:%H:%M}", nil, zone)
local hh, mm = text:match("(%d+):(%d+)")
return tonumber(hh) * 60 + tonumber(mm)
```

That distinction — host time versus location time — is the source of the
timezone traps in [network-map.md](network-map.md). Learn it early.

### 4.10 Luau versus Lua

Luau is a Lua 5.1 derivative used by Roblox, with gradual typing and some extra
syntax. Noctalia embeds Luau. This plugin deliberately stays close to plain
Lua:

| Feature | Used here? |
| --- | --- |
| `--!nonstrict` | Yes, as a comment; it does not change runtime behaviour |
| Type annotations (`local x: number`) | No |
| `continue` | No |
| String interpolation (`` `text {value}` ``) | No |
| `task.wait`, Roblox globals | No |
| Metatables, OOP, coroutines | No |
| `require("./file.luau")` | Yes; the relative form is a Noctalia extension |
| `noctalia.*`, `ui.*`, `barWidget.*` | Yes; host APIs, not Lua |

This is why `luac -p` can parse the plugin even though the runtime is Luau. If
you learn Lua 5.4 from a book, almost everything transfers. The new part is the
host API and the async callback style.

## 5. The six-week path

Each week pairs a language concept with a real slice of the plugin. Read the
slice, do the exercise, then answer the checkpoint without looking.

| Week | Read | Learn | Do | Checkpoint |
| --- | --- | --- | --- | --- |
| **1** | `plugin.toml`, `i18n.luau`, `hijri_date_widget.luau` | file shape, tables, strings, modules, UI tree | Exercises 1–3 | Name the four entries; explain why the bar makes no requests; write `timeToMinutes` from scratch |
| **2** | `hijri_date_service.luau` | callbacks, closures, nil, state, time | Exercises 4–5 | Draw the two-request sequence; explain 2/day and Maghrib 0 |
| **3** | `hijri_date_panel.luau` 1–145 and 303–457 | JSON, pcall, files, TTL, table shapes | Exercises 6–7 | Explain both cache files and the 365-day TTL |
| **4** | `hijri_date_panel.luau` 533–717 | pending maps, dedupe, parallel requests | Exercises 8–9 | Predict 3/1/0 and the failure paths |
| **5** | `hijri_date_panel.luau` 720–819, 1007–1272, 1274–1437; `hijri_date_desktop.luau` | UI trees, RTL, selection, i18n | Exercises 10–11 | Trace a click from a cell to the footer and the Today highlight |
| **6** | The rest of the panel; this doc and the network map | integration, verification, ownership | Capstone | Implement the capstone without AI; explain every line |

If a week takes two weeks, take two weeks. The order matters more than the
calendar.

### Week 1 — the shape

Read the manifest first. It tells you what loads and which settings exist. Then
read `i18n.luau` top to bottom: it is a small, self-contained module and a good
first encounter with tables and string patterns. Then read the bar widget,
starting at `render()`.

The bar widget is the best first file because it is a pure consumer: no HTTP,
no cache, no timers beyond `update()`. If you understand how it turns state into
a `ui.row`, you understand half of Noctalia plugin code.

### Week 2 — the service

Read the service in three passes:

1. `fetchDay` → `fetchBoth` → `applyDay`: how a response becomes state.
2. `publishDisplay`: how the stored Maghrib decides today or tomorrow.
3. `refresh` and `update`: how the plugin decides whether to fetch at all.

Do not start with `refresh`. Start with the data flow, then the decision.

### Week 3 — the cache

Read the panel's constants and cache helpers before the UI. The important
questions are:

- What is the cache key?
- What is stored under `days`?
- Why are there two files?
- What happens when `version` does not match?
- When is an entry removed?

The month cache is the only part of the plugin's network data that survives a
shell restart. It is also the only part that can silently serve stale data for
a year.

### Week 4 — the fetch logic

Read `fetchG`, `fetchH`, `ensureG`, `ensureH`, `ensureGView`, and `ensureHView`
together. Draw the call graph. Then answer: why three requests on first open,
but one when paging?

This is the week where the network map becomes useful as a specification, not
just a reference. Predict first, then check.

### Week 5 — the UI

Read the cell builders, then `render`, then the interaction handlers. The UI is
the largest slice by line count but the least dangerous: a wrong label is
visible immediately. The parts worth slowing down for are:

- how the Gregorian and Hijri grids differ;
- how the selected day is stored;
- how the footer is built;
- how RTL mirrors the rows and arrows;
- how the Today button uses `current_h` rather than the civil date.

### Week 6 — own it

Read the remaining watchers and IPC handlers. Then do the capstone. The
capstone is deliberately a real change, not a toy: it touches the cache, the
render path, and the failure path. If you can do it without an agent, you have
crossed from “can read” to “can maintain”.

## 6. Exercises

Do the first pass without an agent. Then ask the agent to review your version
or quiz you. The point is the difference between your attempt and the better
one.

### Exercise 1 — Rebuild `pad2` and `timeToMinutes`

**Goal:** learn functions, strings, patterns, and numeric conversion.

Write `pad2(n)` and `timeToMinutes(text)` in a scratch file. Do not copy the
service code. Use the description:

- `pad2(7)` → `"07"`, `pad2(12)` → `"12"`.
- `timeToMinutes("18:32 (EET)")` → `1112`.
- `timeToMinutes("6:32 pm")` → `1112`.
- `timeToMinutes("12:00 am")` → `0`.
- `timeToMinutes("12:00 pm")` → `720`.
- `timeToMinutes("nonsense")` → `nil`.

Run it with `lua scratch.lua`. Then read the original and compare. What did the
original handle that you missed?

**Done when:** all six cases pass and you can explain the `pm`/`am` branches.

### Exercise 2 — Rebuild the month helpers

**Goal:** learn tables, arithmetic, and edge cases.

Write `daysInMonth(year, month)` and `shiftMonthParts(year, month, delta)` from
scratch. `shiftMonthParts` must handle December → January and January →
December, including the year change. Test leap years: 2024, 1900, 2000.

**Done when:** the functions work for at least 12 hand-written cases, including
both year boundaries.

### Exercise 3 — Trace the bar

**Goal:** learn how state becomes UI without any network.

Pick five display modes (`main`, `both`, `clock`, `clock_hijri`, `clock_both`).
For each, write down which labels appear, in what order, and what the tooltip
shows. Then read `render()` and `updateTooltip()` and correct your table.

**Done when:** your table matches the code, and you can explain why the widget
never calls HTTP.

### Exercise 4 — Draw the service sequence

**Goal:** learn callbacks, closures, and failure branches.

Draw the sequence from `update()` to `applyDay()`. Include:

- success on both requests;
- failure on today;
- failure on tomorrow with a valid fallback;
- failure on tomorrow on the last day of the Hijri month.

Label where `inFlight`, `failed_at`, and `hijri.day` are set.

**Done when:** you can explain why the bar waits for the second request and why
the first response is not lost.

### Exercise 5 — Write the `refresh` truth table

**Goal:** learn conditionals, nil, and state.

Without opening the code, fill in a table for these state combinations:

| `hijri.day` | `today` | `tomorrow` | `timezone` | `failed_at` | Fetch? |
| --- | --- | --- | --- | --- | --- |
| today | set | set | set | nil | |
| today | set | set | nil | nil | |
| today | nil | nil | set | 1 minute ago | |
| today | nil | nil | set | 10 minutes ago | |
| yesterday | set | set | set | nil | |
| today | set | nil | set | 10 minutes ago | |

Then read `refresh()` and correct it. Pay attention to the order of the
`elseif` branches: the first matching branch wins.

**Done when:** you can explain why the timezone branch has no backoff.

### Exercise 6 — Inspect the real cache

**Goal:** learn JSON, table shapes, and persistence.

With the plugin running and the panel used at least once:

```sh
jq '.version, (.months | keys)' \
  ~/.local/state/noctalia/plugins/data/hazembook/hijri-date/gcache.v3.json
jq '.version, (.months | keys)' \
  ~/.local/state/noctalia/plugins/data/hazembook/hijri-date/hcache.v3.json
```

Pick one month from each file and print its first and last day. Then write a Lua
function `validGEntry(entry)` that checks the required keys (`hy`, `hm`, `hd`,
`hn`) and returns `true`/`false`. Feed it a hand-built table that matches the
real shape, and one that is missing a key.

**Done when:** you can explain why the Gregorian cache is keyed by day number
while the Hijri cache is an array.

### Exercise 7 — Reimplement `pruneMonths`

**Goal:** learn `pairs`, mutation during iteration, and time arithmetic.

Write `pruneMonths(months, now, ttl)` from scratch. It must remove entries that
are not tables, have no numeric `fetchedAt`, or are older than `ttl`. Test it
with a fresh entry, an expired entry, and a malformed entry.

**Done when:** the function removes exactly the bad entries and leaves the rest
untouched.

### Exercise 8 — Request-budget quiz

**Goal:** make the network model yours.

Answer these without opening the code, then check
[network-map.md](network-map.md):

1. Cold shell start, one bar, panel never opened. Requests in the first minute?
2. Same shell, after Maghrib. Requests?
3. First panel open in Gregorian mode, then switch to Hijri.
4. Page forward one month, then back one month.
5. Reopen the panel after a shell restart with a warm disk cache.
6. Tomorrow's request fails on the 29th of a 30-day Hijri month.
7. The API response has no `meta.timezone`.
8. The panel opens while the service is in its midnight fetch.

**Done when:** every answer has a number and a one-sentence reason.

### Exercise 9 — Instrument a real panel session

**Goal:** learn observability and verify your model against reality.

In a scratch branch, add `noctalia.log` lines at the start of `fetchG` and
`fetchH` (URL and key) and in `ensureG`/`ensureH` when a cache hit occurs. Open
the panel, page forward twice, switch direction, close, reopen, and read the
log. Compare the actual sequence with your Exercise 8 predictions. Revert the
instrumentation.

**Done when:** the log matches your predicted counts, or you can explain every
difference.

### Exercise 10 — Change a string, then a behaviour

**Goal:** learn the edit → reload → verify loop.

First, change one label in `translations/en.json` and one in
`translations/ar.json`. Reload the plugin and confirm the change in the bar or
panel. Then add a “last updated” line to the bar tooltip using
`hijri.fetched_at`, formatted as a local time. Keep it small and revert it
afterwards if you do not want it.

**Done when:** the change appears live, the other language still works, and
`noctalia plugins lint` passes.

### Exercise 11 — Explain the Today highlight

**Goal:** understand the difference between the civil date and the Maghrib day.

Read `goToday()`, `currentHijri()`, `hijriCellFor()`, and the
`hijri.current_h` watcher. Explain, in writing:

- what the panel highlights before Maghrib;
- what it highlights after Maghrib;
- why the Gregorian grid's highlight still changes at midnight;
- why the muted Gregorian labels under the Hijri grid do not move at Maghrib.

**Done when:** you can answer without reading the code again.

### Capstone — cache age and refresh

**Goal:** make a real, small feature without an agent.

Requirements:

1. In the panel footer, show how old the visible month's cache is, e.g.
   “Updated 3 days ago”. Use `entry.fetchedAt`; handle a missing entry.
2. Add a **Refresh** action for the visible month. It must:
   - clear `failedG[key]` or `failedH[key]`;
   - invalidate only the visible month, not its neighbours;
   - re-fetch it and re-render;
   - leave the rest of the cache intact.
3. Keep the existing loading, error, and Retry behaviour working.
4. Run `luac -p`, `noctalia plugins lint`, and `noctalia config validate`.
5. Test live: open, refresh, page, switch direction, close, reopen.
6. Write a short diff explanation: what changed, why, what could break.

Do the first implementation with no agent. Then ask the agent to review the
diff and point out bugs — not to rewrite it. If it finds something, fix it
yourself and explain the fix.

**Done when:** the feature works, the checks pass, and you can explain every
line of the diff.

## 7. How to use the agent without losing the skill

The agent is useful. The problem is not using it; the problem is using it
before you have tried.

### The 10-minute rule

When you are stuck, spend ten minutes without the agent:

1. Write down what you expected.
2. Write down what actually happened.
3. Find the exact line where the two diverge.
4. Only then ask a specific question.

“Why does `refresh` not retry when `tomorrow` is non-nil?” is a question that
teaches. “Fix it” is a transaction that leaves you where you started.

### Prompt patterns

| Goal | Prompt |
| --- | --- |
| Understand a function | “Explain `fetchBoth` line by line. Do not rewrite it. Point out the upvalues and the failure branches.” |
| Check your model | “I think the panel issues three requests on first open because `ensureGView` calls `ensureG` for the current, previous, and next month. Correct me with line references.” |
| Review your draft | “Here is my implementation of `pruneMonths`. Review it against these requirements. Do not give me code yet; list the bugs and the cases I missed.” |
| Get unstuck | “I expected `after_maghrib` to be true, but the bar still shows today. Here is the state and the relevant code. What are the three most likely causes?” |
| Quiz yourself | “Ask me five questions about the service's retry logic. Wait for my answers, then correct them.” |
| Learn an idiom | “Show me two ways to write this and explain the trade-off. Do not edit the file.” |
| Verify a change | “Here is my diff. What breaks if this is wrong? What should I test manually?” |

### The 20-line rule

If the agent writes more than about 20 lines, do not merge until you have
written a one-line summary of every function it touched. If you cannot summarize
a function, you do not own it yet.

### The diff review

Before any commit:

1. Read the diff in full.
2. For each hunk, say what it changes and what could break.
3. Run the checks.
4. Test the behaviour live, including the failure path if you touched one.
5. Write the commit message yourself. If you cannot describe the change in one
   sentence, the change is too big or you do not understand it.

### The learning log

Keep a file outside the repo, or a `docs/learning-log.md` if you want it
versioned:

```text
Date:
Read:
What I predicted:
What was true:
New concept:
Question for the agent:
Answer in my own words:
Still unclear:
```

Four lines per session is enough. The value is in the “in my own words” line.

### The revert drill

Once a month, break something on purpose in a scratch branch — change the
panel URL to a bad host, or remove the `timezone` check — and fix it without the
agent. This is the closest you will get to the 3 AM test without waiting for
3 AM.

## 8. Checkpoints

| When | Checkpoint | How |
| --- | --- | --- |
| End of week 1 | You can name the four entries and write `timeToMinutes` | Run your scratch tests; explain the bar's zero network |
| End of week 2 | You can draw the service sequence and its failure branches | Whiteboard or paper, no code |
| End of week 3 | You can explain both cache files, the TTL, and the version | Open the JSON and point to each field |
| End of week 4 | You can predict the request counts | Exercise 8, all eight scenarios |
| End of week 5 | You can trace a click and the Today highlight | Walk through `selectCell` → `render` → footer |
| End of week 6 | You implemented the capstone without AI | Checks pass; you explain every line |
| Month 3 | You can read any commit in this plugin and explain it | Pick a commit; no agent |
| Month 3 | You can debug an offline start | Stop the network, restart the shell, explain what works and what does not |

**The real proof:** `git log --author="<you>" --oneline -- noctalia/plugins/hijri-date`
should show at least one commit you wrote. If it does not, the learning is still
in your head, not in the project. The capstone is the commit to aim for.

## 9. What not to learn yet

Do not spend time on these until the plugin forces you to:

- metatables and object-oriented Lua;
- coroutines;
- Luau's full type system, generics, and `--!strict`;
- Roblox APIs;
- the entire Lua standard library;
- performance tuning;
- writing a UI framework or a date library from scratch.

This plugin uses none of them. Learn them when a real change needs them. The
goal is maintenance, not a language certificate.

## 10. Resources

Use these as lookups, not as a reading list:

| Resource | When it helps |
| --- | --- |
| [Luau documentation](https://luau.org/) | The language Noctalia embeds; syntax and type-checking modes |
| [Lua 5.4 manual](https://www.lua.org/manual/5.4/) | Tables, strings, patterns, `os.time`, `pcall` — the parts this plugin uses |
| [Programming in Lua (first edition)](https://www.lua.org/pil/) | A free, readable book; use the chapters on values, tables, functions, and patterns |
| Noctalia plugin docs, `docs/user/plugins/development/` in the Noctalia source tree | Runtime API, entries, manifest, state, UI |
| [Codebase map](codebase-map.md) | Where each behaviour lives and what is risky |
| [Network map](network-map.md) | The request model and the failure modes |

You can run pure Lua with the `lua` binary on this machine. The plugin's host
calls (`noctalia.*`, `ui.*`, `barWidget.*`) only work inside Noctalia. Use
`luac -p` for syntax and the live shell for behaviour.

## 11. The one-screen cheat sheet

```lua
-- variables
local x = 1
local name = "Hijri"
local missing = nil

-- tables
local t = { "a", "b" }            -- t[1] == "a"
local p = { y = 2026, m = 11 }    -- p.y == 2026
table.insert(t, "c")
for i, v in ipairs(t) do end
for k, v in pairs(p) do end

-- functions
local function add(a, b) return a + b end
local f = function(v) return v * 2 end

-- conditions
if x == nil then
  -- ...
elseif x == 0 then
  -- ...
else
  -- ...
end

-- strings
local s = string.format("%04d-%02d", 2026, 11)
local hh, mm = ("18:32"):match("(%d+):(%d+)")
local escaped = ("a.b"):gsub("(%W)", "%%%1")

-- protected call
local ok, value = pcall(noctalia.json.decode, raw)

-- host state
noctalia.state.set("key", value)
local value = noctalia.state.get("key")
noctalia.state.watch("key", function(nextValue) end)

-- host HTTP (callback runs later)
noctalia.http({ url = url, method = "GET" }, function(response)
  if not response.ok or response.status ~= 200 then return end
end)

-- module
local i18n = require("./i18n.luau")
```

If you can read this page and explain each line, you can read most of the
plugin. The rest is the host API and the domain rules, and those are what the
six weeks are for.

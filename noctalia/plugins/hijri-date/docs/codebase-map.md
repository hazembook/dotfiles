# Codebase map — Hijri Date

> **Scope:** plugin 1.8.2 / commit `b0290f7`.
>
> **Goal:** after reading this, you can find the code that owns any behaviour,
> know which parts are risky, and predict what a change will touch.
>
> **Companions:** [network map](network-map.md) · [learning Luau](learning-luau.md)

## 1. What it is

A Noctalia plugin with four runtime entries:

- a **bar widget** that renders the clock, Gregorian date, Hijri date, or a
  combination;
- a **calendar panel** with Gregorian and Hijri month grids and a shared
  "main calendar" choice;
- a **desktop / lock-screen widget** that mirrors the date;
- a **background service** that owns the Aladhan requests and publishes the
  Maghrib-aware Hijri day to every other entry.

It is deliberately small in responsibility: it does not own the shell clock,
the shell date format, the theme, or the calendar calculation. Aladhan supplies
the date mapping; Noctalia supplies the runtime, UI tree, state store, and
persistence paths.

## 2. What it is not

- It is not a general calendar library. There is no reusable date engine.
- It is not a test suite. There is no test runner and no fixture suite.
- It is not a build system. Luau files are loaded directly by Noctalia.
- It is not a location-aware UI. Latitude, longitude, and method are
  plugin-level settings used only by the timing request.
- It is not offline-first for the bar. The panel has a disk cache; the service
  keeps its day only in memory.

## 3. Stack

| Concern | Choice |
| --- | --- |
| Language | Luau, `--!nonstrict` |
| Host | Noctalia plugin API 26 |
| UI | Declarative `ui.*` trees (`panel.render`, `barWidget.render`) |
| Manifest | TOML, `plugin.toml` |
| Data source | `api.aladhan.com` v1 JSON, no authentication |
| Shared state | `noctalia.state` (in-memory pub/sub, per plugin) |
| Panel persistence | JSON month caches on disk |
| Main-calendar persistence | `~/.local/state/noctalia/hijri-date-main` |
| Checks | `luac -p`, `noctalia plugins lint`, `noctalia config validate` |

## 4. Entry topology

| Entry ID | Type | Loaded when | Network |
| --- | --- | --- | --- |
| `hazembook/hijri-date:fetcher` | service | Plugin enabled / shell start | 2 timing requests per civil day |
| `hazembook/hijri-date:date-clock-hijri` | bar widget | Bar instance is created | None |
| `hazembook/hijri-date:calendar` | panel | Panel is opened | 3 / 1 / 0 month requests |
| `hazembook/hijri-date:hijri-date` | desktop / lock widget | Surface is visible | None |
| `i18n.luau` | module | Imported by each entry | None |

The service is independent of the bar. It keeps fetching and publishing even
when the widget is not visible. The panel and widgets are consumers only.

```text
timings ──► service ──► shared state ──► bar widget
                                  ├────► desktop / lock widget
                                  └────► panel (current_h)

gToHCalendar / hToGCalendar ──► panel ──► month cache ──► month grid
```

## 5. Layout

```text
noctalia/plugins/hijri-date/
├── plugin.toml              112 lines  manifest, settings, four entries
├── hijri_date_service.luau  363 lines  network + civil day + Maghrib state
├── hijri_date_widget.luau   349 lines  bar capsule, display modes, clicks
├── hijri_date_panel.luau   1496 lines  month cache, grids, RTL, selection
├── hijri_date_desktop.luau  119 lines  desktop / lock-screen date
├── i18n.luau                183 lines  catalogs, shell language, RTL
├── translations/
│   ├── en.json               93 lines
│   └── ar.json               93 lines
├── README.md                209 lines  behaviour, API counts, settings
├── docs/
│   ├── codebase-map.md      this file
│   ├── network-map.md       requests, cache, rollovers, failure modes
│   └── learning-luau.md     a path from reading to owning the code
└── thumbnail.webp
```

## 6. Reading budget and risk

Read the service and the panel's cache/fetch code most carefully. The UI code
is readable but less dangerous.

| Risk | File / section | Why |
| --- | --- | --- |
| 🔴 | `hijri_date_service.luau` 148–363 | Date correctness, Maghrib, retry/backoff, state publication |
| 🔴 | `hijri_date_panel.luau` 303–457 | Cache format, TTL, date conversions |
| 🔴 | `hijri_date_panel.luau` 554–717 | Fetch/ensure logic, request budget, duplicate suppression |
| 🟡 | `hijri_date_panel.luau` 720–819 | Gregorian/Hijri cell construction and neighbours |
| 🟡 | `hijri_date_panel.luau` 1007–1272 | Panel render, RTL, loading/error states |
| 🟡 | `hijri_date_panel.luau` 1274–1437 | Today, selection, `onOpen`, main-calendar switch |
| 🟡 | `hijri_date_widget.luau` 218–349 | Display modes, Amiri Bold, update cadence, clicks |
| 🟡 | `hijri_date_desktop.luau` | Maghrib rollover computed locally |
| 🟡 | `i18n.luau` | Language and RTL selection |
| 🟢 | `plugin.toml`, `README.md` | Topology and documented behaviour |
| 🟢 | `translations/*.json`, `thumbnail.webp` | Static assets |

**Risk key:** 🔴 read every line · 🟡 read the diff and the main functions ·
🟢 read when it changes.

## 7. State contract

All keys are scoped to the plugin. The service writes; the widgets, desktop
entry, and panel read.

| Group | Keys | Writer | Reader |
| --- | --- | --- | --- |
| Display text | `hijri.today`, `hijri.today_en`, `hijri.tomorrow`, `hijri.tomorrow_en`, `hijri.display`, `hijri.display_ar`, `hijri.display_en` | service | bar, desktop, status |
| Structured dates | `hijri.today_h`, `hijri.tomorrow_h`, `hijri.today_g`, `hijri.tomorrow_g`, `hijri.current_h`, `hijri.current_g`, `hijri.after_maghrib` | service | panel, status |
| Timing | `hijri.maghrib`, `hijri.timezone` | service | service, desktop, status |
| Fetch metadata | `hijri.day`, `hijri.fetched_at`, `hijri.failed_at` | service | service, status |
| Panel cache | `hijri.calendar.gcache.v3`, `hijri.calendar.hcache.v3` | panel | panel |

The text keys are for display. The structured keys exist because the panel
must compare actual dates, not formatted strings.

## 8. File-by-file

### `plugin.toml`

The manifest is the topology. It declares:

- plugin identity and version;
- plugin settings: latitude, longitude, method, week start, Hijri language;
- the bar widget `date-clock-hijri`;
- the desktop widget `hijri-date`;
- the panel `calendar` with its attached, centered placement;
- the service `fetcher`.

If this file is wrong, an entry never loads, a setting silently falls back to
its default, or the panel opens in the wrong place. Read it before reading any
Luau file.

### `hijri_date_service.luau`

The only entry that owns timing requests and the Maghrib rule.

Key functions:

- `fetchDay(dateDMY, callback)` — builds the timings URL and validates the
  response.
- `fetchBoth(todayDMY)` — fetches today, then tomorrow, then calls `applyDay`.
- `applyDay(data, tomorrowData)` — publishes the text, structured dates,
  Maghrib, timezone, and fetch metadata. Also implements the same-month
  fallback when tomorrow's request fails.
- `publishDisplay()` — compares the location's current time with
  `hijri.maghrib` and chooses today or tomorrow. Runs every 60 seconds.
- `refresh()` — decides whether a network fetch is needed: new civil day,
  missing state, missing tomorrow, or missing timezone.
- `update()` — the 60-second tick. Calls `refresh()` then `publishDisplay()`.

If this file is wrong, the bar shows the wrong Hijri day, flips at the wrong
time, retries too often, or publishes stale data after midnight.

### `hijri_date_widget.luau`

The bar consumer. It never calls HTTP.

Key functions:

- `displayMode()` — reads the widget setting and validates the nine modes.
- `hijriDisplay()` — selects Arabic or English text from state, with a
  compatibility fallback to `hijri.display`.
- `render()` — builds the `ui.row` / `ui.column` of labels, separators, and
  Amiri Bold text.
- `update()` — repaints every 60 seconds, or every second when the clock format
  includes seconds.
- `onClick()` / `onRightClick()` — open the panel / flip the main calendar.
- `onIpc()` — `toggle`, `main`, and `status` debugging commands.

If this file is wrong, the capsule shows the wrong mode, the font is wrong, the
tooltip is stale, or clicks stop opening the panel.

### `hijri_date_panel.luau`

The largest file. Read it in slices, not top to bottom.

| Slice | Lines | Responsibility |
| --- | ---: | --- |
| Constants and mutable state | 29–145 | cache version, TTL, paths, pending/failed maps |
| Cache helpers | 303–409 | load, prune, save, validate cached months |
| Date conversions | 411–457 | Gregorian ↔ Hijri lookup from the two caches |
| View resolution | 533–552 | resolve a pending Gregorian date into a Hijri month |
| Fetch and ensure | 554–717 | HTTP, dedupe, cache-on-success, neighbour prefetch |
| Cell builders | 720–819 | Gregorian and Hijri month grids, muted neighbours |
| Render | 1007–1272 | header, weekday row, grid, footer, loading/error, RTL |
| Interactions | 1274–1437 | Today, selection, `onOpen`, main-calendar switch |
| Watchers and IPC | 1439–1496 | main-calendar and Maghrib-rollover repaint, debug commands |

If this file is wrong, the panel fetches too much, shows the wrong month,
highlights the wrong day, or renders the wrong direction.

### `hijri_date_desktop.luau`

The desktop / lock-screen mirror. It reads the same state as the bar but
computes the Maghrib rollover itself, so the date still flips while the
session is locked and the service is idle. It requests second ticks and renders
one Amiri Bold label. No network.

### `i18n.luau`

Loads the JSON catalogs, reads `shell.lang`, applies the `hijri_language`
preference, and exposes RTL detection. Every entry imports it. It reads shell
config, which is why a shell language change can reload an entry without a
network request.

### `translations/*.json` and `README.md`

Static data and the behaviour contract. If behaviour changes, update the README
and the network map; otherwise the next reader will trust a stale document.

## 9. Reading order

Do not read the panel from top to bottom. This order follows the data.

| Time | Read | Question to answer |
| ---: | --- | --- |
| 15 min | `plugin.toml` + README "Plugin", "Usage", "Maghrib", "API calls" | Which entry owns the network? |
| 40 min | `hijri_date_service.luau` | How does a civil day become a Maghrib-aware Hijri day? |
| 20 min | `hijri_date_widget.luau` | How does the bar render with zero network? |
| 60 min | `hijri_date_panel.luau` slices: cache, fetch/ensure, cells, render, interactions | Why 3 requests on first open and 1 when paging? |
| 15 min | `i18n.luau` + `hijri_date_desktop.luau` | Why does language never cause a request? |
| 15 min | Trace the five scenarios below on paper | Can you predict the request count? |

## 10. Checkpoints

If you can answer these without opening the code, you understand the network
side:

1. Why does the bar show a date without ever calling the API?
2. Why does midnight cost two requests but Maghrib cost zero?
3. Why can the panel render offline but the bar cannot after a restart?
4. What happens if tomorrow's request fails on the 29th of a Hijri month?
5. Why is the first panel open three requests, but the second open zero?
6. Why does changing the language not cost a request, while a shell restart
   does?

## 11. Where to change what

| Change | File / location |
| --- | --- |
| Timings URL or query parameters | `hijri_date_service.luau` → `fetchDay` |
| Panel calendar URLs | `hijri_date_panel.luau` → `fetchG`, `fetchH` |
| Service retry delay | `hijri_date_service.luau` → `RETRY_SECONDS` |
| Service tick interval | `hijri_date_service.luau` → `setUpdateInterval(60000)` |
| Panel cache lifetime | `hijri_date_panel.luau` → `CACHE_TTL_SECONDS` |
| Panel cache format | `CACHE_VERSION`, `fetchG`, `fetchH`, `loadCache` |
| Maghrib decision | `hijri_date_service.luau` → `publishDisplay`, `currentLocationMinutes` |
| Bar display modes and font | `hijri_date_widget.luau` → `render` |
| Panel grid, RTL, language | `hijri_date_panel.luau` → `panelLanguage`, `build*Cells`, `render` |
| Panel placement and size | `plugin.toml` → `[[panel]]` |
| Plugin settings | `plugin.toml` → `[[setting]]` |

## 12. Maintenance rules

- **Cache shape changed?** Bump `CACHE_VERSION` and update the `gcache.v3.json`
  / `hcache.v3.json` names. Old files must be ignored, not half-read.
- **State key changed?** Update the service's state comment and every consumer:
  widget, desktop, panel, `status` IPC.
- **Network behaviour changed?** Update [network-map.md](network-map.md) and the
  README's API-call section.
- **Entry added or moved?** Update `plugin.toml` and this map.
- **Behaviour changed?** Add a trap to the network map if it can surprise the
  next reader.

## 13. Verification and observability

```sh
# Syntax, lint, config
for f in noctalia/plugins/hijri-date/*.luau; do luac -p "$f"; done
noctalia plugins lint noctalia/plugins/hijri-date
noctalia config validate

# Runtime status: main, display, language, Maghrib, timezone, fetch times
noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status

# Inspect the persistent month caches
jq '.version, (.months | keys)' \
  ~/.local/state/noctalia/plugins/data/hazembook/hijri-date/gcache.v3.json
jq '.version, (.months | keys)' \
  ~/.local/state/noctalia/plugins/data/hazembook/hijri-date/hcache.v3.json

# Service failures are logged; panel failures are UI-only
grep -i "hijri-date" ~/.cache/noctalia/noctalia.log
```

## 14. What this map borrowed from the playbooks

- **Reading budget / risk tiers:** `AGENTS.md.template`,
  `ownership-matrix.md.template`.
- **Reading order and checkpoints:** `learning-path.md`.
- **AI-independence questions:** `ai-independence.md`.
- **Not used:** the Go-specific reviewer path, test-discipline, review
  playbook, infra learning path, and Makefile targets. This plugin has no Go,
  no test suite, and no build pipeline.

The playbooks kit deliberately has no `codebase-map.md` template: a map must
describe real code. This one does.

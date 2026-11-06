# Network map — Hijri Date

> **Scope:** plugin 1.8.2 / commit `b0290f7`.
>
> **Goal:** after reading this, you can predict every request the plugin makes,
> explain why Maghrib costs nothing, and diagnose a stale or missing date.
>
> **Companions:** [codebase map](codebase-map.md) · [learning Luau](learning-luau.md)

## 1. The split

Two entries own the network, and they do different jobs:

```text
                         aladhan.com
                    ┌────────┴────────┐
        timings     │                 │   gToHCalendar / hToGCalendar
        2/day       │                 │   only when a month is needed
                    ▼                 ▼
             ┌────────────┐    ┌─────────────┐
             │  service   │    │   panel     │
             │  fetcher   │    │  calendar   │
             │  60 s tick │    │  on demand  │
             └─────┬──────┘    └──────┬──────┘
                   │                  │
             plugin state        memory + disk
             (in memory)         month cache
                   │                  │
        ┌──────────┴──────────┐       │
        ▼                     ▼       ▼
   bar widget          desktop/lock   month grid
   (0 network)         widget (0)     (already cached)
```

- **The service** fetches today's and tomorrow's prayer times once per civil
  day. It also owns the Maghrib comparison. Nothing else calls `timings`.
- **The panel** fetches calendar months, but only the months the user is about
  to see. It never calls `timings`.
- **The bar and desktop widgets** never fetch. They render from shared state.

That separation is the whole design. If the bar is stale, the service is the
suspect. If a month grid is missing, the panel is the suspect.

## 2. Request catalogue

| Caller | When | Request | Fields used |
| --- | --- | --- | --- |
| Service | Start, or first tick of a new civil day | `GET https://api.aladhan.com/v1/timings/{DD-MM-YYYY}?latitude={lat}&longitude={lon}&method={method}` | `data.date.hijri`, `data.date.gregorian`, `data.timings.Maghrib`, `data.meta.timezone` |
| Service | Immediately after today's response | The same URL with tomorrow's `DD-MM-YYYY` | Same |
| Panel, Gregorian mode | A Gregorian month is missing or expired | `GET https://api.aladhan.com/v1/gToHCalendar/{month}/{year}` | each `data[]` entry's `.hijri` and `.gregorian` |
| Panel, Hijri mode | A Hijri month is missing or expired | `GET https://api.aladhan.com/v1/hToGCalendar/{month}/{year}` | each `data[]` entry's `.hijri` and `.gregorian` |

Notes:

- The API is public; there is no token, key, or login.
- Only the `timings` URL carries latitude, longitude, and `method`. The two
  calendar endpoints take only month and year.
- The service sends no `Accept` header. The panel sends
  `Accept: application/json`.
- `DD-MM-YYYY` is built with the **host's** `os.date`, not the location's
  timezone. See §10.
- The panel's URLs contain only month and year; the plugin's `method` setting
  never reaches those calls. If the two API surfaces ever disagree about a
  date, the bar and the panel can disagree too.

## 3. A day in the life

```text
civil day D
00:00                 08:00                Maghrib               24:00
  │                     │                       │                   │
  ├─ service +2         ├─ shell start          ├─ service 0        ├─ service +2
  │  timings today      │  +2 if restarted      │  display flips    │  timings today
  │  then tomorrow      │                       │  within 60 s      │  then tomorrow
  ├─ panel 0            ├─ open panel +3        ├─ panel 0          ├─ panel 0
  │                     │  per direction        │                   │
```

The two clocks are deliberately separate:

1. **The civil-day clock** decides when to refetch. It changes at the host's
   midnight, or when the shell starts with no state.
2. **The Maghrib clock** decides which Hijri date is displayed. It is
   recomputed locally every 60 seconds from the fetched Maghrib time.

### Event table

| Event | Service | Panel | Network |
| --- | --- | --- | --- |
| Shell start, no state | Clears the day, fetches today, then tomorrow | Not loaded | **2** sequential |
| Entry reload with complete state | Publishes the existing state | Not loaded | **0** |
| Every 60 s, day complete | Recomputes `after_maghrib`, republishes display | Repaints only if open and a watched key changed | **0** |
| Maghrib | Flips `current_h` to `tomorrow_h`; republishes | Repaints the Today highlight | **0** |
| Civil midnight | Clears day state, fetches today, then tomorrow | Repaints when `current_h` is cleared/republished | **2** |
| Panel open, cold | No change | Fetches current month + previous + next | **3** for that direction (4 in the cold Hijri edge case) |
| Panel open, warm | No change | Reads cache | **0** |
| Page one month | No change | Fetches the one missing neighbour | **1** |
| Jump several months | No change | Fetches up to three months | **≤3** |
| Switch Gregorian ↔ Hijri | No change | Warms the other direction | **≤4** |
| Close panel | No change | In-flight requests finish and are cached | **0** |
| Shell restart | State is gone; fetches again | Disk cache survives | **2** for the service |
| Language or display-mode change | Entry may reload; shared state survives | Repaints | **0** |
| Network dies after the morning fetch | Keeps working all day, including Maghrib | Cached months still render | **0** for the bar; the panel may try on demand |

## 4. Sequence: the service

At start, or at the first tick after midnight:

```text
refresh()
  └─ fetchBoth(todayDMY)
       ├─ GET timings(today)          inFlight = true
       │    └─ success
       ├─ GET timings(tomorrow)       the first response is held in the closure
       │    └─ success or failure
       └─ applyDay(today, tomorrow)
            ├─ publish text keys (Arabic + English)
            ├─ publish structured dates
            ├─ publish Maghrib + timezone
            ├─ clear failed_at
            └─ publishDisplay()
                 └─ choose today or tomorrow by comparing the location's
                    current time with Maghrib
```

The two requests are **sequential**, not parallel. `applyDay` is not called
until the second response returns, so on a cold fetch (shell start or midnight)
the bar does not show today's date until both requests have finished. If the
tomorrow request hangs, the bar stays on “Loading…” even though today's
response already arrived. A refetch that happens while old state is still
present is different: the old date stays visible until `applyDay` replaces it.

On every later tick:

```text
update()
  ├─ refresh()          sees the same civil day and complete state → returns
  └─ publishDisplay()   recomputes after_maghrib from the stored value
```

`publishDisplay` republishes `hijri.display` every minute even when the text is
unchanged. That wakes the bar's state watcher and causes a repaint. It is CPU,
not network.

The immediate `publishDisplay()` at the bottom of the service file exists for a
different reason: when a language change reloads the entry, the shared state is
still there, so the bar should switch languages immediately rather than waiting
for a fetch.

## 5. Sequence: the panel

```text
onOpen()
  ├─ read main calendar (gregorian or hijri)
  ├─ goToday()
  └─ ensureGView(month) or ensureHView(month)
       ├─ ensure(current) → fetch if missing/expired
       ├─ ensure(previous) → fetch if missing/expired
       └─ ensure(next) → fetch if missing/expired
            │
            └─ all three HTTP calls are issued back-to-back, so they overlap
                 ├─ callback → store days → save cache → afterData()
                 └─ afterData() → render if the panel is still open
```

`ensureGView` / `ensureHView` ask for the **current** month and its two
neighbours. The neighbours exist only to fill the muted leading/trailing cells
and to make paging cheap. They are not fetched one at a time.

The panel is lazy: it does not prefetch a year. It keeps only the months that
have been visited, for 365 days.

Paging to the next month asks for the new current, its previous, and its next.
The old “next” is now the current, and the old current is now the previous, so
usually only the new next is missing: **one request**. Jumping several months
can miss up to three.

## 6. Request budget

Let:

- `T(D)` = one `timings` request for date `D`
- `G(Y,M)` = one `gToHCalendar` request
- `H(HY,HM)` = one `hToGCalendar` request

| Trigger | Requests | Count | Notes |
| --- | --- | ---: | --- |
| Shell start, no state | `T(today)`, `T(tomorrow)` | **2** | Sequential; publish waits for both |
| Entry reload with complete state | — | **0** | Shared state survived the reload |
| Every 60-second tick | — | **0** | Local Maghrib recomputation |
| Maghrib | — | **0** | Local comparison only |
| Civil midnight | `T(today)`, `T(tomorrow)` | **2** | Even if yesterday's tomorrow is today |
| First panel open, Gregorian | `G(current)`, `G(prev)`, `G(next)` | **3** | Parallel |
| First panel open, Hijri | `H(current)`, `H(prev)`, `H(next)` | **3** | Parallel; 4 in the cold-start edge case |
| Switch calendar direction | 3 of the other endpoint | **≤4** | 0 if warm; when switching into Hijri, 1 extra if the Gregorian anchor month is cold |
| Page one month | 1 missing month | **1** | Neighbours were prefetched |
| Jump several months | Up to 3 | **≤3** | Current + neighbours |
| Reopen panel, warm | — | **0** | Current + neighbours cached |
| Month older than 365 days | 1 per expired month in view | **1–3** | Expired entries are dropped, then refetched |
| Today request fails | `T(today)` | **1 / 5 min** | Tomorrow is not requested until today succeeds; the successful retry also fires tomorrow |
| Tomorrow fails, fallback valid | `T(today)`, `T(tomorrow)` | **2 once** | Fallback fills `tomorrow`; no more retries that day |
| Tomorrow fails, fallback impossible | `T(today)`, `T(tomorrow)` | **2 / 5 min** | Last day of a Hijri month |
| Timezone missing from response | `T(today)`, `T(tomorrow)` | **2 / 60 s** | No backoff; see §7 |
| Shell restart | `T(today)`, `T(tomorrow)` | **2** | Service state is memory-only |
| Entry reload / language change | — | **0** | Shared state survives |

The **4-request cold-start edge case** for Hijri mode happens when the panel
opens before the service has published `current_h` (for example, during the
midnight fetch) and the Gregorian cache is also cold. `goToday` first fetches
the current Gregorian month (1 request) to resolve the Hijri month, then
`ensureHView` fetches that Hijri month and its neighbours (3 requests).

### Daily totals

```text
steady state, one shell, warm panel:        2 / day
each shell restart:                        +2
first-ever panel, one direction:           +3
first-ever panel, both directions:         +6
each additional month browsed:             +1
Maghrib:                                   +0
```

A normal day with one restart is therefore **4 requests**, not 2. A first-ever
exploration of both calendar directions is normally **8 requests** (2 service +
3 + 3 panel), or **9** in the cold Hijri edge case, before any extra paging.

## 7. Failure and retry behaviour

| Scenario | What the code does | Network effect |
| --- | --- | --- |
| **Today's request fails** | Sets `failed_at`; skips tomorrow; on a cold day the bar shows “Loading…” | 1 request every 5 minutes until today succeeds |
| **Tomorrow's request fails, fallback valid** | `applyDay` computes tomorrow by adding one day to the current Hijri date, then returns normally | 2 requests total; `tomorrow` is non-nil, so `refresh` stops retrying that day |
| **Tomorrow's request fails on the last day of the Hijri month** | Fallback cannot be computed; `tomorrow` stays nil | 2 requests every 5 minutes; after Maghrib the bar keeps showing today's date until a retry succeeds |
| **Panel month fails** | Sets `failedX[key]`; renders an error and a **Retry** button; cached months still render | No automatic retry. Retry is user-driven, or happens when the month is re-entered/reopened |
| **Maghrib is missing from a successful response** | `after_maghrib` stays false; no retry is scheduled | 0 more requests; the bar never rolls over that day |
| **Timezone is missing from a successful response** | `refresh` sees `hijri.timezone == nil` and sets `needsFetch` on every tick | 2 requests per 60 seconds, with no backoff |
| **Network dies after the morning fetch** | Stored Maghrib and dates are enough for the rest of the day | 0 requests for the bar until the next civil day |
| **Shell restarts offline** | Service state is empty; bar shows “Loading…” | Retries every 5 minutes; panel cache still renders |
| **Host refuses an HTTP request** | `noctalia.http` returns `false` and never calls the callback; the panel has already set `pendingX[key]`, and the service's `inFlight` stays true | That month (or the whole service) stays stuck until the entry reloads; see §9 |

Two failure details matter more than they look:

- **The fallback can silence retries.** If tomorrow fails but same-month
  arithmetic succeeds, `hijri.tomorrow` is non-nil. `refresh` therefore thinks
  the day is complete and stops retrying. The fallback is correct only while
  `day < month.days`. On the last day it refuses to guess, and the retry loop
  continues.
- **The bar prefers a stale date over an error after Maghrib.** `publishDisplay`
  falls back to today if tomorrow is unavailable. So a last-day failure shows
  today's Hijri date after Maghrib rather than “Loading…”. The 5-minute retry
  is the only correction.

## 8. Cache, state, and persistence

### In-memory state

`noctalia.state` is a per-plugin key/value store shared by all entries. It is
**not** persisted. It survives an entry reload, but not a shell restart.

| Key group | Examples | Writer | Readers |
| --- | --- | --- | --- |
| Display text | `hijri.today`, `hijri.today_en`, `hijri.tomorrow`, `hijri.tomorrow_en`, `hijri.display`, `hijri.display_ar`, `hijri.display_en` | service | bar, desktop, status |
| Structured dates | `hijri.today_h`, `hijri.tomorrow_h`, `hijri.today_g`, `hijri.tomorrow_g`, `hijri.current_h`, `hijri.current_g`, `hijri.after_maghrib` | service | panel, status |
| Timing | `hijri.maghrib`, `hijri.timezone` | service | service, desktop, status |
| Fetch metadata | `hijri.day`, `hijri.fetched_at`, `hijri.failed_at` | service | service, status |
| Panel cache | `hijri.calendar.gcache.v3`, `hijri.calendar.hcache.v3` | panel | panel |
| Main calendar | `hijri.calendar.main` | widget, panel | widget, panel |

`hijri.day` is the civil day (`DD-MM-YYYY`) the current day state belongs to.
It is the service's cache key. The panel cache has its own keys and TTL.

### On disk

```text
~/.local/state/noctalia/
├── hijri-date-main                      plain text: gregorian | hijri
└── plugins/data/hazembook/hijri-date/
    ├── gcache.v3.json                   Gregorian month pages
    └── hcache.v3.json                   Hijri month pages
```

`noctalia.pluginDataDir()` supplies the cache directory. If it fails, the panel
falls back to `~/.local/state/noctalia/hijri-date/`.

The main-calendar file is written by `setMain` in the bar widget and by the
panel when the user switches calendars. It is read at entry load and on panel
open, so the bar and panel agree after a restart.

### Cache shape

Both files have the same envelope:

```json
{
  "version": 3,
  "months": {
    "2026-09": {
      "fetchedAt": 1793904205,
      "days": [
        { "hy": 1448, "hm": 3, "hd": 19, "hw": "الثلاثاء", "hn": "رَبيع الأوّل", "hn_en": "Rabīʿ al-awwal" }
      ]
    }
  }
}
```

One day is shown above; a real month has 29–31 entries.

- **Gregorian cache** (`gcache.v3.json`): keys are `YYYY-MM`; `days` is indexed
  by Gregorian day of month. Each item is the Hijri date assigned to that day.
- **Hijri cache** (`hcache.v3.json`): keys are `YYYY-MM` of the Hijri year;
  `days` is an array in Hijri day order. Each item adds `gy`, `gm`, `gd`, `gw`
  for the Gregorian counterpart.
- `version` must equal `CACHE_VERSION` (currently `3`). A mismatch makes the
  whole file invisible: the panel starts empty rather than half-reading it.
- `fetchedAt` is `os.time()` at the moment the request was **started**, not when
  it finished.
- `CACHE_TTL_SECONDS` is `365 * 24 * 60 * 60`. Expired entries are removed on
  save and again in `ensureG` / `ensureH` before a refetch.
- The cache is lazy. It contains only months the user has visited.

### Why the two caches exist

The Gregorian page answers “what Hijri date is this Gregorian day?” The Hijri
page answers “what Gregorian date is this Hijri day, and what is the length of
this Hijri month?” The panel needs both directions:

- Gregorian mode builds a Gregorian grid and labels each cell with the Hijri
  date.
- Hijri mode builds a real 29/30-day Hijri grid and labels each cell with the
  Gregorian date.
- `Today` uses the Hijri cache to find the Gregorian cell for the current Hijri
  day; the Maghrib watcher re-renders the grid with the new current day.

## 9. Concurrency and deduplication

### Service

`inFlight` is a single boolean. While a `fetchBoth` cycle is running, every
60-second tick calls `refresh()`, sees `inFlight == true`, and returns. There is
never more than one service request in flight, and the two requests in a cycle
are sequential by design.

If a request never calls back, `inFlight` stays true and the service stops
refreshing until the entry reloads or the shell restarts.

### Panel

`pendingG` and `pendingH` are per-month booleans. A second `ensure` for the same
month while the first request is in flight is a no-op. Different months can run
in parallel. There is no global queue and no cancellation: closing the panel
does not stop an in-flight request; its result is still cached when it arrives.

`afterData()` renders only when `isOpen` is true. A response that arrives after
the panel closes is stored silently.

### Host limit

In the Noctalia host this plugin targets (plugin API 26), each entry host caps
async HTTP at **8** concurrent requests. The panel normally uses 3, but rapid
paging through several views can exceed the cap. The panel does not check the
boolean return value of `noctalia.http`:

```lua
noctalia.http({ url = url, method = "GET", ... }, callback)
```

If the host refuses the request, the callback is never called, but
`pendingG[key]` / `pendingH[key]` was already set to `true`. That month then
looks permanently “in flight” and is never retried until the entry reloads.
This is a host-boundary trap, not a bug in the API.

## 10. Timezone and rollover traps

1. **Two rollovers.** Midnight is the fetch boundary; Maghrib is the display
   boundary. They are different events, with different code paths.
2. **The service day is host-local; Maghrib is location-local.**
   `os.date("%d-%m-%Y")` uses the machine's timezone. Maghrib is compared in
   the API's IANA zone via `noctalia.formatTime(..., zone)`. If the host and the
   configured location are in different zones, the fetched “today” can be the
   wrong civil day for the location.
3. **`os.time() + 86400` is elapsed seconds, not calendar arithmetic.** On a
   25-hour DST fall-back day, adding 86,400 seconds to a time before the
   transition can land on the same calendar date. The tomorrow request and the
   fallback's Gregorian date both use this pattern. It is exact on normal days
   and worth checking if the configured location observes DST.
4. **Maghrib is minute-granular.** Times are `HH:MM`; the flip happens on the
   first 60-second tick at or after the stored minute. Treat it as accurate to
   about a minute, not to the second.
5. **Missing timezone loops.** A response with `meta.timezone == nil` makes
   `refresh` fetch on every tick. There is no backoff on that branch.
6. **Missing Maghrib does not loop.** A response with no `timings.Maghrib`
   leaves `after_maghrib` false all day, with no retry. The bar silently stays
   on today's date.
7. **The fallback can hide a failure.** See §7. A successful arithmetic fallback
   makes `tomorrow` non-nil and suppresses further retries.
8. **The panel's civil mapping does not move at Maghrib.** The API maps a Hijri
   date to a civil Gregorian date. The panel's muted Gregorian labels come from
   that mapping; only the “Today” highlight follows `current_h`.
9. **The panel does not send `method`.** Only the timings call carries it. If
   the calendar endpoints and the timings endpoint disagree, the bar and panel
   can show different dates for the same day.
10. **Service state is not keyed by location or method.** A configuration
    change that reloads the service does not clear the shared state. If the day
    is already complete, the new latitude/longitude/method may not take effect
    until the next civil day or a full shell restart.
11. **A fetch that straddles midnight can publish one stale cycle.** The
    tomorrow date is computed when the first response arrives, not when the
    cycle started. If the clock crosses midnight during the today request, the
    code can pair date `D`'s response with `D+2`'s response and publish it
    briefly. The next 60-second tick sees the civil day changed, clears the
    state, and refetches. It is self-correcting, but visible for up to a minute.

## 11. Observability

```sh
# Syntax, lint, config
for f in noctalia/plugins/hijri-date/*.luau; do luac -p "$f"; done
noctalia plugins lint noctalia/plugins/hijri-date
noctalia config validate

# Runtime status: main, display, language, Maghrib, timezone, fetch times.
# This opens a notification, it does not print to the terminal.
noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status

# Inspect the persistent month caches
jq '.version, (.months | keys)' \
  ~/.local/state/noctalia/plugins/data/hazembook/hijri-date/gcache.v3.json
jq '.version, (.months | keys)' \
  ~/.local/state/noctalia/plugins/data/hazembook/hijri-date/hcache.v3.json

# Today-request failures are logged; tomorrow failures and panel
# failures are silent (check failed_at and the cache instead).
grep -i "hijri-date" ~/.cache/noctalia/noctalia.log
```

What the status fields mean:

| Field | Meaning |
| --- | --- |
| `main` | Shared Gregorian/Hijri choice |
| `display` | Bar widget mode |
| `hijri language` | Effective Hijri language (`auto`, `arabic`, `english`) |
| `gregorian`, `hijri` | What the bar would render now |
| `maghrib` | Minutes since midnight in the location's zone |
| `timezone` | IANA zone from the API response |
| `fetched_at` | Epoch of the last successful `applyDay` |
| `failed_at` | Epoch of the last failed service request |

There is no panel-specific log line. If a month is missing, check the cache
file and the UI's Retry button, not the log.

## 12. Checkpoints

If you can answer these without opening the code, you understand the network
side:

1. Why does the bar show a date without ever calling the API?
2. Why does midnight cost two requests but Maghrib cost zero?
3. Why can the panel render offline but the bar cannot after a restart?
4. What happens if tomorrow's request fails on the 29th of a Hijri month?
5. Why is the first panel open three requests, but the second open zero?
6. Why does changing the language not cost a request, while a shell restart
   does?
7. Why can the bar and the panel disagree about “today” after Maghrib?
8. What is the request cost of paging one month forward, and why?

## 13. Where to change network behaviour

| Change | File / location |
| --- | --- |
| Timings URL or query parameters | `hijri_date_service.luau` → `fetchDay` |
| Panel calendar URLs | `hijri_date_panel.luau` → `fetchG`, `fetchH` |
| Service retry delay | `hijri_date_service.luau` → `RETRY_SECONDS` |
| Service tick interval | `hijri_date_service.luau` → `setUpdateInterval(60000)` |
| Panel cache lifetime | `hijri_date_panel.luau` → `CACHE_TTL_SECONDS` |
| Panel cache shape/version | `CACHE_VERSION`, `fetchG`, `fetchH`, `loadCache` |
| Neighbour prefetch | `hijri_date_panel.luau` → `ensureGView`, `ensureHView` |
| Maghrib decision | `hijri_date_service.luau` → `publishDisplay`, `currentLocationMinutes` |
| Service failure fallback | `hijri_date_service.luau` → `applyDay`, `fetchBoth` |
| Request dedupe | `hijri_date_service.luau` → `inFlight`; panel → `pendingG`/`pendingH` |

If you change any of these, update this file and the README's **API calls**
section in the same commit. A stale network map is worse than no map, because
the next reader will trust it.

# Hijri Date

A Noctalia bar date label and a two-calendar month panel for a fixed
location. The label and the panel share one "main" calendar choice: Gregorian
or Hijri.

![thumbnail](thumbnail.webp)

## Plugin

| Field | Value |
| --- | --- |
| ID | `hazembook/hijri-date` |
| Entries | Bar label: `date-clock-hijri`; desktop/lock widget: `hijri-date`; panel: `calendar`; service: `fetcher` |
| Data source | [aladhan.com](https://aladhan.com) v1 timings + `gToHCalendar` / `hToGCalendar` APIs |
| Plugin API | 19 |

## Usage

Add the `date-clock-hijri` widget from the Add-widget picker and place it on a
bar next to the shell's clock. It shows one date, in the calendar currently
selected as **main**:

- **Gregorian mode** (default) uses the shell's own date format
  (`noctalia.dateFormat()` / `[shell].date_format`), e.g.
  `Tuesday 3 November 2026`.
- **Hijri mode** shows the Hijri date published by the service, e.g.
  `Tuesday 23 Jumada al-Ula 1448` in English or
  `الثلاثاء 23 جُمادى الأولى 1448` in Arabic.

The bar label follows the shell language: with `[shell].lang = "ar"` the
weekday and month names come from the plugin's Arabic catalog, the panel
mirrors to RTL, and every entry re-reads the effective language so a live
language change stays in sync.

**Left click** flips the main calendar. The choice is shared with the panel,
written to `~/.local/state/noctalia/hijri-date-main`, and restored after a
shell restart.

**Right click** opens the plugin's calendar panel.

Hovering the label shows a two-row tooltip with **Gregorian** and **Hijri**
dates. The shell's built-in clock tooltip is a single strftime string and
cannot mix calendars, so it stays out of the way and this label provides the
combined view.

### Bar clock

The example config also uses Noctalia's built-in `clock` widget next to the
label. Its left click is pointed at the plugin's panel, and its right click
opens the shell's own calendar:

```toml
[bar.default]
center = ["hijri-date", "clock"]

[widget.clock]
type = "clock"

[widget.clock.actions]
left = "panel-toggle hazembook/hijri-date:calendar"
right = "panel-toggle control-center calendar"

[widget.hijri-date]
type = "hazembook/hijri-date:date-clock-hijri"
```

### Calendar panel

The panel has a **Gregorian / Hijri** segmented switch above the month title.
Both segments use the same label font and the capsule border stays consistent
in either state. The switch changes the same main-calendar setting as the bar
label, and the grid re-lays out for the selected calendar:

- **Gregorian mode** fetches a Gregorian month from `gToHCalendar` and prints
  the Hijri day under each Gregorian day number.
- **Hijri mode** fetches a real 29- or 30-day Hijri month from
  `hToGCalendar` and prints the Gregorian day under each Hijri day number.

The week starts on **Friday** by default, matching the Hijri week; the
`week_start` setting changes it. In both modes the header shows the month and
the range covered in the other calendar, the footer shows the selected day in
both calendars, and leading/trailing days from the neighbouring months appear
muted. The arrows page through months and **Today** returns to the current
month and selects today. Switching calendars keeps the current selection as
the anchor.

With `[shell].lang = "ar"` the panel is fully Arabic and RTL: month, weekday
and range labels come from the plugin's `ar.json` catalog, the shell mirrors
the grid and header, and the month arrows point the right way for the reading
direction.

Both directions are cached in memory and persistently on disk (under the
plugin's data directory) for 30 days, so paging back and forth, reopening the
panel and restarting the shell do not hit the network again. The neighbouring
months are prefetched so their muted cells fill in. When an in-flight request
fails, the header shows the error and a **Retry** button appears; cached
months keep working offline.

The panel is attached and centered (`position = "center"`,
`open_near_click = false`), so it opens in the middle of the output regardless
of where the bar was clicked.

Open, close or toggle it from a keybinding or the CLI:

```sh
noctalia msg panel-toggle hazembook/hijri-date:calendar
```

## Maghrib and the civil Hijri date

The bar's Hijri date follows the **Maghrib-to-Maghrib** day: the service
fetches today's and tomorrow's Hijri dates plus Maghrib, and publishes the
next date once Maghrib has passed in the location's own time zone.

The panel's grid uses the **civil** Hijri date assigned to each Gregorian day,
as printed calendars do. In the window between Maghrib and midnight the bar
label already shows the next Hijri day while today's cell still shows the
civil date. This is intentional: the label is a live clock, while the grid is
a month reference.

The service is a headless entry, so the fetch keeps running even when the
label is not on a bar. One successful response is kept for the whole Gregorian
day, since the Hijri date only changes at Maghrib. A failed request backs off
for five minutes instead of retrying on every tick, and the previous day's
values are dropped when the Gregorian date rolls over, so a failed request can
never leave a stale Hijri date on the bar.

The date, month name and weekday follow the shell language: English names in
an English shell, Arabic names under `[shell].lang = "ar"`. The Hijri month
length is taken from the API, so the grid stays correct around month rollovers.

## Settings

The location settings are plugin-level (Settings → Plugins → Hijri Date),
because the service is the one that fetches:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `latitude` | `string` | `32.8872` | Latitude of the location used for prayer times and the Hijri date. |
| `longitude` | `string` | `13.1913` | Longitude of the location used for prayer times and the Hijri date. |
| `method` | `string` | `3` | Hijri calculation method (3 = Muslim World League, 4 = Umm al-Qura). |
| `week_start` | `select` | `friday` | First day of the week in the calendar grid (Friday by default). |

The Gregorian label and the clock are formatted by the shell, so change them
in Settings → Shell (or in `[shell].time_format` / `[shell].date_format`).
The panel and bar label language follows **Settings → Appearance → Language**
(`[shell].lang`); choose Arabic for the RTL layout.

## Debugging

```sh
# Show the shared main calendar, both dates and the service timestamps.
noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status

# Flip the main calendar from the CLI.
noctalia msg plugin hazembook/hijri-date:date-clock-hijri all toggle
noctalia msg plugin hazembook/hijri-date:date-clock-hijri all main hijri

# Jump the open panel to a month without clicking through it.
noctalia msg plugin hazembook/hijri-date:calendar all goto 1448-05
noctalia msg plugin hazembook/hijri-date:calendar all main gregorian
```

# Hijri Date

A configurable Noctalia bar capsule (clock, Gregorian date, Hijri date, or a
combination) and a two-calendar month panel for a fixed location. The capsule
and the panel share one "main" calendar choice: Gregorian or Hijri.

![thumbnail](thumbnail.webp)

## Plugin

| Field | Value |
| --- | --- |
| ID | `hazembook/hijri-date` |
| Entries | Bar widget: `date-clock-hijri`; desktop/lock widget: `hijri-date`; panel: `calendar`; service: `fetcher` |
| Data source | [aladhan.com](https://aladhan.com) v1 timings + `gToHCalendar` / `hToGCalendar` APIs |
| Plugin API | 26 |

## Usage

Add the `date-clock-hijri` widget from the Add-widget picker. Its `display`
setting selects what the capsule shows:

| Mode | Content |
| --- | --- |
| `main` (default) | The date of the calendar currently selected as **main** |
| `gregorian` | Gregorian date only |
| `hijri` | Hijri date only |
| `both` | Both dates |
| `clock` | Clock only |
| `clock_main` | Clock + main date |
| `clock_gregorian` | Clock + Gregorian date |
| `clock_hijri` | Clock + Hijri date |
| `clock_both` | Clock + both dates |

The clock is always **bold** and the dates use the regular weight. When both
dates are shown, the clock sits between them with thin separators for
readability: **Gregorian │ clock │ Hijri**. The Gregorian date uses the
shell's own format (`noctalia.dateFormat()` /
`[shell].date_format`), e.g. `Tuesday 3 November 2026`. The Hijri date comes
from the service, e.g. `Tuesday 23 Jumada al-Ula 1448` in English or
`الثلاثاء 23 جُمادى الأولى 1448` in Arabic.

The `hijri_language` setting chooses the Hijri date language independently of
the shell language: `auto` follows the shell, `arabic` keeps the Hijri date in
Arabic even in an English shell, and `english` does the reverse. Panel layout
still follows the shell's reading direction.

**Left click** flips the main calendar. The choice is shared with the panel,
written to `~/.local/state/noctalia/hijri-date-main`, and restored after a
shell restart.

**Right click** opens the plugin's calendar panel.

The tooltip is only used for dates that are not already visible: with both
dates on the bar it is cleared, with one date it shows the other one, and with
the clock alone it shows both.

### Bar widget

One capsule can replace both the shell clock and a separate date label:

```toml
[bar.default]
center = ["hijri-date"]

[widget.hijri-date]
type = "hazembook/hijri-date:date-clock-hijri"
display = "clock_both"

[plugin_settings."hazembook/hijri-date"]
hijri_language = "arabic"
week_start = "friday"
```

Drop the `display` key for the default `main` mode, or pick any mode from the
table above.

### Calendar panel

Two separate pills sit above the month title: **Gregorian** on the far left
and **Hijri** on the far right, in both LTR and RTL layouts. They are not
joined into one shared capsule, so the active calendar reads as one
independent button. Choosing one changes the same main-calendar setting as
the bar widget, and the grid re-lays out for the selected calendar:

- **Gregorian mode** fetches a Gregorian month from `gToHCalendar` and prints
  the Hijri day under each Gregorian day number.
- **Hijri mode** fetches a real 29- or 30-day Hijri month from
  `hToGCalendar` and prints the Gregorian day under each Hijri day number.

The week starts on **Friday** by default, matching the Hijri week; the
`week_start` setting changes it. In both modes the header shows the month and
the range covered in the other calendar, the footer shows the selected day in
both calendars, and leading/trailing days from the neighbouring months appear
muted. The arrows page through months and **Today** returns to the current
month and selects today. Clicking another day moves the selection; clicking
the selected day again clears it, so the highlight and footer details go back
to the hint. Switching calendars keeps the current selection as the anchor.

With `[shell].lang = "ar"` the panel is RTL: textual labels come from the
plugin's `ar.json` catalog, the shell mirrors the grid and header, and the
month arrows point the right way for the reading direction. Hijri month and
weekday names follow `hijri_language`, so they can stay Arabic in an English
shell.

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

The Hijri date, month name and weekday follow `hijri_language`: `auto` uses
the shell language, `arabic` keeps them Arabic in an English shell, and
`english` does the reverse. The Hijri month length is taken from the API, so
the grid stays correct around month rollovers.

## Settings

The location settings are plugin-level (Settings → Plugins → Hijri Date),
because the service is the one that fetches:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `latitude` | `string` | `32.8872` | Latitude of the location used for prayer times and the Hijri date. |
| `longitude` | `string` | `13.1913` | Longitude of the location used for prayer times and the Hijri date. |
| `method` | `string` | `3` | Hijri calculation method (3 = Muslim World League, 4 = Umm al-Qura). |
| `week_start` | `select` | `friday` | First day of the week in the calendar grid (Friday by default). |
| `hijri_language` | `select` | `auto` | Hijri date language: `auto` (follow shell), `arabic`, or `english`. |

The bar widget's `display` setting is per widget instance (Settings → Bar →
Hijri Date, or `[widget.<name>] display = "…"` in the config):

| Value | Content |
| --- | --- |
| `main` | Main calendar date only (default) |
| `gregorian` / `hijri` | One calendar only |
| `both` | Both dates |
| `clock` | Clock only |
| `clock_main` / `clock_gregorian` / `clock_hijri` / `clock_both` | Clock plus the selected dates |

The Gregorian date and the clock are formatted by the shell, so change them
in Settings → Shell (or in `[shell].time_format` / `[shell].date_format`).
The panel and UI language follows **Settings → Appearance → Language**
(`[shell].lang`); choose Arabic for the RTL layout. The Hijri date itself can
stay Arabic through `hijri_language`.

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

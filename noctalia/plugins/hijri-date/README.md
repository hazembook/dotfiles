# Hijri Date

A Noctalia bar widget that shows the Gregorian date, the clock and the Hijri
date for a fixed location, in one pill.

![thumbnail](thumbnail.webp)

## Plugin

| Field | Value |
| --- | --- |
| ID | `hazembook/hijri-date` |
| Entries | Bar widget: `date-clock-hijri`; service: `fetcher` |
| Data source | [aladhan.com](https://aladhan.com) v1 timings API |
| Plugin API | 19 |

## Usage

Add the `date-clock-hijri` widget from the Add-widget picker and place it on a
bar. It shows:

```
Wednesday, 10/21/2026 | 20:11 | الخميس 11 جُمادى الأولى 1448
```

The clock and the Gregorian date come from Noctalia's own formats
(`noctalia.timeFormat()` and `noctalia.dateFormat()`), so they are exactly what
the shell's clock widget and calendar show, and they follow the shell's
`[shell].time_format` and `[shell].date_format` settings.

The Hijri day runs from **Maghrib to Maghrib**, so the date flips to the next
Hijri day once Maghrib has passed. Maghrib comes from the same API response
and is compared against the current time *in the location's own time zone* —
not by comparing formatted strings, and not in the system zone.

Clicking the widget opens the shell's calendar panel.

The `fetcher` service does the requests and publishes the date that is
currently valid; the widget only renders it. The service is a headless entry,
so the fetch keeps running even when the widget is not on a bar.

A successful response is reused for an hour, since the Hijri date only changes
at Maghrib. A failed request backs off for five minutes instead of retrying on
every tick, and the previous day's values are dropped when the Gregorian date
rolls over, so a failed request can never leave a stale Hijri date on the bar.

The date, month name and weekday are shown exactly as the API spells them
(`الاربعاء`, `جُمادى الأولى`). The Hijri month length is taken from the API,
so the widget stays correct around month rollovers.

## Settings

The location settings are plugin-level (Settings → Plugins → Hijri Date),
because the service is the one that fetches:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `latitude` | `string` | `32.8872` | Latitude of the location used for prayer times and the Hijri date. |
| `longitude` | `string` | `13.1913` | Longitude of the location used for prayer times and the Hijri date. |
| `method` | `string` | `3` | Hijri calculation method (3 = Muslim World League, 4 = Umm al-Qura). |

The clock and the date are formatted by the shell, so change them in
Settings → Shell (or in `[shell].time_format` / `[shell].date_format`).

## Debugging

```sh
noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status
```

shows the currently displayed date, the Maghrib minutes, the location's time
zone and the cache timestamps in a notification.

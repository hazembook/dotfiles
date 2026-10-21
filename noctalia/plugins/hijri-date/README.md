# Hijri Date

A Noctalia bar widget that shows the Gregorian date, the clock and the Hijri
date for a fixed location.

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
Wed 21 Oct 2026 | 20:07 | الخميس 11 جُمادى الأولى 1448
```

The Hijri day runs from **Maghrib to Maghrib**, so the date flips to the next
Hijri day once Maghrib has passed. Maghrib comes from the same API response
and is compared in minutes since midnight, in the location's own time zone —
not by comparing formatted strings.

Clicking the widget opens the shell's calendar panel.

The `fetcher` service does the requests and publishes the result through the
plugin's shared state; the widget only renders. The service is a headless
entry, so the fetch keeps running even when the widget is not on a bar.

A successful response is reused for an hour, since the Hijri date only changes
at Maghrib. A failed request backs off for five minutes instead of retrying
on every tick, and the previous day's values are dropped when the Gregorian
date rolls over, so a failed request can never leave a stale Hijri date on
the bar.

The Hijri date, month name and weekday are shown exactly as the API spells
them (`الاربعاء`, `جُمادى الأولى`). The Hijri month length is taken from the
API, so the widget stays correct around month rollovers.

## Settings

The location settings are plugin-level (Settings → Plugins → Hijri Date),
because the service is the one that fetches:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `latitude` | `string` | `32.8872` | Latitude of the location used for prayer times and the Hijri date. |
| `longitude` | `string` | `13.1913` | Longitude of the location used for prayer times and the Hijri date. |
| `method` | `string` | `3` | Hijri calculation method (3 = Muslim World League, 4 = Umm al-Qura). |

The presentation settings live on the widget itself:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `clock_format` | `select` | `system` | `system` follows the shell's clock format, `12h`/`24h` force one. |
| `date_format` | `select` | `compact` | `compact` is `Wed 21 Oct 2026`, `system` follows the shell's date format. |
| `timezone` | `string` | *(empty)* | IANA zone for the clock, e.g. `Africa/Tripoli`. Empty uses the system zone. |

The clock and the date are rendered with `noctalia.formatTime()`, so they
follow the shell's formats and can be changed in one place (Settings → Shell)
instead of per widget.

## Debugging

```sh
noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status
```

shows the currently displayed Hijri date, the Maghrib minutes, the location's
time zone and the cache timestamps in a notification.

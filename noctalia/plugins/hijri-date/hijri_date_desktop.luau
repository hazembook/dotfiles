--!nonstrict
-- Hijri Date desktop / lock-screen widget.
--
-- The service entry (hijri_date_service.luau) fetches the dates; this
-- widget only renders. The rollover is computed here rather than taken from
-- the service, so the date still flips at Maghrib while the session is
-- locked and the service is idle.
--
-- It mirrors the bar widget's date parts: Gregorian date | Hijri date, in
-- the same font. The clock next to it is the shell's own clock widget.

local i18n = require("./i18n.luau")

local FONT_FAMILY = "Amiri"

local WEEKDAY_KEYS = { "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday" }
local WEEKDAY_SHORT_EN = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local WEEKDAY_LONG_EN = {
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
}
local MONTHS_EN = {
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
}

local function tr(key, fallback)
  return i18n.tr(key, fallback)
end

local function isRtl()
  return i18n.isRtl()
end

local function escapePattern(text)
  return (text:gsub("(%W)", "%%%1"))
end

-- strftime names are not localized by the shell language; replace the
-- English ones with the plugin catalog's names.
local function localizeDate(text)
  local replacements = {}
  for index = 1, 7 do
    local key = WEEKDAY_KEYS[index]
    replacements[#replacements + 1] = {
      WEEKDAY_LONG_EN[index],
      tr("weekday." .. key .. "_full", WEEKDAY_LONG_EN[index]),
    }
    replacements[#replacements + 1] = {
      WEEKDAY_SHORT_EN[index],
      tr("weekday." .. key, WEEKDAY_SHORT_EN[index]),
    }
  end
  for month = 1, 12 do
    replacements[#replacements + 1] = {
      MONTHS_EN[month],
      tr("month." .. tostring(month), MONTHS_EN[month]),
    }
  end
  table.sort(replacements, function(a, b)
    return #a[1] > #b[1]
  end)

  for _, pair in ipairs(replacements) do
    if pair[2] ~= pair[1] then
      text = text:gsub(escapePattern(pair[1]), pair[2])
    end
  end
  return (text:gsub("%s+", " "))
end

-- Current time in the location's own zone (the zone the prayer times, and
-- therefore Maghrib, are expressed in).
local function currentMinutes()
  local zone = noctalia.state.get("hijri.timezone")
  local hours = tonumber(noctalia.formatTime("{:%H}", nil, zone))
  local minutes = tonumber(noctalia.formatTime("{:%M}", nil, zone))
  if hours == nil or minutes == nil then
    return nil
  end
  return hours * 60 + minutes
end

local function hijriText()
  local rtl = isRtl()
  local today = noctalia.state.get(rtl and "hijri.today" or "hijri.today_en")
    or noctalia.state.get("hijri.today")
  local tomorrow = noctalia.state.get(rtl and "hijri.tomorrow" or "hijri.tomorrow_en")
    or noctalia.state.get("hijri.tomorrow")
  local maghrib = noctalia.state.get("hijri.maghrib")
  local current = currentMinutes()
  if maghrib and tomorrow and current ~= nil and current >= maghrib then
    return tomorrow
  end
  return today
end

function update()
  i18n.refresh()
  desktopWidget.setWantsSecondTicks(true)
  local dateText = localizeDate(noctalia.formatTime(noctalia.dateFormat()))
  desktopWidget.render(ui.label({
    text = dateText .. " | " .. (hijriText() or tr("panel.loading", "Loading…")),
    fontFamily = FONT_FAMILY,
    fontWeight = "bold",
    textAlign = "center",
  }))
end

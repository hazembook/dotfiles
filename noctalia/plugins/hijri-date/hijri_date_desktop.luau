--!nonstrict
-- Hijri Date desktop / lock-screen widget.
--
-- The service entry (hijri_date_service.luau) fetches the dates; this
-- widget only renders. The rollover is computed here rather than taken from
-- the service, so the date still flips at Maghrib while the session is
-- locked and the service is idle.
--
-- It mirrors the bar widget: Gregorian date | clock | Hijri date, in the
-- same font, with the clock and date taken from the shell's own formats.

local FONT_FAMILY = "Amiri"
local PLACEHOLDER = "جاري التحميل..."

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
  local today = noctalia.state.get("hijri.today")
  local tomorrow = noctalia.state.get("hijri.tomorrow")
  local maghrib = noctalia.state.get("hijri.maghrib")
  local current = currentMinutes()
  if maghrib and tomorrow and current ~= nil and current >= maghrib then
    return tomorrow
  end
  return today
end

function update()
  desktopWidget.setWantsSecondTicks(true)
  local dateText = noctalia.formatTime(noctalia.dateFormat())
  local clockText = noctalia.formatTime(noctalia.timeFormat())
  desktopWidget.render(ui.label({
    text = dateText .. " | " .. clockText .. " | " .. (hijriText() or PLACEHOLDER),
    fontFamily = FONT_FAMILY,
    fontSize = 40,
    fontWeight = "bold",
    textAlign = "center",
  }))
end

--!nonstrict
-- Hijri Date bar widget - renders the Gregorian date, the clock and the
-- Hijri date published by the service entry (see hijri_date_service.luau).
--
-- The clock and the date follow the shell's formats (Settings -> Shell ->
-- Clock/Date time format) unless the widget settings override them, and the
-- timezone setting decides which zone the clock shows.

local FONT_FAMILY = "Amiri"
local PLACEHOLDER = "جاري التحميل..."

local CLOCK_PATTERNS = {
  ["12h"] = "{:%I:%M %p}",
  ["24h"] = "{:%H:%M}",
}
local COMPACT_DATE_PATTERN = "{:%a %d %b %Y}"

local function setting(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil or value == "" then
    return fallback
  end
  return tostring(value)
end

-- The clock's zone: empty means "the system zone".
local function clockZone()
  local zone = setting("timezone", "")
  if zone == "" then
    return nil
  end
  return zone
end

local function clockText()
  local mode = setting("clock_format", "system")
  local pattern = CLOCK_PATTERNS[mode] or noctalia.timeFormat()
  return noctalia.formatTime(pattern, nil, clockZone())
end

local function dateText()
  local mode = setting("date_format", "compact")
  local pattern = mode == "system" and noctalia.dateFormat() or COMPACT_DATE_PATTERN
  return noctalia.formatTime(pattern, nil, clockZone())
end

-- Current time in the location's zone, which is the zone the prayer times
-- (and therefore Maghrib) are expressed in.
local function locationMinutes()
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
  local current = locationMinutes()
  if maghrib and tomorrow and current ~= nil and current >= maghrib then
    return tomorrow
  end
  return today
end

local lastText = nil

local function render()
  local text = dateText() .. " | " .. clockText() .. " | " .. (hijriText() or PLACEHOLDER)
  if text ~= lastText then
    lastText = text
    barWidget.setText(text)
  end
end

-- One-time setup: the top level of the script runs once at load.
barWidget.setFont(FONT_FAMILY)
noctalia.setUpdateInterval(1000)

-- Repaint as soon as the service publishes new values.
noctalia.state.watch("hijri.today", render)
noctalia.state.watch("hijri.tomorrow", render)
noctalia.state.watch("hijri.maghrib", render)

function update()
  render()
end

function onClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center calendar")
end

-- Debug helper: `noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status`
function onIpc(event, payload)
  if event ~= "status" then
    return
  end
  noctalia.notify("Hijri Date", "display: " .. tostring(hijriText() or PLACEHOLDER)
    .. "\nmaghrib: " .. tostring(noctalia.state.get("hijri.maghrib"))
    .. "\ntimezone: " .. tostring(noctalia.state.get("hijri.timezone"))
    .. "\nfetched_at: " .. tostring(noctalia.state.get("hijri.fetched_at"))
    .. "\nfailed_at: " .. tostring(noctalia.state.get("hijri.failed_at")))
end

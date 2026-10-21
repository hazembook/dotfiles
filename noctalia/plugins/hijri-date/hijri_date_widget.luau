--!nonstrict
-- Hijri Date bar widget - shows the Gregorian date, the clock and the Hijri
-- date in one pill.
--
-- The clock and the Gregorian date are rendered with Noctalia's own formats
-- (noctalia.timeFormat() / noctalia.dateFormat()), so they are exactly what
-- the shell's clock widget and calendar show, and follow the shell's
-- [shell].time_format and [shell].date_format settings.
--
-- The Hijri date and the Maghrib rollover are handled by the service entry
-- (hijri_date_service.luau); the widget only renders what it publishes.

local FONT_FAMILY = "Amiri"
local PLACEHOLDER = "جاري التحميل..."

local function render()
  local dateText = noctalia.formatTime(noctalia.dateFormat())
  local clockText = noctalia.formatTime(noctalia.timeFormat())
  local hijriText = noctalia.state.get("hijri.display") or PLACEHOLDER
  barWidget.setText(dateText .. " | " .. clockText .. " | " .. hijriText)
end

-- One-time setup: the top level of the script runs once at load.
barWidget.setFont(FONT_FAMILY)
noctalia.setUpdateInterval(1000)

-- Repaint as soon as the service publishes a new date.
noctalia.state.watch("hijri.display", render)

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
  noctalia.notify("Hijri Date", "display: " .. tostring(noctalia.state.get("hijri.display") or PLACEHOLDER)
    .. "\nmaghrib: " .. tostring(noctalia.state.get("hijri.maghrib"))
    .. "\ntimezone: " .. tostring(noctalia.state.get("hijri.timezone"))
    .. "\nfetched_at: " .. tostring(noctalia.state.get("hijri.fetched_at"))
    .. "\nfailed_at: " .. tostring(noctalia.state.get("hijri.failed_at")))
end

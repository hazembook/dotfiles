--!nonstrict
-- Hijri Date bar widget - a compact label showing the date in the calendar
-- selected as "main" (Gregorian or Hijri).
--
-- Left click flips the main calendar; right click opens the calendar panel.
-- The panel reads the same choice from `hijri.calendar.main`, so the bar and
-- the panel always agree. The choice is also written to a small state file so
-- it survives a shell restart.
--
-- The Hijri date and the Maghrib rollover are handled by the service entry
-- (hijri_date_service.luau); the widget only renders what it publishes.
-- The Gregorian date comes from the shell's own [shell].date_format.

local MAIN_KEY = "hijri.calendar.main"
local FONT_FAMILY = "Amiri"
local PLACEHOLDER = "جاري التحميل..."

local function stateDir()
  local base = noctalia.getenv("XDG_STATE_HOME")
  if base == nil or base == "" then
    base = (noctalia.getenv("HOME") or "") .. "/.local/state"
  end
  return base .. "/noctalia"
end

local MAIN_FILE = stateDir() .. "/hijri-date-main"

local function readMain()
  local stored = noctalia.state.get(MAIN_KEY)
  if stored == "hijri" or stored == "gregorian" then
    return stored
  end
  local raw = noctalia.fileExists(MAIN_FILE) and noctalia.readFile(MAIN_FILE) or nil
  if type(raw) == "string" then
    local value = raw:gsub("%s+", "")
    if value == "hijri" or value == "gregorian" then
      noctalia.state.set(MAIN_KEY, value)
      return value
    end
  end
  return "gregorian"
end

local main = readMain()

local function render()
  if main == "hijri" then
    barWidget.setText(noctalia.state.get("hijri.display") or PLACEHOLDER)
  else
    barWidget.setText(noctalia.formatTime(noctalia.dateFormat()))
  end
end

local function setMain(value)
  if (value ~= "hijri" and value ~= "gregorian") or value == main then
    return
  end
  main = value
  noctalia.state.set(MAIN_KEY, value)
  noctalia.writeFile(MAIN_FILE, value)
  render()
end

-- One-time setup: the top level of the script runs once at load.
barWidget.setFont(FONT_FAMILY)
noctalia.setUpdateInterval(60000)

-- Another entry (the panel) can change the shared choice too.
noctalia.state.watch(MAIN_KEY, function(value)
  local nextMain = value == "hijri" and "hijri" or "gregorian"
  if nextMain ~= main then
    main = nextMain
    render()
  end
end)

-- Repaint as soon as the service publishes a new date.
noctalia.state.watch("hijri.display", render)

render()

function update()
  render()
end

function onClick()
  setMain(main == "hijri" and "gregorian" or "hijri")
end

function onRightClick()
  noctalia.togglePanel("hazembook/hijri-date:calendar")
end

-- Debug helpers:
--   noctalia msg plugin hazembook/hijri-date:date-clock-hijri all toggle
--   noctalia msg plugin hazembook/hijri-date:date-clock-hijri all main gregorian
--   noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status
function onIpc(event, payload)
  if event == "toggle" then
    setMain(main == "hijri" and "gregorian" or "hijri")
  elseif event == "main" then
    setMain(tostring(payload or ""))
  elseif event == "status" then
    noctalia.notify(
      "Hijri Date",
      "main: " .. main
        .. "\ngregorian: " .. noctalia.formatTime(noctalia.dateFormat())
        .. "\nhijri: " .. tostring(noctalia.state.get("hijri.display") or PLACEHOLDER)
        .. "\nmaghrib: " .. tostring(noctalia.state.get("hijri.maghrib"))
        .. "\ntimezone: " .. tostring(noctalia.state.get("hijri.timezone"))
        .. "\nfetched_at: " .. tostring(noctalia.state.get("hijri.fetched_at"))
        .. "\nfailed_at: " .. tostring(noctalia.state.get("hijri.failed_at"))
    )
  end
end

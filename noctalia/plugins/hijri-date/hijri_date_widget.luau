--!nonstrict
-- Hijri Date bar widget - a configurable label showing the clock, the
-- Gregorian date, the Hijri date, or a combination of them.
--
-- `display` selects what is shown: the clock alone, the clock plus one or
-- both dates, or dates without the clock. The clock is bold; dates keep the
-- regular weight. Left click flips the main calendar; right click opens the
-- calendar panel. The panel reads the same choice from `hijri.calendar.main`,
-- so the bar and the panel always agree. The choice is also written to a
-- small state file so it survives a shell restart.
--
-- The Hijri date and the Maghrib rollover are handled by the service entry
-- (hijri_date_service.luau); the widget only renders what it publishes.
-- The Gregorian date comes from the shell's own [shell].date_format.
--
-- Debug helpers:
--   noctalia msg plugin hazembook/hijri-date:date-clock-hijri all toggle
--   noctalia msg plugin hazembook/hijri-date:date-clock-hijri all main gregorian
--   noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status

local i18n = require("./i18n.luau")

local MAIN_KEY = "hijri.calendar.main"
local PANEL_ID = "hazembook/hijri-date:calendar"
local FONT_FAMILY = "Amiri"

local DISPLAY_MODES = {
  main = true,
  gregorian = true,
  hijri = true,
  both = true,
  clock = true,
  clock_main = true,
  clock_gregorian = true,
  clock_hijri = true,
  clock_both = true,
}

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

local function escapePattern(text)
  return (text:gsub("(%W)", "%%%1"))
end

-- `noctalia.formatTime()` (strftime) is not localized by the shell language,
-- so substitute the English names it prints with the plugin catalog's names.
-- Sorted longest-first so "March" is replaced before "Mar".
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
  -- `%e` pads the day with a leading space; collapse that double space.
  return (text:gsub("%s+", " "))
end

local function gregorianText()
  return localizeDate(noctalia.formatTime(noctalia.dateFormat()))
end

local function placeholder()
  return tr("panel.loading", "Loading…")
end

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

local function displayMode()
  local value = noctalia.getConfig("display")
  if type(value) == "string" and DISPLAY_MODES[value] then
    return value
  end
  return "main"
end

local function hijriDisplay()
  local key = i18n.hijriIsArabic() and "hijri.display_ar" or "hijri.display_en"
  local value = noctalia.state.get(key)
  if type(value) ~= "string" or value == "" then
    value = noctalia.state.get("hijri.display")
  end
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return value
end

local function hijriText()
  return hijriDisplay() or placeholder()
end

local function clockText()
  local value = noctalia.formatTime(noctalia.timeFormat())
  if type(value) ~= "string" or value == "" then
    return "--:--"
  end
  return value
end

local function clockWantsSeconds()
  local format = noctalia.timeFormat()
  if type(format) ~= "string" then
    return false
  end
  return format:find("%%S") ~= nil or format:find("%%T") ~= nil
end

-- The clock's own tooltip only formats a Gregorian strftime string, so the
-- both-calendar tooltip lives on this label instead: one row for each date.
local lastTooltipSignature
local function updateTooltip()
  local greg = gregorianText()
  local hijri = hijriDisplay()
  local rows = {
    { key = tr("tooltip.gregorian", "Gregorian"), value = greg },
  }
  if hijri ~= nil then
    rows[#rows + 1] = { key = tr("tooltip.hijri", "Hijri"), value = hijri }
  end

  local signature = greg .. "\n" .. tostring(hijri)
  if signature ~= lastTooltipSignature then
    barWidget.setTooltip(rows)
    lastTooltipSignature = signature
  end
end

local function render()
  i18n.refresh()

  local mode = displayMode()
  local showMain = mode == "main" or mode == "clock_main"
  local showGregorian = mode == "gregorian"
    or mode == "both"
    or mode == "clock_gregorian"
    or mode == "clock_both"
  local showHijri = mode == "hijri"
    or mode == "both"
    or mode == "clock_hijri"
    or mode == "clock_both"
  local showClock = mode == "clock" or mode:match("^clock_") ~= nil

  if showMain then
    if main == "hijri" then
      showHijri = true
    else
      showGregorian = true
    end
  end

  local parts = {}
  local function addLabel(text, weight)
    parts[#parts + 1] = ui.label({
      text = text,
      fontFamily = FONT_FAMILY,
      fontWeight = weight,
      maxLines = 1,
    })
  end

  -- With both dates the clock sits between them:
  --   Gregorian | clock | Hijri
  if showGregorian then
    addLabel(gregorianText(), "medium")
  end
  if showClock then
    addLabel(clockText(), "bold")
  end
  if showHijri then
    addLabel(hijriText(), "medium")
  end

  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  barWidget.render(container({
    gap = vertical and 1 or 6,
    align = "center",
    justify = "center",
  }, parts))

  updateTooltip()
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
local initialMode = displayMode()
local initialClock = initialMode == "clock" or initialMode:match("^clock_") ~= nil
noctalia.setUpdateInterval(initialClock and clockWantsSeconds() and 1000 or 60000)

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
  noctalia.togglePanel(PANEL_ID)
end

function onIpc(event, payload)
  if event == "toggle" then
    setMain(main == "hijri" and "gregorian" or "hijri")
  elseif event == "main" then
    setMain(tostring(payload or ""))
  elseif event == "status" then
    noctalia.notify(
      "Hijri Date",
      "main: " .. main
        .. "\ndisplay: " .. displayMode()
        .. "\nhijri language: " .. i18n.hijriLang()
        .. "\ngregorian: " .. gregorianText()
        .. "\nhijri: " .. tostring(hijriDisplay() or placeholder())
        .. "\nmaghrib: " .. tostring(noctalia.state.get("hijri.maghrib"))
        .. "\ntimezone: " .. tostring(noctalia.state.get("hijri.timezone"))
        .. "\nfetched_at: " .. tostring(noctalia.state.get("hijri.fetched_at"))
        .. "\nfailed_at: " .. tostring(noctalia.state.get("hijri.failed_at"))
    )
  end
end

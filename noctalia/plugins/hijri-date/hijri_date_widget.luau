--!nonstrict
-- Hijri Date bar widget - a configurable label showing the clock, the
-- Gregorian date, the Hijri date, or a combination of them.
--
-- `display` selects what is shown: the clock alone, the clock plus one or
-- both dates, or dates without the clock. The clock is bold; dates keep the
-- regular weight. Left click opens the calendar panel; right click flips the
-- main calendar. The panel reads the same choice from `hijri.calendar.main`,
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

-- Only show the date that is not already on the bar. When both dates are
-- visible the tooltip is redundant, so clear it.
local lastTooltipSignature
local function updateTooltip(showGregorian, showHijri)
  local rows = {}
  if not showGregorian then
    rows[#rows + 1] = {
      key = tr("tooltip.gregorian", "Gregorian"),
      value = gregorianText(),
    }
  end
  if not showHijri then
    local hijri = hijriDisplay()
    if hijri ~= nil then
      rows[#rows + 1] = { key = tr("tooltip.hijri", "Hijri"), value = hijri }
    end
  end

  local signatureParts = {}
  for _, row in ipairs(rows) do
    signatureParts[#signatureParts + 1] = row.key .. "=" .. row.value
  end
  local signature = table.concat(signatureParts, "\n")
  if signature ~= lastTooltipSignature then
    if #rows == 0 then
      barWidget.setTooltip(nil)
    else
      barWidget.setTooltip(rows)
    end
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

  local entries = {}
  local function addEntry(text, weight)
    entries[#entries + 1] = { text = text, weight = weight }
  end

  -- With both dates the clock sits between them:
  --   Gregorian | clock | Hijri
  if showGregorian then
    addEntry(gregorianText(), "medium")
  end
  if showClock then
    addEntry(clockText(), "bold")
  end
  if showHijri then
    addEntry(hijriText(), "medium")
  end

  local vertical = barWidget.isVertical()
  local parts = {}
  for index, entry in ipairs(entries) do
    if index > 1 then
      -- A small rule instead of the text itself, so the three parts read as
      -- separate blocks without widening the capsule much.
      parts[#parts + 1] = ui.box({
        width = vertical and 12 or 2,
        height = vertical and 2 or 12,
        radius = 1,
        fill = "on_surface_variant/0.7",
      })
    end
    parts[#parts + 1] = ui.label({
      text = entry.text,
      fontFamily = FONT_FAMILY,
      fontWeight = entry.weight,
      maxLines = 1,
    })
  end

  local container = vertical and ui.column or ui.row
  barWidget.render(container({
    gap = vertical and 2 or 4,
    align = "center",
    justify = "center",
  }, parts))

  updateTooltip(showGregorian, showHijri)
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
  noctalia.togglePanel(PANEL_ID)
end

function onRightClick()
  setMain(main == "hijri" and "gregorian" or "hijri")
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

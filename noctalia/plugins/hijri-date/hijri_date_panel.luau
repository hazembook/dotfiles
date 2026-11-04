--!nonstrict
-- Hijri calendar panel - a month grid whose main calendar can be either
-- Gregorian or Hijri.
--
-- Gregorian mode uses aladhan.com's gToHCalendar endpoint: one Gregorian month
-- with the Hijri day under each day number. Hijri mode uses hToGCalendar: a
-- real 29/30-day Hijri month with the Gregorian day under each number, so the
-- grid itself follows the selected main calendar.
--
-- Both directions are cached in the plugin's shared state for 30 days, so
-- paging back and forth and reopening the panel do not hit the network again.
--
-- The main calendar is shared with the bar widget through the state key
-- `hijri.calendar.main` and persisted to a small file so it survives a shell
-- restart. The bar widget toggles the same value; the panel re-anchors when it
-- changes while open.
--
-- Entry points:
--   onOpen(context)  reset the view to today and render
--   onClose()        stop rendering after an in-flight request
--
-- The locale's first day of week is not exposed to plugins, so the grid starts
-- on Sunday (the shell's calendar uses the locale's first day; en_US is Sunday).

local MAIN_KEY = "hijri.calendar.main"
local GCACHE_KEY = "hijri.calendar.gcache.v2"
local HCACHE_KEY = "hijri.calendar.hcache.v2"
local CACHE_VERSION = 2
local CACHE_TTL_SECONDS = 30 * 24 * 60 * 60

local MDAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local HIJRI_MONTHS = {
  "مُحَرَّم",
  "صَفَر",
  "رَبيع الأوّل",
  "رَبيع الآخر",
  "جُمادى الأولى",
  "جُمادى الآخرة",
  "رَجَب",
  "شَعْبان",
  "رَمَضان",
  "شَوّال",
  "ذو القَعْدة",
  "ذو الحِجّة",
}
local WEEKDAYS = {} -- Sunday-first abbreviations, matching the shell calendar

for index = 0, 6 do
  -- 2024-01-07 was a Sunday.
  WEEKDAYS[index] = os.date("%a", os.time({ year = 2024, month = 1, day = 7 + index }))
end

local function stateDir()
  local base = noctalia.getenv("XDG_STATE_HOME")
  if base == nil or base == "" then
    base = (noctalia.getenv("HOME") or "") .. "/.local/state"
  end
  return base .. "/noctalia"
end

local MAIN_FILE = stateDir() .. "/hijri-date-main"

local cacheG
local cacheH
local pendingG = {}
local pendingH = {}
local failedG = {}
local failedH = {}
local isOpen = false
local main = "gregorian"
local viewYear
local viewMonth
local selected -- { g = { y, m, d }, h = { y, m, d, w, name } }
local pendingViewG -- a Gregorian date whose Hijri month should become the view
local ensureGView
local ensureHView
local render
local afterData

local function tr(key, fallback)
  local text = noctalia.tr("panel." .. key)
  if text == nil or text == "" or text == "panel." .. key then
    return fallback
  end
  return text
end

local function daysInMonth(year, month)
  if month == 2 and ((year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0) then
    return 29
  end
  return MDAYS[month]
end

local function monthKey(year, month)
  return string.format("%04d-%02d", year, month)
end

local function shiftMonthParts(year, month, delta)
  local value = month + delta
  local y = year
  if value < 1 then
    value = 12
    y = y - 1
  elseif value > 12 then
    value = 1
    y = y + 1
  end
  return y, value
end

local function todayParts()
  local now = os.date("*t")
  return now.year, now.month, now.day
end

local function gregorianLong(year, month, day)
  return os.date("%A %d %B %Y", os.time({ year = year, month = month, day = day }))
end

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

local function persistMain(value)
  noctalia.state.set(MAIN_KEY, value)
  noctalia.writeFile(MAIN_FILE, value)
end

local function loadGCache()
  if cacheG ~= nil then
    return
  end
  local stored = noctalia.state.get(GCACHE_KEY)
  if type(stored) == "table" and stored.version == CACHE_VERSION and type(stored.months) == "table" then
    cacheG = stored.months
  else
    cacheG = {}
  end
end

local function saveGCache()
  noctalia.state.set(GCACHE_KEY, { version = CACHE_VERSION, months = cacheG })
end

local function loadHCache()
  if cacheH ~= nil then
    return
  end
  local stored = noctalia.state.get(HCACHE_KEY)
  if type(stored) == "table" and stored.version == CACHE_VERSION and type(stored.months) == "table" then
    cacheH = stored.months
  else
    cacheH = {}
  end
end

local function saveHCache()
  noctalia.state.set(HCACHE_KEY, { version = CACHE_VERSION, months = cacheH })
end

local function cachedG(year, month)
  loadGCache()
  local entry = cacheG[monthKey(year, month)]
  if type(entry) ~= "table" or type(entry.days) ~= "table" then
    return nil
  end
  local first = entry.days[1]
  if type(first) ~= "table"
    or type(first.hy) ~= "number"
    or type(first.hm) ~= "number"
    or type(first.hd) ~= "number"
    or type(first.hn) ~= "string" then
    return nil
  end
  return entry
end

local function cachedH(year, month)
  loadHCache()
  local entry = cacheH[monthKey(year, month)]
  if type(entry) ~= "table" or type(entry.days) ~= "table" or #entry.days == 0 then
    return nil
  end
  local first = entry.days[1]
  if type(first) ~= "table"
    or type(first.hy) ~= "number"
    or type(first.hm) ~= "number"
    or type(first.hd) ~= "number"
    or type(first.gy) ~= "number"
    or type(first.gm) ~= "number"
    or type(first.gd) ~= "number" then
    return nil
  end
  return entry
end

-- Looks up the Hijri date assigned to a Gregorian date by the Gregorian cache.
local function hijriForGDate(g)
  local entry = cachedG(g.y, g.m)
  if entry == nil or type(entry.days) ~= "table" then
    return nil
  end
  local day = entry.days[g.d]
  if day == nil or type(day.hy) ~= "number" or type(day.hm) ~= "number" or type(day.hd) ~= "number" then
    return nil
  end
  return { y = day.hy, m = day.hm, d = day.hd, w = day.hw or "", name = day.hn or "" }
end

local function hijriFull(h)
  if h == nil then
    return nil
  end
  local weekday = (h.w ~= nil and h.w ~= "") and h.w .. " " or ""
  return weekday .. tostring(h.d) .. " " .. tostring(h.name) .. " " .. tostring(h.y)
end

local function hijriRangeLabel(entry)
  local days = entry and entry.days
  if type(days) ~= "table" or #days == 0 then
    return nil
  end
  local first = days[1]
  local last = days[#days]
  if type(first) ~= "table" or type(last) ~= "table" then
    return nil
  end
  local firstName = first.hn or ""
  local lastName = last.hn or ""
  if first.hm == last.hm and first.hy == last.hy then
    return firstName .. " " .. tostring(first.hy)
  elseif first.hy == last.hy then
    return firstName .. " – " .. lastName .. " " .. tostring(first.hy)
  end
  return firstName .. " " .. tostring(first.hy) .. " – " .. lastName .. " " .. tostring(last.hy)
end

local function gregorianRangeLabel(entry)
  local days = entry and entry.days
  if type(days) ~= "table" or #days == 0 then
    return nil
  end
  local first = days[1]
  local last = days[#days]
  if type(first) ~= "table" or type(last) ~= "table" then
    return nil
  end
  if type(first.gy) ~= "number" or type(first.gm) ~= "number" or type(first.gd) ~= "number"
    or type(last.gy) ~= "number" or type(last.gm) ~= "number" or type(last.gd) ~= "number" then
    return nil
  end
  local firstName = os.date("%B", os.time({ year = first.gy, month = first.gm, day = first.gd }))
  local lastName = os.date("%B", os.time({ year = last.gy, month = last.gm, day = last.gd }))
  if first.gy == last.gy and first.gm == last.gm then
    return string.format("%d–%d %s %d", first.gd, last.gd, firstName, first.gy)
  elseif first.gy == last.gy then
    return string.format("%d %s – %d %s %d", first.gd, firstName, last.gd, lastName, first.gy)
  end
  return string.format(
    "%d %s %d – %d %s %d",
    first.gd,
    firstName,
    first.gy,
    last.gd,
    lastName,
    last.gy
  )
end

local function resolvePendingView()
  if pendingViewG == nil or main ~= "hijri" then
    return
  end
  local hijri = hijriForGDate(pendingViewG)
  if hijri == nil or hijri.y == nil or hijri.m == nil then
    return
  end
  pendingViewG = nil
  viewYear = hijri.y
  viewMonth = hijri.m
  ensureHView(viewYear, viewMonth)
end

afterData = function()
  resolvePendingView()
  if isOpen and (viewYear ~= nil or pendingViewG ~= nil) then
    render()
  end
end

local function fetchG(year, month)
  local key = monthKey(year, month)
  if pendingG[key] then
    return
  end
  pendingG[key] = true
  failedG[key] = nil

  local requestedAt = os.time()
  local url = string.format("https://api.aladhan.com/v1/gToHCalendar/%d/%d", month, year)
  noctalia.http({ url = url, method = "GET", headers = { "Accept: application/json" } }, function(response)
    pendingG[key] = nil

    if not response.ok or response.status ~= 200 then
      failedG[key] = true
      afterData()
      return
    end

    local ok, payload = pcall(noctalia.json.decode, response.body)
    if not ok or type(payload) ~= "table" or type(payload.data) ~= "table" then
      failedG[key] = true
      afterData()
      return
    end

    local days = {}
    for _, item in ipairs(payload.data) do
      local hijri = item.hijri
      local gregorian = item.gregorian
      if type(hijri) == "table" and type(gregorian) == "table" then
        local day = tonumber(gregorian.day)
        if day ~= nil then
          days[day] = {
            hy = tonumber(hijri.year) or 0,
            hm = (hijri.month and tonumber(hijri.month.number)) or 0,
            hd = tonumber(hijri.day) or 0,
            hw = (hijri.weekday and hijri.weekday.ar) or "",
            hn = (hijri.month and hijri.month.ar) or "",
          }
        end
      end
    end

    if next(days) == nil then
      failedG[key] = true
      afterData()
      return
    end

    loadGCache()
    cacheG[key] = { fetchedAt = requestedAt, days = days }
    saveGCache()
    afterData()
  end)
end

local function fetchH(year, month)
  local key = monthKey(year, month)
  if pendingH[key] then
    return
  end
  pendingH[key] = true
  failedH[key] = nil

  local requestedAt = os.time()
  local url = string.format("https://api.aladhan.com/v1/hToGCalendar/%d/%d", month, year)
  noctalia.http({ url = url, method = "GET", headers = { "Accept: application/json" } }, function(response)
    pendingH[key] = nil

    if not response.ok or response.status ~= 200 then
      failedH[key] = true
      afterData()
      return
    end

    local ok, payload = pcall(noctalia.json.decode, response.body)
    if not ok or type(payload) ~= "table" or type(payload.data) ~= "table" then
      failedH[key] = true
      afterData()
      return
    end

    local days = {}
    for _, item in ipairs(payload.data) do
      local hijri = item.hijri
      local gregorian = item.gregorian
      if type(hijri) == "table" and type(gregorian) == "table" then
        table.insert(days, {
          hy = tonumber(hijri.year) or year,
          hm = (hijri.month and tonumber(hijri.month.number)) or month,
          hd = tonumber(hijri.day) or 0,
          hw = (hijri.weekday and hijri.weekday.ar) or "",
          hn = (hijri.month and hijri.month.ar) or "",
          gy = tonumber(gregorian.year) or 0,
          gm = (gregorian.month and tonumber(gregorian.month.number)) or 0,
          gd = tonumber(gregorian.day) or 0,
          gw = (gregorian.weekday and gregorian.weekday.en) or "",
        })
      end
    end

    if #days == 0 then
      failedH[key] = true
      afterData()
      return
    end

    loadHCache()
    cacheH[key] = { fetchedAt = requestedAt, days = days }
    saveHCache()
    afterData()
  end)
end

local function ensureG(year, month)
  local key = monthKey(year, month)
  local entry = cachedG(year, month)
  if entry ~= nil and type(entry.fetchedAt) == "number" and os.time() - entry.fetchedAt < CACHE_TTL_SECONDS then
    return
  end
  if entry ~= nil then
    loadGCache()
    cacheG[key] = nil
    saveGCache()
  end
  if not pendingG[key] then
    fetchG(year, month)
  end
end

local function ensureH(year, month)
  local key = monthKey(year, month)
  local entry = cachedH(year, month)
  if entry ~= nil and type(entry.fetchedAt) == "number" and os.time() - entry.fetchedAt < CACHE_TTL_SECONDS then
    return
  end
  if entry ~= nil then
    loadHCache()
    cacheH[key] = nil
    saveHCache()
  end
  if not pendingH[key] then
    fetchH(year, month)
  end
end

ensureGView = function(year, month)
  ensureG(year, month)
  local prevYear, prevMonth = shiftMonthParts(year, month, -1)
  local nextYear, nextMonth = shiftMonthParts(year, month, 1)
  ensureG(prevYear, prevMonth)
  ensureG(nextYear, nextMonth)
end

ensureHView = function(year, month)
  ensureH(year, month)
  local prevYear, prevMonth = shiftMonthParts(year, month, -1)
  local nextYear, nextMonth = shiftMonthParts(year, month, 1)
  ensureH(prevYear, prevMonth)
  ensureH(nextYear, nextMonth)
end

-- Gregorian month cells, including the muted days from the neighbouring months.
local function buildGregorianCells(year, month)
  local dim = daysInMonth(year, month)
  local prevYear, prevMonth = shiftMonthParts(year, month, -1)
  local nextYear, nextMonth = shiftMonthParts(year, month, 1)
  local prevDim = daysInMonth(prevYear, prevMonth)
  local firstWeekday = os.date("*t", os.time({ year = year, month = month, day = 1 })).wday
  local leading = firstWeekday - 1 -- Sunday-first
  local cells = {}

  for row = 0, 5 do
    for column = 0, 6 do
      local offset = row * 7 + column - leading
      local cellYear, cellMonth, cellDay
      if offset < 0 then
        cellYear, cellMonth, cellDay = prevYear, prevMonth, prevDim + offset + 1
      elseif offset >= dim then
        cellYear, cellMonth, cellDay = nextYear, nextMonth, offset - dim + 1
      else
        cellYear, cellMonth, cellDay = year, month, offset + 1
      end

      local hijri = hijriForGDate({ y = cellYear, m = cellMonth, d = cellDay })
      table.insert(cells, {
        gy = cellYear,
        gm = cellMonth,
        gd = cellDay,
        inMonth = cellYear == year and cellMonth == month,
        hy = hijri and hijri.y or nil,
        hm = hijri and hijri.m or nil,
        hd = hijri and hijri.d or nil,
        hw = hijri and hijri.w or nil,
        hn = hijri and hijri.name or nil,
      })
    end
  end

  return cells
end

-- Hijri month cells, including the muted days from the neighbouring Hijri
-- months. Missing neighbours render as blank cells until their fetch lands.
local function buildHijriCells(year, month)
  local entry = cachedH(year, month)
  if entry == nil or type(entry.days) ~= "table" or #entry.days == 0 then
    return nil
  end

  local days = entry.days
  local first = days[1]
  local firstWeekday = os.date("*t", os.time({ year = first.gy, month = first.gm, day = first.gd })).wday
  local leading = firstWeekday - 1 -- Sunday-first
  local prevYear, prevMonth = shiftMonthParts(year, month, -1)
  local nextYear, nextMonth = shiftMonthParts(year, month, 1)
  local prevEntry = cachedH(prevYear, prevMonth)
  local nextEntry = cachedH(nextYear, nextMonth)
  local prevDays = prevEntry and prevEntry.days or nil
  local nextDays = nextEntry and nextEntry.days or nil
  local cells = {}

  for row = 0, 5 do
    for column = 0, 6 do
      local position = row * 7 + column
      local index = position - leading
      local day

      if index < 0 then
        local slot = leading + index + 1
        if prevDays ~= nil and #prevDays >= leading then
          day = prevDays[#prevDays - leading + slot]
        end
      elseif index >= #days then
        local nextIndex = index - #days + 1
        if nextDays ~= nil then
          day = nextDays[nextIndex]
        end
      else
        day = days[index + 1]
      end

      if day == nil then
        table.insert(cells, { blank = true, inMonth = false })
      else
        table.insert(cells, {
          gy = day.gy,
          gm = day.gm,
          gd = day.gd,
          inMonth = day.hy == year and day.hm == month,
          hy = day.hy,
          hm = day.hm,
          hd = day.hd,
          hw = day.hw,
          hn = day.hn,
        })
      end
    end
  end

  return cells
end

local function buildSwitchRow(isHijri)
  local function mainLabel(text, active)
    local props = {
      text = text,
      fontSize = 11,
      maxLines = 1,
      color = active and "primary" or "on_surface_variant",
    }
    if active then
      props.fontWeight = "bold"
    end
    return ui.label(props)
  end

  return ui.row({ align = "center", justify = "center", gap = 8 }, {
    mainLabel(tr("gregorian", "Gregorian"), not isHijri),
    ui.toggle({ checked = isHijri, onChange = "onToggleMain" }),
    mainLabel(tr("hijri", "Hijri"), isHijri),
  })
end

local selectCell
local function makeCell(cell, todayG, isHijri)
  if cell.blank then
    return ui.column({ flexGrow = 1, height = 50 })
  end

  local isToday = cell.gy == todayG.y and cell.gm == todayG.m and cell.gd == todayG.d
  local isSelected = selected ~= nil
    and selected.g ~= nil
    and cell.gy == selected.g.y
    and cell.gm == selected.g.m
    and cell.gd == selected.g.d

  local fill
  local border
  local borderWidth
  local primaryColor = cell.inMonth and "on_surface" or "on_surface_variant"
  local secondaryColor = "on_surface_variant"
  local weight = cell.inMonth and "medium" or "normal"

  if isToday then
    fill = "primary/0.14"
    border = "primary/0.55"
    borderWidth = 1
    primaryColor = "primary"
    secondaryColor = "primary/0.85"
    weight = "bold"
  elseif isSelected then
    fill = "surface_variant/0.5"
    primaryColor = "on_surface"
    weight = "bold"
  end

  local primaryText
  local secondaryText
  local primaryFont
  local secondaryFont
  if isHijri then
    primaryText = cell.hd ~= nil and tostring(cell.hd) or ""
    secondaryText = tostring(cell.gd)
    primaryFont = "Amiri"
  else
    primaryText = tostring(cell.gd)
    secondaryText = cell.hd ~= nil and tostring(cell.hd) or ""
    secondaryFont = "Amiri"
  end

  local primaryProps = {
    text = primaryText,
    fontSize = 13,
    fontWeight = weight,
    color = primaryColor,
    maxLines = 1,
  }
  if primaryFont ~= nil then
    primaryProps.fontFamily = primaryFont
  end

  local secondaryProps = {
    text = secondaryText,
    fontSize = 9,
    fontWeight = "normal",
    color = secondaryColor,
    maxLines = 1,
  }
  if secondaryFont ~= nil then
    secondaryProps.fontFamily = secondaryFont
  end

  local props = {
    key = string.format("d-%04d-%02d-%02d", cell.gy, cell.gm, cell.gd),
    flexGrow = 1,
    height = 50,
    align = "center",
    justify = "center",
    gap = 0,
    radius = 6,
    opacity = cell.inMonth and 1.0 or 0.4,
    onClick = function()
      selectCell(cell)
    end,
  }
  if fill ~= nil then
    props.fill = fill
  end
  if border ~= nil then
    props.border = border
    props.borderWidth = borderWidth
  end

  return ui.column(props, {
    ui.label(primaryProps),
    ui.label(secondaryProps),
  })
end

local function renderLoading()
  local pendingFailed = false
  if pendingViewG ~= nil then
    pendingFailed = failedG[monthKey(pendingViewG.y, pendingViewG.m)] == true
  end

  local centerChildren = {
    ui.label({
      text = pendingFailed and tr("error", "Could not load the Hijri calendar") or tr("loading", "Loading…"),
      color = pendingFailed and "error" or "on_surface_variant",
      fontSize = 12,
      maxLines = 2,
      textAlign = "center",
    }),
  }
  if pendingFailed and pendingViewG ~= nil then
    local target = pendingViewG
    table.insert(centerChildren, ui.button({
      text = tr("retry", "Retry"),
      variant = "ghost",
      height = 30,
      onClick = function()
        failedG[monthKey(target.y, target.m)] = nil
        fetchG(target.y, target.m)
        render()
      end,
    }))
  end

  panel.render(ui.column({ gap = 8, flexGrow = 1 }, {
    buildSwitchRow(main == "hijri"),
    ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 6 }, centerChildren),
  }))
end

render = function()
  if viewYear == nil or viewMonth == nil then
    renderLoading()
    return
  end

  local isHijri = main == "hijri"
  local key = monthKey(viewYear, viewMonth)
  local entryG = cachedG(viewYear, viewMonth)
  local entryH = cachedH(viewYear, viewMonth)

  local loadFailed
  if isHijri then
    loadFailed = entryH == nil and failedH[key] == true
  else
    loadFailed = entryG == nil and failedG[key] == true
  end

  local todayYear, todayMonth, todayDay = todayParts()
  local todayG = { y = todayYear, m = todayMonth, d = todayDay }

  local titleText
  local titleFont
  if isHijri then
    local monthName = HIJRI_MONTHS[viewMonth] or ""
    if entryH ~= nil and type(entryH.days) == "table" and entryH.days[1] ~= nil then
      local apiName = entryH.days[1].hn
      if apiName ~= nil and apiName ~= "" then
        monthName = apiName
      end
    end
    titleText = monthName .. " " .. tostring(viewYear)
    titleFont = "Amiri"
  else
    titleText = os.date("%B %Y", os.time({ year = viewYear, month = viewMonth, day = 1 }))
  end

  local subtitleText
  if isHijri then
    subtitleText = entryH ~= nil and gregorianRangeLabel(entryH) or nil
  else
    subtitleText = entryG ~= nil and hijriRangeLabel(entryG) or nil
  end
  if subtitleText == nil then
    subtitleText = loadFailed and tr("error", "Could not load the Hijri calendar") or tr("loading", "Loading…")
  end

  local titleProps = {
    text = titleText,
    fontSize = isHijri and 17 or 16,
    fontWeight = "bold",
    maxLines = 1,
  }
  if titleFont ~= nil then
    titleProps.fontFamily = titleFont
  end

  local subtitleProps = {
    text = subtitleText,
    fontSize = 11,
    color = loadFailed and "error" or "on_surface_variant",
    maxLines = 1,
    maxWidth = 290,
  }
  if not isHijri then
    subtitleProps.fontFamily = "Amiri"
  end

  local header = ui.row({ align = "center", gap = 6 }, {
    ui.button({
      glyph = "chevron-left",
      variant = "ghost",
      width = 30,
      height = 30,
      tooltip = tr("previous", "Previous month"),
      onClick = function()
        local year, month = shiftMonthParts(viewYear, viewMonth, -1)
        viewYear, viewMonth = year, month
        selected = nil
        pendingViewG = nil
        if main == "hijri" then
          ensureHView(year, month)
        else
          ensureGView(year, month)
        end
        render()
      end,
    }),
    ui.column({ flexGrow = 1, align = "center", gap = 0 }, {
      ui.label(titleProps),
      ui.label(subtitleProps),
    }),
    ui.button({
      glyph = "chevron-right",
      variant = "ghost",
      width = 30,
      height = 30,
      tooltip = tr("next", "Next month"),
      onClick = function()
        local year, month = shiftMonthParts(viewYear, viewMonth, 1)
        viewYear, viewMonth = year, month
        selected = nil
        pendingViewG = nil
        if main == "hijri" then
          ensureHView(year, month)
        else
          ensureGView(year, month)
        end
        render()
      end,
    }),
  })

  local weekdayCells = {}
  for index = 0, 6 do
    table.insert(weekdayCells, ui.column({ flexGrow = 1, align = "center" }, {
      ui.label({ text = WEEKDAYS[index], fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
    }))
  end
  local weekdayRow = ui.row({ gap = 2 }, weekdayCells)

  local cells
  if isHijri then
    cells = buildHijriCells(viewYear, viewMonth)
  else
    cells = buildGregorianCells(viewYear, viewMonth)
  end

  local grid
  if cells == nil then
    grid = ui.column({ height = 310, align = "center", justify = "center" }, {
      ui.label({
        text = loadFailed and tr("error", "Could not load the Hijri calendar") or tr("loading", "Loading…"),
        color = loadFailed and "error" or "on_surface_variant",
        fontSize = 12,
        maxLines = 2,
        textAlign = "center",
      }),
    })
  else
    local rows = {}
    for row = 0, 5 do
      local rowCells = {}
      for column = 0, 6 do
        local cell = cells[row * 7 + column + 1]
        table.insert(rowCells, makeCell(cell, todayG, isHijri))
      end
      table.insert(rows, ui.row({ gap = 2, height = 50 }, rowCells))
    end
    grid = ui.column({ gap = 2 }, rows)
  end

  local footerPrimary
  local footerSecondary
  local footerFont
  if selected == nil or selected.g == nil then
    footerPrimary = tr("select_day", "Select a day to see its Hijri date")
    footerSecondary = ""
  else
    local g = selected.g
    local hijri = hijriForGDate(g) or selected.h
    local gregText = gregorianLong(g.y, g.m, g.d)
    local hijriText = hijriFull(hijri)
    if isHijri then
      footerPrimary = hijriText or (loadFailed and tr("error", "Could not load the Hijri calendar")
        or tr("loading", "Loading…"))
      footerSecondary = gregText
      footerFont = "Amiri"
    else
      footerPrimary = gregText
      footerSecondary = hijriText or (loadFailed and tr("error", "Could not load the Hijri calendar")
        or tr("loading", "Loading…"))
    end
  end

  local footerPrimaryProps = {
    text = footerPrimary,
    fontSize = 13,
    fontWeight = "medium",
    maxLines = 1,
    maxWidth = 300,
  }
  if footerFont ~= nil then
    footerPrimaryProps.fontFamily = footerFont
  end

  local footerChildren = {
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label(footerPrimaryProps),
      ui.label({
        text = footerSecondary,
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 1,
        maxWidth = 300,
        fontFamily = (not isHijri) and "Amiri" or nil,
      }),
    }),
  }
  if loadFailed then
    table.insert(footerChildren, ui.button({
      text = tr("retry", "Retry"),
      variant = "ghost",
      height = 30,
      onClick = function()
        if isHijri then
          failedH[key] = nil
          fetchH(viewYear, viewMonth)
        else
          failedG[key] = nil
          fetchG(viewYear, viewMonth)
        end
        render()
      end,
    }))
  end
  table.insert(footerChildren, ui.button({
    text = tr("today", "Today"),
    variant = "ghost",
    height = 30,
    onClick = function()
      goToday()
    end,
  }))

  panel.render(ui.column({ gap = 8, flexGrow = 1 }, {
    buildSwitchRow(isHijri),
    header,
    -- A key per mode recreates the grid when the main calendar changes while
    -- the panel is open, so no label from the previous grid can be reused.
    ui.column({ key = isHijri and "grid-hijri" or "grid-gregorian", gap = 4 }, {
      weekdayRow,
      grid,
    }),
    ui.row({ align = "center", gap = 6 }, footerChildren),
  }))
end

function goToday()
  local year, month, day = todayParts()
  local g = { y = year, m = month, d = day }
  local hijri = hijriForGDate(g)
  selected = { g = g, h = hijri }
  pendingViewG = nil

  if main == "hijri" then
    if hijri ~= nil and hijri.y ~= nil and hijri.m ~= nil then
      viewYear, viewMonth = hijri.y, hijri.m
      ensureHView(viewYear, viewMonth)
    else
      viewYear, viewMonth = nil, nil
      pendingViewG = g
      ensureG(year, month)
      resolvePendingView()
    end
  else
    viewYear, viewMonth = year, month
    ensureGView(year, month)
  end

  render()
end

selectCell = function(cell)
  local hijri = nil
  if cell.hd ~= nil then
    hijri = { y = cell.hy, m = cell.hm, d = cell.hd, w = cell.hw, name = cell.hn }
  else
    hijri = hijriForGDate({ y = cell.gy, m = cell.gm, d = cell.gd })
  end

  selected = {
    g = { y = cell.gy, m = cell.gm, d = cell.gd },
    h = hijri,
  }
  pendingViewG = nil

  if main == "hijri" then
    if cell.hy ~= nil and cell.hm ~= nil and (cell.hy ~= viewYear or cell.hm ~= viewMonth) then
      viewYear, viewMonth = cell.hy, cell.hm
      ensureHView(viewYear, viewMonth)
    end
  else
    if cell.gy ~= viewYear or cell.gm ~= viewMonth then
      viewYear, viewMonth = cell.gy, cell.gm
      ensureGView(viewYear, viewMonth)
    end
  end

  render()
end

local function anchorGregorian()
  if selected ~= nil and selected.g ~= nil then
    return selected.g
  end
  if viewYear ~= nil and viewMonth ~= nil then
    if main == "gregorian" then
      return { y = viewYear, m = viewMonth, d = math.min(15, daysInMonth(viewYear, viewMonth)) }
    end
    local entry = cachedH(viewYear, viewMonth)
    if entry ~= nil and type(entry.days) == "table" and entry.days[15] ~= nil then
      local day = entry.days[15]
      return { y = day.gy, m = day.gm, d = day.gd }
    end
  end
  local year, month, day = todayParts()
  return { y = year, m = month, d = day }
end

local function applyMain(nextMain, persist)
  if nextMain == main then
    return
  end

  local anchor = anchorGregorian()
  main = nextMain
  if persist then
    persistMain(nextMain)
  end
  if not isOpen then
    return
  end

  pendingViewG = nil
  if nextMain == "hijri" then
    local hijri = hijriForGDate(anchor)
    if hijri ~= nil and hijri.y ~= nil and hijri.m ~= nil then
      viewYear, viewMonth = hijri.y, hijri.m
      ensureHView(viewYear, viewMonth)
    else
      viewYear, viewMonth = nil, nil
      pendingViewG = anchor
      ensureG(anchor.y, anchor.m)
      resolvePendingView()
    end
  else
    viewYear, viewMonth = anchor.y, anchor.m
    ensureGView(viewYear, viewMonth)
  end
  render()
end

function onToggleMain(value)
  local hijri = value == true or value == "true"
  applyMain(hijri and "hijri" or "gregorian", true)
end

function onOpen(_context)
  isOpen = true
  main = readMain()
  pendingViewG = nil
  selected = nil
  goToday()
end

function onClose()
  isOpen = false
end

noctalia.state.watch(MAIN_KEY, function(value)
  local nextMain = value == "hijri" and "hijri" or "gregorian"
  if nextMain ~= main then
    applyMain(nextMain, false)
  end
end)

-- Debug helpers:
--   noctalia msg plugin hazembook/hijri-date:calendar all main hijri
--   noctalia msg plugin hazembook/hijri-date:calendar all goto 1448-05
--   noctalia msg plugin hazembook/hijri-date:calendar all today
function onIpc(event, payload)
  if event == "main" then
    local value = tostring(payload or "")
    if value == "hijri" or value == "gregorian" then
      applyMain(value, true)
    end
  elseif event == "toggle" then
    applyMain(main == "hijri" and "gregorian" or "hijri", true)
  elseif event == "goto" then
    local year, month = tostring(payload or ""):match("^(%d%d%d%d)%-(%d%d)$")
    if year ~= nil then
      viewYear = tonumber(year)
      viewMonth = tonumber(month)
      selected = nil
      pendingViewG = nil
      if main == "hijri" then
        ensureHView(viewYear, viewMonth)
      else
        ensureGView(viewYear, viewMonth)
      end
      if isOpen then
        render()
      end
    end
  elseif event == "today" then
    if isOpen then
      goToday()
    end
  end
end

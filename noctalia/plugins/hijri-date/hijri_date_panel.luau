--!nonstrict
-- Hijri calendar panel - a month grid whose main calendar can be either
-- Gregorian or Hijri.
--
-- Gregorian mode uses aladhan.com's gToHCalendar endpoint: one Gregorian month
-- with the Hijri day under each day number. Hijri mode uses hToGCalendar: a
-- real 29/30-day Hijri month with the Gregorian day under each number, so the
-- grid itself follows the selected main calendar.
--
-- Both directions are cached in memory and persistently on disk for one year,
-- so paging back and forth, reopening the panel and restarting the shell do
-- not hit the network again.
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
-- The week starts on Friday by default (the Hijri week); the `week_start`
-- setting changes it.

local i18n = require("./i18n.luau")

local MAIN_KEY = "hijri.calendar.main"
local GCACHE_KEY = "hijri.calendar.gcache.v3"
local HCACHE_KEY = "hijri.calendar.hcache.v3"
local CACHE_VERSION = 3
-- Calendar mappings are stable for a given calculation method, so a fetched
-- month is kept for a year instead of expiring after a few weeks.
local CACHE_TTL_SECONDS = 365 * 24 * 60 * 60

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
local HIJRI_MONTHS_EN = {
  "Muharram",
  "Safar",
  "Rabi' al-Awwal",
  "Rabi' al-Thani",
  "Jumada al-Ula",
  "Jumada al-Akhirah",
  "Rajab",
  "Sha'ban",
  "Ramadan",
  "Shawwal",
  "Dhu al-Qi'dah",
  "Dhu al-Hijjah",
}

local GREGORIAN_MONTHS_EN = {
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
-- Used when the Hijri grid stays Arabic in a non-Arabic shell, where the
-- catalogs only hold the shell language.
local WEEKDAY_SHORT_AR = { "أحد", "إثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت" }
local WEEKDAY_LONG_AR = {
  "الأحد",
  "الاثنين",
  "الثلاثاء",
  "الأربعاء",
  "الخميس",
  "الجمعة",
  "السبت",
}
local WEEK_START_INDEX = {
  sunday = 0,
  monday = 1,
  tuesday = 2,
  wednesday = 3,
  thursday = 4,
  friday = 5,
  saturday = 6,
}

local function stateDir()
  local base = noctalia.getenv("XDG_STATE_HOME")
  if base == nil or base == "" then
    base = (noctalia.getenv("HOME") or "") .. "/.local/state"
  end
  return base .. "/noctalia"
end

local MAIN_FILE = stateDir() .. "/hijri-date-main"

-- Month pages are immutable, so keep them on disk as well as in memory. A
-- shell restart then reuses every month the user has already visited.
local function cacheDir()
  local ok, dir = pcall(noctalia.pluginDataDir)
  if ok and type(dir) == "string" and dir ~= "" then
    return dir
  end
  local fallback = stateDir() .. "/hijri-date"
  noctalia.mkdirAll(fallback)
  return fallback
end

local CACHE_DIR = cacheDir()
local GCACHE_FILE = CACHE_DIR .. "/gcache.v3.json"
local HCACHE_FILE = CACHE_DIR .. "/hcache.v3.json"

local cacheG
local cacheH
local pendingG = {}
local pendingH = {}
local failedG = {}
local failedH = {}
local isOpen = false
local lastCurrentHKey = nil
local main = "gregorian"
local viewYear
local viewMonth
local selected -- { g = { y, m, d }, h = { y, m, d, w, name } }
local pendingViewG -- a Gregorian date whose Hijri month should become the view
local ensureGView
local ensureHView
local render
local afterData
local applyMain

-- The panel speaks the language of the calendar it shows: Arabic when the
-- Hijri calendar is displayed in Arabic, otherwise the shell language. This
-- also localizes the Gregorian range shown alongside an Arabic Hijri month.
local function panelLanguage()
  if main == "hijri" and i18n.hijriIsArabic() then
    return "ar"
  end
  return i18n.lang() or "en"
end

local function trRaw(key, fallback)
  return i18n.trFor(panelLanguage(), key, fallback)
end

local function tr(key, fallback)
  return trRaw("panel." .. key, fallback)
end

-- Whether the shell itself is RTL. The panel can also be RTL when an Arabic
-- Hijri calendar is shown in an otherwise LTR shell; see `contentRtl` below.
local function isRtl()
  return i18n.isRtl()
end

-- The shell mirrors layout rows only for an RTL shell language. An Arabic
-- Hijri grid in an English shell therefore has to mirror its own rows.
local function reversed(items)
  local result = {}
  for index = #items, 1, -1 do
    result[#result + 1] = items[index]
  end
  return result
end

local function weekStart()
  local value = tostring(noctalia.getConfig("week_start") or "friday")
  return WEEK_START_INDEX[value] or WEEK_START_INDEX.friday
end

local function weekdayIndexFromWday(wday)
  -- os.date("*t").wday is 1..7 with Sunday = 1; use 0..6 with Sunday = 0.
  return (wday - 1) % 7
end

local function weekdayName(index, full)
  local key = "weekday." .. WEEKDAY_KEYS[index + 1] .. (full and "_full" or "")
  local fallback = (full and WEEKDAY_LONG_EN or WEEKDAY_SHORT_EN)[index + 1]
  return trRaw(key, fallback)
end

local function gregorianMonthName(month)
  return trRaw("month." .. tostring(month), GREGORIAN_MONTHS_EN[month] or tostring(month))
end

local function hijriMonthName(month, arabicName, englishName)
  if i18n.hijriIsArabic() then
    return (arabicName ~= nil and arabicName ~= "") and arabicName or HIJRI_MONTHS[month] or ""
  end
  return (englishName ~= nil and englishName ~= "") and englishName or HIJRI_MONTHS_EN[month] or arabicName or ""
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

local function stateYmd(key)
  local value = noctalia.state.get(key)
  if type(value) ~= "table" then
    return nil
  end
  local year = tonumber(value.y)
  local month = tonumber(value.m)
  local day = tonumber(value.d)
  if year == nil or month == nil or day == nil then
    return nil
  end
  return { y = year, m = month, d = day }
end

-- The service publishes the Hijri day in effect now, already rolled over at
-- Maghrib. The panel prefers it over converting the civil date so the
-- highlighted day always matches the bar.
local function currentHijri()
  return stateYmd("hijri.current_h")
end

local function currentHijriGregorian()
  return stateYmd("hijri.current_g")
end

local function gregorianLong(year, month, day)
  local wday = os.date("*t", os.time({ year = year, month = month, day = day })).wday
  return weekdayName(weekdayIndexFromWday(wday), true)
    .. " " .. tostring(day)
    .. " " .. gregorianMonthName(month)
    .. " " .. tostring(year)
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

local function decodeCacheFile(path)
  if not noctalia.fileExists(path) then
    return nil
  end
  local raw = noctalia.readFile(path)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local ok, decoded = pcall(noctalia.json.decode, raw)
  if not ok or type(decoded) ~= "table" or decoded.version ~= CACHE_VERSION or type(decoded.months) ~= "table" then
    return nil
  end
  return decoded
end

local function loadCache(key, path)
  local stored = noctalia.state.get(key)
  if type(stored) == "table" and stored.version == CACHE_VERSION and type(stored.months) == "table" then
    return stored.months
  end
  local decoded = decodeCacheFile(path)
  if decoded ~= nil then
    noctalia.state.set(key, decoded)
    return decoded.months
  end
  return {}
end

local function pruneMonths(months)
  local now = os.time()
  for key, entry in pairs(months) do
    if type(entry) ~= "table"
      or type(entry.fetchedAt) ~= "number"
      or now - entry.fetchedAt >= CACHE_TTL_SECONDS then
      months[key] = nil
    end
  end
  return months
end

local function saveCache(key, path, months)
  local cleaned = pruneMonths(months)
  local payload = { version = CACHE_VERSION, months = cleaned }
  noctalia.state.set(key, payload)
  local ok, encoded = pcall(noctalia.json.encode, payload)
  if ok and type(encoded) == "string" then
    noctalia.writeFile(path, encoded)
  end
end

local function loadGCache()
  if cacheG ~= nil then
    return
  end
  cacheG = loadCache(GCACHE_KEY, GCACHE_FILE)
end

local function saveGCache()
  saveCache(GCACHE_KEY, GCACHE_FILE, cacheG)
end

local function loadHCache()
  if cacheH ~= nil then
    return
  end
  cacheH = loadCache(HCACHE_KEY, HCACHE_FILE)
end

local function saveHCache()
  saveCache(HCACHE_KEY, HCACHE_FILE, cacheH)
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
  return {
    y = day.hy,
    m = day.hm,
    d = day.hd,
    w = day.hw or "",
    name = day.hn or "",
    name_en = day.hn_en or "",
  }
end

-- Finds a Hijri day in the panel cache and returns it with the Gregorian
-- date the API assigns to it. Used by Today and by the Maghrib rollover.
local function hijriCellFor(hijri)
  if hijri == nil then
    return nil
  end
  local entry = cachedH(hijri.y, hijri.m)
  if entry == nil or type(entry.days) ~= "table" then
    return nil
  end
  for _, day in ipairs(entry.days) do
    if day.hy == hijri.y and day.hm == hijri.m and day.hd == hijri.d then
      return {
        g = { y = day.gy, m = day.gm, d = day.gd },
        h = {
          y = day.hy,
          m = day.hm,
          d = day.hd,
          w = day.hw,
          name = day.hn,
          name_en = day.hn_en,
        },
      }
    end
  end
  return nil
end

local function hijriFull(h, g)
  if h == nil then
    return nil
  end
  local weekday = ""
  if i18n.hijriIsArabic() then
    if h.w ~= nil and h.w ~= "" then
      weekday = h.w .. " "
    elseif g ~= nil then
      local wday = os.date("*t", os.time({ year = g.y, month = g.m, day = g.d })).wday
      weekday = WEEKDAY_LONG_AR[weekdayIndexFromWday(wday) + 1] .. " "
    end
  elseif g ~= nil then
    local wday = os.date("*t", os.time({ year = g.y, month = g.m, day = g.d })).wday
    weekday = WEEKDAY_LONG_EN[weekdayIndexFromWday(wday) + 1] .. " "
  elseif h.w ~= nil and h.w ~= "" then
    weekday = h.w .. " "
  end
  local monthName = hijriMonthName(h.m, h.name, h.name_en)
  return weekday .. tostring(h.d) .. " " .. monthName .. " " .. tostring(h.y)
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
  local firstName = hijriMonthName(first.hm, first.hn, first.hn_en)
  local lastName = hijriMonthName(last.hm, last.hn, last.hn_en)
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
  local firstName = gregorianMonthName(first.gm)
  local lastName = gregorianMonthName(last.gm)
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
            hn_en = (hijri.month and hijri.month.en) or "",
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
          hn_en = (hijri.month and hijri.month.en) or "",
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
  local leading = (weekdayIndexFromWday(firstWeekday) - weekStart() + 7) % 7
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
        hn_en = hijri and hijri.name_en or nil,
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
  local leading = (weekdayIndexFromWday(firstWeekday) - weekStart() + 7) % 7
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
          hn_en = day.hn_en,
        })
      end
    end
  end

  return cells
end

local function buildSwitchRow(isHijri)
  local function mainLabel(text, active)
    return ui.label({
      text = text,
      fontSize = 11,
      fontWeight = "medium",
      maxLines = 1,
      color = active and "primary" or "on_surface_variant",
    })
  end

  local function option(value, text, active)
    return ui.column({
      width = 104,
      height = 28,
      align = "center",
      justify = "center",
      radius = 14,
      fill = active and "primary/0.18" or "primary/0",
      border = active and "primary/0.55" or "outline_variant",
      borderWidth = 1,
      onClick = function()
        if not active then
          applyMain(value, true)
        end
      end,
    }, {
      mainLabel(text, active),
    })
  end

  -- Two separate pills at opposite ends of the panel instead of one shared
  -- capsule. Keep Gregorian on the left and Hijri on the far right in both
  -- reading directions: under RTL the row mirrors its children, so swap.
  local gregorianOption = option("gregorian", tr("gregorian", "Gregorian"), not isHijri)
  local hijriOption = option("hijri", tr("hijri", "Hijri"), isHijri)
  local options = isRtl() and { hijriOption, gregorianOption } or { gregorianOption, hijriOption }

  return ui.row({
    fill = true,
    height = 28,
    align = "center",
    justify = "space_between",
    gap = 8,
  }, options)
end

local selectCell
local function makeCell(cell, todayG, todayH, isHijri)
  if cell.blank then
    return ui.column({ flexGrow = 1, height = 50 })
  end

  local isToday
  local isSelected
  if isHijri then
    -- "Today" in the Hijri grid follows Maghrib, like the bar. The Gregorian
    -- grid below keeps the civil date.
    isToday = todayH ~= nil
      and cell.hy == todayH.y
      and cell.hm == todayH.m
      and cell.hd == todayH.d
    isSelected = selected ~= nil
      and selected.h ~= nil
      and cell.hy == selected.h.y
      and cell.hm == selected.h.m
      and cell.hd == selected.h.d
  else
    isToday = cell.gy == todayG.y and cell.gm == todayG.m and cell.gd == todayG.d
    isSelected = selected ~= nil
      and selected.g ~= nil
      and cell.gy == selected.g.y
      and cell.gm == selected.g.m
      and cell.gd == selected.g.d
  end

  -- Retained nodes keep appearance props that a later render omits, so every
  -- cell always sets fill/border explicitly; a zero-alpha role clears them.
  local fill = "primary/0"
  local border = "primary/0"
  local borderWidth = 0
  local primaryColor = cell.inMonth and "on_surface" or "on_surface_variant"
  local secondaryColor = "on_surface_variant"
  local weight = cell.inMonth and "medium" or "normal"

  if isSelected then
    -- Selection gets the outline; today only gets a tint. Keeping them
    -- different means clicking today off still shows a visible change.
    fill = "primary/0.2"
    border = "primary/0.7"
    borderWidth = 1
    primaryColor = "primary"
    secondaryColor = "primary/0.85"
    weight = "bold"
  elseif isToday then
    fill = "primary/0.1"
    primaryColor = "primary"
    secondaryColor = "primary/0.8"
    weight = "bold"
  end

  local primaryText
  local secondaryText
  if isHijri then
    primaryText = cell.hd ~= nil and tostring(cell.hd) or ""
    secondaryText = tostring(cell.gd)
  else
    primaryText = tostring(cell.gd)
    secondaryText = cell.hd ~= nil and tostring(cell.hd) or ""
  end

  local primaryProps = {
    text = primaryText,
    fontSize = 13,
    fontWeight = weight,
    color = primaryColor,
    maxLines = 1,
  }

  local secondaryProps = {
    text = secondaryText,
    fontSize = 9,
    fontWeight = "normal",
    color = secondaryColor,
    maxLines = 1,
  }

  local props = {
    key = string.format("d-%04d-%02d-%02d", cell.gy, cell.gm, cell.gd),
    flexGrow = 1,
    height = 50,
    align = "center",
    justify = "center",
    gap = 0,
    radius = 6,
    opacity = cell.inMonth and 1.0 or 0.4,
    fill = fill,
    border = border,
    borderWidth = borderWidth,
    onClick = function()
      selectCell(cell)
    end,
  }

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
  i18n.refresh()
  if viewYear == nil or viewMonth == nil then
    renderLoading()
    return
  end

  local isHijri = main == "hijri"
  local shellRtl = isRtl()
  local contentRtl = isHijri and i18n.hijriIsArabic()
  local rtl = shellRtl or contentRtl
  local mirrorRows = rtl and not shellRtl
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
  local todayH = isHijri and (currentHijri() or hijriForGDate(todayG)) or nil

  local titleText
  if isHijri then
    local apiName = nil
    local apiNameEn = nil
    if entryH ~= nil and type(entryH.days) == "table" and entryH.days[1] ~= nil then
      apiName = entryH.days[1].hn
      apiNameEn = entryH.days[1].hn_en
    end
    local monthName = hijriMonthName(viewMonth, apiName, apiNameEn)
    titleText = monthName .. " " .. tostring(viewYear)
  else
    titleText = gregorianMonthName(viewMonth) .. " " .. tostring(viewYear)
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

  local subtitleProps = {
    text = subtitleText,
    fontSize = 11,
    color = loadFailed and "error" or "on_surface_variant",
    maxLines = 1,
    maxWidth = 290,
  }

  -- RTL puts the previous-month button on the right, pointing right. The
  -- shell mirrors the row for an RTL shell; an Arabic Hijri grid in an LTR
  -- shell is mirrored here instead.
  local previousGlyph = rtl and "chevron-right" or "chevron-left"
  local nextGlyph = rtl and "chevron-left" or "chevron-right"

  local previousButton = ui.button({
    glyph = previousGlyph,
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
  })
  local nextButton = ui.button({
    glyph = nextGlyph,
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
  })
  local headerCenter = ui.column({ flexGrow = 1, align = "center", gap = 0 }, {
    ui.label(titleProps),
    ui.label(subtitleProps),
  })
  local headerChildren = { previousButton, headerCenter, nextButton }
  if mirrorRows then
    headerChildren = { nextButton, headerCenter, previousButton }
  end
  local header = ui.row({ align = "center", gap = 6 }, headerChildren)

  local weekdayCells = {}
  local start = weekStart()
  for index = 0, 6 do
    local weekdayIndex = (start + index) % 7
    local weekdayText
    if isHijri then
      -- The Hijri grid keeps its own language, independent of the shell.
      weekdayText = i18n.hijriIsArabic()
          and WEEKDAY_SHORT_AR[weekdayIndex + 1]
        or WEEKDAY_SHORT_EN[weekdayIndex + 1]
    else
      weekdayText = weekdayName(weekdayIndex, false)
    end
    table.insert(weekdayCells, ui.column({ flexGrow = 1, align = "center" }, {
      ui.label({
        text = weekdayText,
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 1,
      }),
    }))
  end
  if mirrorRows then
    weekdayCells = reversed(weekdayCells)
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
        table.insert(rowCells, makeCell(cell, todayG, todayH, isHijri))
      end
      if mirrorRows then
        rowCells = reversed(rowCells)
      end
      table.insert(rows, ui.row({ gap = 2, height = 50 }, rowCells))
    end
    grid = ui.column({ gap = 2 }, rows)
  end

  local footerPrimary
  local footerSecondary
  if selected == nil or selected.g == nil then
    footerPrimary = tr("select_day", "Select a day to see its Hijri date")
    footerSecondary = ""
  else
    local g = selected.g
    local hijri = hijriForGDate(g) or selected.h
    local gregText = gregorianLong(g.y, g.m, g.d)
    local hijriText = hijriFull(hijri, g)
    if isHijri then
      footerPrimary = hijriText or (loadFailed and tr("error", "Could not load the Hijri calendar")
        or tr("loading", "Loading…"))
      footerSecondary = gregText
    else
      footerPrimary = gregText
      footerSecondary = hijriText or (loadFailed and tr("error", "Could not load the Hijri calendar")
        or tr("loading", "Loading…"))
    end
  end

  local footerTextAlign = rtl and "end" or "start"
  local footerPrimaryProps = {
    text = footerPrimary,
    fontSize = 13,
    fontWeight = "medium",
    maxLines = 1,
    maxWidth = 300,
    textAlign = footerTextAlign,
  }

  local footerChildren = {
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label(footerPrimaryProps),
      ui.label({
        text = footerSecondary,
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 1,
        maxWidth = 300,
        textAlign = footerTextAlign,
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
  if mirrorRows then
    footerChildren = reversed(footerChildren)
  end

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
  local currentH = currentHijri()

  if main == "hijri" and currentH ~= nil then
    local found = hijriCellFor(currentH)
    selected = {
      g = (found ~= nil and found.g) or currentHijriGregorian() or g,
      h = (found ~= nil and found.h) or {
        y = currentH.y,
        m = currentH.m,
        d = currentH.d,
      },
    }
    pendingViewG = nil
    viewYear, viewMonth = currentH.y, currentH.m
    ensureHView(viewYear, viewMonth)
    render()
    return
  end

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
  -- Clicking the selected day again clears the selection, so the footer goes
  -- back to the hint and the cell loses its outline. The Hijri grid compares
  -- Hijri dates, the Gregorian grid Gregorian dates.
  local sameSelection
  if main == "hijri" and selected ~= nil and selected.h ~= nil then
    sameSelection = selected.h.y == cell.hy
      and selected.h.m == cell.hm
      and selected.h.d == cell.hd
  else
    sameSelection = selected ~= nil
      and selected.g ~= nil
      and selected.g.y == cell.gy
      and selected.g.m == cell.gm
      and selected.g.d == cell.gd
  end
  if sameSelection then
    selected = nil
    pendingViewG = nil
    render()
    return
  end

  local hijri = nil
  if cell.hd ~= nil then
    hijri = {
      y = cell.hy,
      m = cell.hm,
      d = cell.hd,
      w = cell.hw,
      name = cell.hn,
      name_en = cell.hn_en,
    }
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

applyMain = function(nextMain, persist)
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

-- The service rolls the Hijri day over at Maghrib. Repaint an open panel so
-- its Today highlight moves with the bar. The service republishes the key
-- every minute, so only act when the day itself changes.
noctalia.state.watch("hijri.current_h", function()
  local current = currentHijri()
  local key = current ~= nil
      and string.format("%04d-%02d-%02d", current.y, current.m, current.d)
    or ""
  if key == lastCurrentHKey then
    return
  end
  lastCurrentHKey = key
  if isOpen then
    render()
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

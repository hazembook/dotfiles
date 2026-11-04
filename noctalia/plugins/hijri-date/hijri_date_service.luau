--!nonstrict
-- Hijri Date service - owns the aladhan.com requests and publishes the
-- result to the bar widget through the plugin's shared state.
--
-- State keys (read by the widget):
--   hijri.today      - Hijri date of the current day, formatted
--   hijri.tomorrow   - Hijri date of the next day (it starts at today's Maghrib)
--   hijri.display    - hijri.today or hijri.tomorrow, whichever applies now
--   hijri.maghrib    - Maghrib in minutes since midnight
--   hijri.timezone   - IANA zone of the location, for the Maghrib comparison
--   hijri.day        - Gregorian day (DD-MM-YYYY) the cache belongs to
--   hijri.fetched_at - epoch of the last successful response
--   hijri.failed_at  - epoch of the last failed attempt
--
-- The Hijri date only changes at Maghrib, so one successful response is kept
-- for the whole Gregorian day. A failed request backs off for five minutes
-- instead of retrying on every tick.

local i18n = require("./i18n.luau")

local RETRY_SECONDS = 5 * 60
local inFlight = false

local function tr(key, fallback)
  return i18n.tr(key, fallback)
end

-- The shell's own language setting also decides the reading direction.
local function isRtl()
  return i18n.isRtl()
end

local function setting(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil or value == "" then
    return fallback
  end
  return tostring(value)
end

local function pad2(n)
  return (n < 10 and "0" or "") .. n
end

-- "18:32 (EET)" -> minutes since midnight. Also understands "6:32 pm".
local function timeToMinutes(timeStr)
  if type(timeStr) ~= "string" then
    return nil
  end
  local hh, mm, suffix = timeStr:match("(%d+):(%d+)(.*)")
  if hh == nil then
    return nil
  end
  local hours = tonumber(hh)
  local minutes = tonumber(mm)
  local rest = (suffix or ""):lower()
  if rest:find("pm") and hours < 12 then
    hours = hours + 12
  elseif rest:find("am") and hours == 12 then
    hours = 0
  end
  return hours * 60 + minutes
end

local ENGLISH_WEEKDAYS = {
  sunday = "Sunday",
  monday = "Monday",
  tuesday = "Tuesday",
  wednesday = "Wednesday",
  thursday = "Thursday",
  friday = "Friday",
  saturday = "Saturday",
}

local function weekdayText(englishKey, language)
  local fallback = ENGLISH_WEEKDAYS[englishKey]
    or (englishKey:sub(1, 1):upper() .. englishKey:sub(2))
  if language == "en" then
    return fallback
  end
  return tr("weekday." .. englishKey .. "_full", fallback)
end

-- The English rendering is stored independently of the active language, so
-- switching `shell.lang` never shows an Arabic weekday in the English bar.
local function formatHijriEn(hijri, gregorian)
  local english = (gregorian.weekday.en or ""):lower()
  local weekday
  if ENGLISH_WEEKDAYS[english] ~= nil then
    weekday = weekdayText(english, "en")
  else
    weekday = hijri.weekday.en or ""
  end
  return weekday .. " " .. hijri.day .. " " .. (hijri.month.en or hijri.month.ar or "") .. " " .. hijri.year
end

local function formatHijriAr(hijri)
  return (hijri.weekday.ar or "") .. " " .. hijri.day .. " " .. (hijri.month.ar or "") .. " " .. hijri.year
end

-- Gregorian weekday of today -> the key of the next day. The Hijri day that
-- starts at Maghrib is the one that contains the next Gregorian day.
local NEXT_WEEKDAY = {
  sunday = "monday",
  monday = "tuesday",
  tuesday = "wednesday",
  wednesday = "thursday",
  thursday = "friday",
  friday = "saturday",
  saturday = "sunday",
}

local function fetchDay(dateDMY, callback)
  local url = "https://api.aladhan.com/v1/timings/" .. dateDMY
    .. "?latitude=" .. setting("latitude", "32.8872")
    .. "&longitude=" .. setting("longitude", "13.1913")
    .. "&method=" .. setting("method", "3")
  noctalia.http({ url = url, method = "GET" }, function(response)
    if not response.ok or response.status ~= 200 then
      callback(nil, "http status " .. tostring(response.status))
      return
    end
    local payload = noctalia.json.decode(response.body)
    if type(payload) ~= "table" or payload.code ~= 200 or type(payload.data) ~= "table" then
      callback(nil, "unexpected payload")
      return
    end
    callback(payload.data)
  end)
end

-- Current time in the location's own zone (the zone the prayer times, and
-- therefore Maghrib, are expressed in).
local function currentLocationMinutes(zone)
  local text = noctalia.formatTime("{:%H:%M}", nil, zone)
  local hh, mm = text:match("(%d+):(%d+)")
  if hh == nil then
    return nil
  end
  return tonumber(hh) * 60 + tonumber(mm)
end

-- The Hijri day runs from Maghrib to Maghrib: once Maghrib has passed, the
-- day that started at it is the current one. The service stores both the
-- Arabic and the English rendering, so changing the shell language does not
-- need another request.
local function publishDisplay()
  i18n.refresh()
  local rtl = isRtl()
  local today = noctalia.state.get(rtl and "hijri.today" or "hijri.today_en")
    or noctalia.state.get("hijri.today")
  local tomorrow = noctalia.state.get(rtl and "hijri.tomorrow" or "hijri.tomorrow_en")
    or noctalia.state.get("hijri.tomorrow")
  local maghrib = noctalia.state.get("hijri.maghrib")
  local current = currentLocationMinutes(noctalia.state.get("hijri.timezone"))

  local display = today
  if maghrib and tomorrow and current ~= nil and current >= maghrib then
    display = tomorrow
  end
  noctalia.state.set("hijri.display", display)
end

-- Publishes the fetched day plus the day that starts at the coming Maghrib.
local function applyDay(data, tomorrowData)
  local hijri = data.date.hijri

  local tomorrowText
  local tomorrowTextEn
  if tomorrowData ~= nil then
    tomorrowText = formatHijriAr(tomorrowData.date.hijri)
    tomorrowTextEn = formatHijriEn(tomorrowData.date.hijri, tomorrowData.date.gregorian)
  else
    -- The second request failed: fall back to same-month arithmetic, which is
    -- only valid while the month still has days left (the API reports the
    -- length of the current Hijri month).
    local day = tonumber(hijri.day)
    local monthDays = tonumber(hijri.month.days)
    if day ~= nil and monthDays ~= nil and day < monthDays then
      local nextKey = NEXT_WEEKDAY[(data.date.gregorian.weekday.en or ""):lower()] or "sunday"
      local nextDay = pad2(day + 1)
      tomorrowText = weekdayText(nextKey)
        .. " " .. nextDay
        .. " " .. (hijri.month.ar or "")
        .. " " .. hijri.year
      tomorrowTextEn = weekdayText(nextKey, "en")
        .. " " .. nextDay
        .. " " .. (hijri.month.en or hijri.month.ar or "")
        .. " " .. hijri.year
    end
  end

  noctalia.state.set("hijri.today", formatHijriAr(hijri))
  noctalia.state.set("hijri.today_en", formatHijriEn(hijri, data.date.gregorian))
  noctalia.state.set("hijri.tomorrow", tomorrowText)
  noctalia.state.set("hijri.tomorrow_en", tomorrowTextEn)
  noctalia.state.set("hijri.maghrib", timeToMinutes(data.timings.Maghrib))
  noctalia.state.set("hijri.timezone", (data.meta and data.meta.timezone) or nil)
  noctalia.state.set("hijri.fetched_at", os.time())
  noctalia.state.set("hijri.failed_at", nil)
  publishDisplay()
end

local function fetchBoth(todayDMY)
  inFlight = true
  fetchDay(todayDMY, function(data, err)
    if data == nil then
      inFlight = false
      noctalia.log("hijri-date: request failed (" .. tostring(err) .. ")")
      noctalia.state.set("hijri.failed_at", os.time())
      return
    end

    local tomorrowDMY = os.date("%d-%m-%Y", os.time() + 86400)
    fetchDay(tomorrowDMY, function(tomorrowData)
      inFlight = false
      applyDay(data, tomorrowData)
      if tomorrowData == nil then
        -- Keep trying for the next day, but respect the retry backoff.
        noctalia.state.set("hijri.failed_at", os.time())
      end
    end)
  end)
end

local function refresh()
  if inFlight then
    return
  end

  local now = os.time()
  local todayDMY = os.date("%d-%m-%Y")
  local cachedDay = noctalia.state.get("hijri.day")
  local today = noctalia.state.get("hijri.today")
  local failedAt = noctalia.state.get("hijri.failed_at")

  local needsFetch = false
  if cachedDay ~= todayDMY then
    -- A new Gregorian day: drop the previous day's values so a failed
    -- request cannot leave a stale Hijri date on the bar.
    noctalia.state.set("hijri.today", nil)
    noctalia.state.set("hijri.today_en", nil)
    noctalia.state.set("hijri.tomorrow", nil)
    noctalia.state.set("hijri.tomorrow_en", nil)
    noctalia.state.set("hijri.maghrib", nil)
    noctalia.state.set("hijri.day", todayDMY)
    needsFetch = true
  elseif today == nil or noctalia.state.get("hijri.today_en") == nil then
    -- The day's fetch failed (or the state is from an older version that did
    -- not keep the English rendering): retry after the backoff.
    needsFetch = failedAt == nil or now - failedAt >= RETRY_SECONDS
  elseif noctalia.state.get("hijri.tomorrow") == nil
    or noctalia.state.get("hijri.tomorrow_en") == nil then
    -- The next-day fetch failed: keep trying, respecting the backoff.
    needsFetch = failedAt == nil or now - failedAt >= RETRY_SECONDS
  elseif noctalia.state.get("hijri.timezone") == nil then
    -- Incomplete state (e.g. left over from an older plugin version): the
    -- location's time zone is missing, so refresh once to publish it.
    needsFetch = true
  end

  if not needsFetch then
    return
  end

  fetchBoth(todayDMY)
end

noctalia.setUpdateInterval(60000)

-- Fetch right away instead of waiting a full interval for the first tick.
refresh()
-- Publish the in-memory date immediately too: a language change reloads this
-- entry without refetching, and the bar should switch languages right away.
publishDisplay()

function update()
  refresh()
  -- Recompute the current day every tick: the rollover happens at Maghrib
  -- without waiting for the next request.
  publishDisplay()
end

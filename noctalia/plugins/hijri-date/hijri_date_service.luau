--!nonstrict
-- Hijri Date service - owns the aladhan.com requests and publishes the
-- result to the bar widget through the plugin's shared state.
--
-- State keys (read by the widget):
--   hijri.today      - Hijri date of the current day, formatted
--   hijri.tomorrow   - Hijri date of the next day (it starts at today's Maghrib)
--   hijri.maghrib    - Maghrib in minutes since midnight
--   hijri.timezone   - IANA zone of the location, for the Maghrib comparison
--   hijri.fetched_at - epoch of the last successful response
--   hijri.failed_at  - epoch of the last failed attempt
--
-- The Hijri date only changes at Maghrib, so a successful response is reused
-- for an hour; a failed request backs off for five minutes instead of
-- retrying on every tick.

local CACHE_SECONDS = 60 * 60
local RETRY_SECONDS = 5 * 60
local inFlight = false

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

local function formatHijri(hijri)
  return hijri.weekday.ar .. " " .. hijri.day .. " " .. hijri.month.ar .. " " .. hijri.year
end

-- Arabic weekday names exactly as the API spells them, keyed by the
-- Gregorian weekday of the *previous* day: the Hijri day that starts at
-- Maghrib is the one that contains the next Gregorian day.
local NEXT_WEEKDAY_AR = {
  Sunday = "الاثنين",
  Monday = "الثلاثاء",
  Tuesday = "الاربعاء",
  Wednesday = "الخميس",
  Thursday = "الجمعة",
  Friday = "السبت",
  Saturday = "الاحد",
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

-- Publishes the fetched day plus the day that starts at the coming Maghrib.
local function applyDay(data, tomorrowData)
  local hijri = data.date.hijri

  local tomorrowText
  if tomorrowData ~= nil then
    tomorrowText = formatHijri(tomorrowData.date.hijri)
  else
    -- The second request failed: fall back to same-month arithmetic, which is
    -- only valid while the month still has days left (the API reports the
    -- length of the current Hijri month).
    local day = tonumber(hijri.day)
    local monthDays = tonumber(hijri.month.days)
    if day ~= nil and monthDays ~= nil and day < monthDays then
      local weekday = NEXT_WEEKDAY_AR[data.date.gregorian.weekday.en] or hijri.weekday.ar
      tomorrowText = weekday
        .. " " .. pad2(day + 1)
        .. " " .. hijri.month.ar
        .. " " .. hijri.year
    end
  end

  noctalia.state.set("hijri.today", formatHijri(hijri))
  noctalia.state.set("hijri.tomorrow", tomorrowText)
  noctalia.state.set("hijri.maghrib", timeToMinutes(data.timings.Maghrib))
  noctalia.state.set("hijri.timezone", (data.meta and data.meta.timezone) or nil)
  noctalia.state.set("hijri.fetched_at", os.time())
  noctalia.state.set("hijri.failed_at", nil)
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
  local fetchedAt = noctalia.state.get("hijri.fetched_at")
  local failedAt = noctalia.state.get("hijri.failed_at")

  local needsFetch = false
  if cachedDay ~= todayDMY then
    -- A new Gregorian day: drop the previous day's values so a failed
    -- request cannot leave a stale Hijri date on the bar.
    noctalia.state.set("hijri.today", nil)
    noctalia.state.set("hijri.tomorrow", nil)
    noctalia.state.set("hijri.maghrib", nil)
    noctalia.state.set("hijri.day", todayDMY)
    needsFetch = true
  elseif noctalia.state.get("hijri.timezone") == nil then
    -- Incomplete state (e.g. left over from an older plugin version): the
    -- location's time zone is missing, so refresh once to publish it.
    needsFetch = true
  elseif fetchedAt ~= nil and now - fetchedAt >= CACHE_SECONDS then
    needsFetch = true
  elseif fetchedAt == nil and (failedAt == nil or now - failedAt >= RETRY_SECONDS) then
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

function update()
  refresh()
end

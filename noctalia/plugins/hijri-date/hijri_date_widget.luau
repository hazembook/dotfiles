--!nonstrict
-- Hijri Date bar widget: Gregorian date, clock and Hijri date for a fixed
-- location. The Hijri day runs from Maghrib to Maghrib, so after Maghrib the
-- date shown is the one the API reports for the next Gregorian day.
--
-- Data source: https://aladhan.com (v1 timings API).
--
-- The Hijri date only changes at Maghrib, so a successful response is reused
-- for CACHE_SECONDS. A failed request backs off for RETRY_SECONDS instead of
-- retrying on every tick.

local FONT_FAMILY = "Amiri"
local PLACEHOLDER = "جاري التحميل..."

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

local CACHE_SECONDS = 60 * 60
local RETRY_SECONDS = 5 * 60

local function setting(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil or value == "" then
    return fallback
  end
  return tostring(value)
end

local LATITUDE = ""
local LONGITUDE = ""
local METHOD = ""
local CLOCK_24H = false

-- Re-read on every tick so a settings change applies without a plugin reload.
local function loadSettings()
  LATITUDE = setting("latitude", "32.8872")
  LONGITUDE = setting("longitude", "13.1913")
  METHOD = setting("method", "3")
  CLOCK_24H = setting("clock_format", "12h") == "24h"
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

local function fetchDay(dateDMY, callback)
  local url = "https://api.aladhan.com/v1/timings/" .. dateDMY
    .. "?latitude=" .. LATITUDE
    .. "&longitude=" .. LONGITUDE
    .. "&method=" .. METHOD
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

local function currentMinutes()
  local now = os.date("*t")
  return now.hour * 60 + now.min
end

local function displayDate()
  local hijriToday = noctalia.state.get("hijri.today")
  local hijriTomorrow = noctalia.state.get("hijri.tomorrow")
  local maghrib = noctalia.state.get("hijri.maghrib")
  if maghrib and hijriTomorrow and currentMinutes() >= maghrib then
    return hijriTomorrow
  end
  return hijriToday
end

local function updateDisplay()
  local dateStr = os.date("%a %d %b %Y")
  local clockStr = os.date(CLOCK_24H and "%H:%M" or "%I:%M %p")
  barWidget.setText(dateStr .. " | " .. clockStr .. " | " .. (displayDate() or PLACEHOLDER))
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
  noctalia.state.set("hijri.fetched_at", os.time())
  noctalia.state.set("hijri.failed_at", nil)
  updateDisplay()
end

local function fetchBoth(todayDMY)
  fetchDay(todayDMY, function(data, err)
    if data == nil then
      noctalia.log("hijri-date: request failed (" .. tostring(err) .. ")")
      noctalia.state.set("hijri.failed_at", os.time())
      updateDisplay()
      return
    end

    local tomorrowDMY = os.date("%d-%m-%Y", os.time() + 86400)
    fetchDay(tomorrowDMY, function(tomorrowData)
      applyDay(data, tomorrowData)
    end)
  end)
end

-- One-time setup: the top level of the script runs once at load.
barWidget.setFont(FONT_FAMILY)
noctalia.setUpdateInterval(1000)

function update()
  loadSettings()

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
  elseif fetchedAt ~= nil and now - fetchedAt >= CACHE_SECONDS then
    needsFetch = true
  elseif fetchedAt == nil and (failedAt == nil or now - failedAt >= RETRY_SECONDS) then
    needsFetch = true
  end

  if needsFetch then
    fetchBoth(todayDMY)
  end

  updateDisplay()
end

function onClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center calendar")
end

-- Debug helper: `noctalia msg plugin hazembook/hijri-date:date-clock-hijri all status`
function onIpc(event, payload)
  if event ~= "status" then
    return
  end
  noctalia.notify("Hijri Date", "display: " .. tostring(displayDate() or PLACEHOLDER)
    .. "\nmaghrib: " .. tostring(noctalia.state.get("hijri.maghrib"))
    .. "\nfetched_at: " .. tostring(noctalia.state.get("hijri.fetched_at"))
    .. "\nfailed_at: " .. tostring(noctalia.state.get("hijri.failed_at")))
end

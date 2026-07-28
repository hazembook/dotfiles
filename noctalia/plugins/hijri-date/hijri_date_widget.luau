local LAT = "32.8872"
local LNG = "13.1913"
local METHOD = 3

local NEXT_WEEKDAY_AR = {
  Saturday = "الأحد",
  Sunday = "الاثنين",
  Monday = "الثلاثاء",
  Tuesday = "الأربعاء",
  Wednesday = "الخميس",
  Thursday = "الجمعة",
  Friday = "السبت",
}

local function pad2(n)
  return (n < 10 and "0" or "") .. n
end

local function stripSuffix(timeStr)
  return timeStr:match("%d+:%d+") or timeStr
end

local function fetchHijri(todayDMY, callback)
  local url = "https://api.aladhan.com/v1/timings/" .. todayDMY .. "?latitude=" .. LAT .. "&longitude=" .. LNG .. "&method=" .. METHOD
  noctalia.http({ url = url, method = "GET", follow_redirects = true }, callback)
end

local function updateDisplay()
  local dateStr = os.date("%a %d %b %Y")
  local clockStr = os.date("%I:%M %p")
  local currentTime = os.date("%H:%M")

  local hijriToday = noctalia.state.get("hijri_today")
  local hijriTomorrow = noctalia.state.get("hijri_tomorrow")
  local maghrib = noctalia.state.get("maghrib")

  local displayDate = hijriToday
  if maghrib and currentTime > maghrib and hijriTomorrow then
    displayDate = hijriTomorrow
  end

  barWidget.setText(dateStr .. " | " .. clockStr .. " | " .. (displayDate or "جاري التحميل..."))
end

function update()
  noctalia.setUpdateInterval(1000)

  barWidget.setFont("Amiri")

  local todayDMY = os.date("%d-%m-%Y")
  local cachedDate = noctalia.state.get("cached_date")
  local cachedAt = noctalia.state.get("cached_at")
  local now = os.time()
  local fetchNeeded = false

  if cachedDate ~= todayDMY then
    fetchNeeded = true
  elseif not cachedAt or now - cachedAt >= 60 then
    fetchNeeded = true
  end

  if fetchNeeded then
    fetchHijri(todayDMY, function(todayRes)
      if not todayRes.ok or todayRes.status ~= 200 then
        updateDisplay()
        return
      end
      local todayData, err = noctalia.json.decode(todayRes.body)
      if not todayData or todayData.code ~= 200 then
        updateDisplay()
        return
      end

      local timings = todayData.data.timings
      local hijri = todayData.data.date.hijri
      local gregorian = todayData.data.date.gregorian
      local maghribStr = stripSuffix(timings.Maghrib)

      local hDay = tonumber(hijri.day)
      local hMonth = hijri.month.ar
      local hYear = hijri.year
      local hWeekday = hijri.weekday.ar

      local hijriToday = hWeekday .. " " .. hijri.day .. " " .. hMonth .. " " .. hYear

      noctalia.state.set("hijri_today", hijriToday)
      noctalia.state.set("maghrib", maghribStr)
      noctalia.state.set("cached_date", todayDMY)

      local function setTomorrow(hijriTomorrow)
        noctalia.state.set("hijri_tomorrow", hijriTomorrow)
        noctalia.state.set("cached_at", os.time())
        updateDisplay()
      end

      if hDay >= 29 then
        local tomorrowDMY = os.date("%d-%m-%Y", now + 86400)
        fetchHijri(tomorrowDMY, function(tomorrowRes)
          if not tomorrowRes.ok or tomorrowRes.status ~= 200 then
            noctalia.state.set("cached_at", os.time())
            updateDisplay()
            return
          end
          local tomorrowData, err2 = noctalia.json.decode(tomorrowRes.body)
          if not tomorrowData or tomorrowData.code ~= 200 then
            noctalia.state.set("cached_at", os.time())
            updateDisplay()
            return
          end
          local h2 = tomorrowData.data.date.hijri
          setTomorrow(h2.weekday.ar .. " " .. h2.day .. " " .. h2.month.ar .. " " .. h2.year)
        end)
      else
        local nextDay = hDay + 1
        local nextDayStr = pad2(nextDay)
        local gWeekEn = gregorian.weekday.en
        local nextWeekAr = NEXT_WEEKDAY_AR[gWeekEn] or hWeekday
        setTomorrow(nextWeekAr .. " " .. nextDayStr .. " " .. hMonth .. " " .. hYear)
      end
    end)
  else
    updateDisplay()
  end
end

function onClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center calendar", function(_) end)
end

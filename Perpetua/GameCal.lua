-- The site's raids as guild events in Blizzard's calendar, so everyone in the guild sees them, addon or not.
--
-- Officers get a bar on the Calendar tab ("2 raids aren't on the guild calendar  [ADD]"). Each click does one thing:
-- adds the next missing raid as a guild sign-up event, or takes off one the site cancelled or moved. One per
-- click because the calendar server handles one action at a time, and making events from a click is what
-- Blizzard's own calendar does (it may refuse them otherwise).
--
-- A raid counts as on the calendar when a guild event on the same day and minute has the same title, whoever
-- made it, so two officers don't add it twice. PerpetuaDB.guilds[g].gameCal remembers which event stood for which
-- raid (title and time), so a moved or cancelled raid's old event can be found and removed.
--
-- Calendar times are realm time; the site's are UTC seconds. The difference comes from the calendar's clock, with
-- summer time worked out for the raid's date (realmDate below).
local _, ns = ...

local TITLE_MAX = 31  -- letters Blizzard's create-event title box takes
local DESC_MAX = 250

local loaded, busy, lastError = false, false, nil

-- A Lua error is for us, not for the officer: the bar says something useful; test installs (-dev) print the detail.
local FRIENDLY = "Couldn't update the guild calendar. Try again, or use Blizzard's calendar."
local function internalError(err)
  if ns.DEV then print("|cffd4af37Perpetua|r (dev) guild calendar: " .. tostring(err)) end
  return FRIENDLY
end

local function api() return C_Calendar and C_Calendar.CreateGuildSignUpEvent and C_Calendar.AddEvent and C_DateAndTime end

local function store()
  local g = PerpetuaDB.guilds and PerpetuaDB.guilds[ns.guildName() or "No guild"]
  if not g then return {} end
  g.gameCal = g.gameCal or {}
  return g.gameCal
end

-- Cuts to n bytes without splitting a UTF-8 character.
local function clip(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  s = s:sub(1, n)
  return (s:gsub("[\192-\255][\128-\191]*$", ""))
end

local function titleOf(e) return clip(e.title or e.instance or "Raid", TITLE_MAX) end

-- Realm time for a raid weeks ahead can't use today's offset: the realm may change clocks before then (and US and
-- EU change on different weekends). So: today's offset from UTC, less an hour if the realm is on summer time now,
-- is its standard offset; a raid's offset is that, plus an hour if the realm is on summer time then. Summer time
-- follows the region's rules (US realms in US time zones, EU realms); anywhere else keeps today's offset.
-- All arithmetic is in UTC, so this computer's own time zone and clock changes play no part.

-- Seconds since 1970 for a UTC calendar date (days-from-civil, so no time zone is involved).
local function utc(y, m, d, h, min)
  y = m <= 2 and y - 1 or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return ((era * 146097 + doe - 719468) * 24 + (h or 0)) * 3600 + (min or 0) * 60
end
ns.utcSeconds = utc -- for the test harness

-- Day of month of the nth Sunday (n = -1: the last) of a month.
local function sunday(y, m, n)
  local function weekday(d) return (math.floor(utc(y, m, d) / 86400) + 4) % 7 end -- 0 = Sunday (1970-01-01 was a Thursday)
  if n > 0 then
    local first = 1 + (7 - weekday(1)) % 7
    return first + (n - 1) * 7
  end
  local last = 31
  while last > 28 and date("!*t", utc(y, m, last)).month ~= m do last = last - 1 end
  return last - weekday(last)
end

-- Is the realm on summer time at UTC second t? std = its standard offset from UTC in seconds.
local RULES = {
  -- US and Canada: second Sunday in March, 2:00 local standard, to first Sunday in November, 2:00 local summer time.
  us = function(t, std)
    local y = date("!*t", t + std).year
    local from = utc(y, 3, sunday(y, 3, 2), 2) - std
    local to = utc(y, 11, sunday(y, 11, 1), 1) - std
    return t >= from and t < to
  end,
  -- EU: last Sunday in March to last Sunday in October, both at 1:00 UTC.
  eu = function(t)
    local y = date("!*t", t).year
    return t >= utc(y, 3, sunday(y, 3, -1), 1) and t < utc(y, 10, sunday(y, 10, -1), 1)
  end,
}

-- Today's realm offset from UTC (calendar clock vs server clock), rounded to 15 minutes.
local function currentOffset()
  local c = C_DateAndTime.GetCurrentCalendarTime()
  if not c then return 0 end
  local now = ns.now()
  return math.floor((utc(c.year, c.month, c.monthDay, c.hour, c.minute) - now) / 900 + 0.5) * 900
end

-- Which rules apply: US region realms between UTC-10 and UTC-3 (not Oceanic or Brazil), EU region realms.
local function rulesFor(offset)
  local region = ns.try(GetCurrentRegion)
  if region == 1 and offset <= -3 * 3600 and offset >= -10 * 3600 then
    -- Brazil realms (UTC-3 all year) keep one time; no US time zone sits there. Latin America realms (UTC-6 all
    -- year) can't be told from US Central by the clock alone and get US rules: an hour out in US summer there.
    if offset == -3 * 3600 then return nil end
    return RULES.us
  end
  if region == 3 then return RULES.eu end
  return nil
end

-- UTC seconds -> the realm's { year, month, day, hour, min } at that time.
local function realmDateAt(t, now, offset)
  local rule = rulesFor(offset)
  if not rule then return date("!*t", t + offset) end
  -- On summer time now (asked with the standard offset that would mean), today's offset is an hour ahead of standard.
  local std = offset - (rule(now, offset - 3600) and 3600 or 0)
  return date("!*t", t + std + (rule(t, std) and 3600 or 0))
end
ns.realmDateAt = realmDateAt -- for the test harness

local function realmDate(t) return realmDateAt(t, ns.now(), currentOffset()) end

-- Looks through one day for a guild event with this title starting at this minute. Returns the day event's index
-- with the month already selected (monthOffset 0), or nil.
-- Switching months makes the game fire CALENDAR_UPDATE_EVENT_LIST on the spot, so: switch only when the month
-- differs, and ignore calendar events during a scan and just after it (see the event handler).
local onMonth, scanning, scannedAt = nil, false, 0
local function showMonth(month, year)
  if onMonth and onMonth.month == month and onMonth.year == year then return end
  C_Calendar.SetAbsMonth(month, year)
  onMonth = { month = month, year = year }
end

local function findOnDay(title, d)
  showMonth(d.month, d.year)
  for i = 1, (C_Calendar.GetNumDayEvents(0, d.day) or 0) do
    local ev = C_Calendar.GetDayEvent(0, d.day, i)
    if ev and (ev.calendarType == "GUILD_EVENT" or ev.calendarType == "GUILD_ANNOUNCEMENT")
      and ev.sequenceType ~= "ONGOING" and ev.sequenceType ~= "END"
      and ev.title == title and ev.startTime and ev.startTime.hour == d.hour and ev.startTime.minute == d.min then
      return i
    end
  end
end

-- Runs fn with the calendar on whatever month it needs, then puts Blizzard's calendar back on its month.
local function keepingMonth(fn)
  if scanning then return nil end
  scanning = true
  local cur = C_Calendar.GetMonthInfo(0)
  onMonth = cur and cur.month and { month = cur.month, year = cur.year } or nil
  local ok, a, b = pcall(fn)
  if cur and cur.month then pcall(showMonth, cur.month, cur.year) end
  scanning, scannedAt = false, GetTime()
  if not ok then lastError = internalError(a) return nil end
  return a, b
end

local function beforeMax(d)
  local m = C_Calendar.GetMaxCreateDate and C_Calendar.GetMaxCreateDate()
  if not m then return true end
  return d.year * 10000 + d.month * 100 + d.day <= m.year * 10000 + m.month * 100 + m.monthDay
end

-- What still needs doing, in order: removals first (cancelled or moved raids), then raids to add.
-- { kind = "remove"|"add", e = site event, title, d = realm date, index (remove only) }
function ns.gameCalTodo()
  if not (api() and loaded) or ns.locked() or not ns.isOfficer(ns.selfName) then return {} end
  local cal = ns.calendar()
  if not cal then return {} end
  local remember = store()
  local removes, adds = {}, {}
  local now = ns.now()
  keepingMonth(function()
    for _, e in ipairs(cal.events or {}) do
      local title, t = titleOf(e), tonumber(e.t)
      local was = remember[e.id]
      -- The event made for this raid's earlier title or time (moved), or for a raid the site has cancelled.
      if was and (e.cancelled == 1 or was.title ~= title or was.t ~= t) and (was.t or 0) > now then
        local d = realmDate(was.t)
        local i = findOnDay(was.title, d)
        if i then removes[#removes + 1] = { kind = "remove", e = e, title = was.title, d = d, index = i }
        elseif e.cancelled == 1 then remember[e.id] = nil end
      end
      if e.cancelled ~= 1 and t and t > now then
        local d = realmDate(t)
        if findOnDay(title, d) then
          remember[e.id] = { title = title, t = t }
        elseif beforeMax(d) then
          adds[#adds + 1] = { kind = "add", e = e, title = title, d = d }
        end
      end
    end
  end)
  -- Forget raids that are over.
  for id, was in pairs(remember) do if (was.t or 0) < now - 86400 then remember[id] = nil end end
  for _, a in ipairs(adds) do removes[#removes + 1] = a end
  return removes
end

-- The scan switches the calendar's month, so it isn't run on every redraw: at most every few seconds, or when the
-- calendar says it changed (and then the tab is redrawn only if the answer changed, so the two can't loop).
local cache, cacheAt, cacheSig = nil, 0, ""
local function signature(todo)
  local out = {}
  for _, x in ipairs(todo) do out[#out + 1] = x.kind .. x.e.id end
  return table.concat(out, ",")
end
local function todo(force)
  if force or not cache or GetTime() - cacheAt > 5 then
    cache, cacheAt = ns.gameCalTodo(), GetTime()
  end
  return cache
end
local function recheck()
  local was = cacheSig
  cacheSig = signature(todo(true))
  return cacheSig ~= was
end

local function description(e)
  local parts = {}
  if e.title and e.instance and e.title ~= e.instance then parts[#parts + 1] = e.instance end
  if e.notes and e.notes ~= "" then parts[#parts + 1] = e.notes end
  local link = "Sign up: " .. ns.SITE .. "/raids/" .. e.id
  local text = table.concat(parts, "\n\n")
  return clip(text, DESC_MAX - #link - 2) .. (text ~= "" and "\n\n" or "") .. link
end

-- The calendar's picture for this raid when Blizzard has one (Raid type), else a plain "Other" event.
local function setTypeAndTexture(instance)
  local raid = Enum and Enum.CalendarEventType and Enum.CalendarEventType.Raid
  local other = Enum and Enum.CalendarEventType and Enum.CalendarEventType.Other
  if raid and C_Calendar.EventGetTextures then
    local ok, textures = pcall(C_Calendar.EventGetTextures, raid)
    for i, tex in ipairs(ok and textures or {}) do
      if tex.title == instance then
        C_Calendar.EventSetType(raid)
        C_Calendar.EventSetTextureID(i)
        return
      end
    end
  end
  if other then C_Calendar.EventSetType(other) end
end

-- One step, from a click.
function ns.gameCalStep()
  if busy or not api() then return end
  if C_Calendar.IsActionPending and C_Calendar.IsActionPending() then return end
  local item = todo(true)[1]
  if not item then return end
  lastError = nil
  local ok, err = pcall(function()
    if item.kind == "remove" then
      keepingMonth(function()
        local i = findOnDay(item.title, item.d)
        if not i then return end
        C_Calendar.ContextMenuSelectEvent(0, item.d.day, i)
        if C_Calendar.ContextMenuEventCanRemove(0, item.d.day, i) then
          busy = true
          C_Calendar.ContextMenuEventRemove()
          store()[item.e.id] = nil
        else
          lastError = "You can't remove \"" .. item.title .. "\" (made by someone else). Ask them or the Guild Master."
        end
      end)
    else
      local d, e = item.d, item.e
      C_Calendar.CloseEvent()
      C_Calendar.CreateGuildSignUpEvent()
      C_Calendar.EventSetTitle(item.title)
      C_Calendar.EventSetDescription(description(e))
      setTypeAndTexture(e.instance)
      C_Calendar.EventSetDate(d.month, d.day, d.year)
      C_Calendar.EventSetTime(d.hour, d.min)
      busy = true
      C_Calendar.AddEvent()
      store()[e.id] = { title = item.title, t = tonumber(e.t) }
    end
  end)
  if not ok then busy = false; lastError = internalError(err) end
  if busy then C_Timer.After(10, function() if busy then busy = false; recheck(); ns.refreshUI() end end) end -- no answer: let them try again
  recheck()
  ns.refreshUI()
end

-- For the Calendar tab's bar: nil when there's nothing to show.
function ns.gameCalStatus()
  if not api() or ns.locked() or not ns.isOfficer(ns.selfName) then return nil end
  if not loaded then return { text = "Reading the guild calendar…" } end
  local list = todo()
  if lastError then return { text = "Guild calendar: " .. lastError, todo = #list, button = #list > 0 and "Try again" or nil, error = true } end
  if busy then return { text = "Updating the guild calendar…", todo = #list } end
  if #list == 0 then return nil end
  local adds, removes = 0, 0
  for _, x in ipairs(list) do if x.kind == "add" then adds = adds + 1 else removes = removes + 1 end end
  local bits = {}
  if adds > 0 then bits[#bits + 1] = adds == 1 and "1 raid isn't on the guild calendar" or (adds .. " raids aren't on the guild calendar") end
  if removes > 0 then bits[#bits + 1] = removes == 1 and "1 old event to take off" or (removes .. " old events to take off") end
  local first = list[1]
  return {
    text = table.concat(bits, "  ·  "), todo = #list,
    button = first.kind == "add" and "Add" or "Remove",
    next = (first.kind == "add" and "Next: " or "Take off: ") .. first.title .. date(", %a %b %d %H:%M", first.e.t),
  }
end

-- ---------- events ----------

local pendingCheck = false
local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_NEW_EVENT", "CALENDAR_UPDATE_ERROR",
  "CALENDAR_UPDATE_ERROR_WITH_COUNT", "CALENDAR_UPDATE_ERROR_WITH_PLAYER_NAME" }) do
  pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event, ...)
  if not api() then return end
  if event == "PLAYER_LOGIN" then
    -- Ask the server for the calendar a little after login; the list arrives as CALENDAR_UPDATE_EVENT_LIST.
    C_Timer.After(12, function() pcall(C_Calendar.OpenCalendar) end)
  elseif event == "CALENDAR_UPDATE_EVENT_LIST" or event == "CALENDAR_NEW_EVENT" then
    -- Our own month switches echo back as updates: ignore those, and look again a moment later, once, for the rest.
    if scanning or (event == "CALENDAR_UPDATE_EVENT_LIST" and loaded and not busy and GetTime() - scannedAt < 1) then return end
    local first = not loaded
    local wasBusy = busy
    loaded, busy = true, false
    if pendingCheck then return end
    pendingCheck = true
    C_Timer.After(0.5, function()
      pendingCheck = false
      if recheck() or first or wasBusy then ns.refreshUI() end
    end)
  elseif event:find("^CALENDAR_UPDATE_ERROR") then
    local message, extra = ...
    local text = message and _G[message] or tostring(message)
    if extra and type(text) == "string" and text:find("%%") then text = text:format(extra) end
    -- Errors from Blizzard's own calendar window aren't ours to show.
    if busy then lastError = text; busy = false; ns.refreshUI() end
  end
end)

-- Raid calendar in game. The site is the source: an officer's Perpetua app writes it into SiteData.lua (loaded at
-- login and /reload), and the addon passes it around the guild as part "C" of guild sync. Only a calendar sent
-- by an officer (by guild rank) is accepted, so nobody can post fake raids.
--
-- Signing up in game stores the choice on this character (PerpetuaCharDB.signups) and sends it with the
-- character's profile; guild sync takes it to the site, where a newer sign-up made on the site wins.
local _, ns = ...

-- ---------- officers ----------

local rankCache, rankCacheAt = {}, 0

local function refreshRanks()
  wipe(rankCache)
  for i = 1, (ns.try(GetNumGuildMembers) or 0) do
    local full, rankName, rankIndex = ns.try(GetGuildRosterInfo, i)
    local key = ns.playerKey(ns.readable(full))
    if key then rankCache[key] = { index = ns.num(rankIndex), name = ns.text(rankName) } end
  end
  rankCacheAt = GetTime()
end

-- Guild Master and the rank below it, or a rank with "officer" in its name ("Officer", "Sr. Officer"). Not just any
-- name with "leader" or "master" in it: "Raid Leader", "Quartermaster" and "Loot Master" aren't officers.
function ns.isOfficer(name)
  if GetTime() - rankCacheAt > 60 then refreshRanks() end
  local r = rankCache[name]
  if not r then
    ns.try(C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster) -- ask for the roster; next time it'll be there
    return false
  end
  if r.index and r.index <= 1 then return true end
  local n = (r.name or ""):lower()
  return n:find("officer") ~= nil
end

-- ---------- the calendar ----------

local function store()
  local g = PerpetuaDB.guilds and PerpetuaDB.guilds[ns.guildName() or "No guild"]
  if not g then ns.players(); g = PerpetuaDB.guilds[ns.guildName() or "No guild"] end
  return g
end

-- { t = when the site made it, events = { { id, title, instance, t, dur, size, notes, cancelled, signups = {...} } } }
function ns.calendar()
  return store().calendar
end

-- Raids in the next week that aren't cancelled (the count on the Calendar button).
function ns.upcomingRaids()
  local c, now, n = ns.calendar(), ns.now(), 0
  for _, e in ipairs(c and c.events or {}) do
    local t = tonumber(e.t)
    if t and not e.cancelled and t > now - 3600 and t < now + 7 * 86400 then n = n + 1 end
  end
  return n
end

function ns.calendarVersion()
  local c = ns.calendar()
  return c and c.t and tostring(c.t) or nil
end

local function valid(cal)
  return type(cal) == "table" and tonumber(cal.t) and type(cal.events) == "table"
end

-- A calendar from SiteData.lua (this computer runs the Perpetua app) or from an officer in the guild.
function ns.adoptCalendar(cal)
  if not valid(cal) then return false end
  -- Not before the guild's name is known (it'd be filed under "No guild"), and not one stamped in the future:
  -- a bad clock would make it "newer" than every real calendar after it.
  if not ns.guildName() or cal.t > ns.now() + 86400 then return false end
  local cur = ns.calendar()
  if cur and (cur.t or 0) >= cal.t then return false end
  store().calendar = cal
  -- Raids this officer made in game that the site has now made: stop sending them.
  if ns.prunePendingRaids() then ns.scheduleRefresh(2) end
  ns.fire()
  return true
end

function ns.loadSiteCalendar()
  if PerpetuaSiteData and ns.adoptCalendar(PerpetuaSiteData) then ns.announce() end
end

-- ---------- sign-ups ----------

local STATUSES = { coming = true, tentative = true, absent = true }

-- roles: { [role] = true } for every role ticked; prefer: the spec's role, the main one when it's ticked.
-- Saved as r = main role (what older sites read) and rs = all of them ("Tank,Off Tank").
function ns.signUp(eventId, status, roles, prefer)
  if not STATUSES[status] then return end
  local class = select(2, UnitClass("player"))
  local list, main = ns.orderRoles(class, roles or {}, prefer)
  if not main then main = ns.classRoles(class)[1]; list = { main } end
  PerpetuaCharDB.signups = PerpetuaCharDB.signups or {}
  PerpetuaCharDB.signups[eventId] = { s = status, r = main, rs = table.concat(list, ","), t = ns.now() }
  ns.refreshSelf()
end

-- This character's sign-ups for raids that haven't finished, for its profile.
function ns.mySignups()
  local out, cal = {}, ns.calendar()
  local ends = {}
  for _, e in ipairs(cal and cal.events or {}) do ends[e.id] = (e.t or 0) + (e.dur or 180) * 60 end
  for id, s in pairs(PerpetuaCharDB.signups or {}) do
    local finish = ends[tonumber(id)]
    if finish and finish < ns.now() then PerpetuaCharDB.signups[id] = nil
    elseif not finish and ns.now() - (s.t or 0) > 30 * 86400 then PerpetuaCharDB.signups[id] = nil
    else out[#out + 1] = { e = tonumber(id), s = s.s, r = s.r, rs = s.rs, t = s.t } end
  end
  table.sort(out, function(a, b) return a.e < b.e end)
  return out
end

-- Who's coming to an event: the site's list, updated with sign-ups made in game since the calendar was made
-- (from guildmates' profiles, and this character's own).
function ns.eventSignups(e)
  local cal = ns.calendar()
  local byName = {}
  for _, s in ipairs(e.signups or {}) do byName[s.n] = { n = s.n, c = s.c, s = s.s, r = s.r, rs = s.rs, l = s.l } end
  for name, rec in pairs(ns.players()) do
    local p = type(rec) == "table" and rec.profile
    for _, s in ipairs(p and p.signups or {}) do
      if s.e == e.id and (s.t or 0) > (cal and cal.t or 0) then
        local cur = byName[name] or { n = name, c = rec.class }
        cur.s, cur.r, cur.rs, cur.game = s.s, s.r, s.rs, true
        byName[name] = cur
      end
    end
  end
  local mine = PerpetuaCharDB.signups and PerpetuaCharDB.signups[e.id]
  if mine and ns.selfName and (mine.t or 0) > (cal and cal.t or 0) then
    local cur = byName[ns.selfName] or { n = ns.selfName, c = select(2, UnitClass("player")) }
    cur.s, cur.r, cur.rs, cur.game = mine.s, mine.r, mine.rs, true
    byName[ns.selfName] = cur
  end
  local list = {}
  for _, s in pairs(byName) do list[#list + 1] = s end
  table.sort(list, function(a, b) return a.n < b.n end)
  return list
end

-- ---------- raids made in game ----------
-- An officer's new raid waits in PerpetuaCharDB.raids and rides along with this character's profile, so guild
-- sync carries it to whoever runs the Perpetua app; the site makes the raid (and its Discord event) from it
-- (worker/raids.js applyAddonRaids). Once the site's calendar comes back with the raid's key, the wait is over.
-- The site only accepts it if this character's owner is also an officer on Discord.

-- { k, title, instance, t, dur, size, notes, w (weeks), made }
function ns.pendingRaids()
  PerpetuaCharDB.raids = PerpetuaCharDB.raids or {}
  return PerpetuaCharDB.raids
end

-- Drops raids the site has made (its calendar carries their key) and ones whose start has passed.
function ns.prunePendingRaids()
  local list, cal = ns.pendingRaids(), ns.calendar()
  local made = {}
  for _, e in ipairs(cal and cal.events or {}) do if e.gk then made[e.gk] = true end end
  local changed = false
  for i = #list, 1, -1 do
    local r = list[i]
    if made[(ns.selfName or "") .. ":" .. r.k] or (r.t or 0) < ns.now() - 3600 then table.remove(list, i); changed = true end
  end
  return changed
end

-- The part of the profile the site reads.
function ns.raidsForProfile()
  ns.prunePendingRaids()
  local out = {}
  for _, r in ipairs(ns.pendingRaids()) do
    out[#out + 1] = { k = r.k, title = r.title, instance = r.instance, t = r.t, dur = r.dur, size = r.size, notes = r.notes, w = r.w }
  end
  return out
end

function ns.createRaid(r)
  if not ns.isOfficer(ns.selfName) then return false, "Only officers can schedule raids." end
  if not (r.t and r.t > ns.now()) then return false, "Pick a time in the future." end
  local list = ns.pendingRaids()
  if #list >= 10 then return false, "Ten raids are already waiting for the site. Sync first." end
  r.k = tostring(ns.now()) .. "-" .. math.random(1000, 9999)
  r.made = ns.now()
  list[#list + 1] = r
  ns.refreshSelf()
  return true
end

function ns.cancelPendingRaid(k)
  local list = ns.pendingRaids()
  for i = #list, 1, -1 do if list[i].k == k then table.remove(list, i) end end
  ns.refreshSelf()
end

-- Hit list: the enemy players this character killed and the ones who killed it, world PvP and battlegrounds kept
-- apart. Shown on the Character page and on the site's character page.
--
-- Forever closes the combat log to addons (COMBAT_LOG_EVENT_UNFILTERED has no payload), so this works the way the
-- Forever port of Spy does, which counted kills and deaths fine on the live client:
--   * a kill is PARTY_KILL with us (or our pet) as the attacker: killing blows only, by the owner's choice;
--   * a death is PLAYER_DEAD, the killer read from the death recap (C_DeathRecap) a moment later, or, when the
--     recap can't say, the one enemy player who had us targeted when we fell (two or more: nobody gets it).
-- Names come from the units we've seen (nameplates, target, mouseover), because GetPlayerInfoByGUID doesn't give
-- the surname. Any value can be secret; ns.readable turns those into nil.
--
-- Saved per character (PerpetuaCharDB.hits). What goes in the profile is the top five of each list and the totals.
-- A kill doesn't re-send the profile on the spot: the hit list is left out of the profile's fingerprint, and a
-- stamp (hv) that moves at most every 15 minutes, never inside a battleground, makes guild sync pick it up.
local _, ns = ...
local readable, text, num, try = ns.readable, ns.text, ns.num, ns.try

local TOP = 5                 -- per list, in the profile
local KEEP = 200              -- names kept per list; the least-hit, oldest go first
local FLUSH_EVERY = 15 * 60   -- seconds between hit-list re-sends
local RECAP_DELAYS = { 0.5, 2 } -- the death recap is filled in shortly after PLAYER_DEAD
local SEEN_LIMIT = 1000

local function db()
  local h = PerpetuaCharDB.hits
  if type(h) ~= "table" or h.v ~= 1 then h = { v = 1 }; PerpetuaCharDB.hits = h end
  for _, mode in ipairs({ "world", "bg" }) do
    h[mode] = h[mode] or { k = {}, d = {}, nk = 0, nd = 0 }
  end
  return h
end

-- world / bg, or nil where we don't count (dungeons, raids: no enemy players there, and mind control would confuse it).
local function mode()
  local _, kind = try(IsInInstance)
  kind = readable(kind)
  if kind == "pvp" or kind == "arena" then return "bg" end
  if kind == nil or kind == "none" then return "world" end
end

-- ---------- who's who ----------

local seen, seenCount = {}, 0 -- GUID -> { n = full name, c = class, l = level, g = guild, f = faction }

local function remember(unit)
  if not readable(UnitExists(unit)) or not readable(UnitIsPlayer(unit)) then return end
  if not readable(try(UnitIsEnemy, "player", unit)) then return end
  local guid = text(UnitGUID(unit))
  if not guid then return end
  local first, surname = UnitName(unit)
  first = text(first)
  if not first then return end
  local guild = text(try(GetGuildInfo, unit))
  local old = seen[guid]
  if not old then
    if seenCount >= SEEN_LIMIT then seen, seenCount = {}, 0 end
    seenCount = seenCount + 1
  end
  local _, classFile = try(UnitClass, unit)
  local level = num(try(UnitLevel, unit))
  seen[guid] = {
    n = ns.fullName(first, ns.FOREVER and text(surname) or nil),
    c = text(classFile), l = level and level > 0 and level or (old and old.l) or nil,
    g = guild or (old and old.g), f = text(try(UnitFactionGroup, unit)),
  }
end

-- What we know about a player GUID, or nil for anything that isn't an enemy player.
local function whoIs(guid)
  guid = text(guid)
  if not guid or not guid:find("^Player%-") then return nil end
  if seen[guid] then return seen[guid] end
  local _, classFile, _, _, _, name = try(GetPlayerInfoByGUID, guid)
  name = text(name)
  if not name then return nil end
  return { n = name, c = text(classFile) }
end

local function isMine(guid)
  return guid == text(UnitGUID("player")) or guid == text(UnitGUID("pet"))
end

-- ---------- recording ----------

local function prune(list)
  local count, worst, worstKey = 0, nil, nil
  for key, r in pairs(list) do
    count = count + 1
    if not worst or r.x < worst.x or (r.x == worst.x and (r.t or 0) < (worst.t or 0)) then worst, worstKey = r, key end
  end
  if count > KEEP and worstKey then list[worstKey] = nil end
end

local flushTry -- below

local function record(kind, who, where)
  local h = db()
  local bucket = h[where]
  if kind == "k" then bucket.nk = bucket.nk + 1 else bucket.nd = bucket.nd + 1 end
  if who and who.n then
    local list = bucket[kind]
    local r = list[who.n]
    -- Seen by first name only before (GetPlayerInfoByGUID), and now with the surname: fold the old entry in.
    local first = who.n:match("^(%S+) ")
    if not r and first and list[first] and (not who.c or list[first].c == who.c) then
      r = list[first]; list[first] = nil
    end
    r = r or { x = 0 }
    list[who.n] = r
    r.x, r.t = r.x + 1, ns.now()
    r.c, r.l, r.g = who.c or r.c, who.l or r.l, who.g or r.g
    prune(list)
  end
  h.dirty = true
  ns.lastHit = { kind = kind, name = who and who.n, where = where, at = ns.now() } -- for /ppta hits
  flushTry()
  ns.refreshUI()
end

local function onPartyKill(attacker, victim)
  attacker, victim = text(attacker), text(victim)
  local where = mode()
  if not (attacker and victim and where) or not isMine(attacker) then return end
  local who = whoIs(victim)
  if not who then return end
  -- Someone on our own side (a duel can't kill, but mind control and the like can): not a hit.
  local mine = text(try(UnitFactionGroup, "player"))
  if who.f and mine and who.f == mine then return end
  record("k", who, where)
end

-- ---------- deaths ----------

local lastRecapID

local function recapID()
  local link = text(try(C_DeathRecap and C_DeathRecap.GetRecapLink))
  return link and tonumber(link:match("death:(%d+)"))
end

-- The killing blow of the latest death recap: who, or nil and why not.
local function killerFromRecap()
  if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil, "unavailable" end
  local id = recapID()
  if id and id == lastRecapID then return nil, "stale" end
  lastRecapID = id -- this recap belongs to this death now, read or not
  local events = try(C_DeathRecap.GetRecapEvents)
  if type(events) ~= "table" or (issecrettable and issecrettable(events)) then return nil, "unreadable" end
  local e = events[1]
  if type(e) ~= "table" or (issecrettable and issecrettable(e)) then return nil, "empty" end
  local stamp = num(e.timestamp)
  if stamp and stamp > 1e9 and math.abs(time() - stamp) > 60 then return nil, "stale" end
  if readable(e.hideCaster) then return nil, "hidden" end
  local guid = text(e.sourceGUID)
  if not (guid and guid:find("^Player%-")) then return nil, "no player" end -- a creature, a fall, a pet
  local who = whoIs(guid)
  if who and not who.f then
    local name = text(e.sourceName)
    if name and not who.n then who.n = name end
  end
  if not (who and who.n) then return nil, "no name" end
  if who.f and who.f == text(try(UnitFactionGroup, "player")) then return nil, "own side" end
  return who, "recap"
end

local UNKNOWN = { unavailable = true, unreadable = true, empty = true, stale = true, hidden = true }

-- The enemy players who have us targeted right now (taken at the moment of death).
local function suspects()
  local out, found = {}, {}
  local units = { "target", "focus", "mouseover" }
  for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
  for _, unit in ipairs(units) do
    if readable(UnitExists(unit)) and readable(UnitIsPlayer(unit)) and readable(try(UnitIsEnemy, "player", unit))
      and readable(try(UnitIsUnit, unit .. "target", "player")) then
      remember(unit)
      local guid = text(UnitGUID(unit))
      if guid and seen[guid] and not found[guid] then found[guid] = true; out[#out + 1] = seen[guid] end
    end
  end
  return out
end

local function resolveDeath(where, targeting, attempt)
  local who, why = killerFromRecap()
  if not who and why == "stale" and attempt < #RECAP_DELAYS then
    C_Timer.After(RECAP_DELAYS[attempt + 1] - RECAP_DELAYS[attempt], function() pcall(resolveDeath, where, targeting, attempt + 1) end)
    return
  end
  if not who and UNKNOWN[why] and #targeting == 1 then who, why = targeting[1], "targeting" end
  ns.lastDeath = { why = why, name = who and who.n, at = ns.now() }
  if who then record("d", who, where) end -- a death nobody gets (a mob, a fall) isn't a PvP death
end

local function onDead()
  local where = mode()
  if not where then return end
  local targeting = suspects()
  C_Timer.After(RECAP_DELAYS[1], function() pcall(resolveDeath, where, targeting, 1) end)
end

-- ---------- for the profile ----------

local function top(list)
  local rows = {}
  for name, r in pairs(list) do rows[#rows + 1] = { n = name, x = r.x, c = r.c, l = r.l, g = r.g, t = r.t } end
  table.sort(rows, function(a, b)
    if a.x ~= b.x then return a.x > b.x end
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
    return a.n < b.n
  end)
  while #rows > TOP do table.remove(rows) end
  return rows
end

-- { w = { k, d, nk, nd }, b = { ... } }, or nil before the first kill or death.
function ns.hitsForProfile()
  local h = PerpetuaCharDB and PerpetuaCharDB.hits
  if type(h) ~= "table" or h.v ~= 1 then return nil end
  local out
  for where, key in pairs({ world = "w", bg = "b" }) do
    local m = h[where]
    if m and (m.nk > 0 or m.nd > 0) then
      out = out or {}
      out[key] = { k = top(m.k), d = top(m.d), nk = m.nk, nd = m.nd }
    end
  end
  return out
end

-- The stamp that goes in the profile's fingerprint.
function ns.hitsVersion()
  local h = PerpetuaCharDB and PerpetuaCharDB.hits
  return type(h) == "table" and h.flushed or nil
end

-- New hits go out with the next profile send once 15 minutes have passed since the last time, outside battlegrounds
-- (every kill there would have the guild asking for the profile mid-fight).
function flushTry()
  local h = PerpetuaCharDB and PerpetuaCharDB.hits
  if type(h) ~= "table" or not h.dirty or mode() == "bg" then return end
  if h.flushed and ns.now() - h.flushed < FLUSH_EVERY then return end
  h.flushed, h.dirty = ns.now(), nil
  if ns.scheduleRefresh then ns.scheduleRefresh(10) end
end

-- ---------- events ----------

local frame = CreateFrame("Frame")
for _, e in ipairs({ "PARTY_KILL", "PLAYER_DEAD", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
  "PLAYER_FOCUS_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
  pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function(_, event, a, b)
  if ns.locked and ns.locked() then return end
  if event == "PARTY_KILL" then pcall(onPartyKill, a, b)
  elseif event == "PLAYER_DEAD" then pcall(onDead)
  elseif event == "NAME_PLATE_UNIT_ADDED" then pcall(remember, a)
  elseif event == "PLAYER_TARGET_CHANGED" then pcall(remember, "target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then pcall(remember, "mouseover")
  elseif event == "PLAYER_FOCUS_CHANGED" then pcall(remember, "focus")
  else
    -- Leaving a battleground (or logging in with hits waiting): send what's new. A recap left over from before a
    -- /reload belongs to an earlier death.
    if event == "PLAYER_ENTERING_WORLD" and lastRecapID == nil then lastRecapID = recapID() or false end
    C_Timer.After(5, function() pcall(flushTry) end)
  end
end)
C_Timer.NewTicker(300, function() pcall(flushTry) end)

ns.hitsForTest = { onPartyKill = onPartyKill, onDead = onDead, remember = remember, seen = function() return seen end,
  resolveDeath = resolveDeath, flush = function() return flushTry() end }

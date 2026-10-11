-- Loot and /roll history. In a raid, the addon notes every epic (or better) drop from the loot messages and
-- every /roll from the system messages, and tells the guild (addon messages "L" and "R"), so the history fills
-- in even when no officer is in the raid. The Perpetua app uploads it to the site, which drops duplicates:
-- several raiders' addons report the same drop.
local _, ns = ...
local MIN_QUALITY = 4 -- epic
local KEEP_LOOT, KEEP_ROLLS = 1500, 3000
-- Rolls only matter in the couple of minutes before a drop, and the Perpetua app uploads both to the site, so old
-- ones are dropped (once a session) instead of filling everyone's saved variables.
local LOOT_DAYS, ROLL_DAYS = 60, 14

-- Blizzard's message formats ("%s receives loot: %s.") as Lua patterns with captures.
local function pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  fmt = fmt:gsub("%%%d%$", "%%") -- positional forms (%1$s) in some locales
  local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. p .. "$"
end

local LOOT_OTHER = { pattern(LOOT_ITEM_MULTIPLE), pattern(LOOT_ITEM) }
local LOOT_SELF = { pattern(LOOT_ITEM_SELF_MULTIPLE), pattern(LOOT_ITEM_SELF), pattern(LOOT_ITEM_PUSHED_SELF) }
local ROLL = pattern(RANDOM_ROLL_RESULT)
local QUALITY_BY_COLOR = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6 }

local pruned = {}
local function prune(list, days)
  local cutoff, keep = ns.now() - days * 86400, {}
  for _, e in ipairs(list) do if (e.t or 0) >= cutoff then keep[#keep + 1] = e end end
  return keep
end

local function store()
  local g = PerpetuaDB.guilds and PerpetuaDB.guilds[ns.guildName() or "No guild"]
  if not g then ns.players(); g = PerpetuaDB.guilds[ns.guildName() or "No guild"] end
  g.loot, g.rolls = g.loot or {}, g.rolls or {}
  if not pruned[g] then
    pruned[g] = true
    g.loot, g.rolls = prune(g.loot, LOOT_DAYS), prune(g.rolls, ROLL_DAYS)
  end
  return g
end

function ns.lootLog() return store().loot end
function ns.rollLog() return store().rolls end

-- Raid members' names as they appear in chat, mapped to the addon's full names ("First Surname").
local function nameMap()
  local map = {}
  for i = 1, (ns.try(GetNumGroupMembers) or 0) do
    local unit = (ns.try(IsInRaid) and "raid" or "party") .. i
    local first, second = ns.try(UnitName, unit)
    first, second = ns.readable(first), ns.readable(second)
    if type(first) == "string" then
      local full = ns.fullName(first, ns.FOREVER and type(second) == "string" and second ~= "" and second or nil)
      map[first] = full
      map[full] = full
      if type(second) == "string" then map[first .. "-" .. second] = full end
    end
  end
  return map
end

-- Rolls come in bursts: the map is reused for a few seconds rather than rebuilt for every one.
local map, mapAt = nil, 0
local function resolve(name)
  if not name then return nil end
  if not map or GetTime() - mapAt > 5 then map, mapAt = nameMap(), GetTime() end
  return map[name] or ns.playerKey(name)
end

-- Adds an entry unless it's already there (another raider reported the same thing a moment apart).
local function addLoot(e)
  local list = store().loot
  for i = #list, math.max(1, #list - 60), -1 do
    local x = list[i]
    if x.n == e.n and x.it == e.it and math.abs((x.t or 0) - e.t) <= 120 then return false end
  end
  list[#list + 1] = e
  while #list > KEEP_LOOT do table.remove(list, 1) end
  return true
end

local function addRoll(e)
  local list = store().rolls
  for i = #list, math.max(1, #list - 80), -1 do
    local x = list[i]
    if x.n == e.n and x.r == e.r and x.lo == e.lo and x.hi == e.hi and math.abs((x.t or 0) - e.t) <= 15 then return false end
  end
  list[#list + 1] = e
  while #list > KEEP_ROLLS do table.remove(list, 1) end
  return true
end

local function inRaid()
  local _, kind = ns.try(IsInInstance)
  return ns.try(IsInRaid) or kind == "raid"
end

local function zone()
  return ns.text(ns.try(GetInstanceInfo)) or ns.text(ns.try(GetRealZoneText))
end

function ns.onLootChat(msg)
  msg = ns.readable(msg)
  if type(msg) ~= "string" or not inRaid() then return end
  local who, link
  for _, p in ipairs(LOOT_SELF) do
    link = msg:match(p)
    if link then who = ns.selfName break end
  end
  if not link then
    for _, p in ipairs(LOOT_OTHER) do
      who, link = msg:match(p)
      if link then who = resolve(who) break end
    end
  end
  local id = ns.itemIdFrom(link)
  if not (who and id) then return end
  local quality = ns.num(select(3, ns.try(C_Item and C_Item.GetItemInfo or GetItemInfo, link)))
    or QUALITY_BY_COLOR[(link:match("|cff(%x%x%x%x%x%x)") or ""):lower()]
  if (quality or 0) < MIN_QUALITY then return end
  local e = { n = who, it = id, name = link:match("%[(.-)%]"), q = quality, z = zone(), t = ns.now(), by = ns.selfName }
  if addLoot(e) then
    ns.sendLine({ "L", e.t, e.n, e.it, e.q, e.name or "", e.z or "" })
    ns.fire()
  end
end

function ns.onSystemChat(msg)
  msg = ns.readable(msg)
  if type(msg) ~= "string" or not ROLL or not ns.try(IsInGroup) then return end
  local who, roll, lo, hi = msg:match(ROLL)
  roll, lo, hi = tonumber(roll), tonumber(lo), tonumber(hi)
  if not (who and roll and lo and hi) then return end
  local e = { n = resolve(who), r = roll, lo = lo, hi = hi, t = ns.now() }
  if e.n and addRoll(e) then
    ns.sendLine({ "R", e.t, e.n, e.r, e.lo, e.hi })
    ns.fire()
  end
end

-- From a guildmate: "L", t, winner, item, quality, name, zone / "R", t, roller, roll, low, high.
function ns.onLootMessage(f, from)
  local t = tonumber(f[2])
  if not t or math.abs(t - ns.now()) > 6 * 3600 then return end
  if f[1] == "L" then
    local id, q = tonumber(f[4]), tonumber(f[5])
    if not (f[3] and id and q and q >= MIN_QUALITY) then return end
    if addLoot({ n = f[3], it = id, q = q, name = f[6] ~= "" and f[6] or nil, z = f[7] ~= "" and f[7] or nil, t = t, by = from }) then ns.fire() end
  elseif f[1] == "R" then
    local r, lo, hi = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
    if not (f[3] and r and lo and hi) then return end
    if addRoll({ n = f[3], r = r, lo = lo, hi = hi, t = t }) then ns.fire() end
  end
end

-- The rolls by time, made again only when the list changes (the Loot page asks once per drop shown: up to 300
-- drops against up to 3000 rolls). Guildmates' rolls can arrive a little out of order, hence the sort.
local byTime, byTimeFor, byTimeN, byTimeLast = {}, nil, -1, nil
local function rollsByTime()
  local list = store().rolls
  local lastRoll = list[#list]
  if list ~= byTimeFor or #list ~= byTimeN or lastRoll ~= byTimeLast then
    byTime = {}
    for i, r in ipairs(list) do byTime[i] = r end
    table.sort(byTime, function(a, b) return (a.t or 0) < (b.t or 0) end)
    byTimeFor, byTimeN, byTimeLast = list, #list, lastRoll
  end
  return byTime
end

-- The /rolls in the couple of minutes before a drop, highest first.
function ns.rollsFor(e)
  local list, from = rollsByTime(), e.t - 150
  -- First roll at or after from (binary search), then forward while still in the window.
  local lo, hi = 1, #list + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if (list[mid].t or 0) < from then lo = mid + 1 else hi = mid end
  end
  local out = {}
  for i = lo, #list do
    local r = list[i]
    if (r.t or 0) > e.t + 5 then break end
    out[#out + 1] = r
  end
  table.sort(out, function(a, b) return a.r > b.r end)
  return out
end

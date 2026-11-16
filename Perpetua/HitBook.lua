-- The hit book: every guildmate's hit list (PvP.lua), passed along by everyone, not just by its owner.
--
-- Profiles travel only from their owner to whoever is online at the same time, so a member who never overlapped
-- with an officer never reached the site, and every guildmate's Hit List showed a different set of people and
-- counts. Hit lists are small, so the whole book goes round: each hello carries a digest of the book, anyone whose
-- book differs asks for it (part B), and everyone merges what arrives. Within a few exchanges everyone online holds
-- the same book, and the sync apps upload it all, so one member's kills reach the site through any chain of
-- guildmates.
--
-- Each entry is { hv, h, c }: the owner's flush stamp (PvP.lua's hv: it moves only when the owner sends new hits),
-- the hit list as of that stamp, and the class. An entry replaces another when its stamp is newer, or the same with
-- more kills and deaths (2.20 sent its live list under an unchanged stamp; counts only grow). Your own entry is only
-- ever written by you. Unlike a profile, a passed-along entry can't be checked against who sent it; the rules above
-- (no stamps from the future, counts never go down for a stamp) keep a bad copy from undoing a good one.
local _, ns = ...
local num, text = ns.num, ns.text

local KEEP = 300               -- entries; the oldest stamps go first
local MAX_AGE = 180 * 86400    -- an entry nobody has refreshed in half a year is dropped
local FUTURE = 600             -- seconds a stamp may be ahead of our clock

local function book()
  local guild = ns.guildName()
  if not guild then return nil end
  ns.players(guild) -- makes the guild's table
  local g = PerpetuaDB.guilds[guild]
  g.hitbook = type(g.hitbook) == "table" and g.hitbook or {}
  return g.hitbook
end

local function total(h)
  local n = 0
  for _, k in ipairs({ "w", "du" }) do
    local m = type(h) == "table" and h[k]
    if type(m) == "table" then n = n + (num(m.nk) or 0) + (num(m.nd) or 0) end
  end
  return n
end
ns.hitTotal = total

local digestCache -- recomputed when the book changes

-- Puts one entry in, if it's better than what's there. Returns whether the book changed.
local function put(b, name, hv, h, class, own)
  name, hv = text(name), num(hv)
  if not (name and hv and hv > 1e9 and hv <= ns.now() + FUTURE) then return false end
  if name == ns.selfName and not own then return false end
  h = ns.hitsSummary(h)
  if not h then return false end
  local old = b[name]
  if old and (old.hv > hv or (old.hv == hv and total(old.h) >= total(h))) then return false end
  b[name] = { hv = hv, h = h, c = text(class) and text(class):sub(1, 16) or (old and old.c) }
  digestCache = nil
  return true
end

local function prune(b)
  local rows, cutoff = {}, ns.now() - MAX_AGE
  for name, e in pairs(b) do
    if type(e) ~= "table" or not num(e.hv) or e.hv < cutoff then b[name] = nil; digestCache = nil
    else rows[#rows + 1] = { name, e.hv } end
  end
  if #rows <= KEEP then return end
  table.sort(rows, function(x, y) return x[2] > y[2] end)
  for i = KEEP + 1, #rows do b[rows[i][1]] = nil end
  digestCache = nil
end

-- A guildmate's profile arrived (Comm.lua accept): its hit list goes in the book too.
function ns.hitbookFromProfile(name, profile)
  local b = book()
  if not (b and type(profile) == "table") then return end
  local c = type(profile.char) == "table" and profile.char.classFile or nil
  if put(b, name, profile.hv, profile.hits, c) then ns.hitbookChanged() end
end

-- Your own entry, from the snapshot of the last flush (PvP.lua). Called on every refresh.
function ns.hitbookOwn()
  local b = book()
  if not (b and ns.selfName) then return end
  local hv, h = ns.hitsVersion and ns.hitsVersion(), ns.hitsForSend and ns.hitsForSend()
  if not (hv and h) then return end
  local _, classFile = ns.try(UnitClass, "player")
  local old = b[ns.selfName]
  if old and old.hv == hv and total(old.h) == total(h) then return end
  if put(b, ns.selfName, hv, h, classFile, true) then ns.hitbookChanged() end
end

-- "-" for an empty book, else a hash of every name, stamp and total: two books with the same digest hold the same
-- entries.
function ns.hitbookDigest()
  local b = book()
  if not b then return "-" end
  if digestCache and digestCache.b == b then return digestCache.d end
  local rows = {}
  for name, e in pairs(b) do rows[#rows + 1] = name .. ":" .. e.hv .. ":" .. total(e.h) end
  table.sort(rows)
  local d = #rows > 0 and ns.hash(table.concat(rows, "|")) or "-"
  digestCache = { b = b, d = d }
  return d
end

-- What part B sends.
function ns.hitbookPayload()
  local b = book()
  if not b then return nil end
  prune(b)
  local out = {}
  for name, e in pairs(b) do out[name] = { hv = e.hv, h = e.h, c = e.c } end
  return { t = ns.now(), e = out }
end

-- A book from a guildmate (part B): take every entry that's better than ours.
function ns.hitbookMerge(data)
  local b = book()
  if not (b and type(data) == "table" and type(data.e) == "table") then return end
  local changed, n = false, 0
  for name, e in pairs(data.e) do
    n = n + 1
    if n > KEEP * 2 then break end
    if type(e) == "table" and put(b, name, e.hv, e.h, e.c) then changed = true end
  end
  if changed then prune(b); ns.hitbookChanged() end
end

-- After a change, say so (once, a little later) so guildmates whose book is behind ask for it.
local announceTimer
function ns.hitbookChanged()
  ns.refreshUI()
  if announceTimer then return end
  announceTimer = C_Timer.NewTimer(20 + math.random() * 20, function()
    announceTimer = nil
    if ns.announce then ns.announce() end
  end)
end

-- A guildmate's hit list as the book has it ({ w, du } or nil), and their class.
function ns.hitsOf(name)
  local b = book()
  local e = b and b[name]
  if e then return e.h, e.c end
end

-- Every entry, for the Hit List page: name -> { hv, h, c }.
function ns.hitbookEntries()
  return book() or {}
end

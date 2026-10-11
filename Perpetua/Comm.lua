-- Guild sync: guildmates with the addon swap profiles over the hidden guild addon channel.
--
--   H  <profile version> <recipes version> <addon version>   "here's what I have" (login, change, every 10 min)
--   Q  <name> <part> <version>                              "please send name's part" (anyone who's behind)
--   D  <part> <version> <i> <n> <chunk>                     one piece of a part, sent to the whole guild
--   L / R                                                   a loot drop / a /roll seen in a raid (Loot.lua)
--
-- Parts: P = profile (gear, talents, stats, attunements, reps, raid sign-ups), R = recipes, C = the raid
-- calendar (Calendar.lua), F = the forums snapshot (Forums.lua). Only officers send C and F, versioned by when
-- the site made them. A version is a hash of the data,
-- so an unchanged character sends nothing. When several people are behind on the same thing they share one
-- broadcast: a request is skipped if someone else already asked or the data is already on its way.
--
-- Everyone only ever sends their own character, and a received profile is kept only if the name inside it
-- matches the sender the server reports, so nobody can post data under someone else's name.
local _, ns = ...
local PREFIX = "PERPETUA"
local CHUNK = 200            -- characters of data per message (the limit is 255 with the header)
local MAX_PAYLOAD = 150000   -- a part bigger than this isn't sent or accepted
local CPS, BURST = 800, 4000 -- bytes per second / burst, the same budget ChatThrottleLib uses

ns.session = { heard = {}, sent = 0, received = 0 }

-- ---------- storage ----------

-- Players are kept per guild, so an alt in another guild doesn't mix the lists.
-- Asked many times per redraw (every ns.players() call): read once per frame (GetTime is the same within one).
local guildNameAt, guildNameValue = nil, nil
function ns.guildName()
  local now = GetTime()
  if now ~= guildNameAt then guildNameAt, guildNameValue = now, ns.text(ns.try(GetGuildInfo, "player")) end
  return guildNameValue
end

function ns.players(guild)
  PerpetuaDB.guilds = PerpetuaDB.guilds or {}
  guild = guild or ns.guildName() or "No guild"
  PerpetuaDB.guilds[guild] = PerpetuaDB.guilds[guild] or { players = {} }
  return PerpetuaDB.guilds[guild].players
end


function ns.me()
  return ns.players()[ns.selfName]
end

-- The addon only works inside Perpetua: anyone else gets the Welcome page and guild sync stays silent. Just after
-- login the guild's name may not have arrived yet; that doesn't count as locked.
function ns.locked()
  if not IsInGuild() then return true end
  local g = ns.guildName()
  return g ~= nil and g ~= ns.GUILD
end

-- ---------- this character ----------

local function recipesForHash()
  local out = {}
  for name, saved in pairs(PerpetuaCharDB.recipes or {}) do
    out[name] = { list = saved.list, r = saved.r, m = saved.m }
  end
  return out
end

-- The other characters that have logged in on this account in this guild, so the site can file them under the
-- same person. PerpetuaDB.account is account-wide: every character adds itself when it refreshes.
local function accountAlts(me, guild)
  local out = {}
  for full, a in pairs(PerpetuaDB.account or {}) do
    if full ~= me and a.g == guild and a.n then out[#out + 1] = { n = a.n, s = a.s, c = a.c, sp = a.sp, l = a.l } end
  end
  table.sort(out, function(x, y) return ns.fullName(x.n, x.s) < ns.fullName(y.n, y.s) end)
  while #out > 20 do table.remove(out) end
  return out
end

local last = {} -- this session's last profile text and recipes change count, to skip unchanged work
local VOLATILE = { "stats", "res" }

-- Re-reads this character and, if anything changed, tells the guild.
function ns.refreshSelf(quiet)
  if ns.locked() then return end
  -- Just after joining a guild the client says we're in one before it knows the guild's name. Wait for the name:
  -- a profile saved now would be filed under "No guild", and once the name arrives nothing would be found to send.
  if IsInGuild() and not ns.guildName() then ns.scheduleRefresh(5) return end
  local profile = ns.collectProfile()
  local c = profile.char
  if not (c and c.name) then return end
  local name = ns.fullName(c.name, c.surname)
  ns.selfName = name
  -- A character that isn't fully loaded (loading screens, logging out) reads as naked with no professions.
  -- Never let that replace a real profile.
  local old = ns.players()[name]
  if #(profile.gear or {}) == 0 and #(profile.profs or {}) == 0 and old and old.profile and #(old.profile.gear or {}) > 0 then return end
  PerpetuaDB.account = PerpetuaDB.account or {}
  PerpetuaDB.account[name] = { n = c.name, s = c.surname, c = c.classFile, sp = profile.spec and profile.spec.n, l = c.level, g = c.guild, t = ns.now() }
  profile.alts = accountAlts(name, c.guild)
  local signups = ns.mySignups and ns.mySignups() or {}
  if #signups > 0 then profile.signups = signups end
  local raids = ns.raidsForProfile and ns.raidsForProfile() or {}
  if #raids > 0 then profile.raids = raids end
  -- A link code from /perpetua link: rides along until guild sync has used it (a week at most).
  local link = PerpetuaDB.link
  if link and link.code and ns.now() - (link.t or 0) < 7 * 86400 then profile.link = link.code else PerpetuaDB.link = nil end
  local players = ns.players()
  local me = players[name] or {}
  players[name] = me
  local changed = false
  -- Same text as last time (the encoder sorts keys): nothing changed, no need to hash it. Lua compares equal
  -- strings in constant time.
  -- The fingerprint leaves out what buffs, food and flasks move (stats, resistances): those alone would re-send the
  -- whole profile to the guild every few minutes in a raid. They still go along whenever anything else changes.
  local volatile = {}
  for _, k in ipairs(VOLATILE) do volatile[k] = profile[k]; profile[k] = nil end
  local json = ns.toJson(profile)
  for k, v in pairs(volatile) do profile[k] = v end
  if json ~= last.json or last.name ~= name then
    last.json, last.name = json, name
    local pv = ns.hash(json)
    if me.pv ~= pv then me.pv, me.pt, changed = pv, ns.now(), true end
  end
  me.profile = profile -- the latest read, stats included, for the site and the next send
  -- Recipes only change when a profession window was read (ns.onRecipesChanged).
  if last.recipes ~= (ns.recipesChanged or 0) or last.recipesFor ~= name then
    last.recipes, last.recipesFor = ns.recipesChanged or 0, name
    local recipes = recipesForHash()
    local rv = next(recipes) and ns.hash(ns.toJson(recipes)) or nil
    if rv and me.rv ~= rv then
      me.recipes, me.rv, me.rt = PerpetuaCharDB.recipes, rv, ns.now()
      changed = true
    end
  end
  me.heard, me.self, me.class, me.level, me.addon = ns.now(), true, profile.char.classFile, profile.char.level, ns.VERSION
  if changed and not quiet then ns.announce() end
  ns.fire()
end

-- One pending refresh; a new request only moves it sooner (looting fires bag updates with a 60 s delay all the time,
-- which used to keep pushing a gear change's 15 s refresh back indefinitely).
local refreshTimer, refreshDue = nil, 0
function ns.scheduleRefresh(delay)
  local due = GetTime() + (delay or 15)
  if refreshTimer and refreshDue <= due then return end
  if refreshTimer then refreshTimer:Cancel() end
  refreshDue = due
  refreshTimer = C_Timer.NewTimer(delay or 15, function() refreshTimer = nil; ns.refreshSelf() end)
end
ns.onRecipesChanged = function() ns.recipesChanged = (ns.recipesChanged or 0) + 1; ns.scheduleRefresh(5) end

-- ---------- sending ----------

local queue, avail, lastPump = {}, BURST, 0
local lastAnnounce = 0

local pumpTicker, pump
-- The send loop runs only while there's something queued (it used to tick five times a second all session).
local function enqueue(msg)
  queue[#queue + 1] = { msg = msg, tries = 0 }
  if not pumpTicker then pumpTicker = C_Timer.NewTicker(0.2, function() pump() end) end
end

local THROTTLED = { [3] = true, [8] = true } -- Enum.SendAddonMessageResult AddonMessageThrottle / ChannelThrottle
local LOCKDOWN, NOT_IN_GUILD = 11, 10       -- AddOnMessageLockdown (boss fights and the like) / NotInGuild

function pump()
  if not queue[1] then
    if pumpTicker then pumpTicker:Cancel(); pumpTicker = nil end
    return
  end
  local now = GetTime()
  avail = math.min(BURST, avail + CPS * (now - lastPump))
  lastPump = now
  while queue[1] do
    local item = queue[1]
    if item.wait and item.wait > now then return end
    local size = #item.msg + 40
    if avail < size then return end
    if not IsInGuild() then wipe(queue); return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, "GUILD")
    if ok and (result == nil or result == true or result == 0) then
      table.remove(queue, 1)
      avail = avail - size
      ns.session.sent = ns.session.sent + 1
    elseif ok and THROTTLED[result] then
      item.wait = now + 1 -- the server's limit; try the same message again shortly
      return
    elseif ok and result == LOCKDOWN then
      item.wait = now + 3 -- addon messages are paused (a boss fight): wait it out, it doesn't count as a failure
      return
    elseif ok and result == NOT_IN_GUILD then
      wipe(queue)
      return
    else
      -- Blocked (combat in an instance, not in a guild yet …): back off, give up after a while.
      item.tries = item.tries + 1
      if item.tries > 6 then table.remove(queue, 1) else item.wait = now + 5 * item.tries end
      return
    end
  end
end

-- Not in combat or a raid instance: guildmates would all ask for the new profile at once, mid-fight. It goes out
-- when that's over (the frame at the bottom).
local function busy()
  if InCombatLockdown() then return true end
  local _, kind = ns.try(IsInInstance)
  return kind == "raid"
end
local heldAnnounce = false

function ns.announce()
  if not (IsInGuild() and ns.selfName) or ns.locked() then return end
  if busy() then heldAnnounce = true return end
  heldAnnounce = false
  local me = ns.me()
  -- Nothing saved for this character in this guild yet (the guild just changed): read it again, which announces.
  if not me then ns.scheduleRefresh(2) return end
  lastAnnounce = GetTime()
  enqueue(table.concat({ "H", me.pv or "-", me.rv or "-", ns.announcedVersion(), ns.calendarVersion and ns.calendarVersion() or "-",
    ns.forumsVersion and ns.forumsVersion() or "-" }, "\t"))
end

-- A one-message update (loot, rolls) for the whole guild.
function ns.sendLine(fields)
  if IsInGuild() and not ns.locked() then enqueue(table.concat(fields, "\t")) end
end

local lastSent, sendPending = {}, {}
local packed = {} -- part -> { v = version, s = packed string }: re-sends reuse it instead of encoding again

local function sendPart(part)
  local me = ns.me()
  if not me then return end
  local version = part == "P" and me.pv or part == "R" and me.rv or part == "C" and ns.calendarVersion()
    or part == "F" and ns.forumsVersion() or nil
  if not version or sendPending[part] then return end
  if (part == "C" or part == "F") and not ns.isOfficer(ns.selfName) then return end -- nobody would accept it
  local last = lastSent[part]
  if last and last.v == version and GetTime() - last.at < 30 then return end -- just sent it; they'll have it
  sendPending[part] = true
  -- A short wait gathers everyone's requests into one broadcast.
  C_Timer.After(2, function()
    sendPending[part] = nil
    me = ns.me()
    if not me then return end
    -- Read the version now: the data may have changed during the wait.
    version = part == "P" and me.pv or part == "R" and me.rv or part == "C" and ns.calendarVersion()
      or part == "F" and ns.forumsVersion() or nil
    if not version then return end
    local cachedPack = packed[part]
    if cachedPack and cachedPack.v == version then
      local s = cachedPack.s
      local n = math.ceil(#s / CHUNK)
      for i = 1, n do enqueue(table.concat({ "D", part, version, i, n, s:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "\t")) end
      lastSent[part] = { v = version, at = GetTime() }
      return
    end
    local payload
    if part == "P" then
      payload = {}
      for k, v in pairs(me.profile or {}) do payload[k] = v end
      payload.t = me.pt
    elseif part == "C" then
      payload = ns.calendar()
      if not payload then return end
    elseif part == "F" then
      payload = ns.forums()
      if not payload then return end
    else
      payload = { t = me.rt, r = me.recipes }
    end
    local s = ns.pack(payload)
    packed[part] = { v = version, s = s }
    if #s > MAX_PAYLOAD then return end
    local n = math.ceil(#s / CHUNK)
    for i = 1, n do
      enqueue(table.concat({ "D", part, version, i, n, s:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "\t"))
    end
    lastSent[part] = { v = version, at = GetTime() }
  end)
end

-- ---------- receiving ----------

local buffers = {}      -- sender .. part .. version -> { n, got, parts, at }
local asked = {}        -- name .. part .. version -> time someone (anyone) asked for it

local function request(name, part, version)
  local key = name .. part .. version
  if asked[key] and GetTime() - asked[key] < 60 then return end
  -- Random wait so one guildmate asks and the rest just listen for the broadcast.
  C_Timer.After(1 + math.random() * 3, function()
    local rec = ns.players()[name]
    local have = part == "C" and ns.calendarVersion() or part == "F" and ns.forumsVersion() or rec and (part == "P" and rec.pv or rec.rv)
    if have == version or buffers[name .. part .. version] then return end
    if asked[key] and GetTime() - asked[key] < 60 then return end
    asked[key] = GetTime()
    enqueue(table.concat({ "Q", name, part, version }, "\t"))
  end)
end

local function accept(from, part, version, s)
  local data = ns.unpack(s, 600000)
  if type(data) ~= "table" then return end
  local players = ns.players()
  if part == "P" then
    local c = data.char
    if type(c) ~= "table" or type(c.name) ~= "string" then return end
    -- Addon 2.1 and earlier sent the surname where Classic had the realm.
    if ns.FOREVER and type(c.surname) ~= "string" and type(c.realm) == "string" and not ns.newer(data.addon, "2.1.99") then
      c.surname = c.realm
    end
    if ns.fullName(c.name, type(c.surname) == "string" and c.surname or nil):lower() ~= from:lower() then return end
    local rec = players[from] or {}
    players[from] = rec
    -- Kept compact: the summary the lists read, and the packed string for when their page is opened.
    rec.profile, rec.pz, rec.pv, rec.pt = ns.summarize(data), s, version, tonumber(data.t)
    rec.class, rec.level = c.classFile, tonumber(c.level)
  elseif part == "C" then
    if ns.isOfficer(from) then ns.adoptCalendar(data) end
    return
  elseif part == "F" then
    if ns.isOfficer(from) then ns.adoptForums(data) end
    return
  elseif part == "R" then
    if type(data.r) ~= "table" then return end
    local rec = players[from] or {}
    players[from] = rec
    rec.rz, rec.recipes, rec.rv, rec.rt = s, nil, version, tonumber(data.t)
    ns.recipesChanged = (ns.recipesChanged or 0) + 1
  else
    return
  end
  players[from].heard = ns.now()
  ns.session.received = ns.session.received + 1
  ns.fire()
end

-- Update notice. A guildmate's hello carries their addon version; the newest one seen is kept (PerpetuaDB.newest)
-- so the notice still shows after a relog, until this install catches up. It shows in the sidebar and the minimap
-- tooltip, and once per new version in chat.
-- A test install has "-dev" on its version (in the installed Perpetua.toc only) and announces "dev" instead, so
-- guildmates aren't told about a release that isn't out. A version nobody has announced for 14 days is dropped,
-- so one modified addon can't leave a notice up for good.
ns.DEV = ns.VERSION:find("-dev", 1, true) ~= nil
function ns.announcedVersion() return ns.DEV and "dev" or ns.VERSION end

function ns.updateAvailable()
  local v = PerpetuaDB.newest
  if v and ns.newer(v, ns.VERSION) and ns.now() - (PerpetuaDB.newestAt or 0) < 14 * 86400 then return v end
end

function ns.noteVersion(v)
  v = ns.text(v)
  if not v or not v:match("^%d+%.%d+[%.%d]*$") then return end
  if v == PerpetuaDB.newest then PerpetuaDB.newestAt = ns.now() return end
  if not ns.newer(v, ns.VERSION) or (ns.updateAvailable() and not ns.newer(v, PerpetuaDB.newest)) then return end
  PerpetuaDB.newest, PerpetuaDB.newestAt = v, ns.now()
  if ns.newer(v, ns.VERSION) and PerpetuaDB.toldNewest ~= v then
    PerpetuaDB.toldNewest = v
    print("|cffd4af37Perpetua|r: version " .. ns.safe(v) .. " is out (you have " .. ns.VERSION .. "). Update through CurseForge or " .. ns.SITE .. "/addon.")
  end
  ns.refreshUI()
end

local function onMessage(text, channel, sender)
  if channel ~= "GUILD" or type(text) ~= "string" or ns.locked() then return end
  -- Just after login the guild's name may not be known yet; anything stored now would land under "No guild".
  if not ns.guildName() then return end
  local from = ns.playerKey(sender)
  if not from or from == ns.selfName then return end
  local f = { strsplit("\t", text) }
  local kind = f[1]
  if kind == "H" then
    local players = ns.players()
    local rec = players[from] or {}
    players[from] = rec
    local wasAddon, newHere = rec.addon, not ns.session.heard[from]
    rec.heard, rec.addon = ns.now(), f[4] ~= "dev" and f[4] or rec.addon -- a test install says "dev"
    ns.noteVersion(f[4])
    -- Someone new this session: answer with our own hello so they can catch up on us too.
    if not ns.session.heard[from] then
      ns.session.heard[from] = true
      if GetTime() - lastAnnounce > 20 then
        C_Timer.After(2 + math.random() * 6, function() if GetTime() - lastAnnounce > 20 then ns.announce() end end)
      end
    end
    if f[2] and f[2] ~= "-" and f[2] ~= rec.pv then request(from, "P", f[2]) end
    if f[3] and f[3] ~= "-" and f[3] ~= rec.rv then request(from, "R", f[3]) end
    -- A newer raid calendar, from an officer.
    local calT = tonumber(f[5])
    if calT and calT > (tonumber(ns.calendarVersion()) or 0) and ns.isOfficer(from) then request(from, "C", f[5]) end
    local forumT = tonumber(f[6])
    if ns.FORUMS and forumT and forumT > (tonumber(ns.forumsVersion()) or 0) and ns.isOfficer(from) then request(from, "F", f[6]) end
    -- A hello only changes the window when it's someone new or their addon version changed.
    if newHere or wasAddon ~= rec.addon then ns.fire() end
  elseif kind == "L" or kind == "R" then
    ns.onLootMessage(f, from)
  elseif kind == "Q" then
    if f[2] and f[3] and f[4] then asked[f[2] .. f[3] .. f[4]] = GetTime() end
    if f[2] == ns.selfName then sendPart(f[3]) end
  elseif kind == "D" then
    local part, version, i, n, chunk = f[2], f[3], tonumber(f[4]), tonumber(f[5]), f[6]
    if not (part and version and i and n and chunk) or n < 1 or n > MAX_PAYLOAD / CHUNK or i < 1 or i > n then return end
    -- Someone else asked for it and we already have this version: don't collect and unpack it all again.
    local rec = ns.players()[from]
    local have = part == "P" and rec and rec.pv or part == "R" and rec and rec.rv
      or part == "C" and ns.calendarVersion() or part == "F" and ns.forumsVersion() or nil
    if have == version then return end
    local key = from .. part .. version
    local b = buffers[key]
    if not b or b.n ~= n then b = { n = n, got = 0, parts = {} }; buffers[key] = b end
    b.at = GetTime()
    if not b.parts[i] then b.parts[i] = chunk; b.got = b.got + 1 end
    if b.got == b.n then
      buffers[key] = nil
      accept(from, part, version, table.concat(b.parts))
    end
  end
end

-- A held announcement goes out once combat or the raid instance is over.
local heldFrame = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do pcall(heldFrame.RegisterEvent, heldFrame, e) end
heldFrame:SetScript("OnEvent", function()
  if heldAnnounce then C_Timer.After(3, function() if heldAnnounce and not busy() then ns.announce() end end) end
end)

-- ---------- start ----------

-- Addon 2.1 and earlier keyed your own characters by first name only; those entries are replaced by full names.
local function tidy()
  if not ns.FOREVER then return end
  for _, g in pairs(PerpetuaDB.guilds or {}) do
    for key, rec in pairs(g.players or {}) do
      local c = type(rec) == "table" and rec.profile and rec.profile.char
      if rec.self and c and not key:find(" ") and c.realm and c.realm ~= "" and not c.surname then g.players[key] = nil end
    end
  end
end

function ns.startComm()
  tidy()
  pcall(ns.compactPlayers)
  ns.try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  -- Re-announce every 10 minutes so anyone who missed a change catches up; drop stalled transfers.
  C_Timer.NewTicker(600, function() ns.announce() end)
  C_Timer.NewTicker(60, function()
    for key, b in pairs(buffers) do if GetTime() - b.at > 120 then buffers[key] = nil end end
  end)
end

ns.onAddonMessage = function(prefix, text, channel, sender)
  if prefix == PREFIX then pcall(onMessage, text, channel, sender) end
end

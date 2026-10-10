-- Hide Olympus: hides chat from players in any guild with "Olympus" in its name (ns.OLYMPUS) and turns away their
-- whispers, guild invites and charters, group invites, trades and duels. It all happens in this client: nobody is
-- put on the ignore list, nothing is sent anywhere, and they can't tell.
--
-- The game only says which guild a player is in when it shows you that player (a nameplate, your target or
-- mouseover, your group, /who, a trade window, an invite), so the addon learns names as it goes and remembers them
-- in PerpetuaDB.olympus.known. Chat from someone it hasn't seen yet still shows until it does, except a whisper
-- from someone on screen, any whisper that says "Olympus" and, with "mentions" on, any chat that does.
local _, ns = ...
local try = ns.try

local O = { session = { learned = 0, counts = {} } }
ns.olympus = O

-- Each can be switched off on the Hide Olympus page; the switch in the sidebar turns them all on or off.
O.OPTIONS = {
  { key = "chat", label = "Hide their chat", hint = "Say, yell, emotes, every channel, and party and raid chat." },
  { key = "mentions", parent = "chat", label = "Hide any chat that says Olympus",
    hint = "From anyone, like trade asking for an Olympus layer." },
  { key = "whispers", label = "Hide their whispers", hint = "Also any whisper that says \"Olympus\", from anyone. They aren't told." },
  { key = "guild", label = "Turn down guild invites and charters", hint = "Invites to an Olympus guild, and Olympus charters to sign." },
  { key = "party", label = "Turn down group invites", hint = "" },
  { key = "trade", label = "Cancel trades", hint = "Including ones you open yourself." },
  { key = "duel", label = "Turn down duels", hint = "" },
}
-- The three running totals on the Hide Olympus page, kept across sessions in PerpetuaDB.olympus.totals.
O.TOTALS = { chat = "messages", mentions = "messages", whispers = "messages", guild = "invites", party = "invites", trade = "trades" }
O.COUNTED = { chat = "messages", mentions = "messages naming Olympus", whispers = "whispers", guild = "guild invites", party = "group invites", trade = "trades", duel = "duels" }

local FORGET_AFTER = 45 * 86400 -- forget anyone not seen in Olympus for this long
local MAX_KNOWN = 5000          -- past this, the ones seen longest ago make room
local byGuid = {}               -- GUID -> name, for chat lines that come with a GUID
local guildOf = {}              -- name -> guild, this session only, for "turned away ... <Olympus XIX>"
local knownN = 0

-- Each known player is saved as one short string, "<last seen> <GUID>" (the GUID when the game gave one), to keep
-- the saved variables small. 2.9.0 saved tables, read here too.
local function parse(v)
  if type(v) == "table" then return tonumber(v.t), ns.text(v.id) end
  if type(v) ~= "string" then return end
  local t, id = v:match("^(%d+) ?(%S*)$")
  return tonumber(t), id ~= "" and id or nil
end

-- Called for every chat line (once per chat window), so the defaults are filled in once, not each time.
local readyDb
function O.db()
  local db = PerpetuaDB.olympus
  if db and db == readyDb then return db end
  PerpetuaDB.olympus = db or {}
  db = PerpetuaDB.olympus
  db.opts = db.opts or {}
  db.known = db.known or {}
  db.totals = db.totals or {}
  for _, o in ipairs(O.OPTIONS) do if db.opts[o.key] == nil then db.opts[o.key] = true end end
  readyDb = db
  return db
end

function O.isOlympus(guild)
  guild = ns.text(guild)
  if not guild then return false end
  guild = guild:lower()
  for _, p in ipairs(ns.OLYMPUS) do if guild:find(p, 1, true) then return true end end
  return false
end

local PARENT = {}
for _, o in ipairs(O.OPTIONS) do PARENT[o.key] = o.parent end

-- Switched on (and, with a key, that part and the one it sits under). Members only, like the rest of the addon.
function O.active(key)
  local db = PerpetuaDB.olympus
  if not (db and db.on) or ns.locked() then return false end
  while key do
    if db.opts[key] == false then return false end
    key = PARENT[key]
  end
  return true
end

function O.knownCount()
  return knownN
end

-- Drops the tenth of the list seen longest ago.
local function makeRoom(known)
  local all = {}
  for name, v in pairs(known) do all[#all + 1] = { name, parse(v) or 0 } end
  table.sort(all, function(a, b) return a[2] < b[2] end)
  for i = 1, math.floor(MAX_KNOWN / 10) do
    if all[i] then known[all[i][1]] = nil; knownN = knownN - 1 end
  end
end

-- Remembers (or refreshes) an Olympus player.
local function remember(name, guid, guild)
  local known = O.db().known
  local _, oldId = parse(known[name])
  guid = guid or oldId
  local seen = parse(known[name])
  if known[name] == nil then
    if knownN >= MAX_KNOWN then makeRoom(known) end
    knownN = knownN + 1
    O.session.learned = O.session.learned + 1
  end
  -- Seen again soon after: the saved entry is good enough (no new string for every nameplate in a city).
  if not (seen and ns.now() - seen < 6 * 3600 and (guid == oldId)) then
    known[name] = ns.now() .. (guid and (" " .. guid) or "")
  end
  if guid then byGuid[guid] = name end
  if guild then guildOf[name] = guild end
end

-- What the game told us about a player: in an Olympus guild (remember them), in another guild (forget them), or
-- nil when it doesn't know (not in a guild, or not loaded yet), which changes nothing.
function O.note(name, guild, guid)
  if not name or name == ns.selfName then return end
  local known = O.db().known
  if O.isOlympus(guild) then
    remember(name, ns.text(guid), ns.text(guild))
  elseif known[name] ~= nil and type(guild) == "string" then
    known[name] = nil
    knownN = knownN - 1
  end
end

local function unitName(unit)
  local first, surname = try(UnitName, unit)
  first = ns.text(first)
  return first and ns.fullName(first, ns.FOREVER and ns.text(surname) or nil)
end

local function learnUnit(unit)
  if not try(UnitIsPlayer, unit) then return end
  local name = unitName(unit)
  if not name then return end
  local guild = ns.text(try(GetGuildInfo, unit))
  -- No guild name can also mean "not loaded yet", so only a guild name counts as an answer.
  O.note(name, guild or nil, ns.text(try(UnitGUID, unit)))
end

-- Whether this player is known to be in Olympus.
function O.match(name, guid)
  local known = O.db().known
  guid = ns.text(guid)
  if guid and byGuid[guid] and known[byGuid[guid]] then return true end
  name = ns.playerKey(ns.text(name))
  return name ~= nil and known[name] ~= nil
end

-- For invites and duels, which come with only a name: also look at the players on screen right now.
local ON_SCREEN = { "target", "mouseover", "focus" }
for i = 1, 40 do ON_SCREEN[#ON_SCREEN + 1] = "nameplate" .. i end

local function matchNow(name, guid)
  if O.match(name, guid) then return true end
  local key = ns.playerKey(ns.text(name))
  if not key then return false end
  for _, unit in ipairs(ON_SCREEN) do
    if try(UnitIsPlayer, unit) and unitName(unit) == key then
      learnUnit(unit)
      return O.isOlympus(try(GetGuildInfo, unit))
    end
  end
  return false
end

local lastLine = {}
local function count(key, line, who)
  if line and lastLine[key] == line then return end -- the same line passes through every chat window
  lastLine[key] = line
  O.session.counts[key] = (O.session.counts[key] or 0) + 1
  local total = O.TOTALS[key]
  if total then
    local totals = O.db().totals
    totals[total] = (totals[total] or 0) + 1
  end
  if who and O.db().notify then
    print("|cffd4af37Perpetua|r: turned away " .. who .. ".")
  end
  ns.refreshUI()
end

local function hidePopup(...)
  for _, which in ipairs({ ... }) do try(StaticPopup_Hide, which) end
end

-- ---------- chat ----------

local CHAT = {
  chat = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
  whispers = { "CHAT_MSG_WHISPER" },
}

-- A whisper that names Olympus ("<Olympus> is recruiting!"), from anyone. Unless it came from a guildmate or friend, its
-- sender is remembered like any other Olympus player, until the game shows them in another guild.
local function recruiting(msg, sender, guid)
  msg = ns.text(msg)
  if not (msg and O.isOlympus(msg)) then return false end
  local who = guid or sender
  if try(IsGuildMember, who) or (C_FriendList and try(C_FriendList.IsFriend, who)) then return true end
  local name = ns.playerKey(ns.text(sender))
  if name and name ~= ns.selfName and O.db().known[name] == nil then remember(name, guid) end
  return true
end

-- What the filters have seen since login, for /ppta olympus debug.
local diag = { calls = {}, unreadable = 0, hidden = 0 }

-- Chat event arguments: message, sender, ..., lineID (11th), sender GUID (12th). Return true to hide the line.
local function chatFilter(key)
  return function(_, event, msg, sender, ...)
    diag.calls[event] = (diag.calls[event] or 0) + 1
    if not ns.text(msg) or not ns.text(sender) then diag.unreadable = diag.unreadable + 1 end
    diag.last = event
    if not O.active(key) then return false end
    local line, guid = select(9, ...), ns.text(select(10, ...))
    -- Recruiters whisper strangers, so a whisper also checks who's on screen and what it says.
    if O.match(sender, guid) or (key == "whispers" and (matchNow(sender, guid) or recruiting(msg, sender, guid))) then
      count(key, ns.readable(line))
      diag.hidden = diag.hidden + 1
      return true
    end
    -- Other chat that says "Olympus" doesn't make its sender one: in trade it's mostly people asking for their layer.
    if key == "chat" and O.active("mentions") and O.isOlympus(msg) then
      count("mentions", ns.readable(line))
      diag.hidden = diag.hidden + 1
      return true
    end
    return false
  end
end

-- Added at login, when the chat frames are sure to be loaded, the way other addons on this client do it.
local function addFilters()
  if diag.api then return end
  local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter
  diag.api = add and "ChatFrameUtil" or "ChatFrame_AddMessageEventFilter"
  add = add or ChatFrame_AddMessageEventFilter
  diag.added, diag.failed = 0, nil
  for key, list in pairs(CHAT) do
    local f = chatFilter(key)
    for _, e in ipairs(list) do
      local ok, err = pcall(add, e, f)
      if ok then diag.added = diag.added + 1 else diag.failed = diag.failed or tostring(err) end
    end
  end
end

function O.debug()
  local p = function(s) print("|cffd4af37Perpetua|r Olympus: " .. s) end
  local db = O.db()
  p(string.format("on=%s locked=%s chat=%s mentions=%s whispers=%s known=%d", tostring(db.on), tostring(ns.locked()),
    tostring(O.active("chat")), tostring(O.active("mentions")), tostring(O.active("whispers")), knownN))
  p(string.format("filters: %s, %d added%s", tostring(diag.api), diag.added or 0, diag.failed and (", error: " .. diag.failed) or ""))
  local seen = {}
  for e, n in pairs(diag.calls) do seen[#seen + 1] = e:gsub("CHAT_MSG_", "") .. "=" .. n end
  table.sort(seen)
  p("lines seen: " .. (#seen > 0 and table.concat(seen, " ") or "none") .. string.format("; hidden %d; unreadable %d", diag.hidden, diag.unreadable))
end

-- ---------- invites, trades, duels ----------

local function display(name, guild)
  return ns.safe(ns.playerKey(ns.text(name)) or "someone") .. (guild and (" <" .. ns.safe(guild) .. ">") or "")
end

local function knownGuild(name)
  return guildOf[ns.playerKey(ns.text(name)) or ""]
end

function O.onEvent(event, ...)
  if not O.active() then return end
  if event == "NAME_PLATE_UNIT_ADDED" then
    learnUnit(...)
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    learnUnit("mouseover")
  elseif event == "PLAYER_TARGET_CHANGED" then
    learnUnit("target")
  elseif event == "PLAYER_FOCUS_CHANGED" then
    learnUnit("focus")
  elseif event == "GROUP_ROSTER_UPDATE" then
    local raid = try(IsInRaid)
    for i = 1, raid and 40 or 4 do learnUnit((raid and "raid" or "party") .. i) end
  elseif event == "WHO_LIST_UPDATE" then
    local who = C_FriendList
    for i = 1, (who and try(who.GetNumWhoResults)) or 0 do
      local info = try(who.GetWhoInfo, i)
      -- /who answers for certain: an empty guild means not in one.
      if info then O.note(ns.playerKey(ns.text(info.fullName)), ns.readable(info.fullGuildName) or nil) end
    end
  elseif event == "GUILD_INVITE_REQUEST" then
    local inviter, guild = ...
    O.note(ns.playerKey(ns.text(inviter)), ns.text(guild))
    if O.active("guild") and O.isOlympus(guild) then
      try(DeclineGuild)
      if GuildInviteFrame then try(GuildInviteFrame.Hide, GuildInviteFrame) end
      hidePopup("GUILD_INVITE")
      count("guild", nil, "a guild invite from " .. display(inviter, ns.text(guild)))
    end
  elseif event == "PETITION_SHOW" then
    local _, title, _, _, originator, isOriginator = try(GetPetitionInfo)
    if O.active("guild") and not isOriginator and (O.isOlympus(title) or O.match(originator)) then
      try(ClosePetition)
      count("guild", nil, "a guild charter for <" .. ns.safe(ns.text(title) or "?") .. "> from " .. display(originator))
    end
  elseif event == "PARTY_INVITE_REQUEST" then
    local name = ...
    local guid = select(7, ...)
    if O.active("party") and matchNow(name, guid) then
      try(DeclineGroup)
      hidePopup("PARTY_INVITE", "PARTY_INVITE_XREALM")
      count("party", nil, "a group invite from " .. display(name, knownGuild(name)))
    end
  elseif event == "TRADE_SHOW" then
    learnUnit("NPC") -- the other side of a trade is the "NPC" unit
    local name = unitName("NPC")
    if O.active("trade") and O.match(name, ns.text(try(UnitGUID, "NPC"))) then
      try(CancelTrade)
      count("trade", nil, "a trade with " .. display(name, knownGuild(name)))
    end
  elseif event == "DUEL_REQUESTED" then
    local name = ...
    if O.active("duel") and matchNow(name) then
      try(CancelDuel)
      hidePopup("DUEL_REQUESTED")
      count("duel", nil, "a duel from " .. display(name, knownGuild(name)))
    end
  end
end

local events = CreateFrame("Frame")
-- Always: login, guild changes, and the rare invites, trades and duels.
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "GUILD_INVITE_REQUEST", "PETITION_SHOW", "PARTY_INVITE_REQUEST", "TRADE_SHOW", "DUEL_REQUESTED" }) do
  pcall(events.RegisterEvent, events, e) -- not every client has every event
end
-- Only while Hide Olympus is on: the frequent ones it learns guilds from (nameplates fire constantly in cities).
local LEARN = { "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE", "WHO_LIST_UPDATE" }
local learning
function O.syncEvents()
  local on = O.active() and true or false
  if on == learning then return end
  learning = on
  for _, e in ipairs(LEARN) do pcall(on and events.RegisterEvent or events.UnregisterEvent, events, e) end
end
events:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    addFilters()
    -- Forget anyone not seen in Olympus for a while; index the rest by GUID (and turn 2.9.0's tables into strings).
    local cutoff = ns.now() - FORGET_AFTER
    local known = O.db().known
    knownN = 0
    for name, v in pairs(known) do
      local t, id = parse(v)
      if not t or t < cutoff then
        known[name] = nil
      else
        knownN = knownN + 1
        if type(v) == "table" then known[name] = t .. (id and (" " .. id) or "") end
        if id then byGuid[id] = name end
      end
    end
    if knownN > MAX_KNOWN then makeRoom(known) end
    O.syncEvents()
    -- The guild name arrives a little after login (until then the addon counts as locked).
    C_Timer.After(10, O.syncEvents)
    return
  end
  if event == "PLAYER_GUILD_UPDATE" then O.syncEvents() return end
  local ok, err = pcall(O.onEvent, event, ...)
  if not ok and ns.debug then print("Perpetua Olympus:", err) end
end)

-- ---------- switches ----------

function O.set(on)
  O.db().on = on and true or false
  O.syncEvents()
  print("|cffd4af37Perpetua|r: Hide Olympus is " .. (on and "|cff8fd18aon|r" or "off") .. ".")
  ns.refreshUI(true)
end

function O.setOption(key, on)
  O.db().opts[key] = on and true or false
  O.syncEvents()
  ns.refreshUI(true)
end

-- /who finds up to 50 players at a time, so the button works through level and class groups, one per click. The
-- game only allows /who from a click or key press, which is why it can't run by itself.
-- The class names come from the game (this client's classes, in its language): /who's c-"..." only matches the
-- localized name. Built the first time it's used, when the class list is sure to be loaded.
local WHO = {}
local FALLBACK_CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local function buildWho()
  if #WHO > 0 then return end
  local classes = {}
  for i = 1, (try(GetNumClasses) or 0) do
    local name = ns.text(try(GetClassInfo, i))
    if name then classes[#classes + 1] = name end
  end
  if #classes == 0 then classes = FALLBACK_CLASSES end
  for _, levels in ipairs({ "60", "55-59", "50-54", "40-49", "30-39", "20-29", "10-19", "1-9" }) do
    for _, class in ipairs(classes) do WHO[#WHO + 1] = levels .. ' c-"' .. class .. '"' end
  end
  O.WHO_TOTAL = #WHO
end
O.WHO_TOTAL = #FALLBACK_CLASSES * 8 -- until the first search builds the real list

function O.lookUp()
  buildWho()
  local db = O.db()
  db.whoNext = (db.whoNext or 0) % #WHO + 1
  local query = 'g-"' .. ns.OLYMPUS_WHO .. '" ' .. WHO[db.whoNext]
  if C_FriendList and C_FriendList.SendWho then try(C_FriendList.SendWho, query) else try(SendWho, query) end
  return db.whoNext
end

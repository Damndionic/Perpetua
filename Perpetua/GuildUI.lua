-- Everything Blizzard's guild window does, in the Perpetua window: the full roster (rank, zone, notes, last
-- online) with a member panel and a right-click menu (rank, notes, whisper, invite to group, remove, make leader),
-- inviting, and the Guild Info page (message of the day, guild information, the guild event log, leave and
-- disband). GuildTakeover.lua makes the guild key and button open it.
--
-- Every action uses the same permission checks as Blizzard's Communities guild UI (Blizzard_Communities/GuildRoster.lua,
-- GuildInfo.lua on the Forever client), with our own dialogs in place of StaticPopups, which addon code would taint.
--
-- What addons may call: the Forever client marks C_GuildInfo.SetGuildRankOrder, RemoveFromGuild, SetNote, SetMOTD
-- and SetInfoText "HasRestrictions" (Blizzard's UI only; Blizzard_APIDocumentationGenerated/GuildInfoDocumentation.lua).
-- So ranks change one step at a time with Promote/Demote, removing uses Uninvite (by name), and notes, the message of
-- the day and guild info are edited in Blizzard's guild window, which our buttons open through a secure click
-- (GuildTakeover.lua ns.opensBlizzardGuild). Guild Control (rank names, permissions, bank tabs) is Blizzard's window.
local _, ns = ...
local try, safe, T = ns.try, ns.safe, ns.T

local function color(hex, s) return "|cff" .. hex .. s .. "|r" end
local function say(msg) print("|cffd4af37Perpetua|r: " .. msg) end

-- Runs a guild action; some are refused in combat or instances on this client, so say so instead of erroring.
local function act(what, fn, ...)
  if type(fn) ~= "function" then say("can't " .. what .. " on this client.") return end
  local ok, err = pcall(fn, ...)
  if not ok then say("couldn't " .. what .. " (" .. tostring(err):gsub("^.-:%d+: ", "") .. ").") end
end

-- ---------- roster data ----------

local function myRankOrder()
  local _, _, rankIndex = try(GetGuildInfo, "player")
  return (ns.num(rankIndex) or 99) + 1
end

local function lastOnlineText(m)
  if m.online then return color(T.HEX.ok, "Online") end
  if m.mobile then return color(T.HEX.warm, "Mobile") end
  local y, mo, d, h = unpack(m.last)
  if not (y or mo or d or h) then return "" end
  local text = TimeUtil and TimeUtil.GetRecentTimeDate and try(TimeUtil.GetRecentTimeDate, y, mo, d, h)
  if text then return text end
  if (y or 0) > 0 then return y .. "y" elseif (mo or 0) > 0 then return mo .. "mo" elseif (d or 0) > 0 then return d .. "d" end
  return math.max(h or 0, 1) .. "h"
end

-- Every member, offline ones included: { full ("First-Surname", what the API wants), name ("First Surname"),
-- rank, rankOrder (1 = Guild Master), level, classFile, zone, note, officerNote, online, guid, ... }.
local function members()
  local list, me = {}, UnitGUID("player")
  for i = 1, (ns.num(try(GetNumGuildMembers)) or 0) do
    local full, rankName, rankIndex, level, className, zone, note, officerNote, online, _, classFile, _, _, isMobile,
      _, _, guid = try(GetGuildRosterInfo, i)
    full = ns.text(full)
    if full then
      local y, mo, d, h = try(GetGuildRosterLastOnline, i)
      local m = {
        index = i, full = full, name = ns.playerKey(full), rank = ns.text(rankName) or "?",
        rankOrder = (ns.num(rankIndex) or 0) + 1, level = ns.num(level), className = ns.text(className),
        classFile = ns.text(classFile), zone = ns.text(zone) or "", note = ns.text(note) or "",
        officerNote = ns.text(officerNote) or "", online = ns.readable(online) and true or false,
        mobile = ns.readable(isMobile) and true or false, guid = ns.text(guid),
        last = { ns.num(y), ns.num(mo), ns.num(d), ns.num(h) },
      }
      m.isSelf = m.guid ~= nil and m.guid == me
      m.away = m.online and 0 or ((m.last[1] or 0) * 8760 + (m.last[2] or 0) * 730 + (m.last[3] or 0) * 24 + (m.last[4] or 0) + (m.mobile and 0.5 or 1))
      list[#list + 1] = m
    end
  end
  return list
end
ns.guildMembers = members

-- What I may do to member m, by Blizzard's own rules (CommunitiesGuildMemberDetailMixin:DisplayMember).
local function rights(m)
  local mine, maxRank = myRankOrder(), ns.num(try(GuildControlGetNumRanks)) or 0
  local promote, demote = try(CanGuildPromote), try(CanGuildDemote)
  return {
    -- One rank up (never to your own rank or above) or one down.
    ranks = not m.isSelf and (promote or demote) and m.rankOrder > mine and true or false, -- show the two buttons
    promote = not m.isSelf and promote and m.rankOrder > mine + 1,
    demote = not m.isSelf and demote and m.rankOrder < maxRank and m.rankOrder > mine,
    remove = not m.isSelf and try(CanGuildRemove) and m.rankOrder > mine,
    publicNote = m.isSelf or try(CanEditPublicNote),
    viewOfficer = try(C_GuildInfo.CanViewOfficerNote),
    officerNote = try(C_GuildInfo.CanEditOfficerNote),
    leader = not m.isSelf and try(IsGuildLeader),
  }
end

-- ---------- actions ----------

local A = {}
function A.whisper(m)
  local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
  if tell then tell(m.full) end
end
function A.groupInvite(m) act("invite " .. m.name .. " to your group", C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit, m.full) end
local function rankName(order) return try(GuildControlGetRankName, order) or ("rank " .. order) end
-- Promote / demote / remove / make leader / leave / disband run Blizzard's secure slash commands from a real click
-- (GuildTakeover.lua ns.secureGuildCommand), since the game blocks addons calling them. The roster update redraws.
local function refreshSoon() C_Timer.After(0.6, function() try(C_GuildInfo.GuildRoster) end) end
-- The command for one step up (dir -1) or down (+1), or nil if not allowed.
function A.stepCommand(m, dir)
  local r = m and rights(m)
  if not r or not (dir < 0 and r.promote or dir > 0 and r.demote) then return nil end
  if dir < 0 and m.guid and try(C_GuildInfo.IsGuildRankAssignmentAllowed, m.guid, m.rankOrder - 1) == false then return nil end
  return ns.guildSlash(dir < 0 and "promote" or "demote", m.full)
end
function A.remove(m)
  T.dialog({
    title = "Remove from guild", accept = "Remove",
    text = "Remove " .. m.name .. " from the guild?",
    command = function() return ns.guildSlash("remove", m.full) end,
  })
end
-- Blizzard's Guild Control: rank names and permissions, adding and removing ranks, guild bank tabs.
function A.guildControl()
  if GuildControlUI_Show then GuildControlUI_Show() return end
  if UIParentLoadAddOn then try(UIParentLoadAddOn, "Blizzard_GuildControlUI") end
  if GuildControlUI then ShowUIPanel(GuildControlUI) else say("Guild Control isn't available on this client.") end
end
function A.canGuildControl() return (try(IsGuildLeader) or try(CanGuildPromote)) and true or false end
function A.leader(m)
  T.dialog({
    title = "Make guild leader", accept = "Make leader",
    text = "Make " .. m.name .. " the Guild Master? You'll step down to the rank below.",
    command = function() return ns.guildSlash("leader", m.full) end,
  })
end
function A.invite()
  T.dialog({
    title = "Invite to guild", text = "Their character name (First-Surname works too).", accept = "Invite",
    input = { maxLetters = 48 },
    onAccept = function(name)
      name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-")
      if name ~= "" then act("invite " .. name, C_GuildInfo.Invite, name) end
    end,
  })
end
function A.leave()
  local leader = try(IsGuildLeader)
  T.dialog({
    title = "Leave guild", accept = "Leave",
    text = leader and "You're the Guild Master: make someone else leader first, or disband the guild."
      or ("Leave <" .. safe(ns.guildName() or "") .. ">?"),
    command = not leader and function() return ns.guildSlash("leave") end or nil,
  })
end
function A.disband()
  T.dialog({
    title = "Disband guild", accept = "Disband",
    text = "Disband <" .. safe(ns.guildName() or "") .. ">? Everyone is removed and the guild is gone for good.\n\nType DISBAND to confirm.",
    input = { maxLetters = 7 },
    command = function(text) return (text or ""):upper() == "DISBAND" and ns.guildSlash("disband") or nil end,
    okUsable = function(text) return text:upper() == "DISBAND" end, okWhy = "Type DISBAND first.",
  })
end
ns.guildActions = A

-- Sorted by the last column (online first, then most recently seen) until a header is clicked.
local R = { showOffline = true, alts = false, filter = "", sort = 8, desc = false, selected = nil }

-- ---------- right-click menu ----------

local function memberMenu(owner, m)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  local r = rights(m)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(m.name)
    if not m.isSelf then
      root:CreateButton("Whisper", function() A.whisper(m) end)
      local inv = root:CreateButton("Invite to group", function() A.groupInvite(m) end)
      if not m.online then inv:SetEnabled(false) end
    end
    if ns.players()[m.name] then
      root:CreateButton("View profile", function() ns.selected = m.name; ns.showTab("Character") end)
    end
    -- Rank changes need a real click on a button (the game's rule), so the menu opens the member panel for them.
    if r.promote or r.demote then root:CreateButton("Change rank…", function() R.selected = m.guid; ns.refreshUI(true) end) end
    if r.leader then root:CreateButton("Make guild leader", function() A.leader(m) end) end
    if r.remove then root:CreateButton(color(T.HEX.danger, "Remove from guild"), function() A.remove(m) end) end
    if m.isSelf then root:CreateButton(color(T.HEX.danger, "Leave guild"), function() A.leave() end) end
  end)
end

-- ---------- member panel ----------


local function noteBox(parent, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(46)
  b.label = T.text(b, "label"); b.label:SetPoint("TOPLEFT"); b.label:SetText(label:upper())
  local bg = T.fill(b, "BACKGROUND", T.C.ink, 0.55)
  bg:SetPoint("TOPLEFT", 0, -14); bg:SetPoint("BOTTOMRIGHT")
  local edge = CreateFrame("Frame", nil, b); edge:SetPoint("TOPLEFT", 0, -14); edge:SetPoint("BOTTOMRIGHT")
  b.edge = T.outline(edge, 0, T.C.gold, 0.22)
  b.text = T.text(b, "small")
  b.text:SetPoint("TOPLEFT", 9, -21); b.text:SetPoint("RIGHT", -9, 0)
  local hl = T.fill(b, "HIGHLIGHT", T.C.gold, 0.08)
  hl:SetPoint("TOPLEFT", 0, -14); hl:SetPoint("BOTTOMRIGHT")
  return b
end

-- The member panel: the site's character header in miniature (name, surname, badges), their notes and alts, and
-- what you can do, two buttons to a row along the bottom.
local function buildPanel(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetWidth(256)
  p:SetPoint("TOPRIGHT"); p:SetPoint("BOTTOMRIGHT")
  local bg = T.gradient(p, "BACKGROUND", "VERTICAL", T.C.midnight, 1, T.C.royal, 1); bg:SetAllPoints()
  T.outline(p, 0, T.C.gold, 0.45)
  p:SetClipsChildren(true)
  local mark = p:CreateTexture(nil, "BORDER")
  mark:SetTexture(T.CREST); mark:SetSize(150, 150); mark:SetPoint("TOPRIGHT", 36, 32); mark:SetAlpha(0.07)
  p.bar = T.fill(p, "ARTWORK", { 1, 1, 1 }, 1); p.bar:SetPoint("TOPLEFT", 1, -1); p.bar:SetPoint("BOTTOMLEFT", 1, 1); p.bar:SetWidth(3)
  p:Hide()
  local close = T.closeButton(p, function() R.selected = nil; ns.refreshUI(true) end)
  close:SetPoint("TOPRIGHT", -4, -4)
  p.name = T.text(p, "name"); p.name:SetPoint("TOPLEFT", 16, -16); p.name:SetPoint("RIGHT", -34, 0)
  p.surname = T.text(p, "surname"); p.surname:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -2)
  p.badges = {}
  for i = 1, 3 do p.badges[i] = T.badge(p) end
  p.badges[1]:SetPoint("TOPLEFT", p.surname, "BOTTOMLEFT", 0, -9)
  p.badges[2]:SetPoint("LEFT", p.badges[1], "RIGHT", 5, 0)
  p.badges[3]:SetPoint("LEFT", p.badges[2], "RIGHT", 5, 0)
  p.line1 = T.text(p, "small"); p.line1:SetPoint("TOPLEFT", p.badges[1], "BOTTOMLEFT", 0, -9); p.line1:SetPoint("RIGHT", -14, 0)
  p.line2 = T.text(p, "muted"); p.line2:SetPoint("TOPLEFT", p.line1, "BOTTOMLEFT", 0, -3); p.line2:SetPoint("RIGHT", -14, 0)
  p.note = noteBox(p, "Public note")
  p.note:SetPoint("TOPLEFT", p.line2, "BOTTOMLEFT", 0, -11); p.note:SetPoint("RIGHT", -16, 0)
  ns.opensBlizzardGuild(p.note, "Edit notes", "The game only lets Blizzard's guild window change notes. This opens it: click the member there, then their note.")
  p.officer = noteBox(p, "Officer note")
  p.officer:SetPoint("TOPLEFT", p.note, "BOTTOMLEFT", 0, -8); p.officer:SetPoint("RIGHT", -16, 0)
  ns.opensBlizzardGuild(p.officer, "Edit notes", "The game only lets Blizzard's guild window change notes. This opens it: click the member there, then their note.")
  p.altsLabel = T.text(p, "label"); p.altsLabel:SetText("ALSO PLAYS")
  p.alts = {}
  -- Buttons, two to a row from the bottom up, laid out by render.
  p.buttons = {
    whisper = T.button(p, "Whisper", 108, function() A.whisper(R.member) end),
    group = T.button(p, "Invite", 108, function() A.groupInvite(R.member) end, "tab"),
    promote = T.button(p, "Promote", 108, function() end, "tab"),
    demote = T.button(p, "Demote", 108, function() end, "tab"),
    profile = T.button(p, "Profile", 108, function() ns.selected = R.member.name; ns.showTab("Character") end, "tab"),
    leader = T.button(p, "Make leader", 108, function() A.leader(R.member) end, "tab"),
    remove = T.button(p, "Remove", 108, function() A.remove(R.member) end, "tab"),
    leave = T.button(p, "Leave guild", 108, function() A.leave() end, "tab"),
  }
  ns.secureGuildCommand(p.buttons.promote, function() return A.stepCommand(R.member, -1) end, "Promote", nil, refreshSoon)
  ns.secureGuildCommand(p.buttons.demote, function() return A.stepCommand(R.member, 1) end, "Demote", nil, refreshSoon)
  for _, k in ipairs({ "remove", "leave" }) do
    local b = p.buttons[k]
    b.edge:SetColor({ 1, 0.54, 0.48 }, 0.55)
    b.label:SetTextColor(1, 0.54, 0.48)
  end
  return p
end

local function renderPanel(p, m, others, info)
  R.member = m
  local r = rights(m)
  local first, surname = m.name:match("^(%S+)%s+(.+)$")
  p.name:SetText(color(ns.classColor(m.classFile), safe(first or m.name)))
  p.surname:SetText(surname and safe(surname) or "")
  local rgb = ns.classRGB(m.classFile)
  p.bar:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
  p.badges[1]:Set("Level", m.level or "?", true)
  p.badges[2]:Set(nil, safe(m.rank), m.rankOrder <= 2)
  p.badges[3]:SetShown(info and info.ilvl ~= nil)
  if info and info.ilvl then p.badges[3]:Set("iLvl", info.ilvl) end
  local spec = info and info.spec ~= "" and (info.spec .. " ") or ""
  p.line1:SetText(spec .. safe(m.className or ""))
  p.line2:SetText((m.zone ~= "" and (safe(m.zone) .. "  ·  ") or "") .. lastOnlineText(m))
  p.note.text:SetText(m.note ~= "" and safe(m.note) or (r.publicNote and color(T.HEX.dim, "Add one in Blizzard's guild window") or color(T.HEX.dim, "—")))
  p.note:EnableMouse(r.publicNote and true or false)
  p.officer:SetShown(r.viewOfficer and true or false)
  p.officer.text:SetText(m.officerNote ~= "" and safe(m.officerNote) or (r.officerNote and color(T.HEX.dim, "Add one in Blizzard's guild window") or color(T.HEX.dim, "—")))
  p.officer:EnableMouse(r.officerNote and true or false)
  -- Also plays
  local anchor = r.viewOfficer and p.officer or p.note
  for _, fs in ipairs(p.alts) do fs:Hide() end
  p.altsLabel:SetShown(#others > 0)
  if #others > 0 then
    p.altsLabel:ClearAllPoints(); p.altsLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -11)
    local prev = p.altsLabel
    for i, o in ipairs(others) do
      if i > 4 then break end
      local fs = p.alts[i]
      if not fs then fs = T.text(p, "small"); p.alts[i] = fs end
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -5 or -2); fs:SetPoint("RIGHT", -16, 0)
      fs:SetText(color(ns.classColor(o.classFile), safe(o.name)) .. color(T.HEX.muted, "   Level " .. (o.level or "?")) .. (o.online and color(T.HEX.ok, "  online") or ""))
      fs:Show()
      prev = fs
    end
  end
  local show = {
    -- Promote and Demote stay put for officers (greyed out when that move isn't possible) so the panel doesn't shift.
    whisper = not m.isSelf, group = not m.isSelf, promote = r.ranks, demote = r.ranks,
    profile = true, leader = r.leader, remove = r.remove, leave = m.isSelf,
  }
  -- Fixed pairs, one pair per row, so related buttons stay side by side whatever else is shown.
  local PAIRS = { { "whisper", "group" }, { "promote", "demote" }, { "profile", "leader" }, { "remove", "leave" } }
  local rowsShown = {}
  for _, pair in ipairs(PAIRS) do
    local row = {}
    for _, key in ipairs(pair) do
      if show[key] then row[#row + 1] = key else p.buttons[key]:Hide() end
    end
    if #row > 0 then rowsShown[#rowsShown + 1] = row end
  end
  -- Our own arrows (Media/arrow-*.tga, tinted gold): the button font has no arrow characters.
  local function arrow(dir) return "|TInterface\\AddOns\\Perpetua\\Media\\arrow-" .. dir .. ":9:9:0:0:32:32:0:32:0:32:212:175:55|t " end
  p.buttons.promote.label:SetText(r.promote and (arrow("up") .. rankName(m.rankOrder - 1):upper()) or "PROMOTE")
  p.buttons.demote.label:SetText(r.demote and (arrow("down") .. rankName(m.rankOrder + 1):upper()) or "DEMOTE")
  -- Profile is always there, greyed out for members without the addon (nothing to show yet).
  local rec = ns.players()[m.name]
  p.buttons.profile:SetUsable(type(rec) == "table" and rec.profile ~= nil,
    m.name .. " doesn't have the Perpetua addon yet (or hasn't been online with it), so there's no profile to show.")
  p.buttons.promote:SetUsable(r.promote, "Can't promote " .. m.name .. " further: the next rank up is yours or above, or your rank can't promote.")
  p.buttons.demote:SetUsable(r.demote, m.rankOrder >= (ns.num(try(GuildControlGetNumRanks)) or 0)
    and (m.name .. " is already at the lowest rank.") or ("Can't demote " .. m.name .. ": your rank can't demote."))
  p.buttons.group:SetUsable(m.online, m.name .. " is offline.")
  local rows = #rowsShown
  for row, keys in ipairs(rowsShown) do
    for col, key in ipairs(keys) do
      local b = p.buttons[key]
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", 16 + (col - 1) * 116, 14 + (rows - row) * 32)
      b:Show()
    end
  end
  p:Show()
end

-- ---------- the Guild list ----------
-- One list: everyone on the guild roster (rank, note, last online, the officer tools) with what guild sync knows
-- about them (spec, item level, professions, raid attunements, alts).

-- Builds the Guild page: controls along the top, the list, and the member panel.
function ns.buildRoster(page)
  local bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(28)
  local area = CreateFrame("Frame", nil, page)
  area:SetPoint("TOPLEFT", 0, -38); area:SetPoint("BOTTOMRIGHT")
  R.area = area
  local holder = CreateFrame("Frame", nil, area)
  holder:SetPoint("TOPLEFT"); holder:SetPoint("BOTTOMRIGHT")
  R.holder = holder
  R.list = ns.List(holder, {
    { "Name", 146 }, { "Lvl", 26, "RIGHT" }, { "Rank", 102, pill = true }, { "Spec", 104 }, { "iLvl", 30, "RIGHT" },
    { "Professions", 108 }, { "Note", 86 }, { "Last on", 62, "RIGHT" },
  }, function(i)
    if R.sort == i then R.desc = not R.desc else R.sort, R.desc = i, (i == 2 or i == 5) end
    ns.refreshUI(true)
  end)
  R.list.header:SetClipsChildren(true)
  R.panel = buildPanel(area)

  R.search = T.searchBox(bar, 170, "Search the guild…", function(t) R.filter = t:lower(); ns.refreshUI() end)
  R.search:SetPoint("TOPLEFT", 2, 0)
  local function toggle(label, key)
    local check = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetChecked(R[key])
    check:SetScript("OnClick", function(self)
      R[key] = self:GetChecked() and true or false
      try(C_GuildInfo.GuildRoster)
      ns.refreshUI(true)
    end)
    local text = T.text(bar, "muted"); text:SetText(label)
    return check, text
  end
  local c1, t1 = toggle("Show offline", "showOffline")
  local c2, t2 = toggle("Alts separately", "alts")
  c1:SetPoint("LEFT", R.search, "RIGHT", 12, 0); t1:SetPoint("LEFT", c1, "RIGHT", 2, 0)
  c2:SetPoint("LEFT", t1, "RIGHT", 12, 0); t2:SetPoint("LEFT", c2, "RIGHT", 2, 0)
  R.invite = T.button(bar, "+ Invite", 100, function() A.invite() end)
  R.invite:SetPoint("TOPRIGHT", -26, -1)
  R.control = T.button(bar, "Guild Control", 118, function() A.guildControl() end, "tab")
  R.blizzard = T.button(bar, "Blizzard UI", 100, function() end, "tab")
  ns.opensBlizzardGuild(R.blizzard, "Blizzard's guild window", "For what only Blizzard's window can do here: notes, the message of the day and guild info.")
  page:SetScript("OnShow", function() try(C_GuildInfo.GuildRoster) end)
end

-- Guild sync's knowledge of a player, for the list and the tooltip.
local function syncInfo(name)
  local rec = ns.players()[name]
  local p = type(rec) == "table" and rec.profile or nil
  local spec = p and p.spec and p.spec.n
  local cls = p and p.char and p.char.class
  if spec and cls and spec == cls then spec = nil end -- older addons sent Forever's class-named spec
  return {
    rec = type(rec) == "table" and rec or nil, profile = p,
    spec = spec and safe(spec) or "", ilvl = p and ns.avgItemLevel(p),
    profs = ns.professionsText(p), raids = ns.raidsText(p),
  }
end

local function addonStatus(info)
  local rec = info.rec
  if not rec then return color("5a6380", "no addon") end
  if not info.profile and rec.addon and ns.newer(ns.VERSION, rec.addon) then return color(T.HEX.warm, "old addon " .. safe(rec.addon)) end
  local stamp = math.max(rec.pt or 0, rec.rt or 0)
  return color(T.HEX.muted, "profile from " .. ns.ago(stamp > 0 and stamp or rec.heard))
end

local function rowTooltip(row, d)
  local m, info = d.member, d.info
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(T.classIcon(m.classFile) .. " " .. color(ns.classColor(m.classFile), safe(m.name)))
  local where = (m.zone ~= "" and safe(m.zone) or "") .. (m.zone ~= "" and "  ·  " or "") .. lastOnlineText(m)
  if where ~= "" then GameTooltip:AddLine(where, 0.64, 0.67, 0.79) end
  if m.note ~= "" then GameTooltip:AddLine("Note: " .. safe(m.note), 1, 1, 1, true) end
  if d.officer and m.officerNote ~= "" then GameTooltip:AddLine("Officer note: " .. safe(m.officerNote), 1, 1, 1, true) end
  if info.raids:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") ~= "" then GameTooltip:AddLine("Attuned: " .. info.raids, 1, 1, 1) end
  GameTooltip:AddLine(addonStatus(info), 1, 1, 1)
  if #d.others > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Also plays", T.C.gold[1], T.C.gold[2], T.C.gold[3])
    for _, o in ipairs(d.others) do
      GameTooltip:AddDoubleLine(T.classIcon(o.classFile) .. color(ns.classColor(o.classFile), safe(o.name)),
        (o.level and ("Level " .. o.level) or "") .. (o.online and "  online" or ""), 1, 1, 1, 0.64, 0.67, 0.79)
    end
  end
  GameTooltip:Show()
end

-- Before the roster has loaded (just after login), what guild sync heard, so the page isn't empty.
local function fromSync()
  local list = {}
  for name, rec in pairs(ns.players()) do
    if type(rec) == "table" then
      list[#list + 1] = { name = name, full = name, rank = "", rankOrder = 99, level = ns.levelOf(name, rec.level),
        classFile = rec.class, zone = "", note = "", officerNote = "", online = false, mobile = false,
        last = {}, away = 1e9, noRoster = true }
    end
  end
  return list
end

function ns.renderRoster()
  local all = members()
  if #all == 0 then all = fromSync() end
  local byName, names = {}, {}
  for _, m in ipairs(all) do byName[m.name] = m; names[#names + 1] = m.name end
  local groups = ns.accountGroups(names)

  -- One row per person unless "Alts separately": the character they're on now, else the one seen last.
  local shown, online = {}, 0
  for _, m in ipairs(all) do
    if m.online then online = online + 1 end
    local group = groups[m.name] or { m.name }
    if R.alts or #group == 1 then
      shown[#shown + 1] = { m = m, others = {} }
    else
      local best = m
      for _, n in ipairs(group) do
        local o = byName[n]
        if o and (o.away < best.away or (o.away == best.away and n < best.name)) then best = o end
      end
      if best == m then
        local others = {}
        for _, n in ipairs(group) do if n ~= m.name and byName[n] then others[#others + 1] = byName[n] end end
        shown[#shown + 1] = { m = m, others = others }
      end
    end
  end

  local officer = try(C_GuildInfo.CanViewOfficerNote)
  local rows, selected = {}, nil
  for _, row in ipairs(shown) do
    local m, others = row.m, row.others
    local info = syncInfo(m.name)
    if R.selected and m.guid == R.selected then selected = { m = m, others = others, info = info } end
    local anyOnline = m.online or m.mobile
    for _, o in ipairs(others) do anyOnline = anyOnline or o.online end
    local text = (m.name .. " " .. m.rank .. " " .. m.zone .. " " .. m.note .. " " .. (m.className or "") .. " "
      .. info.spec .. " " .. info.profs) :lower()
    for _, o in ipairs(others) do text = text .. " " .. o.name:lower() end
    if (R.showOffline or anyOnline) and (R.filter == "" or text:find(R.filter, 1, true)) then
      local dim = not m.online
      local extra = #others > 0 and color(T.HEX.muted, "  +" .. #others) or ""
      rows[#rows + 1] = {
        key = { m.name:lower(), m.level or 0, m.rankOrder, info.spec:lower(), info.ilvl or 0, info.profs:lower(), m.note:lower(), m.away },
        cells = {
          color(ns.classColor(m.classFile), safe(m.name)) .. extra,
          m.level and color(T.HEX.pale, m.level) or "", { m.rank ~= "" and m.rank or nil, m.rankOrder <= 2 },
          info.spec, info.ilvl or "", info.profs, color(T.HEX.muted, safe(m.note)), lastOnlineText(m),
        },
        bar = ns.classRGB(m.classFile), selected = ns.newGuildWindow() and R.selected ~= nil and m.guid == R.selected,
        member = m, info = info, others = others, officer = officer,
        onClick = function(d, button, r)
          -- Without the New guild window the list is just the list: a click opens their profile, as it always did.
          if d.member.noRoster or not ns.newGuildWindow() then
            if d.info.profile then ns.selected = d.member.name; ns.showTab("Character") end
            return
          end
          if button == "RightButton" then memberMenu(r, d.member) return end
          R.selected = (R.selected ~= d.member.guid) and d.member.guid or nil
          ns.refreshUI(true)
        end,
        onEnter = rowTooltip,
      }
    end
  end
  local k, desc = R.sort, R.desc
  table.sort(rows, function(a, b)
    local x, y = a.key[k], b.key[k]
    if x == y then return a.key[1] < b.key[1] end
    if desc then return x > y end
    return x < y
  end)
  local withAddon = 0
  for _, rec in pairs(ns.players()) do if type(rec) == "table" and rec.profile then withAddon = withAddon + 1 end end
  ns.setStats({ { #all, "members" }, { online, "online", "ok" }, { withAddon, "with the addon" } })
  -- Right end of the top bar, right to left: + Invite, Guild Control, Blizzard UI (only those that apply).
  local on = ns.newGuildWindow()
  local x = -26
  for _, item in ipairs({ { R.invite, on and try(CanGuildInvite) }, { R.control, on and A.canGuildControl() }, { R.blizzard, on } }) do
    local b, show = item[1], item[2] and true or false
    b:SetShown(show)
    if show then b:ClearAllPoints(); b:SetPoint("TOPRIGHT", x, -1); x = x - b:GetWidth() - 8 end
  end
  if not ns.newGuildWindow() then selected = nil end
  R.holder:SetPoint("BOTTOMRIGHT", selected and -268 or 0, 0)
  R.list:SetRows(rows)
  if selected then renderPanel(R.panel, selected.m, selected.others, selected.info) else R.panel:Hide(); R.selected = nil; R.member = nil end
  ns.lastRosterRows = rows -- for the test harness
end

-- ---------- Guild Info page ----------

local G = {}

local function scrollText(parent, fontKey)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(1, 1)
  scroll:SetScrollChild(child)
  local fs = T.text(child, fontKey or "body")
  fs:SetPoint("TOPLEFT"); fs:SetWordWrap(true); fs:SetJustifyV("TOP"); fs:SetNonSpaceWrap(true)
  scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w); fs:SetWidth(w) end)
  function scroll:SetText(text)
    fs:SetText(text)
    child:SetHeight(math.max(1, fs:GetStringHeight() + 4))
  end
  return scroll
end

-- A heading, with an Edit button that opens Blizzard's guild window (the only place the game allows the edit).
local function section(parent, title, editable)
  local h = T.text(parent, "heading"); h:SetText(title:upper())
  local edit = editable and T.button(parent, "Edit", 64, function() end, "tab") or nil
  if edit then
    edit:SetHeight(20); edit:SetPoint("LEFT", h, "RIGHT", 10, 0)
    ns.opensBlizzardGuild(edit, "Edit " .. title:lower(), "The game only lets Blizzard's guild window change this. This opens it: the Guild Info tab.")
  end
  return h, edit
end

function ns.buildGuildInfo(page)
  local left = CreateFrame("Frame", nil, page)
  left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT", 0, 46); left:SetWidth(360)
  local right = CreateFrame("Frame", nil, page)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 24, 0); right:SetPoint("BOTTOMRIGHT", 0, 46)

  local h1, e1 = section(left, "Message of the day", true)
  h1:SetPoint("TOPLEFT", 2, 0)
  G.motdEdit = e1
  local motdBox = CreateFrame("Frame", nil, left); T.panel(motdBox)
  motdBox:SetPoint("TOPLEFT", 0, -22); motdBox:SetPoint("RIGHT"); motdBox:SetHeight(90)
  G.motd = scrollText(motdBox); G.motd:SetPoint("TOPLEFT", 10, -8); G.motd:SetPoint("BOTTOMRIGHT", -28, 8)

  local h2, e2 = section(left, "Guild information", true)
  h2:SetPoint("TOPLEFT", motdBox, "BOTTOMLEFT", 2, -18)
  G.infoEdit = e2
  local infoBox = CreateFrame("Frame", nil, left); T.panel(infoBox)
  infoBox:SetPoint("TOPLEFT", motdBox, "BOTTOMLEFT", 0, -40); infoBox:SetPoint("BOTTOMRIGHT")
  G.info = scrollText(infoBox); G.info:SetPoint("TOPLEFT", 10, -8); G.info:SetPoint("BOTTOMRIGHT", -28, 8)

  local h3 = section(right, "Guild log")
  h3:SetPoint("TOPLEFT", 2, 0)
  local logBox = CreateFrame("Frame", nil, right); T.panel(logBox)
  logBox:SetPoint("TOPLEFT", 0, -22); logBox:SetPoint("BOTTOMRIGHT")
  G.log = scrollText(logBox, "small"); G.log:SetPoint("TOPLEFT", 10, -8); G.log:SetPoint("BOTTOMRIGHT", -28, 8)

  -- Bottom row: the New guild window switch (also at the top of the window), then leave / disband.
  local switch = T.switch(page, function(on) ns.setNewGuildWindow(on, true) end)
  switch:SetPoint("BOTTOMLEFT", 2, 8)
  G.switch = switch
  local sl = T.text(page, "small"); sl:SetPoint("LEFT", switch, "RIGHT", 10, 0)
  sl:SetText("New guild window")
  local hint = T.text(page, "muted"); hint:SetPoint("LEFT", sl, "RIGHT", 8, 0)
  hint:SetText("(the guild key and button open this; Shift for Blizzard's)")
  G.control = T.button(page, "Guild Control", 130, function() A.guildControl() end, "tab")
  G.disband = T.button(page, "Disband", 100, function() A.disband() end, "tab")
  G.disband:SetPoint("BOTTOMRIGHT", 0, 4)
  G.leave = T.button(page, "Leave guild", 120, function() A.leave() end, "tab")
  G.leave:SetPoint("RIGHT", G.disband, "LEFT", -10, 0)
  G.control:SetPoint("RIGHT", G.leave, "LEFT", -10, 0)
  G.leave.label:SetTextColor(1, 0.54, 0.48); G.disband.label:SetTextColor(1, 0.54, 0.48)
  G.shown = false
  page:SetScript("OnShow", function() try(QueryGuildEventLog); try(C_GuildInfo.GuildRoster) end)
end

local LOG = {
  invite = "GUILDEVENT_TYPE_INVITE", join = "GUILDEVENT_TYPE_JOIN", promote = "GUILDEVENT_TYPE_PROMOTE",
  demote = "GUILDEVENT_TYPE_DEMOTE", remove = "GUILDEVENT_TYPE_REMOVE", quit = "GUILDEVENT_TYPE_QUIT",
}

function ns.renderGuildInfo()
  local motd = try(C_GuildInfo.GetMOTD) or ""
  local info = try(C_GuildInfo.GetInfoText) or ""
  G.motd:SetText(motd ~= "" and safe(motd) or color(T.HEX.muted, "No message of the day."))
  G.info:SetText(info ~= "" and safe(info) or color(T.HEX.muted, "No guild information yet."))
  G.motdEdit:SetShown(try(CanEditMOTD) and true or false)
  G.infoEdit:SetShown(try(CanEditGuildInfo) and true or false)
  local lines = {}
  for i = (ns.num(try(GetNumGuildEvents)) or 0), 1, -1 do
    local kind, p1, p2, rank, y, mo, d, h = try(GetGuildEventInfo, i)
    local fmt = LOG[kind or ""] and _G[LOG[kind]]
    if fmt then
      local a, b = ns.playerKey(ns.text(p1)) or UNKNOWN, ns.playerKey(ns.text(p2)) or UNKNOWN
      local ok, msg = pcall(string.format, fmt, a, b, ns.text(rank) or "")
      if ok then
        local when = TimeUtil and try(TimeUtil.GetRecentTimeDate, y, mo, d, h)
        lines[#lines + 1] = safe(msg) .. (when and color(T.HEX.muted, "  " .. when) or "")
      end
    end
  end
  G.log:SetText(#lines > 0 and table.concat(lines, "\n") or color(T.HEX.muted, "Nothing in the log yet."))
  G.switch:SetOn(ns.newGuildWindow())
  G.disband:SetShown(try(IsGuildLeader) and true or false)
  G.control:SetShown(A.canGuildControl())
  -- Leave / Guild Control shift right when Disband isn't there.
  G.leave:ClearAllPoints()
  if G.disband:IsShown() then G.leave:SetPoint("RIGHT", G.disband, "LEFT", -10, 0) else G.leave:SetPoint("BOTTOMRIGHT", 0, 4) end
end

-- Redraw when the guild changes.
local ev = CreateFrame("Frame")
for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "GUILD_MOTD", "GUILD_EVENT_LOG_UPDATE", "GUILD_RANKS_UPDATE", "PLAYER_GUILD_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
-- Which pages show what these events change; other pages aren't redrawn for them.
local SHOWS = {
  GUILD_ROSTER_UPDATE = { Guild = true, ["Guild Info"] = true }, GUILD_RANKS_UPDATE = { Guild = true, ["Guild Info"] = true },
  GUILD_MOTD = { ["Guild Info"] = true }, GUILD_EVENT_LOG_UPDATE = { ["Guild Info"] = true },
}
ev:SetScript("OnEvent", function(_, event, arg1)
  -- Blizzard's member panel asks for a fresh roster when the update says it may.
  if event == "GUILD_ROSTER_UPDATE" and arg1 and PerpetuaFrame and PerpetuaFrame:IsShown() then try(C_GuildInfo.GuildRoster) end
  local pages = SHOWS[event]
  if pages and not pages[ns.currentTabForTest and ns.currentTabForTest() or ""] then return end
  ns.refreshUI()
end)

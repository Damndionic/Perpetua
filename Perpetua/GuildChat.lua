-- Guild Chat page: the guild chat log Blizzard's guild window shows (history from before you logged in included),
-- with Guild and Officer tabs and a box to type in, so the Perpetua guild window doesn't lose Blizzard's chat pane.
--
-- The log is the guild's "club" stream, read the way Blizzard_Communities/CommunitiesChatFrame.lua does: focus the
-- stream, ask for history when none is loaded (C_Club.RequestMoreMessagesBefore), then C_Club.GetMessagesBefore
-- the newest message; CLUB_MESSAGE_ADDED adds new ones, CLUB_MESSAGE_HISTORY_RECEIVED older ones. Reading isn't
-- restricted on the Forever client.
--
-- Sending: C_Club.SendMessage (what Blizzard's pane uses) is marked restricted. It's tried from the Enter key (a
-- real key press); if the game refuses it (an error, or ADDON_ACTION_BLOCKED / FORBIDDEN naming us), the message
-- goes into your normal chat box as "/g ..." (or "/o ...") so pressing Enter there sends it, and the box says so from
-- then on (per kind of place: the world, dungeons, raids... can differ).
--
-- In combat in instances the game may hand addons "secret" text: it can be shown, not read, so those lines are
-- shown as they come and never searched or changed.
local _, ns = ...
local try, safe, T = ns.try, ns.safe, ns.T

local MAX_LINES = 500
local PER_REQUEST = 100 -- history asked for at a time (Blizzard's pane uses the same)
local GUILD, OFFICERS = 1, 2 -- Enum.ClubStreamType

local function color(hex, s) return "|cff" .. hex .. s .. "|r" end
local function secret(v) return issecretvalue and issecretvalue(v) or false end

local GC = { kind = GUILD, unread = 0, blockedIn = {}, oldest = nil, shownStream = nil }
ns.guildChat = GC

-- ---------- club and streams ----------

local function clubId() return C_Club and try(C_Club.GetGuildClubId) end

local function streamOf(kind)
  local club = clubId()
  if not club then return nil end
  for _, s in ipairs(try(C_Club.GetStreams, club) or {}) do
    if s.streamType == kind then return s.streamId end
  end
end

-- Officer chat for those who can see it: the server only lists the stream for ranks with officer chat, and the
-- addon's own officer check backs that up.
local function canOfficer()
  return streamOf(OFFICERS) ~= nil and (try(C_GuildInfo.CanViewOfficerNote) or try(IsGuildLeader)) and true or false
end

-- ---------- formatting ----------

local classByID = {}
local function classFileOf(classID)
  if not classID then return nil end
  if classByID[classID] == nil then
    local info = C_CreatureInfo and try(C_CreatureInfo.GetClassInfo, classID)
    classByID[classID] = info and info.classFile or false
  end
  return classByID[classID] or nil
end

-- "First-Surname" or "First Surname" from the club: the addon's own key ("First Surname").
local function nameKey(name) return name and ns.playerKey(name) or nil end

local function dayOf(epoch) return date("%Y-%m-%d", math.floor(epoch / 1000000)) end

local function dayLabel(epoch)
  local t = math.floor(epoch / 1000000)
  local today, yesterday = date("%Y-%m-%d"), date("%Y-%m-%d", time() - 86400)
  local d = date("%Y-%m-%d", t)
  if d == today then return "Today" elseif d == yesterday then return "Yesterday" end
  return date("%A %b %d", t)
end

-- One message as a chat line: time, the name (class coloured, clickable: our own "addon:" link), the text.
local function format(m)
  local author = m.author or {}
  local name = author.name
  local key = nameKey(name)
  local who
  if key then
    local shown = color(ns.classColor(classFileOf(author.classID)), safe(key))
    who = "|Haddon:perpetua:player:" .. key .. "|h" .. shown .. "|h"
  else
    who = color(T.HEX.muted, "someone")
  end
  local stamp = m.messageId and m.messageId.epoch and color(T.HEX.dim, date("%H:%M", math.floor(m.messageId.epoch / 1000000))) .. "  " or ""
  if m.destroyed then return stamp .. who .. color(T.HEX.dim, "  (message removed)") end
  local content = m.content
  if secret(content) then return nil, stamp .. who .. ": ", content end -- shown as is, never changed
  return stamp .. who .. ": " .. (content or "") .. (m.edited and color(T.HEX.dim, "  (edited)") or "")
end

-- ---------- the log ----------

local log -- the ScrollingMessageFrame
local lastDay -- the day of the newest line shown, for "Today" / "Yesterday" separators

local function addSeparator(epoch, backfill)
  local text = color(T.HEX.gold, "—  " .. dayLabel(epoch) .. "  —")
  if backfill then log:BackFillMessage(text) else log:AddMessage(text) end
end

-- Lines in the colour your chat window uses for guild / officer chat (green by default).
local function chatColor()
  local info = ChatTypeInfo and ChatTypeInfo[GC.kind == OFFICERS and "OFFICER" or "GUILD"]
  if info and info.r then return info.r, info.g, info.b end
  return T.C.text[1], T.C.text[2], T.C.text[3]
end

local function addMessage(m, backfill)
  local fn = backfill and log.BackFillMessage or log.AddMessage
  local cr, cg, cb = chatColor()
  local function put(_, text) return fn(log, text, cr, cg, cb) end
  local ok, line, prefix, secretText = pcall(format, m) -- a hidden (secret) name can't be worked with either
  if not ok then pcall(put, log, color(T.HEX.dim, "(hidden by the game until combat ends)")) return end
  if line then
    if not pcall(put, log, line) then pcall(put, log, color(T.HEX.dim, "(a message the addon can't show)")) end
    return
  end
  -- Secret text: shown as the game hands it over. Joined to the name if the game allows that, else on its own
  -- line under the name, else a note that the game is hiding it.
  if pcall(function() put(log, prefix .. secretText) end) then return end -- the join itself may be refused
  if backfill then
    if pcall(put, log, secretText) then pcall(put, log, prefix) return end
  else
    pcall(put, log, prefix)
    if pcall(put, log, secretText) then return end
  end
  pcall(put, log, color(T.HEX.dim, "(hidden by the game until combat ends)"))
end

-- Everything loaded for the current stream, oldest first, with a separator where the day changes.
local function messagesToShow(club, stream)
  local ranges = try(C_Club.GetMessageRanges, club, stream)
  local r = ranges and ranges[#ranges]
  if not r or r.newestMessageId.epoch < r.oldestMessageId.epoch then return nil end
  return try(C_Club.GetMessagesBefore, club, stream, r.newestMessageId, PER_REQUEST)
end

local function redraw()
  if not log then return end
  log:Clear()
  lastDay, GC.oldest = nil, nil
  local club, stream = clubId(), streamOf(GC.kind)
  -- Tell the game which stream is being watched (it sends its new messages), as Blizzard's pane does.
  if club and GC.shownStream ~= stream then
    if GC.shownStream then try(C_Club.UnfocusStream, club, GC.shownStream) end
    if stream then try(C_Club.FocusStream, club, stream) end
  end
  GC.shownStream = stream
  if not (club and stream) then
    log:AddMessage(color(T.HEX.muted, "Guild chat isn't available yet (the game is still loading the guild). It shows up in a moment."))
    return
  end
  local msgs = messagesToShow(club, stream)
  if not msgs or #msgs == 0 then
    log:AddMessage(color(T.HEX.muted, "Loading the chat history…"))
    try(C_Club.RequestMoreMessagesBefore, club, stream, nil, PER_REQUEST)
    return
  end
  for _, m in ipairs(msgs) do
    local epoch = m.messageId and m.messageId.epoch
    if epoch and dayOf(epoch) ~= lastDay then addSeparator(epoch); lastDay = dayOf(epoch) end
    addMessage(m)
  end
  GC.oldest = msgs[1].messageId
  GC.older:SetUsable(true)
  try(C_Club.AdvanceStreamViewMarker, club, stream)
end

-- Older history, put above what's shown.
local function loadOlder()
  local club, stream = clubId(), GC.shownStream
  if not (club and stream and GC.oldest) then return end
  if try(C_Club.IsBeginningOfStream, club, stream, GC.oldest) then
    GC.older:SetUsable(false, "That's the start of the chat history.")
    return
  end
  local have = try(C_Club.RequestMoreMessagesBefore, club, stream, GC.oldest, PER_REQUEST)
  -- Not loaded yet: it arrives with CLUB_MESSAGE_HISTORY_RECEIVED, which calls this again once (wantOlder), so
  -- one click loads one batch and history never pages back by itself.
  if not have then GC.wantOlder = true return end
  GC.wantOlder = false
  local msgs = try(C_Club.GetMessagesBefore, club, stream, GC.oldest, PER_REQUEST) or {}
  local last = #msgs
  if last > 0 and msgs[last].messageId.epoch == GC.oldest.epoch and msgs[last].messageId.position == GC.oldest.position then last = last - 1 end
  for i = last, 1, -1 do addMessage(msgs[i], true) end
  if msgs[1] then GC.oldest = msgs[1].messageId end
end

-- ---------- sending ----------

local function placeKind()
  local _, kind = try(IsInInstance)
  return kind and kind ~= "none" and kind or "world"
end

-- Your normal chat box, with the message after /g or /o: Enter there sends it, through Blizzard's own code.
local function handOff(text)
  local slash = GC.kind == OFFICERS and "/o " or "/g "
  if ChatFrameUtil and ChatFrameUtil.OpenChat then pcall(ChatFrameUtil.OpenChat, slash .. text)
  elseif ChatFrame_OpenChat then pcall(ChatFrame_OpenChat, slash .. text) end
end

local sending = false
local function send(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return end
  if GC.kind == GUILD and try(C_GuildInfo.CanSpeakInGuildChat) == false then
    log:AddMessage(color(T.HEX.danger, "Your rank can't speak in guild chat."))
    return
  end
  local where = placeKind()
  if GC.blockedIn[where] or InCombatLockdown() then handOff(text) return end
  local club, stream = clubId(), streamOf(GC.kind)
  if not (club and stream and C_Club.SendMessage) then handOff(text) return end
  sending, GC.refused = true, false
  local ok = pcall(C_Club.SendMessage, club, stream, text)
  sending = false
  if not ok or GC.refused then
    GC.blockedIn[where] = true
    ns.refreshUI(true)
    handOff(text)
  end
end

local guard = CreateFrame("Frame")
pcall(guard.RegisterEvent, guard, "ADDON_ACTION_BLOCKED")
pcall(guard.RegisterEvent, guard, "ADDON_ACTION_FORBIDDEN")
guard:SetScript("OnEvent", function(_, _, addon) if sending and addon == "Perpetua" then GC.refused = true end end)

-- ---------- the page ----------

local function onLink(_, link, text, button)
  local key = type(link) == "string" and link:match("^addon:perpetua:player:(.+)$")
  if key then
    if button == "RightButton" and ns.guildMemberMenu and ns.guildMemberMenu(GC.page, key) then return end
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if tell then pcall(tell, key) end
    return
  end
  -- Items and the like: shift-click puts the link in the box, a click shows it like chat does.
  if IsModifiedClick and IsModifiedClick("CHATLINK") and GC.box:HasFocus() then GC.box:Insert(text) return end
  if SetItemRef then pcall(SetItemRef, link, text, button) end
end

function ns.buildGuildChat(page)
  GC.page = page
  -- Guild / Officer tabs on the left, "Older messages" and Blizzard's window on the right.
  GC.tabs = {}
  local x = 0
  for _, t in ipairs({ { GUILD, "Guild" }, { OFFICERS, "Officer" } }) do
    local b = T.button(page, t[2], 100, function() GC.kind = t[1]; GC.unread = 0; redraw(); ns.refreshUI(true) end, "tab")
    b:SetPoint("TOPLEFT", x, 0)
    GC.tabs[t[1]] = b
    x = x + 108
  end
  GC.blizzard = T.button(page, "Blizzard UI", 100, function() end, "tab")
  GC.blizzard:SetPoint("TOPRIGHT", -2, 0)
  if ns.opensBlizzardGuild then ns.opensBlizzardGuild(GC.blizzard, "Blizzard's guild window", "Its chat pane, and everything else in Blizzard's guild window.") end
  GC.older = T.button(page, "Older messages", 140, loadOlder, "tab")
  GC.older:SetPoint("RIGHT", GC.blizzard, "LEFT", -8, 0)

  local box = CreateFrame("Frame", nil, page)
  box:SetPoint("TOPLEFT", 0, -36); box:SetPoint("BOTTOMRIGHT", 0, 40)
  T.panel(box)
  log = CreateFrame("ScrollingMessageFrame", nil, box)
  log:SetPoint("TOPLEFT", 12, -10); log:SetPoint("BOTTOMRIGHT", -12, 10)
  log:SetFontObject(T.fonts.small)
  log:SetJustifyH("LEFT")
  log:SetFading(false)
  log:SetMaxLines(MAX_LINES)
  log:SetHyperlinksEnabled(true)
  if log.SetIndentedWordWrap then log:SetIndentedWordWrap(true) end
  log:EnableMouseWheel(true)
  log:SetScript("OnMouseWheel", function(self, delta)
    if IsShiftKeyDown() then if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
    elseif delta > 0 then self:ScrollUp(); self:ScrollUp() else self:ScrollDown(); self:ScrollDown() end
  end)
  log:SetScript("OnHyperlinkClick", onLink)
  log:SetScript("OnHyperlinkEnter", function(self, link)
    if type(link) ~= "string" or link:find("^addon:") then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
  end)
  log:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  GC.log = log

  GC.box = T.searchBox(page, 100, "", function() end)
  GC.box:SetPoint("BOTTOMLEFT", 0, 6); GC.box:SetPoint("BOTTOMRIGHT", 0, 6)
  GC.box:SetMaxLetters(255)
  GC.box:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    self:SetText("")
    send(text)
  end)
  GC.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  page:SetScript("OnShow", function()
    GC.unread = 0
    GC.shownStream = nil -- redraw focuses it again
    redraw()
  end)
  page:SetScript("OnHide", function()
    local club, stream = clubId(), GC.shownStream
    if club and stream then try(C_Club.UnfocusStream, club, stream) end
  end)
end

-- Text that changes: tabs, the box's hint (says when Enter hands off to the chat box).
function ns.renderGuildChat()
  local officer = canOfficer()
  if GC.kind == OFFICERS and not officer then GC.kind = GUILD; redraw() end
  GC.tabs[OFFICERS]:SetShown(officer)
  for kind, b in pairs(GC.tabs) do b:SetSelected(kind == GC.kind) end
  GC.blizzard:SetShown(ns.newGuildWindow and ns.newGuildWindow() or false)
  if not GC.blizzard:IsShown() then GC.older:ClearAllPoints(); GC.older:SetPoint("TOPRIGHT", -2, 0)
  else GC.older:ClearAllPoints(); GC.older:SetPoint("RIGHT", GC.blizzard, "LEFT", -8, 0) end
  local to = GC.kind == OFFICERS and "officers" or "guild"
  local handsOff = GC.blockedIn[placeKind()] or InCombatLockdown()
  GC.box:SetPlaceholder(handsOff and ("Message the " .. to .. " (Enter puts it in your chat box to send)") or ("Message the " .. to .. "… (Enter to send)"))
  if ns.setChatUnread then ns.setChatUnread(GC.unread) end
end

-- New lines while the page is open; a count on the sidebar while it isn't.
local ev = CreateFrame("Frame")
for _, e in ipairs({ "CLUB_MESSAGE_ADDED", "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_STREAMS_LOADED", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, club, stream, messageId)
  local open = GC.page and GC.page:IsVisible()
  if event == "CLUB_MESSAGE_ADDED" then
    if not (open and log and club == clubId() and stream == GC.shownStream) then return end
    local m = try(C_Club.GetMessageInfo, club, stream, messageId)
    if not m then return end
    local epoch = m.messageId and m.messageId.epoch
    if epoch and dayOf(epoch) ~= lastDay then addSeparator(epoch); lastDay = dayOf(epoch) end
    addMessage(m)
    try(C_Club.AdvanceStreamViewMarker, club, stream)
  elseif event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
    if open and club == clubId() and stream == GC.shownStream then
      if not GC.oldest then redraw() elseif GC.wantOlder then GC.wantOlder = false; loadOlder() end
    end
  elseif event == "CLUB_STREAMS_LOADED" then
    if open then redraw(); ns.refreshUI() end
  elseif not open and not ns.locked() then -- CHAT_MSG_GUILD / CHAT_MSG_OFFICER
    if event == "CHAT_MSG_OFFICER" and not canOfficer() then return end
    GC.unread = GC.unread + 1
    if ns.setChatUnread then ns.setChatUnread(GC.unread) end
  end
end)

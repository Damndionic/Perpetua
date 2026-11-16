-- The Shit List: enemy players the guild has marked. Officers add and remove names in game (Hit List tab, or
-- /ppta shitlist add First Surname - why); the list goes round the guild as part "S" of guild sync, and anyone on
-- it is flagged in their unit tooltip (a red banner and a red border) and in the group finder (a red row, and a
-- warning under the group's tooltip naming who in that group is on the list).
--
-- The list travels whole, stamped with when it last changed (t), so a removal travels as well as an addition.
-- Like the raid calendar it's only accepted from an officer (by guild rank), so nobody can put names on it or
-- wipe it. Two officers editing at once: the later edit wins.
local _, ns = ...

local MAX = 500        -- entries
local FUTURE = 600     -- seconds a stamp may be ahead of our clock
local NAME_MAX, WHY_MAX = 48, 120

local function store()
  local guild = ns.guildName()
  if not guild then return nil end
  ns.players(guild) -- makes the guild's table
  local g = PerpetuaDB.guilds[guild]
  if type(g.shitlist) ~= "table" or type(g.shitlist.list) ~= "table" then g.shitlist = { t = 0, list = {} } end
  return g.shitlist
end

-- The key for a name in any form the game gives it ("First Surname", "First-Surname", any case).
local function keyOf(name)
  name = ns.playerKey(ns.readable(name))
  if not name then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  return name ~= "" and name:lower() or nil
end
ns.shitlistKey = keyOf

-- "gankus maximus" -> "Gankus Maximus" (for names typed in lower case).
local function tidy(name)
  return (name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

function ns.shitlistVersion()
  local s = store()
  return s and (s.t or 0) > 0 and tostring(s.t) or nil
end

-- The entry for a player ({ n, r = why, by, at }), or nil.
function ns.shitlistEntry(name)
  local s, k = store(), keyOf(name)
  return s and k and s.list[k] or nil
end

-- Everyone on it, newest first.
function ns.shitlistEntries()
  local out, s = {}, store()
  for _, e in pairs(s and s.list or {}) do out[#out + 1] = e end
  table.sort(out, function(a, b)
    if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
    return (a.n or "") < (b.n or "")
  end)
  return out
end

function ns.canEditShitlist()
  return ns.selfName ~= nil and ns.isOfficer(ns.selfName)
end

local function changed()
  if ns.refreshGroupFinder then ns.refreshGroupFinder() end
  ns.fire()
  ns.announce()
end

-- Officers only. Returns true, or nil and why not.
function ns.shitlistAdd(name, why)
  if not ns.canEditShitlist() then return nil, "Only officers can change the Shit List." end
  local s, k = store(), keyOf(name)
  if not s then return nil, "Not in a guild yet." end
  if not k or #k > NAME_MAX then return nil, "Give a character name." end
  if ns.selfName and k == ns.selfName:lower() then return nil, "That's you." end
  local count = 0
  for _ in pairs(s.list) do count = count + 1 end
  if not s.list[k] and count >= MAX then return nil, "The list is full (" .. MAX .. ")." end
  why = why and why:gsub("^%s+", ""):gsub("%s+$", "") or ""
  s.list[k] = { n = tidy(ns.playerKey(name)), r = why ~= "" and why:sub(1, WHY_MAX) or nil, by = ns.selfName, at = ns.now() }
  s.t = math.max(ns.now(), (s.t or 0) + 1)
  changed()
  return true
end

function ns.shitlistRemove(name)
  if not ns.canEditShitlist() then return nil, "Only officers can change the Shit List." end
  local s, k = store(), keyOf(name)
  if not (s and k and s.list[k]) then return nil, "They're not on the list." end
  s.list[k] = nil
  s.t = math.max(ns.now(), (s.t or 0) + 1)
  changed()
  return true
end

-- What guild sync sends.
function ns.shitlistPayload()
  local s = store()
  if not s or (s.t or 0) == 0 then return nil end
  return { t = s.t, list = s.list }
end

-- A list from guild sync (already checked to come from an officer). Every field is checked: it's shown on screen.
function ns.adoptShitlist(data)
  local s = store()
  if not s or type(data) ~= "table" or type(data.list) ~= "table" then return false end
  local t = ns.num(data.t)
  if not t or t <= (s.t or 0) or t > ns.now() + FUTURE then return false end
  local list, count = {}, 0
  for _, e in pairs(data.list) do
    if count >= MAX then break end
    local k = type(e) == "table" and type(e.n) == "string" and #e.n <= NAME_MAX and keyOf(e.n)
    if k then
      list[k] = {
        n = e.n,
        r = type(e.r) == "string" and e.r:sub(1, WHY_MAX) or nil,
        by = type(e.by) == "string" and e.by:sub(1, NAME_MAX) or nil,
        at = ns.num(e.at),
      }
      count = count + 1
    end
  end
  s.t, s.list = t, list
  if ns.refreshGroupFinder then ns.refreshGroupFinder() end
  ns.fire()
  return true
end

-- ---------- adding and removing (dialogs and /ppta shitlist) ----------

-- "Gankus Maximus - camps the flight path": the name before " - " (or ":" / ","), else the first two words.
function ns.parseShitlistInput(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("^([^%s%-]+)%-([^%s%-])", "%1 %2", 1) -- "First-Surname" as the game writes it
  local name, why = text:match("^(.-)%s*[%-:,]%s+(.*)$")
  if not name or name == "" then
    name, why = text:match("^(%S+%s+%S+)%s*(.*)$")
    if not name then name, why = text, "" end
  end
  return name, why
end

local function targetName()
  if not ns.try(UnitIsPlayer, "target") then return nil end
  local first, surname = ns.try(UnitName, "target")
  first, surname = ns.readable(first), ns.readable(surname)
  return first and ns.fullName(first, surname) or nil
end

local function say(msg) print("|cffd4af37Perpetua|r " .. msg) end

function ns.promptShitlistAdd(prefill)
  local T = ns.T
  if not ns.canEditShitlist() then say("Only officers can change the Shit List.") return end
  local name = prefill or targetName()
  if name then
    -- From a portrait, a name in chat or your target: the name is known, so only ask why.
    T.dialog({
      title = "Add to the Shit List", accept = "Add",
      text = "Why is " .. ns.safe(name) .. " going on the Shit List? The reason shows in tooltips, the group finder and the Hit List.",
      input = { text = "", maxLetters = WHY_MAX },
      okUsable = function(t) return t:match("%S") ~= nil end, okWhy = "Give a reason first.",
      onAccept = function(why)
        local ok, err = ns.shitlistAdd(name, why)
        say(ok and (ns.safe(tidy(ns.playerKey(name))) .. " is on the Shit List.") or err)
      end,
    })
    return
  end
  T.dialog({
    title = "Add to the Shit List", accept = "Add",
    text = "Their name, then why. The reason shows in tooltips, the group finder and the Hit List.\nExample: Gankus Maximus - camps the Stormwind flight path",
    input = { text = name and (name .. " - ") or "", maxLetters = NAME_MAX + 3 + WHY_MAX },
    okUsable = function(t) return keyOf((ns.parseShitlistInput(t))) ~= nil end, okWhy = "Type a name first.",
    onAccept = function(t)
      local n, why = ns.parseShitlistInput(t)
      local ok, err = ns.shitlistAdd(n, why)
      say(ok and (ns.safe(tidy(n)) .. " is on the Shit List.") or err)
    end,
  })
end

function ns.promptShitlistRemove(e)
  ns.T.dialog({
    title = "Take off the Shit List", accept = "Remove",
    text = "Take " .. ns.safe(e.n) .. " off the Shit List, for the whole guild?",
    onAccept = function()
      local ok, err = ns.shitlistRemove(e.n)
      say(ok and (ns.safe(e.n) .. " is off the Shit List.") or err)
    end,
  })
end

-- /ppta shitlist [add|remove] [Name - why]. raw keeps the case the player typed.
function ns.shitlistCommand(raw)
  local verb, rest = raw:match("^%s*%S+%s*(%S*)%s*(.-)%s*$")
  verb = (verb or ""):lower()
  if verb == "add" then
    if rest == "" then ns.promptShitlistAdd() return end
    local n, why = ns.parseShitlistInput(rest)
    local ok, err = ns.shitlistAdd(n, why)
    say(ok and (ns.safe(tidy(n)) .. " is on the Shit List.") or err)
  elseif verb == "remove" or verb == "del" or verb == "rm" then
    local n = rest ~= "" and rest or targetName()
    if not n then say("Who? /ppta shitlist remove First Surname") return end
    local ok, err = ns.shitlistRemove((n:gsub("%-", " ", 1)))
    say(ok and (ns.safe(tidy(n)) .. " is off the Shit List.") or err)
  else
    ns.showShitList()
  end
end

-- ---------- the unit tooltip ----------

local RED = { 1, 0.1, 0.1 }
local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:18:18|t"

local function resetBorder(tip)
  if tip.perpetuaRed then
    tip.perpetuaRed = nil
    if type(tip.NineSlice) == "table" and tip.NineSlice.SetBorderColor then
      local c = TOOLTIP_DEFAULT_COLOR
      ns.try(tip.NineSlice.SetBorderColor, tip.NineSlice, c and c.r or 1, c and c.g or 1, c and c.b or 1)
    end
  end
end

local function onUnitTooltip(tip)
  if tip ~= GameTooltip or ns.locked() then return end
  local _, unit = ns.try(tip.GetUnit, tip)
  unit = ns.readable(unit)
  if not unit or not ns.try(UnitIsPlayer, unit) then return end
  local first, surname = ns.try(UnitName, unit)
  first, surname = ns.readable(first), ns.readable(surname)
  local e = first and ns.shitlistEntry(ns.fullName(first, surname))
  if not e then return end
  tip:AddLine(" ")
  tip:AddLine(SKULL .. "  SHIT LIST  " .. SKULL, RED[1], RED[2], RED[3])
  local last = _G["GameTooltipTextLeft" .. (ns.try(tip.NumLines, tip) or 0)]
  if last and GameFontNormalLarge then last:SetFontObject(GameFontNormalLarge); last:SetTextColor(RED[1], RED[2], RED[3]) end
  if e.r then tip:AddLine(ns.safe(e.r), 1, 0.55, 0.5, true) end
  if e.by then tip:AddLine("Added by " .. ns.safe(e.by) .. (e.at and (", " .. ns.ago(e.at)) or ""), 0.7, 0.7, 0.7) end
  if type(tip.NineSlice) == "table" and tip.NineSlice.SetBorderColor then
    tip.perpetuaRed = true
    ns.try(tip.NineSlice.SetBorderColor, tip.NineSlice, RED[1], RED[2], RED[3])
  end
  tip:Show() -- resize to the new lines
end

local function hookTooltip()
  local hooked = false
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tip) pcall(onUnitTooltip, tip) end)
  end
  if not hooked then GameTooltip:HookScript("OnTooltipSetUnit", function(tip) pcall(onUnitTooltip, tip) end) end
  -- The big font and red border stay on the reused line and frame: put them back for the next tooltip.
  GameTooltip:HookScript("OnTooltipCleared", function(tip)
    resetBorder(tip)
    for i = 1, ns.try(tip.NumLines, tip) or 0 do
      local l = _G["GameTooltipTextLeft" .. i]
      if l and GameTooltipText and l:GetFontObject() == GameFontNormalLarge then l:SetFontObject(i == 1 and GameTooltipHeaderText or GameTooltipText) end
    end
  end)
  GameTooltip:HookScript("OnHide", resetBorder)
end

-- ---------- the group finder ----------
-- Blizzard_GroupFinder_VanillaStyle (loaded on demand). Post-hooks only (hooksecurefunc), and our own textures on
-- the rows, so nothing of Blizzard's is changed or tainted.

-- Who in a search result is on the list: { entry, ... }.
local function flaggedIn(resultID)
  local out, seen = {}, {}
  local info = ns.try(C_LFGList.GetSearchResultInfo, resultID)
  if not info then return out end
  local function check(name)
    local e = name and ns.shitlistEntry(name)
    if e and not seen[e] then seen[e] = true; out[#out + 1] = e end
  end
  check(ns.readable(info.leaderName))
  for i = 1, ns.num(info.numMembers) or 0 do
    local m = ns.try(C_LFGList.GetSearchResultPlayerInfo, resultID, i)
    check(m and ns.readable(m.name))
  end
  return out
end

local function markRow(row)
  local list = (not ns.locked() and row.resultID) and flaggedIn(row.resultID) or {}
  local on = #list > 0
  if not row.perpetuaFlag then
    if not on then return end
    local f = {}
    f.bg = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.bg:SetPoint("TOPLEFT", 3, -2); f.bg:SetPoint("BOTTOMRIGHT", -3, 0)
    f.bg:SetColorTexture(0.75, 0, 0, 0.45)
    f.bar = row:CreateTexture(nil, "ARTWORK", nil, 2)
    f.bar:SetPoint("TOPLEFT", 3, -2); f.bar:SetPoint("BOTTOMLEFT", 3, 0); f.bar:SetWidth(3)
    f.bar:SetColorTexture(1, 0.1, 0.1, 1)
    f.skull = row:CreateTexture(nil, "OVERLAY", nil, 2)
    f.skull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    f.skull:SetSize(14, 14)
    f.skull:SetPoint("TOPRIGHT", -6, -3)
    f.label = row:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    f.label:SetPoint("RIGHT", f.skull, "LEFT", -2, 0)
    f.label:SetText("SHIT LIST")
    row.perpetuaFlag = f
  end
  for _, r in pairs(row.perpetuaFlag) do r:SetShown(on) end
end

local warn
local function warnUnder(tip, resultID)
  local list = ns.locked() and {} or flaggedIn(resultID)
  if #list == 0 then if warn then warn:Hide() end return end
  if not warn then
    warn = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    warn:SetFrameStrata("TOOLTIP")
    if warn.SetBackdrop then
      warn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
      warn:SetBackdropColor(0.25, 0, 0, 0.95)
      warn:SetBackdropBorderColor(1, 0.1, 0.1, 1)
    end
    warn.text = warn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    warn.text:SetPoint("TOPLEFT", 10, -8); warn.text:SetPoint("RIGHT", -10, 0)
    warn.text:SetJustifyH("LEFT"); warn.text:SetWordWrap(true)
    tip:HookScript("OnHide", function() warn:Hide() end)
  end
  local lines = { "|cffff2020" .. SKULL .. "  SHIT LIST  " .. SKULL .. "|r" }
  for _, e in ipairs(list) do
    lines[#lines + 1] = "|cffff4040" .. ns.safe(e.n) .. "|r" .. (e.r and ("|cffffb0a8 - " .. ns.safe(e.r) .. "|r") or "")
  end
  warn:SetWidth(math.max(tip:GetWidth(), 200))
  warn.text:SetText(table.concat(lines, "\n"))
  warn:SetHeight(warn.text:GetStringHeight() + 16)
  warn:SetScale(tip:GetEffectiveScale() / UIParent:GetEffectiveScale())
  warn:ClearAllPoints()
  warn:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, -2)
  warn:Show()
end

local finderHooked = false
local function hookFinder()
  if finderHooked or not LFGBrowseSearchEntry_Update then return end
  finderHooked = true
  hooksecurefunc("LFGBrowseSearchEntry_Update", function(row) pcall(markRow, row) end)
  if LFGBrowseSearchEntryTooltip_UpdateAndShow then
    hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", function(tip, resultID) pcall(warnUnder, tip, resultID) end)
  end
end

-- After the list changes: redo the rows on screen (the finder only updates them on its own events).
function ns.refreshGroupFinder()
  if not finderHooked or not LFGBrowseFrame or not LFGBrowseFrame:IsVisible() then return end
  local box = LFGBrowseFrame.ScrollBox
  if box and box.ForEachFrame then pcall(box.ForEachFrame, box, function(row) pcall(markRow, row) end) end
end

-- ---------- right-click menus (portraits, chat names, the guild and raid lists) ----------
-- Menu.ModifyMenu adds to Blizzard's tagged menus without tainting them. Officers get "Add to the Shit List" (a
-- dialog asks why) or "Take off the Shit List"; everyone sees a red line with the reason when the player is on it.

local MENUS = { "PLAYER", "ENEMY_PLAYER", "TARGET", "FOCUS", "PARTY", "RAID_PLAYER", "FRIEND", "CHAT_ROSTER",
  "GUILD", "COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER", "WORLD_STATE_SCORE", "PVP_SCOREBOARD", "RECENT_ALLY" }

local function menuName(ctx)
  if type(ctx) ~= "table" then return nil end
  local first, surname = ns.readable(ctx.name), ns.readable(ctx.surname)
  if (not first or first == "") and ctx.unit then first, surname = ns.try(UnitName, ctx.unit); first, surname = ns.readable(first), ns.readable(surname) end
  if type(first) ~= "string" or first == "" then return nil end
  if type(surname) ~= "string" or surname == "" then return ns.playerKey(first) end
  return ns.fullName(first, surname)
end

local function addToMenu(_, root, ctx)
  if ns.locked() then return end
  local name = menuName(ctx)
  if not name or (ns.selfName and keyOf(name) == ns.selfName:lower()) then return end
  local e = ns.shitlistEntry(name)
  if not e and not ns.canEditShitlist() then return end
  root:CreateDivider()
  root:CreateTitle("|cffd4af37Perpetua|r")
  if e then
    root:CreateTitle("|cffff2020On the Shit List|r" .. (e.r and ("|cffffb0a8: " .. ns.safe(e.r) .. "|r") or ""))
  end
  if ns.canEditShitlist() then
    if e then
      root:CreateButton("Take off the Shit List", function() ns.promptShitlistRemove(e) end)
    else
      root:CreateButton("|cffff4040Add to the Shit List|r", function() ns.promptShitlistAdd(name) end)
    end
  end
end

local function hookMenus()
  if not (Menu and Menu.ModifyMenu) then return end
  for _, which in ipairs(MENUS) do
    pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, function(...) pcall(addToMenu, ...) end)
  end
end

local hooks = CreateFrame("Frame")
hooks:RegisterEvent("PLAYER_LOGIN")
hooks:RegisterEvent("ADDON_LOADED")
hooks:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGIN" then
    pcall(hookTooltip)
    pcall(hookFinder)
    pcall(hookMenus)
  elseif name == "Blizzard_GroupFinder_VanillaStyle" then
    pcall(hookFinder)
  end
end)

ns.shitlistForTest = { addToMenu = addToMenu, menuName = menuName, keyOf = keyOf, tidy = tidy, markRow = markRow, flaggedIn = flaggedIn, onUnitTooltip = onUnitTooltip, warnUnder = warnUnder }

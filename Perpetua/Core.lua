-- Start-up, events and slash commands.
--
-- PerpetuaDB (account-wide) holds what guild sync has collected, per guild; it's what the Perpetua app on an
-- officer's computer reads (sync/perpetua_sync.py). WoW writes it to disk only on logout, /reload or exit.
-- PerpetuaCharDB (per character) holds this character's recipes, read whenever a profession window opens.
local _, ns = ...

PerpetuaDB = PerpetuaDB or {}
PerpetuaCharDB = PerpetuaCharDB or {}

local function start()
  local first, second = UnitName("player")
  ns.selfName = ns.fullName(first, ns.FOREVER and second or nil)
  ns.createMinimapButton()
  ns.startComm()
  -- Guild info arrives a little after login; give it a moment before the first announce.
  local tries = 0
  local function first()
    tries = tries + 1
    if IsInGuild() and not ns.guildName() and tries < 12 then C_Timer.After(5, first) return end
    ns.refreshSelf(true)
    ns.loadSiteCalendar()
    ns.loadSiteForums()
    ns.announce()
    if ns.locked() then
      print("|cffd4af37Perpetua|r: this is the <" .. ns.GUILD .. "> guild's addon and it only works for members. We're recruiting: type /ppta to find out about us.")
    elseif not PerpetuaDB.setupSeen then
      print("|cffd4af37Perpetua|r: new here? Click the Perpetua crest on your minimap (or type /ppta) to link your characters to " .. ns.SITE .. ". /ppta help lists the commands.")
    end
  end
  C_Timer.After(8, first)
end

-- Things that change what the profile says. Refreshes are debounced, so a burst of gear swaps sends once.
local CHANGES = {
  PLAYER_EQUIPMENT_CHANGED = 15, PLAYER_LEVEL_UP = 5, TRAIT_CONFIG_UPDATED = 10,
  ACTIVE_PLAYER_SPECIALIZATION_CHANGED = 10, PLAYER_SPECIALIZATION_CHANGED = 10, CHARACTER_POINTS_CHANGED = 10,
  SKILL_LINES_CHANGED = 30, QUEST_TURNED_IN = 10, BAG_UPDATE_DELAYED = 60, UPDATE_FACTION = 120,
  PLAYER_GUILD_UPDATE = 10, UNIT_INVENTORY_CHANGED = 15,
}
-- Which parts of the profile each can change (Collect.lua reads only those again; stats are always read).
local SECTIONS_FOR = {
  PLAYER_EQUIPMENT_CHANGED = { "gear" }, UNIT_INVENTORY_CHANGED = { "gear" }, -- the second covers enchants
  PLAYER_LEVEL_UP = { "character", "talents", "professions" },
  TRAIT_CONFIG_UPDATED = { "talents" }, ACTIVE_PLAYER_SPECIALIZATION_CHANGED = { "talents" },
  PLAYER_SPECIALIZATION_CHANGED = { "talents" }, CHARACTER_POINTS_CHANGED = { "talents" },
  SKILL_LINES_CHANGED = { "professions" }, QUEST_TURNED_IN = { "attunements" }, BAG_UPDATE_DELAYED = { "attunements" },
  UPDATE_FACTION = { "reputation" }, PLAYER_GUILD_UPDATE = { "character" },
}

local events = CreateFrame("Frame")
-- No PLAYER_LOGOUT refresh: by then the client has unloaded gear, guild, professions and talents, so a last look
-- saved a blank profile over the real one. The refreshes while playing keep the saved file current.
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM", "TRADE_SKILL_SHOW",
  "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  pcall(events.RegisterEvent, events, e) -- not every client has every event
end
for e in pairs(CHANGES) do
  if e == "UNIT_INVENTORY_CHANGED" then pcall(events.RegisterUnitEvent, events, e, "player")
  else pcall(events.RegisterEvent, events, e) end
end

local started, scanTimer = false, nil
events:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    ns.onAddonMessage(...)
  elseif event == "CHAT_MSG_LOOT" then
    if not ns.locked() and ns.guildName() then pcall(ns.onLootChat, ...) end
  elseif event == "CHAT_MSG_SYSTEM" then
    if not ns.locked() and ns.guildName() then pcall(ns.onSystemChat, ...) end
  elseif event == "ADDON_LOADED" then
    if ... == "Perpetua" then
      PerpetuaDB = PerpetuaDB or {}
      PerpetuaCharDB = PerpetuaCharDB or {}
    end
  elseif event == "PLAYER_LOGIN" then
    if not started then started = true; start() end
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" or event:find("^TRADE_SKILL") then
    -- These come in bursts (every craft, every filter change): read the window once things settle.
    local craft = event:find("^CRAFT") ~= nil
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(1, function() scanTimer = nil; pcall(craft and ns.scanCraft or ns.scanTradeSkill) end)
  elseif event == "UPDATE_FACTION" and ns.repReadAt and GetTime() - ns.repReadAt < 2 then
    return -- our own header toggles while reading reputations (Collect.lua), not a real change
  elseif CHANGES[event] and started then
    for _, section in ipairs(SECTIONS_FOR[event] or {}) do ns.markDirty(section) end
    ns.scheduleRefresh(CHANGES[event])
    -- Joining or leaving the guild locks or unlocks the window.
    if event == "PLAYER_GUILD_UPDATE" then ns.fire() end
  end
end)

SLASH_PERPETUA1 = "/perpetua"
SLASH_PERPETUA2 = "/perp"
SLASH_PERPETUA3 = "/ppta"

local HELP = {
  { "", "open or close the window" },
  { "setup", "link your characters to " .. ns.SITE },
  { "link CODE", "save a link code from " .. ns.SITE .. "/member" },
  { "me", "your character" },
  { "raids", "the raid calendar" },
  { "loot", "loot and roll history" },
  { "attune", "attunements" },
  { "crafters", "who can make what" },
  { "export", "your export for the site" },
  { "sync", "save for the Perpetua app (reloads your UI)" },
  { "minimap", "hide or show the minimap button" },
  { "olympus [on|off]", "hide chat and invites from Olympus guilds" },
  { "guildui [on|off]", "the new guild window: the guild key and button open Perpetua's" },
  { "guild", "the guild roster" },
}
SlashCmdList.PERPETUA = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if ns.locked() and msg ~= "minimap" then ns.showTab("Welcome") return end
  if msg == "help" or msg == "?" then
    print("|cffd4af37Perpetua|r commands (/perpetua, /perp or /ppta):")
    for _, h in ipairs(HELP) do print("  |cfff2d78c/ppta" .. (h[1] ~= "" and (" " .. h[1]) or "") .. "|r  " .. h[2]) end
  elseif msg == "export" then ns.showTab("Export"); ns.renderExport(true)
  elseif msg == "sync" then ns.refreshSelf(true); ReloadUI()
  elseif msg == "attune" or msg == "attunements" then ns.showTab("Attunements")
  elseif msg == "raids" or msg == "calendar" then ns.showTab("Calendar")
  elseif msg == "loot" then ns.showTab("Loot")
  elseif ns.FORUMS and (msg == "forums" or msg == "forum") then ns.showTab("Forums")
  elseif msg == "craft" or msg == "crafters" then ns.showTab("Crafters")
  elseif msg == "minimap" then ns.toggleMinimapButton()
  elseif msg == "setup" then ns.showTab("Setup")
  elseif msg == "olympus on" or msg == "olympus off" then ns.olympus.set(msg == "olympus on")
  elseif msg == "olympus" then ns.showTab("Hide Olympus")
  elseif msg == "olympus debug" then ns.olympus.debug()
  elseif msg:match("^link") then
    local code = msg:match("^link%s+(%w+)$")
    code = code and code:upper()
    if not code or #code ~= 6 then
      print("|cffd4af37Perpetua|r: get your link code at " .. ns.SITE .. "/member, then type /perpetua link CODE")
      return
    end
    PerpetuaDB.link = { code = code, t = ns.now() }
    ns.refreshSelf()
    print("|cffd4af37Perpetua|r: link code saved. Your characters will appear under your Discord account on " .. ns.SITE ..
      " the next time an officer syncs the guild.")
    ns.refreshUI(true)
  elseif msg == "me" then ns.selected = ns.selfName; ns.showTab("Character")
  elseif msg == "guild" or msg == "roster" then ns.showTab("Guild")
  elseif msg == "guildui" or msg == "guildui on" or msg == "guildui off" then
    -- "on" = the new guild window; bare toggles.
    local on = (msg == "guildui on") or (msg == "guildui" and not ns.newGuildWindow())
    ns.setNewGuildWindow(on)
  else ns.toggle() end
end

-- The addon compartment (the addons button by the minimap).
function Perpetua_Toggle() ns.toggle() end

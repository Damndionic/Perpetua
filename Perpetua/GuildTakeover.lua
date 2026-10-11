-- The guild key and the guild button on the micro menu open the Perpetua window's Guild page instead of
-- Blizzard's guild window. Holding Shift opens Blizzard's, as before.
--
-- Nothing of Blizzard's is replaced, so nothing of theirs is tainted:
--  * the key: an override binding (ours, set out of combat) on whatever key is bound to "Toggle Guild" clicks
--    our own button; Shift + that key clicks a secure button that clicks the real guild button, so Blizzard's
--    window still opens through secure code.
--  * the micro button: a plain frame of ours sits over it and opens Perpetua. While Shift is held it stops
--    taking the mouse, so the click lands on the real button underneath.
-- It's a "new feature" you opt into (PerpetuaDB.guildTakeover = true): the New guild window switch at the top of
-- the Perpetua window, Options > AddOns > Perpetua, the Guild Info page or /ppta guildui. Off (the default) or
-- outside the guild, the key and the button are Blizzard's.
local _, ns = ...
local try = ns.try

local owner = CreateFrame("Frame")             -- owns the override bindings
local opener = CreateFrame("Button", "PerpetuaGuildKey", UIParent)
opener:SetScript("OnClick", function() ns.toggle("Guild") end)

-- Shift: Blizzard's window, through a secure click on the real micro button.
local blizzard = CreateFrame("Button", "PerpetuaBlizzardGuild", UIParent, "SecureActionButtonTemplate")
blizzard:RegisterForClicks("AnyUp", "AnyDown")
blizzard:SetAttribute("type", "click")
blizzard:SetAttribute("useOnKeyDown", false)

blizzard:Hide() -- bindings click it while hidden; it only shows while floating over one of our buttons (below)

-- Secure clicks from the Perpetua window. The game lets only Blizzard's own UI change ranks, remove members, change
-- notes and so on; an addon calling those gets "blocked from an action only available to the Blizzard UI". Two
-- secure buttons do it for us, each a real click by the player:
--  * the one above opens Blizzard's guild window (notes, message of the day, guild info);
--  * "action" runs Blizzard's own secure guild slash commands (/gpromote, /gdemote, /gremove, /gleader, /gquit,
--    /gdisband: Blizzard_ChatFrameBase SlashCommands.lua), the same as typing them.
-- Our buttons can't hold them, and the client won't anchor protected frames to ours, so on hover the secure button
-- goes onto UIParent exactly over ours and takes the click. In combat it can't move, so our button's own click says so.
local action = CreateFrame("Button", "PerpetuaGuildAction", UIParent, "SecureActionButtonTemplate")
-- Act on the mouse-up of the click. Without useOnKeyDown the template follows the ActionButtonUseKeyDown setting
-- (on by default: act on the down), and a button registered only for up then never acts.
action:RegisterForClicks("AnyUp", "AnyDown")
action:SetAttribute("useOnKeyDown", false)
action:SetAttribute("type", "macro")
action:Hide()

local hovering, hoverSecure
local function float(secure, target)
  if InCombatLockdown() then return end
  -- Protected frames can't be anchored to ours (the client refuses), so it goes on UIParent at the same screen spot.
  local left, bottom, w, h = target:GetLeft(), target:GetBottom(), target:GetWidth(), target:GetHeight()
  if not (left and bottom and w and h) then return end
  local k = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
  hovering, hoverSecure = target, secure
  secure:ClearAllPoints()
  secure:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * k, bottom * k)
  secure:SetSize(w * k, h * k)
  -- Top layer, so nothing of ours sits over it (it only shows while the mouse is on our button, which was on top).
  secure:SetFrameStrata("FULLSCREEN_DIALOG")
  secure:SetFrameLevel(math.min(target:GetFrameLevel() + 50, 9000))
  secure:Show()
end
local function onEnter(self)
  if not hovering or not hovering.secureTitle then return end
  try(hovering.LockHighlight, hovering)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(hovering.secureTitle, 0.83, 0.69, 0.22)
  if hovering.secureTip then GameTooltip:AddLine(hovering.secureTip, 1, 1, 1, true) end
  GameTooltip:Show()
end
-- Parks a secure button: hidden, and the command button disarmed, so nothing is left waiting under the mouse.
local function park(b)
  if InCombatLockdown() then return end
  b:Hide(); b:ClearAllPoints()
  if b == action then action:SetAttribute("macrotext", nil) end
end
local function onLeave(self)
  if hovering then try(hovering.UnlockHighlight, hovering) end
  GameTooltip:Hide()
  hovering, hoverSecure = nil, nil
  park(self)
end
-- Combat is about to lock them in place: park both now (still allowed while PLAYER_REGEN_DISABLED runs). After
-- combat, one the mouse isn't on goes away too.
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:RegisterEvent("PLAYER_REGEN_ENABLED")
guard:SetScript("OnEvent", function(_, event)
  for _, b in ipairs({ blizzard, action }) do
    if b:IsShown() and (event == "PLAYER_REGEN_DISABLED" or not b:IsMouseOver()) then
      if hovering then try(hovering.UnlockHighlight, hovering) end
      hovering, hoverSecure = nil, nil
      GameTooltip:Hide()
      b:Hide(); b:ClearAllPoints()
      if b == action then action:SetAttribute("macrotext", nil) end
    end
  end
end)
for _, b in ipairs({ blizzard, action }) do
  b:SetScript("OnEnter", onEnter)
  b:SetScript("OnLeave", onLeave)
end
-- The Perpetua window steps aside so Blizzard's has the screen. Only after the click has gone through: hiding it
-- sooner (on the mouse-down) hides our button, which parks this one before the mouse-up that opens the window.
blizzard:SetScript("PostClick", function(_, _, down)
  if down then return end
  if hoverSecure == blizzard and PerpetuaFrame then PerpetuaFrame:Hide() end
end)
-- After a guild command: whatever our button wants to do next (close a dialog, refresh the roster). If the mouse is
-- still on our button once the roster has updated, it's armed again with the new command (promote twice in a row).
local rearm
action:SetScript("PostClick", function(self, _, down)
  if down then return end -- the action happens on the up
  if ns.DEV then print("|cffd4af37Perpetua|r (dev): ran " .. tostring(self:GetAttribute("macrotext"))) end
  local target = hovering
  if target and target.secureAfter then target.secureAfter() end
  onLeave(self)
  if target then C_Timer.After(0.8, function() rearm(target) end) end
end)

local function inCombatNote(what)
  print("|cffd4af37Perpetua|r: " .. what .. " only works out of combat (the game hands it to Blizzard's UI, which won't move in combat).")
end

-- Puts the command button back over our button if the mouse is (still) on it and there's something to run.
function rearm(target)
  if InCombatLockdown() or not (target and target:IsVisible() and target:IsMouseOver() and target.secureCommand) then return end
  if hovering then return end
  local text = target.secureCommand()
  if not text then return end
  action:SetAttribute("macrotext", text)
  float(action, target)
end

function ns.opensBlizzardGuild(button, title, tip)
  button.secureTitle, button.secureTip = title, tip
  -- A greyed-out button (T.button SetUsable false) keeps the mouse: its tooltip says why, and nothing opens.
  local function usable(self) return GuildMicroButton and (not self.IsEnabled or self:IsEnabled()) end
  button:HookScript("OnEnter", function(self) if usable(self) then float(blizzard, self) end end)
  -- Our button and the secure one go away together (a dialog closing under the mouse, say).
  button:HookScript("OnHide", function(self) if hovering == self then onLeave(hoverSecure) end end)
  -- Only reached when the secure button wasn't over it: in combat, or the mouse never left after a click.
  button:HookScript("OnClick", function(self)
    if InCombatLockdown() then inCombatNote("Opening Blizzard's guild window from here")
    elseif usable(self) then float(blizzard, self) end -- the next click takes
  end)
end

-- Our button runs a guild slash command through the secure button. command() returns the macro text, or nil when
-- there's nothing to do (then our button keeps the click); after() runs once it's done.
function ns.secureGuildCommand(button, command, title, tip, after)
  button.secureTitle, button.secureTip, button.secureAfter, button.secureCommand = title, tip, after, command
  button:HookScript("OnEnter", function(self)
    local text = command()
    if not text then return end
    action:SetAttribute("macrotext", text)
    float(action, self)
  end)
  button:HookScript("OnHide", function(self) if hovering == self then onLeave(hoverSecure) end end)
  -- Only reached when the secure button wasn't over it: in combat, or the mouse never left after the last click
  -- (then it's armed now and the next click runs it).
  button:HookScript("OnClick", function(self)
    if not command() then return end
    if InCombatLockdown() then inCombatNote("That") else rearm(self) end
  end)
end

-- Blizzard's slash command for a guild action, as this client spells it.
local SLASH = { promote = "PROMOTE", demote = "DEMOTE", remove = "UNINVITE", leader = "LEADER", leave = "LEAVE", disband = "DISBAND" }
local FALLBACK = { promote = "/gpromote", demote = "/gdemote", remove = "/gremove", leader = "/gleader", leave = "/gquit", disband = "/gdisband" }
function ns.guildSlash(kind, name)
  local cmd = _G["SLASH_GUILD_" .. SLASH[kind] .. "1"]
  if type(cmd) ~= "string" or not cmd:match("^/%S+$") then cmd = FALLBACK[kind] end
  return name and (cmd .. " " .. name) or cmd
end

local overlay -- over GuildMicroButton

function ns.newGuildWindow() return PerpetuaDB.guildTakeover == true end
function ns.guildTakeoverOn() return ns.newGuildWindow() and not ns.locked() end

local pending, applied = false, nil
local function apply()
  if InCombatLockdown() then pending = true return end
  pending = false
  local on = ns.guildTakeoverOn()
  -- Setting override bindings fires UPDATE_BINDINGS, which calls this again: only redo it when something changed.
  local state = tostring(on) .. ":" .. table.concat({ GetBindingKey("TOGGLEGUILDTAB") }, ",")
  if state == applied then return end
  applied = state
  ClearOverrideBindings(owner)
  if GuildMicroButton then blizzard:SetAttribute("clickbutton", GuildMicroButton) end
  if on then
    for _, key in ipairs({ GetBindingKey("TOGGLEGUILDTAB") }) do
      SetOverrideBindingClick(owner, false, key, "PerpetuaGuildKey", "LeftButton")
      -- Shift + the key for Blizzard's window, unless Shift + that key already does something else.
      local shifted = key:find("SHIFT%-") and nil or ("SHIFT-" .. key)
      if shifted and (GetBindingAction(shifted) or "") == "" and GuildMicroButton then
        SetOverrideBindingClick(owner, false, shifted, "PerpetuaBlizzardGuild", "LeftButton")
      end
    end
  end
  if overlay then overlay:SetShown(on) end
end
ns.applyGuildTakeover = apply

-- The one switch everything uses.
function ns.setNewGuildWindow(on, quiet)
  PerpetuaDB.guildTakeover = on and true or false
  apply()
  if not quiet then
    print("|cffd4af37Perpetua|r: " .. (on and "new guild window on: the guild key and guild button open Perpetua (hold Shift for Blizzard's)."
      or "new guild window off: the guild key and guild button open Blizzard's guild window."))
  end
  if ns.refreshUI then ns.refreshUI(true) end
end

-- Options > AddOns > Perpetua: a checkbox for it.
local function registerSettings()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end
  local category = Settings.RegisterVerticalLayoutCategory("Perpetua")
  local setting = Settings.RegisterProxySetting(category, "PERPETUA_NEW_GUILD_WINDOW", Settings.VarType.Boolean,
    "New guild window", false, ns.newGuildWindow, function(value) ns.setNewGuildWindow(value, true) end)
  Settings.CreateCheckbox(category, setting,
    "New: the guild key (J) and the guild button open Perpetua's guild window instead of Blizzard's. Hold Shift for Blizzard's.")
  -- Window size (Theme.lua T.scale; also /ppta scale and Ctrl + mouse wheel on the window).
  if Settings.CreateSlider and Settings.CreateSliderOptions and Settings.VarType.Number then
    local T = ns.T
    local size = Settings.RegisterProxySetting(category, "PERPETUA_WINDOW_SCALE", Settings.VarType.Number,
      "Window size", 1, T.scale, function(value) ns.setScale(value, true) end)
    local options = Settings.CreateSliderOptions(T.SCALE_MIN, T.SCALE_MAX, 0.05)
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
      options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
    end
    Settings.CreateSlider(category, size, options, "How big the Perpetua window is. Ctrl + mouse wheel on the window does the same.")
  end
  Settings.RegisterAddOnCategory(category)
end

local function makeOverlay()
  local mb = GuildMicroButton
  if overlay or not mb then return end
  overlay = CreateFrame("Button", nil, mb)
  overlay:SetAllPoints(mb)
  overlay:SetFrameLevel(mb:GetFrameLevel() + 5)
  overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  overlay:SetScript("OnClick", function() ns.toggle("Guild") end)
  -- Look like the button underneath: its highlight and its tooltip.
  overlay:SetScript("OnEnter", function()
    try(mb.LockHighlight, mb)
    local enter = mb:GetScript("OnEnter")
    if enter then try(enter, mb) end
    if GameTooltip:IsOwned(mb) then
      GameTooltip:AddLine("Opens Perpetua. Shift-click for Blizzard's guild window.", 0.83, 0.69, 0.22, true)
      GameTooltip:Show()
    end
  end)
  overlay:SetScript("OnLeave", function()
    try(mb.UnlockHighlight, mb)
    local leave = mb:GetScript("OnLeave")
    if leave then try(leave, mb) else GameTooltip:Hide() end
  end)
  overlay:SetShown(ns.guildTakeoverOn())
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UPDATE_BINDINGS")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("MODIFIER_STATE_CHANGED")
f:SetScript("OnEvent", function(_, event)
  if event == "MODIFIER_STATE_CHANGED" then
    -- Shift held: let clicks through to the real button.
    if overlay then overlay:EnableMouse(not IsShiftKeyDown()) end
    return
  end
  if event == "PLAYER_LOGIN" then
    makeOverlay()
    try(registerSettings)
  end
  if event == "PLAYER_REGEN_ENABLED" and not pending then return end
  -- Guild info arrives a moment after login and after joining or leaving.
  C_Timer.After(event == "PLAYER_LOGIN" and 5 or 0.5, apply)
end)

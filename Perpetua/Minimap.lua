-- Minimap button with the Perpetua crest (the site's favicon, Media/icon.tga). Left-click opens the window,
-- right-click your export; drag it around the minimap. Position and visibility live in PerpetuaDB.minimap.
local _, ns = ...

local button

local function settings()
  PerpetuaDB.minimap = PerpetuaDB.minimap or { angle = 200, hide = false }
  return PerpetuaDB.minimap
end

local function place()
  local angle = math.rad(settings().angle or 200)
  local radius = (Minimap:GetWidth() or 140) / 2 + 10
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  settings().angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
  place()
end

function ns.createMinimapButton()
  if button or not Minimap then return end
  button = CreateFrame("Button", "PerpetuaMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("AnyUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  -- Same layout as current LibDBIcon on the retail client: a 50px border anchored top-left puts its ring's
  -- centre on the button's centre, so the background and icon are centred too.
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(24, 24)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetPoint("CENTER")

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetTexture("Interface\\AddOns\\Perpetua\\Media\\icon")
  icon:SetPoint("CENTER")
  -- Round it like the other minimap buttons (the icon's own corners are rounded squares).
  if not pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") then
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  end
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(50, 50)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then ns.showTab("Export"); ns.renderExport(true)
    else ns.toggle() end
  end)
  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Perpetua", 0.83, 0.69, 0.22)
    local n = 0
    for _, rec in pairs(ns.players()) do if type(rec) == "table" and rec.profile then n = n + 1 end end
    GameTooltip:AddLine(n .. " guildmates with the addon", 1, 1, 1)
    local update = ns.updateAvailable()
    if update then GameTooltip:AddLine("Update available: " .. update, 0.95, 0.84, 0.55) end
    GameTooltip:AddLine("Left-click: guild, characters, attunements, professions", 0.64, 0.67, 0.79)
    GameTooltip:AddLine("Right-click: your export for " .. ns.SITE, 0.64, 0.67, 0.79)
    GameTooltip:AddLine("Drag to move · /perpetua minimap to hide", 0.64, 0.67, 0.79)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  place()
  button:SetShown(not settings().hide)
end

function ns.toggleMinimapButton()
  local s = settings()
  s.hide = not s.hide
  if not button then ns.createMinimapButton() end
  button:SetShown(not s.hide)
  print("|cffd4af37Perpetua|r: minimap button " .. (s.hide and "hidden. Type /perpetua minimap to bring it back." or "shown."))
end

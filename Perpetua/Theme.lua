-- The site's look in game: gold linework on deep royal navy, Cinzel for headings and buttons, Cormorant
-- Garamond for text (both SIL Open Font License, in Media/Fonts; the Cormorant files are cut down to Latin, Cyrillic
-- and common symbols to keep the download small), the crest and the corner brackets from
-- perpetua.css. Everything is drawn with plain textures, so it doesn't depend on Blizzard's frame art.
local _, ns = ...
local T = {}
ns.T = T

local MEDIA = "Interface\\AddOns\\Perpetua\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
T.CREST = MEDIA .. "crest"

-- perpetua.css :root
local C = {
  gold = { 0.831, 0.686, 0.216 }, pale = { 0.949, 0.843, 0.549 }, warm = { 0.910, 0.784, 0.455 },
  navy = { 0.055, 0.102, 0.251 }, midnight = { 0.047, 0.090, 0.188 }, royal = { 0.082, 0.165, 0.369 },
  royalLight = { 0.110, 0.184, 0.431 }, ink = { 0.027, 0.051, 0.118 }, dim = { 0.498, 0.533, 0.659 },
  text = { 0.937, 0.902, 0.784 }, muted = { 0.639, 0.675, 0.788 },
}
T.C = C
T.HEX = { gold = "d4af37", pale = "f2d78c", warm = "e8c874", text = "efe6c8", muted = "a3acc9", ok = "8fd18a", danger = "ff8a7a", dim = "7f88a8" }

local function font(name, file, size, color, fallback)
  local f = CreateFont(name)
  if f:SetFont(MEDIA .. "Fonts\\" .. file, size, "") == false and fallback then f:CopyFontObject(fallback) end
  f:SetTextColor(color[1], color[2], color[3])
  f:SetShadowColor(0, 0, 0, 0.85)
  f:SetShadowOffset(1, -1)
  return f
end

T.fonts = {
  title   = font("PerpetuaFontTitle", "Cinzel-Bold.ttf", 24, C.gold, GameFontNormalLarge),
  heading = font("PerpetuaFontHeading", "Cinzel-Bold.ttf", 12, C.gold, GameFontNormal),
  label   = font("PerpetuaFontLabel", "Cinzel-SemiBold.ttf", 10, C.gold, GameFontNormalSmall),
  button  = font("PerpetuaFontButton", "Cinzel-Bold.ttf", 11, C.gold, GameFontNormal),
  name    = font("PerpetuaFontName", "Cinzel-Bold.ttf", 22, C.text, GameFontNormalLarge),
  body    = font("PerpetuaFontBody", "CormorantGaramond-SemiBold.ttf", 16, C.text, GameFontHighlight),
  small   = font("PerpetuaFontSmall", "CormorantGaramond-SemiBold.ttf", 15, C.text, GameFontHighlightSmall),
  muted   = font("PerpetuaFontMuted", "CormorantGaramond-SemiBoldItalic.ttf", 14, C.muted, GameFontDisableSmall),
  tagline = font("PerpetuaFontTagline", "CormorantGaramond-SemiBoldItalic.ttf", 14, C.warm, GameFontNormalSmall),
  close   = font("PerpetuaFontClose", "CormorantGaramond-SemiBold.ttf", 30, C.warm, GameFontNormalLarge),
  brand   = font("PerpetuaFontBrand", "Cinzel-Bold.ttf", 17, C.gold, GameFontNormalLarge),
  page    = font("PerpetuaFontPage", "Cinzel-Bold.ttf", 21, C.gold, GameFontNormalLarge),
  nav     = font("PerpetuaFontNav", "Cinzel-SemiBold.ttf", 11, C.text, GameFontNormal),
  group   = font("PerpetuaFontGroup", "Cinzel-SemiBold.ttf", 10, C.dim, GameFontNormalSmall),
  stat    = font("PerpetuaFontStat", "Cinzel-Bold.ttf", 26, C.pale, GameFontNormalLarge),
  hero    = font("PerpetuaFontHero", "Cinzel-Bold.ttf", 28, C.text, GameFontNormalLarge),
  badge   = font("PerpetuaFontBadge", "Cinzel-SemiBold.ttf", 10, C.muted, GameFontNormalSmall),
  badgeValue = font("PerpetuaFontBadgeValue", "Cinzel-Bold.ttf", 12, C.pale, GameFontNormalSmall),
  lvl     = font("PerpetuaFontLevel", "Cinzel-SemiBold.ttf", 11, C.pale, GameFontNormalSmall),
  surname = font("PerpetuaFontSurname", "CormorantGaramond-SemiBoldItalic.ttf", 17, C.muted, GameFontDisable),
}

function T.hex(key, s) return "|cff" .. (T.HEX[key] or key) .. s .. "|r" end

-- How faded something greyed out is: still readable (about 3.4:1 for gold on navy), clearly not active.
T.DISABLED_ALPHA = 0.55

-- The window's size setting (Options > AddOns > Perpetua, /ppta scale, Ctrl + mouse wheel on the window): the
-- Perpetua window and its pop-ups are drawn at this scale. 1 = as designed.
T.SCALE_MIN, T.SCALE_MAX = 0.7, 1.5
function T.scale()
  local s = tonumber(PerpetuaDB and PerpetuaDB.scale) or 1
  return math.max(T.SCALE_MIN, math.min(T.SCALE_MAX, s))
end

function T.text(parent, fontKey, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(T.fonts[fontKey or "body"])
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

function T.fill(frame, layer, color, alpha)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(WHITE)
  t:SetVertexColor(color[1], color[2], color[3], alpha or 1)
  return t
end

-- A texture that fades from color c1/alpha a1 to c2/alpha a2, "VERTICAL" (bottom to top) or "HORIZONTAL" (left to right).
function T.gradient(frame, layer, orientation, c1, a1, c2, a2)
  local t = T.fill(frame, layer, { 1, 1, 1 }, 1)
  if not pcall(t.SetGradient, t, orientation, CreateColor(c1[1], c1[2], c1[3], a1), CreateColor(c2[1], c2[2], c2[3], a2)) then
    t:SetVertexColor(c2[1], c2[2], c2[3], (a1 + a2) / 2)
  end
  return t
end

-- A 1px rectangle `inset` pixels inside frame. Returns an object with SetAlpha / SetColor for all four sides.
function T.outline(frame, inset, color, alpha, layer)
  inset = inset or 0
  local sides = {}
  for i = 1, 4 do sides[i] = T.fill(frame, layer or "BORDER", color or C.gold, alpha) end
  local top, bottom, left, right = sides[1], sides[2], sides[3], sides[4]
  top:SetPoint("TOPLEFT", inset, -inset); top:SetPoint("TOPRIGHT", -inset, -inset); top:SetHeight(1)
  bottom:SetPoint("BOTTOMLEFT", inset, inset); bottom:SetPoint("BOTTOMRIGHT", -inset, inset); bottom:SetHeight(1)
  left:SetPoint("TOPLEFT", inset, -inset); left:SetPoint("BOTTOMLEFT", inset, inset); left:SetWidth(1)
  right:SetPoint("TOPRIGHT", -inset, -inset); right:SetPoint("BOTTOMRIGHT", -inset, inset); right:SetWidth(1)
  return {
    SetAlpha = function(_, a) for _, s in ipairs(sides) do s:SetAlpha(a) end end,
    SetColor = function(_, c, a) for _, s in ipairs(sides) do s:SetVertexColor(c[1], c[2], c[3], a or 1) end end,
  }
end

-- The window, like the site's .card: royal-navy field with a glow along the top, a gold border, a faint
-- hairline 5px inside and the corner brackets.
function T.window(frame)
  local base = T.gradient(frame, "BACKGROUND", "VERTICAL", C.midnight, 0.98, C.navy, 0.98)
  base:SetAllPoints()
  local glow = T.gradient(frame, "BACKGROUND", "VERTICAL", C.royalLight, 0, C.royalLight, 0.85)
  glow:SetPoint("TOPLEFT"); glow:SetPoint("TOPRIGHT"); glow:SetHeight(260)
  T.outline(frame, 0, C.gold, 0.9)
  T.outline(frame, 5, C.gold, 0.2)
  local coords = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 }, BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 } }
  for point, tc in pairs(coords) do
    local t = frame:CreateTexture(nil, "OVERLAY")
    t:SetTexture(MEDIA .. "bracket")
    t:SetSize(30, 30)
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    t:SetPoint(point, point:find("LEFT") and 2 or -2, point:find("TOP") and -2 or 2)
  end
end

-- A small framed label and value, like the site's .badge ("LEVEL 20"). b:Set(label, value, gold) sizes it.
function T.badge(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetHeight(22)
  local bg = T.fill(b, "BACKGROUND", C.midnight, 0.6); bg:SetAllPoints()
  b.edge = T.outline(b, 0, C.gold, 0.32)
  b.label = T.text(b, "badge"); b.label:SetPoint("LEFT", 9, 0)
  b.value = T.text(b, "badgeValue"); b.value:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
  function b:Set(label, value, gold)
    self.label:SetText(label and label:upper() or "")
    self.value:SetText(value and tostring(value) or "")
    self.value:ClearAllPoints()
    if label and label ~= "" then self.value:SetPoint("LEFT", self.label, "RIGHT", 6, 0) else self.value:SetPoint("LEFT", 9, 0) end
    local w = (label and label ~= "" and (self.label:GetStringWidth() + 6) or 0) + (self.value:GetStringWidth() or 0) + 18
    self:SetWidth(math.max(28, w))
    self.edge:SetColor(C.gold, gold and 1 or 0.32)
  end
  return b
end

-- A small outlined tag (rank in the guild list): gold for officers, quiet otherwise.
-- maxWidth (the column's width) caps it: a longer rank name ends in "…" rather than running into the next column.
function T.pill(parent, maxWidth)
  local p = CreateFrame("Frame", nil, parent)
  p:SetHeight(17)
  p.edge = T.outline(p, 0, C.gold, 0.32)
  p.text = T.text(p, "badge", "CENTER"); p.text:SetPoint("LEFT", 7, 0); p.text:SetPoint("RIGHT", -7, 0)
  function p:Set(text, gold)
    self.text:SetText((text or ""):upper())
    local c = gold and C.pale or C.muted
    self.text:SetTextColor(c[1], c[2], c[3])
    self.edge:SetColor(C.gold, gold and 1 or 0.32)
    local w = math.max(20, (self.text:GetStringWidth() or 0) + 14)
    if maxWidth then w = math.min(w, maxWidth) end
    self:SetWidth(w)
  end
  return p
end

-- A thin progress bar with a gold fill (professions, reputation). m:SetValue(fraction).
function T.meter(parent)
  local m = CreateFrame("Frame", nil, parent)
  m:SetHeight(6)
  local track = T.fill(m, "BACKGROUND", C.muted, 0.12); track:SetAllPoints()
  m.fill = T.gradient(m, "ARTWORK", "HORIZONTAL", C.gold, 1, C.pale, 1)
  m.fill:SetPoint("TOPLEFT"); m.fill:SetPoint("BOTTOMLEFT")
  function m:SetValue(f)
    f = math.max(0, math.min(1, f or 0))
    self.fill:SetShown(f > 0)
    self.fill:SetWidth(math.max(1, (self:GetWidth() or 0) * f))
    self.frac = f
  end
  m:SetScript("OnSizeChanged", function(self) if self.frac then self:SetValue(self.frac) end end)
  return m
end

-- A game icon cropped of its baked-in border, with a thin gold edge. Returns the texture.
function T.icon(parent, path, size)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(size, size)
  local tex = holder:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
  tex:SetTexture(path)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  holder.edge = T.outline(holder, 0, C.gold, 0.35, "OVERLAY")
  holder.tex = tex
  return holder
end

-- Sidebar entry: icon and label; hover glows, the selected one gets a gold bar and a gold wash fading to the right.
-- b:SetCount(n) shows a small gold count (upcoming raids).
function T.navButton(parent, label, iconPath, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(34)
  b.wash = T.gradient(b, "BACKGROUND", "HORIZONTAL", C.gold, 0.22, C.gold, 0)
  b.wash:SetAllPoints()
  b.bar = T.fill(b, "ARTWORK", C.gold, 1)
  b.bar:SetPoint("TOPLEFT", 0, -6); b.bar:SetPoint("BOTTOMLEFT", 0, 6); b.bar:SetWidth(3)
  local hl = T.gradient(b, "HIGHLIGHT", "HORIZONTAL", C.gold, 0.12, C.gold, 0)
  hl:SetAllPoints()
  b.icon = T.icon(b, iconPath, 18)
  b.icon:SetPoint("LEFT", 18, 0)
  b.label = T.text(b, "nav")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 11, 0)
  b.label:SetText(label:upper())
  b.count = CreateFrame("Frame", nil, b)
  b.count:SetSize(18, 15); b.count:SetPoint("RIGHT", -14, 0)
  local cbg = T.fill(b.count, "BACKGROUND", C.gold, 1); cbg:SetAllPoints()
  b.count.text = T.text(b.count, "badge", "CENTER"); b.count.text:SetPoint("CENTER", 0, 0)
  b.count.text:SetTextColor(C.navy[1], C.navy[2], C.navy[3]); b.count.text:SetShadowColor(0, 0, 0, 0)
  b.count:Hide()
  function b:SetCount(n)
    self.count:SetShown((n or 0) > 0)
    self.count.text:SetText(n and tostring(n) or "")
    self.count:SetWidth(math.max(18, (self.count.text:GetStringWidth() or 0) + 10))
  end
  function b:SetSelected(on)
    self.wash:SetShown(on)
    self.bar:SetShown(on)
    local c = on and C.pale or C.text
    self.label:SetTextColor(c[1], c[2], c[3], on and 1 or 0.8)
    self.icon.tex:SetDesaturated(not on)
    self.icon.tex:SetAlpha(on and 1 or 0.75)
    self.icon.edge:SetAlpha(on and 0.9 or 0.3)
  end
  b:SetSelected(false)
  b:SetScript("OnClick", onClick)
  return b
end

-- Icons inside text: a class crest or an item's icon, as a |T...|t escape.
function T.classIcon(classFile, size)
  local c = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
  if not c then return "" end
  size = size or 16
  return string.format("|TInterface\\WorldStateFrame\\ICONS-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t ", size, size,
    c[1] * 256 + 4, c[2] * 256 - 4, c[3] * 256 + 4, c[4] * 256 - 4)
end

function T.itemIcon(itemID, size)
  local icon = itemID and (ns.try(C_Item and C_Item.GetItemIconByID, itemID) or ns.try(GetItemIcon, itemID))
  if not icon then return "" end
  size = size or 16
  return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", tostring(icon), size, size)
end

-- The site's .card: navy gradient, gold line, a fainter line inside, and the four corner brackets.
function T.card(frame)
  local bg = T.fill(frame, "BACKGROUND", C.midnight, 0.97)
  bg:SetAllPoints()
  pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(C.midnight[1], C.midnight[2], C.midnight[3], 0.98),
    CreateColor(C.royal[1], C.royal[2], C.royal[3], 0.97))
  T.outline(frame, 0, C.gold, 1)
  T.outline(frame, 5, C.gold, 0.22)
  T.outline(frame, 10, C.gold, 0.38)
  local coords = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 }, BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 } }
  local offsets = { TOPLEFT = { -7, 7 }, TOPRIGHT = { 7, 7 }, BOTTOMLEFT = { -7, -7 }, BOTTOMRIGHT = { 7, -7 } }
  for point, tc in pairs(coords) do
    local t = frame:CreateTexture(nil, "OVERLAY")
    t:SetTexture(MEDIA .. "bracket")
    t:SetSize(42, 42)
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    t:SetPoint(point, offsets[point][1], offsets[point][2])
  end
end

-- The gold rule with a diamond in the middle (.rule on the site).
function T.rule(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(10)
  local left, right = T.fill(f, "ARTWORK", C.gold, 0.6), T.fill(f, "ARTWORK", C.gold, 0.6)
  left:SetHeight(1); right:SetHeight(1)
  left:SetPoint("LEFT"); left:SetPoint("RIGHT", f, "CENTER", -9, 0)
  right:SetPoint("RIGHT"); right:SetPoint("LEFT", f, "CENTER", 9, 0)
  local diamond = T.fill(f, "ARTWORK", C.gold, 1)
  diamond:SetSize(7, 7)
  diamond:SetPoint("CENTER")
  pcall(diamond.SetRotation, diamond, math.rad(45))
  return f
end

-- Buttons like the site's .cta: "solid" (gold, navy text) or "tab" (gold outline, solid when selected).
function T.button(parent, label, width, onClick, kind)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 120, 26)
  b.bg = T.fill(b, "BACKGROUND", C.gold, 1)
  b.bg:SetAllPoints()
  b.edge = T.outline(b, 0, C.pale, 1)
  b.label = T.text(b, "button", "CENTER")
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetText(label:upper())
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(WHITE)
  hl:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.18)
  function b:SetSelected(on)
    local solid = kind ~= "tab" or on
    self.bg:SetAlpha(solid and 1 or 0)
    self.edge:SetColor(solid and C.pale or C.gold, solid and 1 or 0.55)
    local c = solid and C.navy or C.gold
    self.label:SetTextColor(c[1], c[2], c[3])
    self.label:SetShadowColor(0, 0, 0, solid and 0 or 0.85)
  end
  b:SetSelected(false)
  b:SetScript("OnClick", onClick)
  -- Greyed out and unclickable when there's nothing it can do; why goes in the tooltip (optional).
  function b:SetUsable(on, why)
    on = on and true or false
    self:SetEnabled(on)
    self:SetAlpha(on and 1 or T.DISABLED_ALPHA)
    self.why = not on and why or nil
  end
  b:HookScript("OnEnter", function(self)
    if not self.why then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.why, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:HookScript("OnLeave", function(self) if self.why then GameTooltip:Hide() end end)
  return b
end

-- On/off switch: an outlined track with a square knob, filled gold with the knob on the right when on.
-- onChange(on) gets the state a click asks for; the caller saves it and calls SetOn.
function T.switch(parent, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(36, 18)
  b.track = T.fill(b, "BACKGROUND", C.midnight, 1)
  b.track:SetAllPoints()
  b.edge = T.outline(b, 0, C.gold, 0.55)
  b.knob = T.fill(b, "ARTWORK", C.muted, 1)
  b.knob:SetSize(12, 12)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); hl:SetTexture(WHITE); hl:SetVertexColor(C.pale[1], C.pale[2], C.pale[3], 0.15)
  function b:SetOn(on)
    self.on = on and true or false
    local track, knob = on and C.gold or C.midnight, on and C.navy or C.muted
    self.track:SetVertexColor(track[1], track[2], track[3], 1)
    self.knob:SetVertexColor(knob[1], knob[2], knob[3], 1)
    self.knob:ClearAllPoints()
    self.knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
    self.edge:SetColor(on and C.pale or C.gold, on and 1 or 0.55)
  end
  b:SetOn(false)
  b:SetScript("OnClick", function(self) onChange(not self.on) end)
  return b
end

-- Search box: midnight field with a gold hairline, placeholder text while empty.
function T.searchBox(parent, width, placeholder, onChange)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(width, 26)
  e:SetAutoFocus(false)
  e:SetFontObject(T.fonts.small)
  e:SetTextInsets(10, 10, 0, 0)
  local bg = T.fill(e, "BACKGROUND", C.midnight, 1)
  bg:SetAllPoints()
  local edge = T.outline(e, 0, C.gold, 0.4)
  local hint = T.text(e, "muted")
  hint:SetPoint("LEFT", 10, 0)
  hint:SetPoint("RIGHT", -10, 0) -- a placeholder longer than the box ends in "…" instead of running past it
  hint:SetText(placeholder or "")
  local function sync() hint:SetShown((e:GetText() or "") == "" and not e:HasFocus()) end
  e:SetScript("OnTextChanged", function(self) sync(); onChange(self:GetText() or "") end)
  e:SetScript("OnEditFocusGained", function() edge:SetAlpha(1); sync() end)
  e:SetScript("OnEditFocusLost", function() edge:SetAlpha(0.4); sync() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

function T.closeButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(28, 28)
  local x = T.text(b, "close", "CENTER")
  x:SetPoint("CENTER", 0, 1)
  x:SetText("×")
  b:SetScript("OnEnter", function() x:SetTextColor(C.pale[1], C.pale[2], C.pale[3]) end)
  b:SetScript("OnLeave", function() x:SetTextColor(C.warm[1], C.warm[2], C.warm[3]) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A plain panel (.panel): faint navy fill and a gold hairline.
function T.panel(frame)
  local bg = T.fill(frame, "BACKGROUND", C.midnight, 0.55)
  bg:SetAllPoints()
  T.outline(frame, 0, C.gold, 0.32)
end

-- Escape closes this frame only. (Frames in UISpecialFrames all close together, so a dialog listed there took the
-- whole Perpetua window with it.) In combat the key can't be kept from the game, so there it just closes.
function T.escapeCloses(f)
  f:EnableKeyboard(true)
  pcall(f.SetPropagateKeyboardInput, f, true) -- other keys (movement!) keep working, in combat too
  f:SetScript("OnKeyDown", function(self, key)
    local own = key == "ESCAPE"
    if not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, not own) end
    if own then self:Hide() end
  end)
end

-- Addons can't open a browser, so a web address is shown in a box, selected, ready for Ctrl+C.
local copyBox
function T.copyBox(title, url)
  if not copyBox then
    local f = CreateFrame("Frame", "PerpetuaCopyBox", UIParent)
    f:SetSize(520, 150)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    T.window(f)
    T.escapeCloses(f)
    f.title = T.text(f, "heading")
    f.title:SetPoint("TOPLEFT", 22, -20)
    f.title:SetPoint("RIGHT", -50, 0)
    local close = T.closeButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -12)
    local field = CreateFrame("EditBox", nil, f)
    field:SetPoint("TOPLEFT", 22, -52)
    field:SetPoint("RIGHT", -22, 0)
    field:SetHeight(30)
    field:SetAutoFocus(false)
    field:SetFontObject(ChatFontNormal)
    field:SetTextColor(C.pale[1], C.pale[2], C.pale[3])
    field:SetTextInsets(10, 10, 0, 0)
    local bg = T.fill(field, "BACKGROUND", C.midnight, 1)
    bg:SetAllPoints()
    T.outline(field, 0, C.gold, 0.6)
    -- Read-only: typing puts the address back, selected.
    field:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(f.url); self:HighlightText() end end)
    field:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    field:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    field:SetScript("OnEscapePressed", function() f:Hide() end)
    field:SetScript("OnEnterPressed", function() f:Hide() end)
    -- Close once it's been copied.
    field:SetScript("OnKeyUp", function(_, key) if key == "C" and IsControlKeyDown() then C_Timer.After(0.1, function() f:Hide() end) end end)
    f.field = field
    f.hint = T.text(f, "muted")
    f.hint:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -10)
    f.hint:SetText("Press Ctrl+C to copy, then paste it into your browser.")
    copyBox = f
  end
  copyBox.url = url
  copyBox:SetScale(T.scale())
  copyBox.title:SetText((title or "Open on the site"):upper())
  copyBox.field:SetText(url)
  copyBox:Show()
  copyBox.field:SetFocus()
  copyBox.field:HighlightText()
end

-- A small modal dialog in the window's style, used instead of Blizzard's StaticPopups (which addon code would
-- taint). opts: title, text, accept (button label), input = { text, maxLetters, multiline, height },
-- onAccept(value) (value is the input's text when there is one), or command(value) for a guild action the game
-- only allows through Blizzard's secure slash commands: it returns the macro text (e.g. "/gremove Name"), or nil
-- while the input isn't right, and the OK button runs it with a secure click (GuildTakeover.lua). Only one is open at a time.
local dialog
function T.dialog(opts)
  if not dialog then
    local f = CreateFrame("Frame", "PerpetuaDialog", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    T.window(f)
    T.escapeCloses(f)
    f.title = T.text(f, "heading")
    f.title:SetPoint("TOPLEFT", 22, -20); f.title:SetPoint("RIGHT", -22, 0)
    f.body = T.text(f, "body")
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -10); f.body:SetPoint("RIGHT", -22, 0)
    f.body:SetWordWrap(true); f.body:SetJustifyV("TOP")
    -- One edit box in a scroll frame serves both one-line and multi-line input.
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("LEFT", 22, 0); holder:SetPoint("RIGHT", -22, 0)
    local bg = T.fill(holder, "BACKGROUND", C.midnight, 1); bg:SetAllPoints()
    T.outline(holder, 0, C.gold, 0.6)
    local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -6); scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextColor(C.text[1], C.text[2], C.text[3])
    edit:SetAutoFocus(false)
    edit:SetWidth(300)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnSizeChanged", function(self, w) edit:SetWidth(w) end)
    holder:SetScript("OnMouseDown", function() edit:SetFocus() end)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    edit:SetScript("OnEnterPressed", function(self)
      if self:IsMultiLine() and not IsShiftKeyDown() then self:Insert("\n") return end
      if f.command then -- a guild action needs a real click on the button
        f.hint:SetText("Click " .. (f.ok.label:GetText() or "OK"):lower() .. " to confirm.")
        return
      end
      f.ok:Click()
    end)
    edit:SetScript("OnTextChanged", function(self)
      local n, max = #(self:GetText() or ""), self:GetMaxLetters()
      f.count:SetText(max > 0 and (n .. " / " .. max) or "")
      if f.okUsable then f.ok:SetUsable(f.okUsable(self:GetText() or ""), f.okWhy) end
    end)
    f.holder, f.scroll, f.edit = holder, scroll, edit
    f.count = T.text(f, "muted", "RIGHT")
    f.count:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -4)
    f.hint = T.text(f, "muted")
    f.hint:SetPoint("BOTTOMLEFT", 22, 24)
    f.ok = T.button(f, "OK", 110, function()
      if f.command then return end -- guild actions run through the secure button over this one (or not, in combat)
      local value = f.holder:IsShown() and (f.edit:GetText() or "") or nil
      local cb = f.onAccept
      f:Hide()
      if cb then cb(value) end
    end)
    f.cancel = T.button(f, "Cancel", 110, function() f:Hide() end, "tab")
    f.cancel:SetPoint("BOTTOMRIGHT", -22, 18)
    f.ok:SetPoint("RIGHT", f.cancel, "LEFT", -10, 0)
    f:SetScript("OnHide", function() f.onAccept, f.command = nil, nil; f.edit:ClearFocus() end)
    dialog = f
  end
  local f = dialog
  f:SetScale(T.scale())
  f.onAccept = opts.onAccept
  f.command = opts.command
  -- okUsable(text): the confirm button stays greyed until the input is right (okWhy says what's missing). A dialog
  -- with nothing to confirm (no onAccept or command) shows just one button.
  f.okUsable, f.okWhy = opts.okUsable, opts.okWhy
  f.hint:SetText("")
  local confirmable = opts.onAccept ~= nil or opts.command ~= nil
  f.ok:SetShown(confirmable)
  f.cancel.label:SetText(confirmable and "CANCEL" or "OK")
  f.ok:SetUsable(true)
  if f.command and not f.secured and ns.secureGuildCommand then
    f.secured = true
    ns.secureGuildCommand(f.ok, function()
      return f:IsShown() and f.command and f.command(f.holder:IsShown() and (f.edit:GetText() or "") or nil) or nil
    end, nil, nil, function() f:Hide(); if C_GuildInfo and C_GuildInfo.GuildRoster then C_Timer.After(0.6, function() pcall(C_GuildInfo.GuildRoster) end) end end)
  end
  f.title:SetText((opts.title or ""):upper())
  f.body:SetText(opts.text or "")
  f.ok.label:SetText((opts.accept or "OK"):upper())
  local input = opts.input
  local bodyH = (opts.text and opts.text ~= "") and (f.body:GetStringHeight() + 12) or 0
  local inputH = input and (input.height or (input.multiline and 120 or 30)) or 0
  f:SetSize(opts.width or 440, 20 + 22 + bodyH + inputH + (input and 26 or 0) + 62)
  f.holder:SetShown(input ~= nil)
  f.count:SetShown(input ~= nil)
  if input then
    f.holder:ClearAllPoints()
    f.holder:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -bodyH)
    f.holder:SetPoint("RIGHT", -22, 0)
    f.holder:SetHeight(inputH)
    f.edit:SetMultiLine(input.multiline and true or false)
    f.edit:SetMaxLetters(input.maxLetters or 0)
    f.edit:SetText(input.text or "")
    if f.okUsable then f.ok:SetUsable(f.okUsable(input.text or ""), f.okWhy) end
    f.edit:SetHeight(inputH - 12)
    f.edit:HighlightText()
  end
  f:ClearAllPoints()
  f:SetPoint("CENTER", 0, 120)
  f:Show()
  if input then f.edit:SetFocus() end
end

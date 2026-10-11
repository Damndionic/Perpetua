-- The Perpetua window (/perpetua): Guild, Character, Attunements, Crafters and Export tabs, all read from
-- what guild sync has collected (ns.players()). Styled after the site by Theme.lua; the only Blizzard
-- templates used are the scroll frame and the checkbox.
local _, ns = ...
local safe, try, T = ns.safe, ns.try, ns.T

local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:15|t"
local NOT_READY = "|cff4a5270—|r"
local ROW_H = 26

local main, tabs, pages, current = nil, {}, {}, nil
ns.selected = nil -- name shown in the Character tab

local function color(hex, s) return "|cff" .. hex .. s .. "|r" end
local function classed(name, classFile) return color(ns.classColor(classFile), safe(name)) end

-- All players this guild has heard from, merged with the guild roster when asked (members without the addon).
local function everyone(includeRoster)
  local list, byName = {}, {}
  for name, rec in pairs(ns.players()) do
    if type(rec) == "table" then
      local row = { name = name, rec = rec, profile = rec.profile, class = rec.class, level = ns.levelOf(name, rec.level) }
      list[#list + 1] = row
      byName[name] = row
    end
  end
  if includeRoster and GetNumGuildMembers then
    for i = 1, (try(GetNumGuildMembers) or 0) do
      local full, _, _, level, _, _, _, _, online, _, classFile = try(GetGuildRosterInfo, i)
      local name = ns.playerKey(full)
      if name and not byName[name] then
        list[#list + 1] = { name = name, class = classFile, level = level, online = online, noAddon = true }
      end
    end
  end
  return list
end

-- ---------- list widget ----------
-- cols = { { title, width, justify, pill = true } }; rows = { { cells = {...}, onClick = fn, onEnter = fn,
-- bar = { r, g, b } (a class-colour bar at the row's left edge), selected = true } }. A pill column's cell is
-- { text, gold } and draws as an outlined tag.

local function List(parent, cols, onSort)
  local L = { rows = {}, cols = cols }
  local header = CreateFrame("Frame", nil, parent)
  header:SetPoint("TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", -26, 0)
  header:SetHeight(22)
  local underline = T.fill(header, "ARTWORK", T.C.gold, 0.25)
  underline:SetHeight(1)
  underline:SetPoint("BOTTOMLEFT"); underline:SetPoint("BOTTOMRIGHT")
  local x = 12
  for i, c in ipairs(cols) do
    local h = CreateFrame("Button", nil, header)
    h:SetPoint("LEFT", x, 0)
    h:SetSize(c[2], 22)
    local fs = T.text(h, "label", c[3])
    fs:SetAllPoints()
    fs:SetText(c[1]:upper())
    h.label = fs
    if onSort then
      h:SetScript("OnClick", function() onSort(i) end)
      h:SetScript("OnEnter", function() fs:SetTextColor(T.C.pale[1], T.C.pale[2], T.C.pale[3]) end)
      h:SetScript("OnLeave", function() fs:SetTextColor(T.C.gold[1], T.C.gold[2], T.C.gold[3]) end)
    end
    c.header = h
    x = x + c[2] + 8
  end
  L.header = header

  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -24)
  scroll:SetPoint("BOTTOMRIGHT", -26, 0)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(x, 1)
  scroll:SetScrollChild(child)
  L.child = child

  local function row(i)
    if L.rows[i] then return L.rows[i] end
    local r = CreateFrame("Button", nil, child)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", child, "RIGHT")
    -- Thin separators instead of stripes; a soft gold wash on hover.
    local sep = T.fill(r, "BACKGROUND", T.C.gold, 0.08)
    sep:SetHeight(1); sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT")
    local hl = T.fill(r, "HIGHLIGHT", T.C.gold, 0.07)
    hl:SetAllPoints()
    r.bar = T.fill(r, "ARTWORK", { 1, 1, 1 }, 1)
    r.bar:SetPoint("TOPLEFT", 0, -1); r.bar:SetPoint("BOTTOMLEFT", 0, 1); r.bar:SetWidth(3)
    r.selFill = T.gradient(r, "BACKGROUND", "HORIZONTAL", T.C.gold, 0.16, T.C.gold, 0.04)
    r.selFill:SetAllPoints()
    r.selEdge = T.outline(r, 0, T.C.gold, 0.55, "ARTWORK")
    r.cells, r.pills = {}, {}
    local cx = 12
    for c, col in ipairs(cols) do
      local fs = T.text(r, "small", col[3])
      fs:SetPoint("LEFT", cx, 0)
      fs:SetWidth(col[2])
      r.cells[c] = fs
      if col.pill then
        local pill = T.pill(r, col[2])
        pill:SetPoint("LEFT", cx, 0)
        r.pills[c] = pill
      end
      cx = cx + col[2] + 8
    end
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button) if self.data and self.data.onClick then self.data.onClick(self.data, button, self) end end)
    r:SetScript("OnEnter", function(self) if self.data and self.data.onEnter then self.data.onEnter(self, self.data) end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    L.rows[i] = r
    return r
  end

  function L:SetRows(data)
    child:SetWidth(math.max(scroll:GetWidth() or 0, 1))
    for i, d in ipairs(data) do
      local r = row(i)
      r.data = d
      for c = 1, #cols do
        local v = d.cells[c]
        if r.pills[c] then
          r.cells[c]:SetText("")
          r.pills[c]:SetShown(type(v) == "table" and v[1] ~= nil and v[1] ~= "")
          if type(v) == "table" then r.pills[c]:Set(v[1], v[2]) end
        else
          r.cells[c]:SetText(v or "")
        end
      end
      r.bar:SetShown(d.bar ~= nil)
      if d.bar then r.bar:SetVertexColor(d.bar[1], d.bar[2], d.bar[3], 1) end
      r.selFill:SetShown(d.selected and true or false)
      r.selEdge:SetAlpha(d.selected and 0.55 or 0)
      r:Show()
    end
    for i = #data + 1, #L.rows do L.rows[i]:Hide(); L.rows[i].data = nil end
    child:SetHeight(math.max(1, #data * ROW_H))
  end
  return L
end

ns.List = List -- GuildUI.lua's roster uses it too

-- ---------- text canvas (Character tab) ----------
-- Two scrolling columns of lines; item lines are buttons with the item's tooltip.

local LINE_H = { name = 30, heading = 26, body = 21, small = 21, muted = 19 }

local function Canvas(parent, layout)
  local C = { lines = {}, rules = {}, used = 0, usedRules = 0, y = { 0, 0 }, col = 1 }
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", -26, 0)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(layout and layout.width or 780, 1)
  scroll:SetScrollChild(child)
  local COL_X, COL_W = layout and layout.x or { 6, 386 }, layout and layout.w or 356

  function C:Reset()
    for _, l in ipairs(self.lines) do l:Hide(); l.link = nil; l.onClick = nil end
    for _, r in ipairs(self.rules) do r:Hide() end
    for _, f in ipairs(self.paras or {}) do f:Hide() end
    for _, b in ipairs(self.bars or {}) do b.meter:Hide(); b.text:Hide() end
    self.usedBars = 0
    self.used, self.usedRules, self.usedParas, self.y, self.col = 0, 0, 0, { 0, 0 }, 1
    scroll:SetVerticalScroll(0)
  end
  function C:Col(n) self.col = n end
  function C:Gap(h) self.y[self.col] = self.y[self.col] + (h or 10) end
  -- text, font key (Theme fonts), link (hyperlink for the tooltip), indent, right (short text kept at the right
  -- edge: a long text is cut short before it, never the right text)
  function C:Line(text, fontKey, link, indent, right)
    fontKey = fontKey or "body"
    self.used = self.used + 1
    local l = self.lines[self.used]
    if not l then
      l = CreateFrame("Button", nil, child)
      l.fs = T.text(l, "body")
      l.right = T.text(l, "body", "RIGHT")
      l.right:SetPoint("TOPRIGHT"); l.right:SetPoint("BOTTOMRIGHT")
      l:SetScript("OnEnter", function(b)
        if not b.link then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, b.link)
        GameTooltip:Show()
      end)
      l:SetScript("OnLeave", function() GameTooltip:Hide() end)
      l:SetScript("OnClick", function(b) if b.onClick then b.onClick() end end)
      self.lines[self.used] = l
    end
    l.fs:SetFontObject(T.fonts[fontKey])
    l.fs:SetWordWrap(false)
    l.fs:SetText(text)
    l.right:SetFontObject(T.fonts[fontKey])
    l.right:SetText(right or "")
    l.right:SetShown(right ~= nil)
    l.fs:ClearAllPoints()
    l.fs:SetPoint("TOPLEFT"); l.fs:SetPoint("BOTTOMLEFT")
    if right then l.fs:SetPoint("RIGHT", l.right, "LEFT", -8, 0) else l.fs:SetPoint("RIGHT") end
    local h = LINE_H[fontKey] or 20
    local col = self.col
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", COL_X[col] + (indent or 0), -self.y[col])
    l:SetSize(COL_W - (indent or 0), h)
    l.link = link
    l.onClick = nil
    l:Show()
    self.y[col] = self.y[col] + h
    child:SetHeight(math.max(self.y[1], self.y[2]) + 10)
    return l
  end
  -- Wrapped text (forum posts). Each paragraph gets a font string anchored only at its top and sides, so WoW
  -- lays out every line and GetStringHeight reports the real height (a fixed-height box would clip it).
  C.paras, C.usedParas = {}, 0
  function C:Para(text, fontKey, indent)
    self.usedParas = self.usedParas + 1
    local fs = self.paras[self.usedParas]
    if not fs then
      fs = child:CreateFontString(nil, "OVERLAY")
      fs:SetJustifyH("LEFT")
      fs:SetJustifyV("TOP")
      fs:SetWordWrap(true)
      self.paras[self.usedParas] = fs
    end
    local col = self.col
    fs:SetFontObject(T.fonts[fontKey or "body"])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", COL_X[col] + (indent or 0), -self.y[col])
    fs:SetWidth(COL_W - (indent or 0))
    fs:SetText(text)
    fs:Show()
    local h = math.max(LINE_H[fontKey or "body"] or 20, math.ceil((fs:GetStringHeight() or 16) + 6))
    self.y[col] = self.y[col] + h
    child:SetHeight(math.max(self.y[1], self.y[2]) + 10)
    return fs
  end
  -- A line you can click (opens the copy box for a site address).
  function C:Action(text, onClick, fontKey, indent)
    local l = self:Line(color(T.HEX.warm, text), fontKey or "small", nil, indent)
    l.onClick = onClick
    return l
  end
  -- A label, a gold progress bar and a value on one line (professions, reputation).
  C.bars, C.usedBars = {}, 0
  function C:Bar(label, value, fraction, indent)
    local l = self:Line(label, "small", nil, indent)
    self.usedBars = self.usedBars + 1
    local b = self.bars[self.usedBars]
    if not b then
      b = { meter = T.meter(child), text = T.text(child, "muted", "RIGHT") }
      self.bars[self.usedBars] = b
    end
    local w = COL_W - (indent or 0)
    b.meter:ClearAllPoints(); b.meter:SetPoint("LEFT", l, "LEFT", math.floor(w * 0.36), 0); b.meter:SetWidth(math.floor(w * 0.40))
    b.text:ClearAllPoints(); b.text:SetPoint("RIGHT", l, "RIGHT", -10, 0); b.text:SetWidth(math.floor(w * 0.22))
    b.meter:SetValue(fraction); b.text:SetText(value or "")
    b.meter:Show(); b.text:Show()
    return l
  end
  -- Section heading: Cinzel caps over a faint gold hairline.
  function C:Heading(text)
    if self.y[self.col] > 0 then self:Gap(12) end
    self:Line(text:upper(), "heading")
    self.usedRules = self.usedRules + 1
    local r = self.rules[self.usedRules]
    if not r then r = T.gradient(child, "ARTWORK", "HORIZONTAL", T.C.gold, 0.45, T.C.gold, 0); r:SetHeight(1); self.rules[self.usedRules] = r end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", COL_X[self.col], -(self.y[self.col] - 2))
    r:SetWidth(COL_W - 10)
    r:Show()
    self:Gap(4)
  end
  return C
end

-- ---------- Guild tab ----------


local function professionsText(p)
  local out = {}
  for _, x in ipairs(p and p.profs or {}) do
    if x.p == 1 then out[#out + 1] = safe(x.n) .. (x.r and color(T.HEX.muted, " " .. x.r) or "") end
  end
  return table.concat(out, ", ")
end

local function raidsText(p)
  local out = {}
  for _, a in ipairs(ns.ATTUNEMENTS) do
    if a.group == "Raids" and ns.attuned(p, a) then out[#out + 1] = a.short end
  end
  return color(T.HEX.gold, table.concat(out, " "))
end

-- Characters grouped by WoW account: every profile lists the account's other characters (PerpetuaDB.account on
-- theirs), so anyone linked by those lists is one person. Returns name -> group (a shared table of names).
local function accountGroups(names)
  local parent = {}
  local function find(x)
    while parent[x] and parent[x] ~= x do x = parent[x] end
    return x
  end
  local function union(a, b)
    parent[a] = parent[a] or a
    parent[b] = parent[b] or b
    local ra, rb = find(a), find(b)
    if ra ~= rb then parent[rb] = ra end
  end
  for _, name in ipairs(names) do
    parent[name] = parent[name] or name
    local rec = ns.players()[name]
    for _, alt in ipairs(rec and rec.profile and rec.profile.alts or {}) do
      if alt.n then union(name, ns.fullName(alt.n, alt.s)) end
    end
  end
  for alt in pairs(PerpetuaDB.account or {}) do if ns.selfName then union(ns.selfName, alt) end end
  local groups, out = {}, {}
  for _, name in ipairs(names) do
    local root = find(name)
    groups[root] = groups[root] or {}
    table.insert(groups[root], name)
    out[name] = groups[root]
  end
  return out
end

ns.professionsText, ns.raidsText, ns.accountGroups = professionsText, raidsText, accountGroups

-- The Guild page itself lives in GuildUI.lua (roster, guild sync's data and the officer tools in one list).
local function buildGuild(page) ns.buildRoster(page) end
local function renderGuild() ns.renderRoster() end

-- ---------- Character tab ----------

local char = {}

-- The Character page: a header block (class crest, name, level and spec, guild and freshness, a button to the
-- site), then gear and stats on the left, talents, professions, attunements and reputation on the right.
-- The Character page's header card, like the site's character page: a class-coloured edge and wash, the class
-- crest, the name large with the surname and spec under it, badges on the right.
local function buildCharacter(page)
  local head = CreateFrame("Frame", nil, page)
  head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT", -26, 0); head:SetHeight(90)
  head:SetClipsChildren(true)
  local base = T.fill(head, "BACKGROUND", T.C.midnight, 0.85); base:SetAllPoints()
  char.wash = T.gradient(head, "BACKGROUND", "HORIZONTAL", T.C.gold, 0.22, T.C.royal, 0)
  char.wash:SetPoint("TOPLEFT"); char.wash:SetPoint("BOTTOMLEFT"); char.wash:SetWidth(360)
  T.outline(head, 0, T.C.gold, 0.5)
  char.bar = T.fill(head, "ARTWORK", T.C.gold, 1); char.bar:SetPoint("TOPLEFT", 1, -1); char.bar:SetPoint("BOTTOMLEFT", 1, 1); char.bar:SetWidth(4)
  local mark = head:CreateTexture(nil, "BORDER")
  mark:SetTexture(T.CREST); mark:SetSize(190, 190); mark:SetPoint("TOPRIGHT", 30, 50); mark:SetAlpha(0.07)
  local holder = CreateFrame("Frame", nil, head)
  holder:SetSize(58, 58); holder:SetPoint("LEFT", 20, 0)
  local bg = T.fill(holder, "BACKGROUND", T.C.midnight, 1)
  bg:SetAllPoints()
  char.icon = holder:CreateTexture(nil, "ARTWORK")
  char.icon:SetPoint("TOPLEFT", 3, -3); char.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  char.iconEdge = T.outline(holder, 0, T.C.gold, 0.8, "OVERLAY")
  char.name = T.text(head, "hero"); char.name:SetPoint("TOPLEFT", holder, "TOPRIGHT", 18, -6)
  char.line1 = T.text(head, "surname"); char.line1:SetPoint("TOPLEFT", char.name, "BOTTOMLEFT", 0, -4)
  char.line2 = T.text(head, "muted"); char.line2:SetPoint("TOPLEFT", char.line1, "BOTTOMLEFT", 0, -3)
  char.badges = {}
  for i = 1, 4 do char.badges[i] = T.badge(head) end
  char.badges[4]:SetPoint("TOPRIGHT", -16, -14)
  for i = 3, 1, -1 do char.badges[i]:SetPoint("RIGHT", char.badges[i + 1], "LEFT", -6, 0) end
  char.site = T.button(head, "Open on the site", 150, function()
    if char.shown then T.copyBox(char.shown .. " on the site", "https://" .. ns.SITE .. "/characters/" .. (char.shown:gsub(" ", "-"))) end
  end, "tab")
  char.site:SetHeight(22)
  char.site:SetPoint("BOTTOMRIGHT", -16, 12)
  local area = CreateFrame("Frame", nil, page)
  area:SetPoint("TOPLEFT", 0, -104); area:SetPoint("BOTTOMRIGHT")
  char.canvas = Canvas(area)
end

-- badges = { { label, value, gold }, ... } (up to four, right-aligned).
local function characterHeader(name, classFile, line1, line2, badges)
  char.shown = name
  local coords = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
  if coords then
    char.icon:SetTexture("Interface\\WorldStateFrame\\ICONS-CLASSES")
    char.icon:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
  else
    char.icon:SetTexture(T.CREST)
    char.icon:SetTexCoord(0, 1, 0, 1)
  end
  local rgb = classFile and ns.classRGB(classFile) or T.C.gold
  char.bar:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
  pcall(char.wash.SetGradient, char.wash, "HORIZONTAL", CreateColor(rgb[1], rgb[2], rgb[3], 0.22), CreateColor(T.C.royal[1], T.C.royal[2], T.C.royal[3], 0))
  char.iconEdge:SetColor(T.C.gold, classFile and 0.8 or 0.3)
  local first, surname = (name or ""):match("^(%S+)%s+(.+)$")
  char.name:SetText(name and color(ns.classColor(classFile), safe(first or name)) or "")
  char.line1:SetText(((surname and (safe(surname) .. (line1 and line1 ~= "" and "  ·  " or ""))) or "") .. (line1 or ""))
  char.line2:SetText(line2 or "")
  -- Badges fill from the right.
  local list = badges or {}
  for i = 1, 4 do
    local b = char.badges[5 - i]
    local item = list[#list - i + 1]
    b:SetShown(item ~= nil)
    if item then b:Set(item[1], item[2], item[3]) end
  end
  char.site:SetShown(name ~= nil)
end

local function itemLink(g)
  return "item:" .. g.id .. ":" .. (g.e or 0) .. ":0:0:0:0:" .. (g.sf or 0)
end

local function renderCharacter()
  local C = char.canvas
  C:Reset()
  local name = ns.selected or ns.selfName
  local rec = name and ns.players()[name]
  local p = rec and ns.fullProfile(rec)
  if not p then
    if rec then
      local old = rec.addon and ns.newer(ns.VERSION, rec.addon)
      characterHeader(name, rec.class, old and ("Their addon (" .. safe(rec.addon) .. ") is older than yours and can't share with it.")
        or "Their profile hasn't arrived yet.", old and ("Ask them to update: " .. ns.SITE .. "/addon") or "It comes through while you're both online.")
    else
      characterHeader(nil, nil, "Pick someone on the Guild tab.", nil)
    end
    return
  end
  local c = p.char or {}
  local muted = T.HEX.muted
  local spec = p.spec and p.spec.n ~= c.class and p.spec.n or nil
  local ilvl = ns.avgItemLevel(p)
  local level = ns.levelOf(name, c.level)
  local line1 = (c.race and (safe(c.race) .. " ") or "") .. (c.class and ((spec and (safe(spec) .. " ") or "") .. safe(c.class)) or "")
  local line2 = {}
  if c.guild then line2[#line2 + 1] = color(T.HEX.warm, "<" .. safe(c.guild) .. ">") end
  line2[#line2 + 1] = "profile from " .. ns.ago(rec.pt)
  local badges = { { "Level", level or "?", true } }
  if ilvl then badges[#badges + 1] = { "Avg iLvl", ilvl } end
  if p.spec and p.spec.role and ns.ROLE[p.spec.role] then badges[#badges + 1] = { "Role", ns.ROLE[p.spec.role] } end
  if c.guildRank then badges[#badges + 1] = { nil, safe(c.guildRank), true } end
  characterHeader(name, c.classFile, line1, table.concat(line2, "  ·  "), badges)
  -- Left column: gear, stats
  C:Col(1)
  C:Heading("Gear")
  local bySlot = {}
  for _, g in ipairs(p.gear or {}) do bySlot[g.s] = g end
  for _, slot in ipairs(ns.SLOTS) do
    local g = bySlot[slot[1]]
    if g then
      local q = ns.QUALITY[g.q or 1] or "ffffff"
      C:Line(T.itemIcon(g.id, 17) .. color(q, safe(g.n or ("Item " .. g.id))) .. color(muted, "  " .. slot[2]),
        "small", itemLink(g), nil, g.il and color(muted, g.il) or nil)
      if g.en then C:Line(color("7fe07a", safe(g.en)), "muted", nil, 22) end
    end
  end
  local s, r = p.stats or {}, p.res or {}
  if next(s) then
    C:Heading("Stats")
    C:Line(string.format("Health %s    Mana %s    Armor %s", s.hp or "-", s.mp or "-", s.armor or "-"), "small")
    C:Line(string.format("Str %s   Agi %s   Sta %s   Int %s   Spi %s", s.str or "-", s.agi or "-", s.sta or "-", s["int"] or "-", s.spi or "-"), "small")
    C:Line(color("ff7a45", "Fire " .. (r.fire or 0)) .. "   " .. color("7fd46a", "Nature " .. (r.nature or 0)) .. "   " ..
      color("6fc8ff", "Frost " .. (r.frost or 0)) .. "   " .. color("b28cff", "Shadow " .. (r.shadow or 0)) .. "   " ..
      color("f0d8ff", "Arcane " .. (r.arcane or 0)), "small")
  end

  -- Right column: talents, professions, attunements, reputation
  C:Col(2)
  C:Heading("Talents")
  if p.spec and p.spec.n then C:Line(safe(p.spec.n) .. (p.spec.role and ns.ROLE[p.spec.role] and color(muted, "  ·  " .. ns.ROLE[p.spec.role]) or ""), "body") end
  for _, t in ipairs(p.talents and p.talents.trees or {}) do C:Line(safe(t.n) .. color(T.HEX.gold, "  " .. (t.pts or 0)), "small") end
  local talents = {}
  for _, t in ipairs(p.talents and p.talents.list or {}) do talents[#talents + 1] = t end
  table.sort(talents, function(a, b) return (a.y or 0) < (b.y or 0) or ((a.y or 0) == (b.y or 0) and (a.x or 0) < (b.x or 0)) end)
  for _, t in ipairs(talents) do
    C:Line(safe(t.n) .. color(t.r == t.m and T.HEX.ok or T.HEX.gold, "  " .. (t.r or 0) .. (t.m and ("/" .. t.m) or "")), "small", t.sp and ("spell:" .. t.sp) or nil, 8)
  end
  C:Heading("Professions")
  for _, x in ipairs(p.profs or {}) do
    local n = x.recipes and #x.recipes or 0
    if x.m and x.m > 0 then
      C:Bar(safe(x.n) .. (n > 0 and color(T.HEX.gold, "  " .. n) or ""), (x.r or 0) .. " / " .. x.m, (x.r or 0) / x.m)
    else
      C:Line(safe(x.n) .. (n > 0 and color(T.HEX.gold, "  ·  " .. n .. " recipes") or ""), "small")
    end
  end
  C:Heading("Attunements & keys")
  for _, a in ipairs(ns.ATTUNEMENTS) do
    local done = ns.attuned(p, a)
    C:Line((done and READY or NOT_READY) .. "  " .. (done and a.name or color("7a8298", a.name)), "small")
  end
  local reps = {}
  for _, x in ipairs(p.rep or {}) do if x.id then reps[x.id] = x end end
  local any = false
  for _, id in ipairs(ns.RAID_FACTIONS) do
    local x = reps[id]
    if x and x.s then
      if not any then C:Heading("Reputation"); any = true end
      local standing = color(ns.STANDING_COLOR[x.s] or "ffffff", ns.STANDING[x.s] or "")
      if x.v and x.m and x.m > 0 then C:Bar(safe(x.n), standing, x.v / x.m) else C:Line(safe(x.n) .. "  " .. standing, "small") end
    end
  end
end

-- ---------- Attunements tab ----------

local att = {}

local function buildAttunements(page)
  local cols = { { "Name", 170 }, { "Lvl", 30, "RIGHT" } }
  for _, a in ipairs(ns.ATTUNEMENTS) do cols[#cols + 1] = { a.short, 44, "CENTER" } end
  att.list = List(page, cols)
  att.cols = cols
end

local function renderAttunements()
  local rows, counts = {}, {}
  for _, e in ipairs(everyone(false)) do
    if e.profile then
      local cells = { T.classIcon(e.class) .. classed(e.name, e.class), e.level or "" }
      for i, a in ipairs(ns.ATTUNEMENTS) do
        local done = ns.attuned(e.profile, a)
        if done then counts[i] = (counts[i] or 0) + 1 end
        cells[#cells + 1] = done and READY or NOT_READY
      end
      rows[#rows + 1] = { cells = cells, name = e.name, level = e.level or 0,
        onClick = function() ns.selected = e.name; ns.showTab("Character") end }
    end
  end
  table.sort(rows, function(a, b) return a.level > b.level or (a.level == b.level and a.name < b.name) end)
  for i, a in ipairs(ns.ATTUNEMENTS) do
    att.cols[i + 2].header.label:SetText(a.short:upper() .. " " .. color(T.HEX.text, counts[i] or 0))
  end
  att.list:SetRows(rows)
end

-- ---------- Crafters tab ----------

local crafters = { filter = "" }

local function buildCrafters(page)
  local search = T.searchBox(page, 300, "Search recipes…", function(t) crafters.filter = t:lower(); ns.refreshUI() end)
  search:SetPoint("TOPLEFT", 2, 0)
  crafters.hint = T.text(page, "muted")
  crafters.hint:SetPoint("LEFT", search, "RIGHT", 14, 0)
  local area = CreateFrame("Frame", nil, page)
  area:SetPoint("TOPLEFT", 0, -38)
  area:SetPoint("BOTTOMRIGHT")
  crafters.list = List(area, { { "Recipe", 300 }, { "Profession", 120 }, { "Who can make it", 280 } })
end

-- recipe name -> { prof, item, spell, people }, built from everyone's (packed) recipes when the page is shown and
-- rebuilt only when someone's recipes change; let go when the window closes (crafters.index = nil in OnHide).
local function craftersIndex()
  if crafters.index and crafters.indexAt == (ns.recipesChanged or 0) then return crafters.index, crafters.count end
  local index, count = {}, 0
  for name, rec in pairs(ns.players()) do
    local recipes = ns.recipesOf(rec)
    for prof, saved in pairs(type(recipes) == "table" and recipes or {}) do
      for _, r in ipairs(type(saved) == "table" and saved.list or {}) do
        if r.n then
          local e = index[r.n]
          if not e then e = { prof = prof, item = r.it, spell = r.id, people = {} }; index[r.n] = e; count = count + 1 end
          e.people[#e.people + 1] = name
        end
      end
    end
  end
  crafters.index, crafters.count, crafters.indexAt = index, count, ns.recipesChanged or 0
  return index, count
end

local function renderCrafters()
  local index, count = craftersIndex()
  local rows, shown = {}, 0
  for recipe, e in pairs(index) do
    if crafters.filter == "" or recipe:lower():find(crafters.filter, 1, true) then
      shown = shown + 1
      if shown <= 300 then
        table.sort(e.people)
        local names = {}
        for _, n in ipairs(e.people) do
          local rec = ns.players()[n]
          names[#names + 1] = classed(n, rec and rec.class)
        end
        rows[#rows + 1] = {
          sortKey = recipe:lower(),
          cells = { T.itemIcon(e.item) .. safe(recipe), color(T.HEX.muted, safe(e.prof)), table.concat(names, ", ") },
          onEnter = function(row)
            local link = e.item and ("item:" .. e.item) or e.spell and ("spell:" .. e.spell)
            if not link then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            GameTooltip:AddLine("Click to whisper " .. e.people[1], T.C.gold[1], T.C.gold[2], T.C.gold[3])
            GameTooltip:Show()
          end,
          onClick = function()
            -- Straight to a whisper: typing "/w First Surname" would stop at the space.
            local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
            if tell then pcall(tell, e.people[1]) end
          end,
        }
      end
    end
  end
  table.sort(rows, function(a, b) return a.sortKey < b.sortKey end)
  crafters.hint:SetText(count == 0 and "No recipes yet: guildmates share them after opening their profession windows."
    or string.format("%d recipes known across the guild%s", count, shown > 300 and "  ·  showing the first 300 matches" or ""))
  crafters.list:SetRows(rows)
end

-- ---------- Calendar tab ----------

local cal = { selected = nil }
local STATUS_TEXT = { coming = "Coming", tentative = "Tentative", absent = "Can't make it" }
local STATUS_COLOR = { coming = T.HEX.ok, tentative = T.HEX.warm, absent = "7a8298" }

local function whenText(t) return date("%a %b %d, %H:%M", t) end

local function myClass() return select(2, UnitClass("player")) end

-- The spec's role when the class can take it, otherwise the class's first role.
local function myRole()
  local me = ns.me()
  local role = ns.ROLE[me and me.profile and me.profile.spec and me.profile.spec.role or ""]
  if role and ns.canTake(myClass(), role) then return role end
  return ns.classRoles(myClass())[1]
end

-- ---------- New raid (officers) ----------
-- The form behind the Calendar tab's "New raid" button. Times are this computer's local time, like the rest of
-- the tab; the raid goes to the site with guild sync (Calendar.lua ns.createRaid).

local newRaid
local function stepper(parent, width, onStep)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(width, 26)
  local prev = T.button(holder, "<", 26, function() onStep(-1) end, "tab")
  prev:SetPoint("LEFT")
  local nextB = T.button(holder, ">", 26, function() onStep(1) end, "tab")
  nextB:SetPoint("RIGHT")
  holder.value = T.text(holder, "body", "CENTER")
  holder.value:SetPoint("LEFT", prev, "RIGHT", 6, 0); holder.value:SetPoint("RIGHT", nextB, "LEFT", -6, 0)
  return holder
end

local function showNewRaid()
  if not newRaid then
    local f = CreateFrame("Frame", "PerpetuaNewRaid", UIParent)
    f:SetSize(460, 452)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    T.window(f)
    T.escapeCloses(f)
    local title = T.text(f, "heading")
    title:SetPoint("TOPLEFT", 22, -20)
    title:SetText("NEW RAID")
    local close = T.closeButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -12)

    local y = -54
    local function row(label, height)
      local l = T.text(f, "label")
      l:SetPoint("TOPLEFT", 22, y - 7)
      l:SetText(label:upper())
      local at = y
      y = y - (height or 26) - 10
      return at
    end
    local W = 290
    local function place(widget, at) widget:SetPoint("TOPLEFT", 148, at) end

    f.raid = stepper(f, W, function(d)
      f.ri = (f.ri - 1 + d) % #ns.RAIDS + 1
      local r = ns.RAIDS[f.ri]
      f.size:SetText(tostring(r[2]))
      if not f.titleTouched then f.title:SetText(r[1]) end
      f:Update()
    end)
    place(f.raid, row("Raid"))
    f.title = T.searchBox(f, W, "Title", function() end)
    f.title:SetMaxLetters(80)
    f.title:HookScript("OnTextChanged", function(_, user) if user then f.titleTouched = true end end)
    place(f.title, row("Title"))
    f.day = stepper(f, W, function(d) f.dayOffset = math.max(0, math.min(60, f.dayOffset + d)); f:Update() end)
    place(f.day, row("Day"))
    f.time = T.searchBox(f, 90, "20:00", function() f:Update() end)
    f.time:SetMaxLetters(5)
    place(f.time, row("Starts (your time)"))
    f.hours = T.searchBox(f, 90, "3", function() end)
    f.hours:SetMaxLetters(4)
    place(f.hours, row("Hours"))
    f.size = T.searchBox(f, 90, "40", function() end)
    f.size:SetMaxLetters(2)
    f.size:SetNumeric(true)
    place(f.size, row("Players"))
    f.weeks = stepper(f, W, function(d) f.w = math.max(1, math.min(12, f.w + d)); f:Update() end)
    place(f.weeks, row("Repeat"))
    f.notes = T.searchBox(f, W, "Notes (optional)", function() end)
    f.notes:SetMaxLetters(300)
    place(f.notes, row("Notes"))
    f.hint = T.text(f, "muted")
    f.hint:SetPoint("TOPLEFT", 22, y - 2); f.hint:SetPoint("RIGHT", -22, 0)
    f.hint:SetWordWrap(true); f.hint:SetJustifyH("LEFT")

    -- The start as UTC seconds, or nil and why not.
    function f:Start()
      local h, m = (self.time:GetText() or ""):match("^%s*(%d%d?):?(%d%d)%s*$")
      if (self.time:GetText() or "") == "" then h, m = "20", "00" end
      h, m = tonumber(h), tonumber(m)
      if not (h and m and h < 24 and m < 60) then return nil, "Time as HH:MM, 24-hour (e.g. 19:30)." end
      local d = date("*t", time() + self.dayOffset * 86400)
      return time({ year = d.year, month = d.month, day = d.day, hour = h, min = m, sec = 0 })
    end
    function f:Update()
      self.raid.value:SetText(ns.RAIDS[self.ri][1])
      self.day.value:SetText(date("%a %b %d", time() + self.dayOffset * 86400) .. (self.dayOffset == 0 and "  (today)" or ""))
      self.weeks.value:SetText(self.w == 1 and "Just once" or ("Weekly, " .. self.w .. " weeks"))
      local t, why = self:Start()
      self.hint:SetText(why or ("The raid goes to " .. ns.SITE .. " with the next guild sync, then to Discord and everyone's addon. "
        .. "Create & sync reloads your UI so it leaves now."))
    end
    local function create(reload)
      local t, why = f:Start()
      if not t then f.hint:SetText(color("e06666", why)) return end
      local r = ns.RAIDS[f.ri]
      local hours = tonumber((string.gsub(f.hours:GetText() or "", ",", "."))) or 3
      local ok, err = ns.createRaid({
        instance = r[1], title = (f.title:GetText() or "") ~= "" and f.title:GetText() or r[1], t = t,
        dur = math.floor(math.max(0.25, math.min(12, hours)) * 60 + 0.5), size = tonumber(f.size:GetText()) or r[2],
        notes = f.notes:GetText() or "", w = f.w,
      })
      if not ok then f.hint:SetText(color("e06666", err)) return end
      f:Hide()
      ns.refreshUI(true)
      if reload then ReloadUI() end
    end
    f.cancel = T.button(f, "Cancel", 100, function() f:Hide() end, "tab")
    f.cancel:SetPoint("BOTTOMRIGHT", -22, 18)
    f.sync = T.button(f, "Create & sync", 150, function() create(true) end)
    f.sync:SetPoint("RIGHT", f.cancel, "LEFT", -10, 0)
    f.ok = T.button(f, "Create", 100, function() create(false) end, "tab")
    f.ok:SetPoint("RIGHT", f.sync, "LEFT", -10, 0)
    newRaid = f
  end
  local f = newRaid
  f.ri, f.dayOffset, f.w, f.titleTouched = 1, 1, 1, false
  f.title:SetText(ns.RAIDS[1][1])
  f.time:SetText("20:00"); f.hours:SetText("3"); f.size:SetText(tostring(ns.RAIDS[1][2])); f.notes:SetText("")
  f:Update()
  f:ClearAllPoints()
  f:SetPoint("CENTER", 0, 60)
  f:Show()
end

local function buildCalendar(page)
  local left = CreateFrame("Frame", nil, page)
  left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(384)
  -- Officers: the guild calendar bar and "New raid" under the list.
  local tools = CreateFrame("Frame", nil, left)
  tools:SetPoint("BOTTOMLEFT"); tools:SetPoint("BOTTOMRIGHT"); tools:SetHeight(66)
  T.panel(tools)
  cal.gcText = T.text(tools, "muted")
  cal.gcText:SetPoint("TOPLEFT", 10, -8); cal.gcText:SetPoint("RIGHT", -96, 0)
  cal.gcText:SetJustifyH("LEFT"); cal.gcText:SetWordWrap(true)
  cal.gcButton = T.button(tools, "Add", 80, function() ns.gameCalStep() end)
  cal.gcButton:SetPoint("TOPRIGHT", -8, -6)
  cal.gcButton:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  cal.gcButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  cal.newButton = T.button(tools, "New raid", 110, showNewRaid, "tab")
  cal.newButton:SetPoint("BOTTOMLEFT", 8, 6)
  cal.tools = tools
  local listHolder = CreateFrame("Frame", nil, left)
  listHolder:SetPoint("TOPLEFT"); listHolder:SetPoint("RIGHT")
  listHolder:SetPoint("BOTTOM", 0, 0)
  cal.listHolder = listHolder
  cal.list = List(listHolder, { { "When", 118 }, { "Raid", 146 }, { "Coming", 56, "RIGHT" } })

  local right = CreateFrame("Frame", nil, page)
  right:SetPoint("TOPLEFT", 398, 0); right:SetPoint("BOTTOMRIGHT")
  T.panel(right)
  cal.title = T.text(right, "heading"); cal.title:SetPoint("TOPLEFT", 14, -12); cal.title:SetPoint("RIGHT", -14, 0)
  cal.when = T.text(right, "body"); cal.when:SetPoint("TOPLEFT", cal.title, "BOTTOMLEFT", 0, -6); cal.when:SetPoint("RIGHT", -14, 0)
  cal.mine = T.text(right, "muted"); cal.mine:SetPoint("TOPLEFT", cal.when, "BOTTOMLEFT", 0, -4); cal.mine:SetPoint("RIGHT", -14, 0)
  cal.status = {}
  local x = 14
  for _, s in ipairs({ "coming", "tentative", "absent" }) do
    local b = T.button(right, STATUS_TEXT[s], s == "absent" and 118 or 100, function()
      if cal.selected then ns.signUp(cal.selected, s, cal.role or myRole()); ns.refreshUI(true) end
    end, "tab")
    b:SetPoint("TOPLEFT", x, -86)
    cal.status[s] = b
    x = x + (s == "absent" and 118 or 100) + 8
  end
  cal.roles = {}
  x = 14
  for _, r in ipairs({ "Tank", "Healer", "DPS" }) do
    local b = T.button(right, r, 100, function()
      cal.role = r
      local mine = cal.selected and PerpetuaCharDB.signups and PerpetuaCharDB.signups[cal.selected]
      if mine then ns.signUp(cal.selected, mine.s, r) end
      ns.refreshUI(true)
    end, "tab")
    b:SetPoint("TOPLEFT", x, -118)
    cal.roles[r] = b
    x = x + 108
  end
  local area = CreateFrame("Frame", nil, right)
  area:SetPoint("TOPLEFT", 8, -154); area:SetPoint("BOTTOMRIGHT", -4, 6)
  cal.canvas = Canvas(area, { width = 350, x = { 6, 6 }, w = 330 })
  cal.right = right
end

local function renderCalendar()
  local c = ns.calendar()
  local events = {}
  for _, e in ipairs(c and c.events or {}) do
    if (e.t or 0) + (e.dur or 180) * 60 > ns.now() then events[#events + 1] = e end
  end
  table.sort(events, function(a, b) return a.t < b.t end)
  if not cal.selected or not (function() for _, e in ipairs(events) do if e.id == cal.selected then return true end end end)() then
    cal.selected = events[1] and events[1].id
  end
  local rows = {}
  for _, e in ipairs(events) do
    local coming = 0
    for _, s in ipairs(ns.eventSignups(e)) do if s.s == "coming" then coming = coming + 1 end end
    local label = safe(e.title or e.instance or "Raid")
    if e.cancelled == 1 then label = color("7a8298", label .. " (cancelled)") end
    rows[#rows + 1] = {
      cells = { (e.id == cal.selected and color(T.HEX.pale, whenText(e.t)) or whenText(e.t)), label, coming .. "/" .. (e.size or 40) },
      onClick = function() cal.selected = e.id; cal.role = nil; ns.refreshUI(true) end,
    }
  end
  -- Raids this officer made in game, still on their way to the site.
  for _, r in ipairs(ns.pendingRaids()) do
    rows[#rows + 1] = {
      cells = { color(T.HEX.muted, whenText(r.t)), color(T.HEX.muted, safe(r.title) .. " (to the site)"), color(T.HEX.muted, "–") },
      onClick = function()
        T.dialog({
          title = "Waiting for the site",
          text = safe(r.title) .. ", " .. whenText(r.t) .. (r.w and r.w > 1 and (", weekly for " .. r.w .. " weeks") or "")
            .. ".\n\nIt goes to " .. ns.SITE .. " with the next guild sync (your /reload or logout, or a guildmate's who runs the Perpetua app). Drop it instead?",
          accept = "Drop it",
          onAccept = function() ns.cancelPendingRaid(r.k); ns.refreshUI(true) end,
        })
      end,
    }
  end
  cal.list:SetRows(rows)

  local officer = ns.isOfficer(ns.selfName)
  cal.tools:SetShown(officer)
  cal.listHolder:SetPoint("BOTTOM", 0, officer and 74 or 0)
  if officer then
    local st = ns.gameCalStatus and ns.gameCalStatus()
    if st then
      cal.gcText:SetText((st.error and color("e06666", safe(st.text)) or safe(st.text)) .. (st.next and ("\n" .. color(T.HEX.muted, safe(st.next))) or ""))
    else
      cal.gcText:SetText(C_Calendar and color(T.HEX.muted, "Guild calendar is up to date.") or "")
    end
    cal.gcButton:SetShown(st ~= nil and st.button ~= nil)
    if st and st.button then
      cal.gcButton.label:SetText(st.button:upper())
      cal.gcButton.tip = "One change per click: Blizzard's calendar takes one at a time."
    end
  end

  local C = cal.canvas
  C:Reset()
  local e
  for _, x in ipairs(events) do if x.id == cal.selected then e = x end end
  for _, b in pairs(cal.status) do b:SetShown(e ~= nil and e.cancelled ~= 1) end
  -- Only the roles this class can fill, side by side.
  local x = 14
  for _, r in ipairs({ "Tank", "Healer", "DPS" }) do
    local b = cal.roles[r]
    local show = e ~= nil and e.cancelled ~= 1 and ns.canTake(myClass(), r)
    b:SetShown(show)
    if show then b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -118); x = x + 108 end
  end
  if not e then
    cal.title:SetText("NO RAIDS SCHEDULED")
    cal.when:SetText(c and ("Officers schedule raids on " .. ns.SITE .. "/raids" .. (officer and " or with New raid below." or ".")) or "The calendar arrives from an officer's addon.")
    cal.mine:SetText(c and ("Calendar from " .. ns.ago(c.t)) or "")
    return
  end
  cal.title:SetText(safe(e.title or e.instance):upper())
  cal.when:SetText(whenText(e.t) .. " – " .. date("%H:%M", e.t + (e.dur or 180) * 60) .. color(T.HEX.muted, "  ·  " .. safe(e.instance) .. ", " .. (e.size or 40)))
  local mine = PerpetuaCharDB.signups and PerpetuaCharDB.signups[e.id]
  local list = ns.eventSignups(e)
  local siteMine
  for _, s in ipairs(list) do if s.n == ns.selfName then siteMine = s end end
  local status = mine and mine.s or siteMine and siteMine.s
  local role = cal.role or mine and mine.r or siteMine and siteMine.r
  if not (role and ns.canTake(myClass(), role)) then role = myRole() end
  cal.role = role
  for s, b in pairs(cal.status) do b:SetSelected(s == status) end
  for r, b in pairs(cal.roles) do b:SetSelected(r == role) end
  cal.mine:SetText(status and ("You: " .. color(STATUS_COLOR[status], STATUS_TEXT[status]) .. (mine and (mine.t or 0) > (ns.calendar().t or 0) and "  (goes to the site with the next guild sync)" or ""))
    or "You haven't signed up. Pick one below.")

  C:Action("> Open this raid on the site", function() T.copyBox("Raid on the site", "https://" .. ns.SITE .. "/raids/" .. e.id) end)
  if e.notes and e.notes ~= "" then
    for line in (e.notes .. "\n"):gmatch("(.-)\n") do if line ~= "" then C:Para(color(T.HEX.muted, safe(line)), "small") end end
  end
  local groups = { Tank = {}, Healer = {}, DPS = {} }
  local tentative, absent = {}, {}
  for _, s in ipairs(list) do
    local who = T.classIcon(s.c) .. classed(s.n, s.c) .. (s.l == "confirmed" and color(T.HEX.ok, "  in") or s.l == "bench" and color(T.HEX.muted, "  bench") or "")
    if s.s == "coming" then table.insert(groups[s.r] or groups.DPS, who)
    elseif s.s == "tentative" then tentative[#tentative + 1] = who
    else absent[#absent + 1] = who end
  end
  for _, r in ipairs({ "Tank", "Healer", "DPS" }) do
    C:Heading((r == "DPS" and "DPS" or r .. "s") .. "  " .. #groups[r])
    if #groups[r] == 0 then C:Line(color(T.HEX.muted, "None yet"), "small") end
    for _, w in ipairs(groups[r]) do C:Line(w, "small", nil, 6) end
  end
  if #tentative > 0 then C:Heading("Tentative  " .. #tentative); for _, w in ipairs(tentative) do C:Line(w, "small", nil, 6) end end
  if #absent > 0 then C:Heading("Can't make it  " .. #absent); for _, w in ipairs(absent) do C:Line(w, "small", nil, 6) end end
end

-- ---------- Loot tab ----------

local loot = { filter = "" }

local function buildLoot(page)
  local search = T.searchBox(page, 300, "Search items or players…", function(t) loot.filter = t:lower(); ns.refreshUI() end)
  search:SetPoint("TOPLEFT", 2, 0)
  loot.hint = T.text(page, "muted")
  loot.hint:SetPoint("LEFT", search, "RIGHT", 14, 0)
  local area = CreateFrame("Frame", nil, page)
  area:SetPoint("TOPLEFT", 0, -38)
  area:SetPoint("BOTTOMRIGHT")
  loot.list = List(area, { { "When", 90 }, { "Item", 230 }, { "Winner", 150 }, { "Where", 100 }, { "Rolls", 130 } })
end

local function renderLoot()
  local rows, log = {}, ns.lootLog()
  for i = #log, 1, -1 do
    local e = log[i]
    local text = ((e.name or "") .. " " .. (e.n or "")):lower()
    if loot.filter == "" or text:find(loot.filter, 1, true) then
      local rolls = ns.rollsFor(e)
      local top = {}
      for j = 1, math.min(3, #rolls) do top[#top + 1] = safe((rolls[j].n or ""):match("^(%S+)")) .. " " .. rolls[j].r end
      local rec = ns.players()[e.n]
      rows[#rows + 1] = {
        cells = { color(T.HEX.muted, date("%b %d %H:%M", e.t)), T.itemIcon(e.it) .. color(ns.QUALITY[e.q or 4] or "a335ee", safe(e.name or ("Item " .. e.it))),
          classed(e.n, rec and rec.class), color(T.HEX.muted, safe(e.z or "")), table.concat(top, ", ") },
        onEnter = function(row)
          GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
          pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. e.it)
          if #rolls > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Rolls", T.C.gold[1], T.C.gold[2], T.C.gold[3])
            for _, r in ipairs(rolls) do GameTooltip:AddDoubleLine(safe(r.n), r.r .. (r.hi ~= 100 and (" (" .. r.lo .. "-" .. r.hi .. ")") or ""), 1, 1, 1, 1, 1, 1) end
          end
          GameTooltip:Show()
        end,
      }
      if #rows >= 300 then break end
    end
  end
  loot.hint:SetText(#log == 0 and "Epic drops and /rolls in raids show up here." or (#log .. " drops recorded"))
  loot.list:SetRows(rows)
end

-- ---------- Forums tab ----------

local forum = { board = nil, selected = nil }

local function buildForums(page)
  forum.page = page
  forum.tabs = {}  -- board buttons, made when the boards are known (they come with the snapshot)
  forum.left = CreateFrame("Frame", nil, page)
  forum.left:SetWidth(360)
  forum.list = List(forum.left, { { "Thread", 240 }, { "Last", 56, "RIGHT" } })

  forum.right = CreateFrame("Frame", nil, page)
  T.panel(forum.right)
  local inner = CreateFrame("Frame", nil, forum.right)
  inner:SetPoint("TOPLEFT", 8, -10); inner:SetPoint("BOTTOMRIGHT", -4, 6)
  forum.canvas = Canvas(inner, { width = 380, x = { 8, 8 }, w = 350 })
end

-- One tab per board ("All" first), wrapping onto a second row when they don't fit. Returns the height used.
local function layoutBoardTabs(boards)
  local list = { { id = false, n = "All" } }
  for _, b in ipairs(boards) do list[#list + 1] = b end
  local maxW = math.max(600, (forum.page:GetWidth() or 0) > 0 and forum.page:GetWidth() or 828)
  local x, y = 0, 0
  for i, b in ipairs(list) do
    local tab = forum.tabs[i]
    if not tab then
      tab = T.button(forum.page, "", 80, function(self) forum.board = self.boardId or nil; forum.selected = nil; ns.refreshUI(true) end, "tab")
      forum.tabs[i] = tab
    end
    tab.boardId = b.id
    tab.label:SetText(safe(b.n):upper())
    local w = math.ceil((tab.label:GetStringWidth() or 60) + 24)
    tab:SetWidth(w)
    if x > 0 and x + w > maxW then x, y = 0, y + 32 end
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", x, -y)
    tab:SetSelected((forum.board or false) == b.id)
    tab:Show()
    x = x + w + 6
  end
  for i = #list + 1, #forum.tabs do forum.tabs[i]:Hide() end
  return y + 26
end

local function renderForums()
  local f = ns.forums()
  local boards = {}
  for _, b in ipairs(f and f.boards or {}) do boards[b.id] = b end
  local top = layoutBoardTabs(f and f.boards or {}) + 10
  forum.left:ClearAllPoints(); forum.left:SetPoint("TOPLEFT", 0, -top); forum.left:SetPoint("BOTTOMLEFT")
  forum.right:ClearAllPoints(); forum.right:SetPoint("TOPLEFT", 374, -top); forum.right:SetPoint("BOTTOMRIGHT")
  local threads = {}
  for _, t in ipairs(f and f.threads or {}) do
    if not forum.board or t.b == forum.board then threads[#threads + 1] = t end
  end
  table.sort(threads, function(a, b)
    if (a.pin or 0) ~= (b.pin or 0) then return (a.pin or 0) > (b.pin or 0) end
    return (a.last or 0) > (b.last or 0)
  end)
  local rows, current = {}, nil
  for _, t in ipairs(threads) do
    if t.id == forum.selected then current = t end
    local mark = ns.threadUnread(t) and color(T.HEX.gold, "● ") or "   "
    local title = (t.pin == 1 and color(T.HEX.warm, "Pinned  ") or "") .. (t.lock == 1 and color(T.HEX.muted, "Locked  ") or "") .. safe(t.title)
    rows[#rows + 1] = {
      cells = { mark .. (t.id == forum.selected and color(T.HEX.pale, title) or title), color(T.HEX.muted, ns.ago(t.last)) },
      onClick = function() forum.selected = t.id; ns.refreshUI(true) end,
    }
  end
  forum.list:SetRows(rows)

  local C = forum.canvas
  C:Reset()
  if not f then
    C:Para(color(T.HEX.muted, "The forums arrive from an officer's addon: when an officer with the Perpetua app logs in or presses Save & reload, they're shared with everyone online."), "body")
    return
  end
  if not current then
    C:Heading(forum.board and boards[forum.board] and boards[forum.board].n or "Forums")
    C:Para("Pick a thread on the left. " .. #threads .. " recently active " .. (#threads == 1 and "thread" or "threads") .. " from " .. ns.SITE .. "/forums, as of " .. ns.ago(f.t) .. ".", "body")
    C:Para(color(T.HEX.muted, "Officer-only boards stay on the site."), "small")
    return
  end
  ns.markThreadRead(current)
  C:Para(color(T.HEX.gold, safe(current.title)), "heading")
  C:Line(color(T.HEX.muted, (boards[current.b] and safe(boards[current.b].n) or "") .. "  ·  started by " .. safe(current.by) .. "  ·  " .. (current.n or 0) .. " posts"), "muted")
  C:Gap(6)
  local first = (current.n or 0) - #(current.posts or {})
  if first > 0 then C:Line(color(T.HEX.muted, "Showing the latest " .. #current.posts .. " of " .. current.n .. " posts."), "muted") end
  for _, p in ipairs(current.posts or {}) do
    C:Gap(8)
    local rank = p.r == "gm" and color(T.HEX.gold, "  Guild Master") or p.r == "officer" and color(T.HEX.gold, "  Officer") or ""
    C:Line(color(T.HEX.pale, safe(p.by)) .. rank .. color(T.HEX.muted, "  ·  " .. ns.ago(p.t)), "small")
    C:Para(safe(p.body), "small", 6)
    if p.cut then C:Line(color(T.HEX.muted, "(continues on the site)"), "muted", nil, 6) end
  end
  C:Gap(12)
  local threadUrl = "https://" .. ns.SITE .. "/forums/t/" .. current.id
  C:Action("> Reply on the site" .. (current.lock == 1 and "  (locked)" or ""), function() T.copyBox("Reply on the site", threadUrl) end)
  C:Line(color(T.HEX.muted, "Forums as of " .. ns.ago(f.t)), "muted")
end

-- ---------- Setup tab (first time) ----------
-- Shown the first time someone opens the addon: what it does, why linking their characters to their Discord
-- account on the site matters, and a box to enter the link code. The status card reads the site's list of
-- known characters (it comes with the raid calendar) to say whether this character is linked yet.

local setup = {}

local function stepCard(parent, number, title, height, bottom)
  local card = CreateFrame("Frame", nil, parent)
  T.panel(card)
  card:SetHeight(height)
  local badge = CreateFrame("Frame", nil, card)
  badge:SetSize(30, 30); badge:SetPoint("TOPLEFT", 14, -14)
  local bbg = T.fill(badge, "BACKGROUND", T.C.gold, 1); bbg:SetAllPoints()
  local n = T.text(badge, "button", "CENTER"); n:SetPoint("CENTER", 0, 0); n:SetText(number)
  n:SetTextColor(T.C.navy[1], T.C.navy[2], T.C.navy[3]); n:SetShadowColor(0, 0, 0, 0)
  local h = T.text(card, "heading"); h:SetPoint("LEFT", badge, "RIGHT", 12, 0); h:SetText(title:upper())
  card.body = card:CreateFontString(nil, "OVERLAY")
  card.body:SetFontObject(T.fonts.small)
  card.body:SetJustifyH("LEFT"); card.body:SetJustifyV("TOP"); card.body:SetWordWrap(true); card.body:SetSpacing(2)
  -- Fixed box, as on the Welcome page: GetStringHeight reports one line before the width resolves, so cards that
  -- measured their text came out too short and the text ran over the next card and out of the window.
  card.body:SetPoint("TOPLEFT", 16, -48); card.body:SetPoint("BOTTOMRIGHT", -16, bottom or 10)
  return card
end

local function buildSetup(page)
  local left = CreateFrame("Frame", nil, page)
  left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(452)
  -- Fixed heights (519px of the page's ~528), each with a line to spare for the text measured in the addon's font.
  setup.cards = {
    -- Heights fit the page under the window's header (496px); the text boxes are the size they always were.
    stepCard(left, "1", "What the addon does", 134),
    stepCard(left, "2", "Why link your characters", 164),
    stepCard(left, "3", "How to link", 179, 48), -- the copy button sits under the text
  }
  local prev
  for _, card in ipairs(setup.cards) do
    if prev then card:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12) else card:SetPoint("TOPLEFT") end
    card:SetPoint("RIGHT", left, "RIGHT")
    prev = card
  end
  setup.cards[1].body:SetText("Everyone in the guild with the addon shares their gear, talents, professions, attunements and raid loot with each other, "
    .. "right here in game. You'll also see the raid calendar and can sign up for raids with one click.")
  setup.cards[2].body:SetText("Linking ties this WoW account to your Discord account on " .. ns.SITE .. ", so your characters, raid sign-ups "
    .. "and loot show up there under your name.\n\n"
    .. color(T.HEX.pale, "You do it once.") .. " Every character on this WoW account follows by itself.")
  setup.cards[3].body:SetText("1.  On " .. color(T.HEX.pale, ns.SITE .. "/member") .. ", sign in with Discord and click " .. color(T.HEX.pale, "Get my link code") .. ".\n"
    .. "2.  Type the code in the box on the right and press " .. color(T.HEX.pale, "Link") .. ".\n"
    .. "3.  Done. It goes through at the next guild sync, usually the same day.")
  setup.site = T.button(setup.cards[3], "Copy the address", 170, function() T.copyBox("Get your link code", "https://" .. ns.SITE .. "/member") end, "tab")
  setup.site:SetPoint("BOTTOMLEFT", 16, 14)

  local right = CreateFrame("Frame", nil, page)
  right:SetPoint("TOPLEFT", 468, 0); right:SetPoint("BOTTOMRIGHT")
  local status = CreateFrame("Frame", nil, right)
  status:SetPoint("TOPLEFT"); status:SetPoint("TOPRIGHT", -2, 0); status:SetHeight(250)
  T.panel(status)
  setup.statusAccent = T.fill(status, "ARTWORK", T.C.gold, 1)
  setup.statusAccent:SetPoint("TOPLEFT"); setup.statusAccent:SetPoint("BOTTOMLEFT"); setup.statusAccent:SetWidth(3)
  local sh = T.text(status, "label"); sh:SetPoint("TOPLEFT", 18, -16); sh:SetText("YOUR STATUS")
  setup.state = T.text(status, "heading"); setup.state:SetPoint("TOPLEFT", sh, "BOTTOMLEFT", 0, -10)
  setup.detail = status:CreateFontString(nil, "OVERLAY")
  setup.detail:SetFontObject(T.fonts.small); setup.detail:SetJustifyH("LEFT"); setup.detail:SetJustifyV("TOP"); setup.detail:SetWordWrap(true)
  setup.detail:SetPoint("TOPLEFT", setup.state, "BOTTOMLEFT", 0, -8); setup.detail:SetPoint("RIGHT", -16, 0)
  setup.code = T.searchBox(status, 150, "Link code", function() end)
  setup.code:SetMaxLetters(6)
  setup.code:SetPoint("BOTTOMLEFT", 18, 18)
  setup.link = T.button(status, "Link", 90, function()
    local code = (setup.code:GetText() or ""):upper():gsub("%s", "")
    if not code:match("^%w%w%w%w%w%w$") then setup.error:SetText(color(T.HEX.danger, "Codes are six letters and numbers.")); return end
    PerpetuaDB.link = { code = code, t = ns.now() }
    setup.code:SetText("")
    setup.code:ClearFocus()
    setup.error:SetText("")
    ns.refreshSelf()
    ns.refreshUI(true)
  end)
  setup.link:SetPoint("LEFT", setup.code, "RIGHT", 10, 0)
  setup.code:SetScript("OnEnterPressed", function() setup.link:Click() end)
  setup.error = T.text(status, "muted"); setup.error:SetPoint("BOTTOMLEFT", setup.code, "TOPLEFT", 0, 6)

  local shares = right:CreateFontString(nil, "OVERLAY")
  shares:SetFontObject(T.fonts.muted); shares:SetJustifyH("LEFT"); shares:SetJustifyV("TOP"); shares:SetWordWrap(true)
  shares:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 4, -16); shares:SetPoint("RIGHT", -6, 0)
  shares:SetText(color(T.HEX.gold, "SHARED WITH THE GUILD") .. "\nYour characters' gear, talents, professions, attunements, reputations, raid sign-ups and the loot you see in raids.\n\n"
    .. color(T.HEX.gold, "NEVER SHARED") .. "\nGold, bags and bank, chat and whispers, your Battle.net account. The addon never goes online; it only talks to guildmates in game.")
  local done = T.button(right, "Done", 150, function()
    PerpetuaDB.setupSeen = true
    ns.showTab("Guild")
  end)
  done:SetPoint("BOTTOMRIGHT", -2, 6)
end

local function renderSetup()
  local cal = ns.calendar()
  local known = {}
  for _, n in ipairs(cal and cal.roster or {}) do known[n] = true end
  local mine, others = ns.selfName and known[ns.selfName], 0
  for alt in pairs(PerpetuaDB.account or {}) do if alt ~= ns.selfName and known[alt] then others = others + 1 end end
  local pending = PerpetuaDB.link

  if mine then
    setup.statusAccent:SetVertexColor(0.56, 0.82, 0.54)
    setup.state:SetText(color(T.HEX.ok, "LINKED"))
    setup.detail:SetText(safe(ns.selfName) .. " is on " .. ns.SITE .. (others > 0 and (", along with " .. others .. " of your other characters.") or ".")
      .. "\n\nNew characters on this account are added by themselves. Enter a code again only if you want them under a different Discord account.")
  elseif pending then
    setup.statusAccent:SetVertexColor(T.C.gold[1], T.C.gold[2], T.C.gold[3])
    setup.state:SetText(color(T.HEX.warm, "CODE SAVED"))
    setup.detail:SetText("Code " .. color(T.HEX.pale, safe(pending.code)) .. " goes to the site with the next guild sync (saved " .. ns.ago(pending.t) .. ").\n\n"
      .. "Nothing else to do. If a week passes without your characters appearing on the site, get a new code.")
  else
    setup.statusAccent:SetVertexColor(T.C.muted[1], T.C.muted[2], T.C.muted[3])
    setup.state:SetText("NOT LINKED YET")
    setup.detail:SetText("Your characters aren't on " .. ns.SITE .. " yet" .. (cal and "" or " (or the site's list hasn't reached you: it comes with the raid calendar)")
      .. ". Get a code on the site and enter it below.")
  end
end

-- ---------- Welcome page (not in the guild) ----------
-- The addon only works for members of Perpetua (ns.locked). Anyone else sees this page instead of the tabs: who we
-- are, that we're recruiting, where to apply, and why the addon has nothing to show them yet.

local welcome = {}

local function infoCard(parent, iconName, title, height)
  local card = CreateFrame("Frame", nil, parent)
  T.panel(card)
  card:SetHeight(height)
  local icon = T.icon(card, "Interface\\Icons\\" .. iconName, 26)
  icon:SetPoint("TOPLEFT", 14, -14)
  local h = T.text(card, "heading"); h:SetPoint("LEFT", icon, "RIGHT", 12, 0); h:SetText(title:upper())
  -- Fixed box: the text wraps inside the card instead of the card measuring the text (GetStringHeight reported one
  -- line before the width resolved, so the cards came out too short and the text ran over the next one).
  card.body = card:CreateFontString(nil, "OVERLAY")
  card.body:SetFontObject(T.fonts.small)
  card.body:SetJustifyH("LEFT"); card.body:SetJustifyV("TOP"); card.body:SetWordWrap(true); card.body:SetSpacing(2)
  card.body:SetPoint("TOPLEFT", 16, -50); card.body:SetPoint("BOTTOMRIGHT", -16, 10)
  return card
end

local WELCOME_W = 452

local function buildWelcome(page)
  -- Three static cards, stacked with fixed heights (roomier than the text needs; 494px of the page's ~528).
  local left = CreateFrame("Frame", nil, page)
  left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(WELCOME_W)
  welcome.cards = {
    infoCard(left, "INV_BannerPVP_02", "Who we are", 150),
    infoCard(left, "INV_Misc_Note_01", "We're recruiting", 150),
    infoCard(left, "INV_Misc_Book_09", "About this addon", 170),
  }
  local prev
  for _, card in ipairs(welcome.cards) do
    if prev then card:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -12) else card:SetPoint("TOPLEFT") end
    card:SetPoint("RIGHT", left, "RIGHT")
    prev = card
  end
  welcome.cards[1].body:SetText("An " .. color(T.HEX.pale, "Alliance") .. " guild on the " .. color(T.HEX.pale, "PvP")
    .. " ruleset for World of Warcraft: Forever, and a community that has been gaming together for over eight years. "
    .. "People come first: we have a strong PvE and PvP presence, but you don't need to be hardcore to belong here.")
  welcome.cards[2].body:SetText("We're building a raid team and a community that lasts well beyond launch week, and every role is welcome. "
    .. "Apply on " .. color(T.HEX.pale, ns.SITE) .. ", get to know us on Discord, and see if Perpetua feels like home.")
  welcome.cards[3].body:SetText("Members share gear, talents, professions, attunements and raid loot, see the raid calendar and link their characters to "
    .. ns.SITE .. ". " .. color(T.HEX.pale, "It only works inside the guild,") .. " over Perpetua's private guild channel. "
    .. "Keep it installed: the moment you join, it unlocks by itself.")

  local right = CreateFrame("Frame", nil, page)
  right:SetPoint("TOPLEFT", 468, 0); right:SetPoint("BOTTOMRIGHT")
  local hero = CreateFrame("Frame", nil, right)
  hero:SetPoint("TOPLEFT"); hero:SetPoint("TOPRIGHT", -2, 0); hero:SetHeight(300)
  T.panel(hero)
  local crest = hero:CreateTexture(nil, "ARTWORK")
  crest:SetTexture(T.CREST); crest:SetSize(72, 72); crest:SetPoint("TOP", 0, -26)
  local name = T.text(hero, "title", "CENTER"); name:SetPoint("TOP", crest, "BOTTOM", 0, -12); name:SetText("PERPETUA")
  local tag = T.text(hero, "tagline", "CENTER"); tag:SetPoint("TOP", name, "BOTTOM", 0, -6); tag:SetText("Alliance  ·  PvP  ·  Now recruiting")
  local rule = T.rule(hero); rule:SetWidth(180); rule:SetPoint("TOP", tag, "BOTTOM", 0, -12)
  local apply = T.button(hero, "Apply to join", 190, function() T.copyBox("Apply to join Perpetua", "https://" .. ns.SITE .. "/apply") end)
  apply:SetPoint("TOP", tag, "BOTTOM", 0, -40)
  local about = T.button(hero, "More about us", 190, function() T.copyBox("About Perpetua", "https://" .. ns.SITE .. "/who-we-are") end, "tab")
  about:SetPoint("TOP", apply, "BOTTOM", 0, -10)
  local hint = T.text(hero, "muted", "CENTER"); hint:SetPoint("TOP", about, "BOTTOM", 0, -12)
  hint:SetText("Copy the address and open it in your browser.")

  local status = CreateFrame("Frame", nil, right)
  status:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -12); status:SetPoint("RIGHT", -2, 0); status:SetHeight(140)
  T.panel(status)
  local accent = T.fill(status, "ARTWORK", T.C.muted, 1)
  accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(3)
  local sh = T.text(status, "label"); sh:SetPoint("TOPLEFT", 18, -16); sh:SetText("THIS CHARACTER")
  welcome.state = T.text(status, "heading"); welcome.state:SetPoint("TOPLEFT", sh, "BOTTOMLEFT", 0, -10)
  welcome.detail = status:CreateFontString(nil, "OVERLAY")
  welcome.detail:SetFontObject(T.fonts.small); welcome.detail:SetJustifyH("LEFT"); welcome.detail:SetJustifyV("TOP"); welcome.detail:SetWordWrap(true)
  welcome.detail:SetPoint("TOPLEFT", welcome.state, "BOTTOMLEFT", 0, -8); welcome.detail:SetPoint("RIGHT", -16, 0)
end

local function renderWelcome()
  local guild = IsInGuild() and ns.guildName()
  local horde = try(UnitFactionGroup, "player") == "Horde"
  welcome.state:SetText(guild and ("IN <" .. safe(guild):upper() .. ">") or "NOT IN A GUILD")
  welcome.detail:SetText((guild and "The addon stays locked on characters in other guilds." or "Join Perpetua and everything here unlocks.")
    .. (horde and ("\n\nPerpetua is an Alliance guild, so you'll need an Alliance character to join us.") or ""))
end

-- ---------- Export tab ----------

local export = {}

local function buildExport(page)
  export.info = T.text(page, "body")
  export.info:SetPoint("TOPLEFT", 4, 0)
  export.info:SetPoint("TOPRIGHT", -4, 0)
  export.info:SetWordWrap(true)
  export.info:SetJustifyV("TOP")
  export.info:SetHeight(110)
  export.info:SetSpacing(4)

  local box = CreateFrame("Frame", nil, page)
  box:SetPoint("TOPLEFT", 0, -118)
  box:SetPoint("BOTTOMRIGHT", 0, 46)
  local bg = T.fill(box, "BACKGROUND", T.C.midnight, 1)
  bg:SetAllPoints()
  T.outline(box, 0, T.C.gold, 0.4)

  local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -8)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetMaxLetters(0)
  edit:SetFontObject(ChatFontNormal)
  edit:SetTextColor(T.C.pale[1], T.C.pale[2], T.C.pale[3])
  edit:SetWidth(700)
  edit:SetAutoFocus(false)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- Read-only: typing puts the export back and selects it again.
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self:GetText() ~= export.text then self:SetText(export.text or ""); self:HighlightText() end
  end)
  edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  scroll:SetScrollChild(edit)
  export.edit = edit

  local sync = T.button(page, "Save & reload", 150, function() ns.saveAndReload() end, "tab")
  sync:SetPoint("BOTTOMRIGHT", 0, 6)
  sync:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Save & reload", T.C.gold[1], T.C.gold[2], T.C.gold[3])
    GameTooltip:AddLine("Reloads your UI so WoW saves the guild's data for the Perpetua app.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  sync:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local copy = T.button(page, "Select all", 150, function() ns.renderExport(true) end, "tab")
  copy:SetPoint("RIGHT", sync, "LEFT", -12, 0)
  export.status = T.text(page, "muted")
  export.status:SetPoint("BOTTOMLEFT", 2, 12)
end

local function summary(d)
  local parts, missing = {}, {}
  if d.gear then parts[#parts + 1] = #d.gear .. " items" end
  if d.spec and d.spec.n then parts[#parts + 1] = safe(d.spec.n) .. " talents" end
  for _, p in ipairs(d.profs or {}) do
    if p.recipes then parts[#parts + 1] = safe(p.n) .. " (" .. #p.recipes .. " recipes)"
    else
      parts[#parts + 1] = safe(p.n)
      if not ns.NO_RECIPES[p.n] then missing[#missing + 1] = safe(p.n) end
    end
  end
  local line = color(T.HEX.muted, "Includes " .. table.concat(parts, ", ") .. ".")
  if #missing > 0 then line = line .. "\n" .. color(T.HEX.warm, "Open your " .. table.concat(missing, " and ") .. " window once to include those recipes.") end
  if d.errors then line = line .. "\n" .. color(T.HEX.danger, "Some parts couldn't be read (" .. #d.errors .. "). The rest is fine; tell an officer if this keeps happening.") end
  return line
end

function ns.renderExport(focus)
  local me = ns.me()
  if not me or not me.profile then return end
  local d = ns.merge(me.profile, me.recipes)
  d.t = math.max(me.pt or 0, me.rt or 0)
  export.text = ns.pack(d)
  export.edit:SetText(export.text)
  export.info:SetText("Paste this on " .. color(T.HEX.gold, ns.SITE .. "/characters/" .. safe((ns.selfName:gsub(" ", "-")))) .. " while signed in. It's selected: press " ..
    color(T.HEX.pale, "Ctrl+C") .. ".\nOr let the officers' Perpetua app pick it up: it's saved when you log out or press Save & reload.\n" ..
    (PerpetuaDB.link and color(T.HEX.ok, "Link code " .. safe(PerpetuaDB.link.code) .. " is waiting for the next guild sync.")
      or color(T.HEX.muted, "Not on the site yet? Get a code at " .. ns.SITE .. "/member and type /perpetua link CODE.")) .. "\n\n" .. summary(d))
  local n = 0
  for _ in pairs(ns.session.heard) do n = n + 1 end
  export.status:SetText(string.format("Guild sync: heard from %d guildmates this session  ·  %d updates received", n, ns.session.received))
  if focus then export.edit:SetFocus(); export.edit:HighlightText() end
end

-- ---------- Hide Olympus page ----------
-- Opened from "Hide Olympus" above Save & reload in the sidebar (Olympus.lua does the hiding). The sidebar switch turns
-- everything on or off; here each part can be switched off on its own.

local oly = {}

local function buildOlympus(page)
  local O = ns.olympus
  local left = CreateFrame("Frame", nil, page)
  left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(452)
  T.panel(left)
  local h = T.text(left, "heading"); h:SetPoint("TOPLEFT", 18, -18); h:SetText("HIDE OLYMPUS")
  oly.switch = T.switch(left, O.set)
  oly.switch:SetPoint("TOPRIGHT", -18, -16)
  oly.state = T.text(left, "muted", "RIGHT"); oly.state:SetPoint("RIGHT", oly.switch, "LEFT", -10, 0)
  local intro = left:CreateFontString(nil, "OVERLAY")
  intro:SetFontObject(T.fonts.small); intro:SetJustifyH("LEFT"); intro:SetJustifyV("TOP"); intro:SetWordWrap(true)
  intro:SetPoint("TOPLEFT", 18, -46); intro:SetPoint("RIGHT", -18, 0); intro:SetHeight(58)
  intro:SetText("For players in any guild with " .. color(T.HEX.pale, "Olympus") .. " in its name. It all happens on your screen: "
    .. "nobody goes on your ignore list and they can't tell.")
  oly.checks = {}
  local function check(key, label, hint, y, indent)
    local c = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    c:SetSize(24, 24); c:SetPoint("TOPLEFT", 14 + (indent or 0), y)
    local l = T.text(left, "body"); l:SetPoint("TOPLEFT", c, "TOPRIGHT", 4, -3); l:SetText(label)
    local d = T.text(left, "muted"); d:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -2); d:SetPoint("RIGHT", -18, 0); d:SetText(hint or "")
    oly.checks[#oly.checks + 1] = { key = key, check = c, label = l, hint = d }
    return c
  end
  local y = -108
  for _, o in ipairs(O.OPTIONS) do
    local c = check(o.key, o.label, o.hint, y, o.parent and 26)
    oly.checks[#oly.checks].parent = o.parent
    c:SetScript("OnClick", function(self) O.setOption(o.key, self:GetChecked()) end)
    y = y - (o.hint ~= "" and (o.parent and 46 or 52) or 36)
  end
  local n = check("notify", "Tell me in chat when something's turned away", "Invites, trades and duels. Hidden chat is only counted.", y - 6)
  n:SetScript("OnClick", function(self) O.db().notify = self:GetChecked() and true or false end)

  local right = CreateFrame("Frame", nil, page)
  right:SetPoint("TOPLEFT", 468, 0); right:SetPoint("BOTTOMRIGHT")
  local status = CreateFrame("Frame", nil, right)
  status:SetPoint("TOPLEFT"); status:SetPoint("TOPRIGHT", -2, 0); status:SetHeight(290)
  T.panel(status)
  local sh = T.text(status, "label"); sh:SetPoint("TOPLEFT", 18, -16); sh:SetText("OLYMPUS PLAYERS KNOWN")
  oly.known = T.text(status, "name"); oly.known:SetPoint("TOPLEFT", sh, "BOTTOMLEFT", 0, -8)
  oly.learned = T.text(status, "muted"); oly.learned:SetPoint("TOPLEFT", oly.known, "BOTTOMLEFT", 0, -4)
  -- Running totals, three across: messages hidden, invites turned down, trades cancelled.
  oly.totals = {}
  for i, key in ipairs({ "messages", "invites", "trades" }) do
    local n = T.text(status, "brand"); n:SetPoint("TOPLEFT", oly.learned, "BOTTOMLEFT", (i - 1) * 88, -14)
    n:SetTextColor(T.C.pale[1], T.C.pale[2], T.C.pale[3])
    local l = T.text(status, "label"); l:SetPoint("TOPLEFT", n, "BOTTOMLEFT", 0, -3); l:SetText(key:upper()); l:SetAlpha(0.8)
    oly.totals[key] = n
  end
  local th = T.text(status, "label"); th:SetPoint("TOPLEFT", oly.learned, "BOTTOMLEFT", 0, -64); th:SetText("TURNED AWAY THIS SESSION")
  oly.counts = status:CreateFontString(nil, "OVERLAY")
  oly.counts:SetFontObject(T.fonts.small); oly.counts:SetJustifyH("LEFT"); oly.counts:SetJustifyV("TOP"); oly.counts:SetWordWrap(true)
  oly.counts:SetPoint("TOPLEFT", th, "BOTTOMLEFT", 0, -6); oly.counts:SetPoint("BOTTOMRIGHT", -16, 12)

  local lookup = T.button(right, "Look them up", 170, function()
    local i = O.lookUp()
    oly.lookupNote:SetText("Searched " .. i .. " of " .. O.WHO_TOTAL .. ". Click for the next.")
  end, "tab")
  lookup:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -14)
  oly.lookupNote = T.text(right, "muted"); oly.lookupNote:SetPoint("TOPLEFT", lookup, "BOTTOMLEFT", 2, -6); oly.lookupNote:SetPoint("RIGHT", -4, 0)
  oly.lookupNote:SetText("A /who for Olympus players, 50 a click.")
  local how = right:CreateFontString(nil, "OVERLAY")
  how:SetFontObject(T.fonts.muted); how:SetJustifyH("LEFT"); how:SetJustifyV("TOP"); how:SetWordWrap(true)
  how:SetPoint("TOPLEFT", oly.lookupNote, "BOTTOMLEFT", 0, -14); how:SetPoint("BOTTOMRIGHT", -6, 4)
  how:SetText(color(T.HEX.gold, "HOW IT KNOWS") .. "\nThe game only shows someone's guild when you see them: nameplates, "
    .. "mouseover, target, your group, a trade or an invite. Everyone spotted is remembered; chat from someone not seen "
    .. "yet still shows until they are. Your own /who searches teach it too.")
end

local function renderOlympus()
  local O = ns.olympus
  local db = O.db()
  oly.switch:SetOn(db.on)
  oly.state:SetText(db.on and color(T.HEX.ok, "On") or "Off")
  for _, c in ipairs(oly.checks) do
    if c.key == "notify" then c.check:SetChecked(db.notify and true or false) else c.check:SetChecked(db.opts[c.key] ~= false) end
    local on = db.on and not (c.parent and db.opts[c.parent] == false)
    c.check:SetEnabled(on and true or false)
    local a = on and 1 or 0.45
    c.label:SetAlpha(a); c.hint:SetAlpha(a)
  end
  oly.known:SetText(O.knownCount())
  oly.learned:SetText(O.session.learned .. " new this session")
  for key, n in pairs(oly.totals) do n:SetText(db.totals[key] or 0) end
  local lines = {}
  for _, o in ipairs(O.OPTIONS) do
    local n = O.session.counts[o.key] or 0
    if n > 0 then lines[#lines + 1] = color(T.HEX.pale, n) .. "  " .. O.COUNTED[o.key] end
  end
  oly.counts:SetText(#lines > 0 and table.concat(lines, "\n") or color(T.HEX.muted, db.on and "Nothing yet." or "Switched off."))
end

-- ---------- window ----------

-- The sidebar, in groups: the guild, you, and reference pages.
local TABS = {
  { "Guild", buildGuild, renderGuild, group = "Guild" },
  { "Guild Info", function(page) ns.buildGuildInfo(page) end, function() ns.renderGuildInfo() end, group = "Guild", newGuild = true }, -- with the New guild window
  { "Calendar", buildCalendar, renderCalendar, group = "Guild" },
  { "Loot", buildLoot, renderLoot, group = "Guild" },
  { "Forums", buildForums, renderForums, group = "Guild" },
  { "Character", buildCharacter, renderCharacter, group = "You" },
  { "Export", buildExport, function() ns.renderExport() end, group = "You" },
  { "Setup", buildSetup, renderSetup, group = "You" },
  { "Attunements", buildAttunements, renderAttunements, group = "Reference" },
  { "Crafters", buildCrafters, renderCrafters, group = "Reference" },
  { "Welcome", buildWelcome, renderWelcome, noNav = true }, -- the only page for characters outside the guild
  { "Hide Olympus", buildOlympus, renderOlympus, noNav = true }, -- opened from its row above Save & reload
}
if not ns.FORUMS then
  for i, t in ipairs(TABS) do if t[1] == "Forums" then table.remove(TABS, i) break end end
end

local NAV = {
  Guild = { "INV_BannerPVP_02", "Everyone in the guild: ranks, notes, specs, gear and professions" },
  ["Guild Info"] = { "INV_Misc_Note_01", "Message of the day, guild information and the guild log" },
  Character = { "INV_Chest_Plate16", "Gear, talents, professions and more" },
  Calendar = { "INV_Misc_PocketWatch_01", "Upcoming raids and who's coming" },
  Attunements = { "INV_Misc_Key_14", "Who can get in where" },
  Crafters = { "Trade_BlackSmithing", "Who can make what" },
  Loot = { "INV_Misc_Bag_10", "Raid drops and the rolls for them" },
  Forums = { "INV_Scroll_03", "The latest from the guild forums" },
  Export = { "INV_Scroll_05", "Your profile for the site" },
  Setup = { "INV_Misc_Book_09", "Link your characters to perpetua.gg" },
  Welcome = { "INV_BannerPVP_02", "The guild companion for Perpetua members" },
  ["Hide Olympus"] = { "INV_Shield_06", "Hide chat, invites, trades and duels from Olympus guilds" },
}

-- Big numbers in the page header (the site's "42 characters on the roster"). A page's renderer calls
-- ns.setStats({ { 42, "members" }, { 12, "online", "ok" } }); pages that don't, show none.
local function setStats(list)
  local x = 0
  for i = #main.stats, 1, -1 do main.stats[i].n:Hide(); main.stats[i].l:Hide() end
  local prev
  for i = #(list or {}), 1, -1 do
    local st = main.stats[i]
    if not st then
      st = { n = T.text(main, "stat", "RIGHT"), l = T.text(main, "muted", "RIGHT") }
      main.stats[i] = st
    end
    local item = list[i]
    st.l:SetText(item[2] or ""); st.n:SetText(tostring(item[1] or ""))
    local c = item[3] == "ok" and { 0.561, 0.820, 0.541 } or T.C.pale
    st.n:SetTextColor(c[1], c[2], c[3])
    st.l:ClearAllPoints(); st.n:ClearAllPoints()
    -- Every label on the same line: the first at a fixed spot, the rest left of the number before them, level
    -- with it (the number sits 2px lower than its label).
    if prev then st.l:SetPoint("BOTTOMRIGHT", prev, "BOTTOMLEFT", -24, 2) else st.l:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", -26, -112) end
    st.n:SetPoint("BOTTOMRIGHT", st.l, "BOTTOMLEFT", -7, -2)
    st.n:Show(); st.l:Show()
    prev = st.n
  end
  main.statsSet = true
end
function ns.setStats(list) if main then setStats(list) end end

local TOP, SIDE = 62, 196 -- top bar height, sidebar width

local function build()
  main = CreateFrame("Frame", "PerpetuaFrame", UIParent)
  -- Closed: let go of what only the open window needed.
  main:SetScript("OnHide", function() crafters.index = nil end)
  main:SetSize(1020, 640)
  main:SetPoint("CENTER")
  main:SetFrameStrata("HIGH")
  main:SetMovable(true)
  main:EnableMouse(true)
  main:RegisterForDrag("LeftButton")
  main:SetScript("OnDragStart", main.StartMoving)
  main:SetScript("OnDragStop", main.StopMovingOrSizing)
  main:SetClampedToScreen(true)
  T.window(main)
  tinsert(UISpecialFrames, "PerpetuaFrame") -- Escape closes it
  main:Hide()
  main.stats = {}

  -- Top bar: crest, wordmark and motto; the New guild window switch, the guild and close on the right.
  local top = CreateFrame("Frame", nil, main)
  top:SetPoint("TOPLEFT", 6, -6); top:SetPoint("TOPRIGHT", -6, -6); top:SetHeight(TOP - 6)
  local tbg = T.gradient(top, "BACKGROUND", "VERTICAL", T.C.ink, 0, T.C.ink, 0.55); tbg:SetAllPoints()
  local tline = T.fill(top, "BORDER", T.C.gold, 0.22); tline:SetHeight(1); tline:SetPoint("BOTTOMLEFT", -5, 0); tline:SetPoint("BOTTOMRIGHT", 5, 0)
  local crest = top:CreateTexture(nil, "ARTWORK")
  crest:SetTexture(T.CREST); crest:SetSize(38, 38); crest:SetPoint("LEFT", 16, 0)
  local brand = T.text(top, "brand"); brand:SetPoint("TOPLEFT", crest, "TOPRIGHT", 12, -4); brand:SetText("PERPETUA")
  local motto = T.text(top, "tagline"); motto:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3); motto:SetText("the grind never stops")
  local close = T.closeButton(top, function() main:Hide() end)
  close:SetPoint("RIGHT", -10, 0)
  main.guild = T.text(top, "muted", "RIGHT"); main.guild:SetPoint("RIGHT", close, "LEFT", -12, 0)
  local div = T.fill(top, "ARTWORK", T.C.gold, 0.25); div:SetSize(1, 24); div:SetPoint("RIGHT", main.guild, "LEFT", -14, 0)
  -- "Try the new look" style switch for features still being tried out: a NEW tag, the name and a switch.
  local newRow = CreateFrame("Frame", nil, top)
  newRow:SetSize(240, 22); newRow:SetPoint("RIGHT", div, "LEFT", -14, 0)
  main.newSwitch = T.switch(newRow, function(on) ns.setNewGuildWindow(on) end)
  main.newSwitch:SetPoint("RIGHT")
  local newLabel = T.text(newRow, "nav", "RIGHT"); newLabel:SetPoint("RIGHT", main.newSwitch, "LEFT", -9, 0)
  newLabel:SetText("GUILD WINDOW")
  local tag = CreateFrame("Frame", nil, newRow); tag:SetSize(32, 14); tag:SetPoint("RIGHT", newLabel, "LEFT", -8, 0)
  local tagBg = T.fill(tag, "BACKGROUND", T.C.gold, 1); tagBg:SetAllPoints()
  local tagText = T.text(tag, "badge", "CENTER"); tagText:SetPoint("CENTER", 0, 0); tagText:SetText("NEW")
  tagText:SetTextColor(T.C.navy[1], T.C.navy[2], T.C.navy[3]); tagText:SetShadowColor(0, 0, 0, 0)
  local hover = CreateFrame("Frame", nil, newRow); hover:SetPoint("TOPLEFT", tag, "TOPLEFT"); hover:SetPoint("BOTTOMRIGHT", newLabel, "BOTTOMRIGHT")
  hover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("New guild window", T.C.gold[1], T.C.gold[2], T.C.gold[3])
    GameTooltip:AddLine("The guild key (J) and the guild button on the menu bar open Perpetua's guild window instead of Blizzard's, with the officer tools (ranks, notes, invites, the Guild Info page). Hold Shift for Blizzard's. Turn it off here any time.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  main.newRow = newRow

  -- Sidebar: the sections in groups, the sync card at the bottom.
  local side = CreateFrame("Frame", nil, main)
  side:SetPoint("TOPLEFT", 1, -TOP); side:SetPoint("BOTTOMLEFT", 1, 1); side:SetWidth(SIDE)
  local sbg = T.fill(side, "BACKGROUND", T.C.ink, 0.45); sbg:SetAllPoints()
  local edge = T.fill(side, "BORDER", T.C.gold, 0.18)
  edge:SetWidth(1); edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT")
  main.side = side
  main.groups = {}
  for _, t in ipairs(TABS) do
    if not t.noNav then
      local b = T.navButton(side, t[1], "Interface\\Icons\\" .. NAV[t[1]][1], function()
        -- "Character" under You is you, not whoever was looked at last from the Guild page.
        if t[1] == "Character" then ns.selected = ns.selfName end
        ns.showTab(t[1])
      end)
      b:SetPoint("RIGHT", -1, 0)
      tabs[t[1]] = b
      if t.group and not main.groups[t.group] then
        local g = T.text(side, "group"); g:SetText(t.group:upper()); main.groups[t.group] = g
      end
    end
  end

  local card = CreateFrame("Frame", nil, side)
  card:SetPoint("BOTTOMLEFT", 14, 14); card:SetPoint("BOTTOMRIGHT", -14, 14); card:SetHeight(132)
  local cbg = T.fill(card, "BACKGROUND", T.C.midnight, 0.7); cbg:SetAllPoints()
  T.outline(card, 0, T.C.gold, 0.25)
  main.syncCard = card
  main.syncDot = T.fill(card, "ARTWORK", { 0.561, 0.820, 0.541 }, 1); main.syncDot:SetSize(6, 6); main.syncDot:SetPoint("TOPLEFT", 12, -15)
  main.sync = T.text(card, "small"); main.sync:SetPoint("LEFT", main.syncDot, "RIGHT", 7, 0); main.sync:SetPoint("RIGHT", -10, 0)
  main.update = T.text(card, "tagline"); main.update:SetPoint("TOPLEFT", 12, -28); main.update:SetPoint("RIGHT", -10, 0)
  -- Hide Olympus: the switch turns it all on or off, the label opens its page.
  local oly = CreateFrame("Frame", nil, card)
  oly:SetPoint("TOPLEFT", 12, -50); oly:SetPoint("RIGHT", -12, 0); oly:SetHeight(20)
  local olyLabel = CreateFrame("Button", nil, oly)
  olyLabel:SetPoint("TOPLEFT"); olyLabel:SetPoint("BOTTOMRIGHT", -44, 0)
  olyLabel.text = T.text(olyLabel, "badge"); olyLabel.text:SetPoint("LEFT", 0, 0); olyLabel.text:SetText("HIDE OLYMPUS")
  olyLabel.text:SetTextColor(T.C.text[1], T.C.text[2], T.C.text[3])
  olyLabel:SetScript("OnClick", function() ns.showTab("Hide Olympus") end)
  olyLabel:SetScript("OnEnter", function(self)
    self.text:SetTextColor(T.C.pale[1], T.C.pale[2], T.C.pale[3])
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Hide Olympus", T.C.gold[1], T.C.gold[2], T.C.gold[3])
    GameTooltip:AddLine("Hides chat from players in Olympus guilds and turns away their whispers, invites, trades and duels. Click to choose which.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  olyLabel:SetScript("OnLeave", function(self) self.text:SetTextColor(T.C.text[1], T.C.text[2], T.C.text[3]); GameTooltip:Hide() end)
  main.olySwitch = T.switch(oly, ns.olympus.set)
  main.olySwitch:SetPoint("RIGHT", 0, 0)
  main.olyRow = oly
  local sync = T.button(card, "Save & reload", 140, function() ns.saveAndReload() end, "tab")
  sync:SetPoint("TOPLEFT", 12, -80); sync:SetPoint("RIGHT", -12, 0)
  main.syncButton = sync
  local version = T.text(card, "muted", "CENTER"); version:SetPoint("TOP", sync, "BOTTOM", 0, -6)
  version:SetText("v" .. ns.VERSION); version:SetAlpha(0.6)
  sync:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Save & reload", T.C.gold[1], T.C.gold[2], T.C.gold[3])
    GameTooltip:AddLine("Reloads your UI so WoW saves the guild's data for the Perpetua app, and loads the newest calendar" .. (ns.FORUMS and " and forums" or "") .. ".", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  sync:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Outside the guild the sidebar shows only this in place of the sections.
  main.lockedNote = T.text(side, "muted")
  main.lockedNote:SetPoint("TOPLEFT", 18, -18); main.lockedNote:SetPoint("RIGHT", -14, 0)
  main.lockedNote:SetWordWrap(true); main.lockedNote:SetJustifyH("LEFT")
  main.lockedNote:SetText("Guild sync, the calendar, loot and everything else unlock when you join <" .. ns.GUILD .. ">.")

  -- Page header: the title over the site's gold rule with a diamond, a subtitle beside it, numbers on the right.
  local X = SIDE + 26
  main.title = T.text(main, "title"); main.title:SetPoint("TOPLEFT", X, -(TOP + 18))
  main.rule = T.rule(main); main.rule:SetPoint("TOPLEFT", main.title, "BOTTOMLEFT", 0, -6); main.rule:SetWidth(150)
  main.subtitle = T.text(main, "muted"); main.subtitle:SetPoint("LEFT", main.rule, "RIGHT", 12, 0)
  main.status = T.text(main, "muted", "RIGHT"); main.status:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", -26, -112) -- errors only

  for _, t in ipairs(TABS) do
    local page = CreateFrame("Frame", nil, main)
    page:SetPoint("TOPLEFT", X, -(TOP + 64))
    page:SetPoint("BOTTOMRIGHT", -24, 18)
    page:Hide()
    pages[t[1]] = page
    t[2](page)
  end
end

local renderers = {}
for _, t in ipairs(TABS) do renderers[t[1]] = t[3] end

local lastTab -- where a member was before the window locked (they left the guild)
function ns.showTab(name)
  if not main then build() end
  if not pages[name] then name = "Guild" end -- a switched-off page (ns.FORUMS)
  local locked = ns.locked()
  if locked then name = "Welcome" elseif name == "Welcome" then name = lastTab or (not PerpetuaDB.setupSeen and "Setup") or "Guild" end
  -- Going anywhere but Setup counts as having seen it: no more "new here?" at login, no landing on Setup.
  if not locked and name ~= "Setup" and name ~= "Welcome" then PerpetuaDB.setupSeen = true end
  if name ~= "Welcome" then lastTab = name end
  current = name
  -- Pages that come with the New guild window go away when it's off.
  local newGuild = ns.newGuildWindow()
  for _, t in ipairs(TABS) do
    if t[1] == name and t.newGuild and not newGuild then name = "Guild" end
  end
  current = name
  for n, page in pairs(pages) do page:SetShown(n == name) end
  -- The sidebar, top to bottom: a group's label before its first page, no gaps for hidden pages.
  local y, lastGroup = -6, nil
  for _, g in pairs(main.groups) do g:Hide() end
  for _, t in ipairs(TABS) do
    local b = tabs[t[1]]
    if b then
      local shown = not locked and (newGuild or not t.newGuild)
      b:SetShown(shown)
      b:SetSelected(t[1] == name)
      if shown then
        if t.group ~= lastGroup and main.groups[t.group] then
          y = y - 12
          local g = main.groups[t.group]
          g:ClearAllPoints(); g:SetPoint("TOPLEFT", main.side, "TOPLEFT", 18, y); g:Show()
          y = y - 16
          lastGroup = t.group
        end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", main.side, "TOPLEFT", 0, y); b:SetPoint("RIGHT", main.side, "RIGHT", -1, 0)
        y = y - 34
      end
    end
  end
  main.syncCard:SetShown(not locked); main.lockedNote:SetShown(locked)
  main.newRow:SetShown(not locked)
  main.title:SetText(name:upper())
  local tabsCalendar = tabs.Calendar
  if tabsCalendar then tabsCalendar:SetCount(ns.upcomingRaids and ns.upcomingRaids() or 0) end
  main.subtitle:SetText(NAV[name][2])
  main:Show()
  ns.refreshUI(true)
end

-- WoW only writes saved variables on logout or a UI reload, so "saving" for the Perpetua app means reloading.
-- Asked first (it closes everything for a few seconds), and not in combat.
function ns.saveAndReload()
  if InCombatLockdown() then
    print("|cffd4af37Perpetua|r: Save & reload waits until you're out of combat.")
    return
  end
  T.dialog({
    title = "Save & reload", accept = "Reload",
    text = "Reloads your UI so WoW saves your profile and the guild's data for the Perpetua app, and loads the newest raid calendar. It takes a few seconds.",
    onAccept = function() ns.refreshSelf(true); ReloadUI() end,
  })
end

local pendingRefresh = false
function ns.refreshUI(now)
  if not (main and main:IsShown() and current) then return end
  if not now then
    -- Sync can deliver many updates in a row: redraw at most once a second.
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(1, function() pendingRefresh = false; ns.refreshUI(true) end)
    return
  end
  -- Joined or left the guild while the window was open, or the New guild window was switched.
  if ns.locked() ~= (current == "Welcome") then ns.showTab(current) return end
  if main.newGuildShown ~= ns.newGuildWindow() then main.newGuildShown = ns.newGuildWindow(); ns.showTab(current) return end
  main.guild:SetText(current ~= "Welcome" and ns.guildName() and ("<" .. safe(ns.guildName()) .. ">") or "")
  main.status:SetText("")
  local heard = 0
  for _ in pairs(ns.session.heard) do heard = heard + 1 end
  main.olySwitch:SetOn(ns.olympus.db().on)
  main.newSwitch:SetOn(ns.newGuildWindow())
  local update = not ns.locked() and ns.updateAvailable()
  main.update:SetText(update and ("Update available: " .. safe(update)) or "")
  main.sync:SetText(heard .. " guildmates heard  ·  " .. ns.session.received .. " updates")
  main.syncDot:SetVertexColor(heard > 0 and 0.561 or 0.639, heard > 0 and 0.820 or 0.675, heard > 0 and 0.541 or 0.788, 1)
  main.statsSet = false
  local ok, err = pcall(renderers[current])
  if not main.statsSet then setStats(nil) end
  if not ok then main.status:SetText(color(T.HEX.danger, safe(tostring(err):sub(1, 120)))) end
end
ns.fire = function() ns.refreshUI() end
function ns.currentTabForTest() return current end -- for the test harness

function ns.toggle(tab)
  if main and main:IsShown() and (not tab or tab == current) then main:Hide() return end
  -- The first time, the setup page; after that wherever they left off.
  ns.showTab(tab or current or (not PerpetuaDB.setupSeen and "Setup") or "Guild")
end

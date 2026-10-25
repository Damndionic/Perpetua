-- The loot master's window: in a raid, an officer running master loot gets this beside the loot window for each
-- epic. A contested item shows its priority list and who of it is here; anything else is rolled: the window posts
-- the roll to raid warning, collects /rolls for a few seconds, adds everyone's pity bonus and names the winner.
-- Awarding tells the raid, records the award for the guild and the site (Loot.lua), and hands the item over with
-- master loot when the client allows it (otherwise the loot master trades it).
local _, ns = ...
local T, safe, try = ns.T, ns.safe, ns.try

local LM = { rolls = {}, rows = {} }
ns.lootMaster = LM
local ROLL_TIME = 20
local f

local function color(hex, s) return "|cff" .. hex .. s .. "|r" end
local function firstName(n) return (n or ""):match("^(%S+)") or n end

local function itemLink()
  local it = LM.item
  local q = ns.QUALITY[it.q or 4] or "a335ee"
  return "|cff" .. q .. "|Hitem:" .. it.id .. "::::::::::::|h[" .. (it.name or ("Item " .. it.id)) .. "]|h|r"
end

-- Raid members, as the addon names them ("First Surname").
local function raidNames()
  local out = {}
  for i = 1, (try(GetNumGroupMembers) or 0) do
    local first, second = try(UnitName, (try(IsInRaid) and "raid" or "party") .. i)
    first, second = ns.readable(first), ns.readable(second)
    if type(first) == "string" then out[ns.fullName(first, ns.FOREVER and type(second) == "string" and second ~= "" and second or nil)] = true end
  end
  if ns.selfName then out[ns.selfName] = true end
  return out
end

local function say(msg, channel)
  local ok = pcall(C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage, msg, channel or (try(IsInRaid) and "RAID" or "PARTY"))
  if not ok then print("|cffd4af37Perpetua|r: " .. msg) end
end

local function build()
  f = CreateFrame("Frame", "PerpetuaLootMaster", UIParent)
  f:SetSize(440, 400)
  f:SetPoint("LEFT", UIParent, "LEFT", 380, 60)
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
  f.title = T.text(f, "heading"); f.title:SetPoint("TOPLEFT", 22, -20); f.title:SetText("LOOT MASTER")
  local close = T.closeButton(f, function() f:Hide() end); close:SetPoint("TOPRIGHT", -12, -12)
  f.icon = T.icon(f, nil, 36); f.icon:SetPoint("TOPLEFT", 22, -46)
  f.item = T.text(f, "body"); f.item:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -1); f.item:SetPoint("RIGHT", -22, 0)
  f.lane = T.text(f, "muted"); f.lane:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", 0, -3); f.lane:SetPoint("RIGHT", -22, 0)
  f.timer = T.text(f, "badgeValue", "RIGHT"); f.timer:SetPoint("TOPRIGHT", -24, -50)
  -- column heads and rows
  local heads = CreateFrame("Frame", nil, f)
  heads:SetPoint("TOPLEFT", 22, -96); heads:SetPoint("RIGHT", -22, 0); heads:SetHeight(18)
  local line = T.fill(heads, "ARTWORK", T.C.gold, 0.25); line:SetHeight(1); line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
  local COLS = { { 0, 160, "LEFT" }, { 170, 50, "RIGHT" }, { 226, 50, "RIGHT" }, { 282, 56, "RIGHT" }, { 346, 50, "RIGHT" } }
  f.heads = {}
  for i, c in ipairs(COLS) do
    local h = T.text(heads, "label", c[3]); h:SetPoint("LEFT", c[1], 0); h:SetWidth(c[2])
    f.heads[i] = h
  end
  for i = 1, 9 do
    local r = CreateFrame("Frame", nil, f)
    r:SetPoint("TOPLEFT", heads, "BOTTOMLEFT", 0, -2 - (i - 1) * 22); r:SetPoint("RIGHT", heads, "RIGHT"); r:SetHeight(22)
    r.win = T.gradient(r, "BACKGROUND", "HORIZONTAL", T.C.gold, 0.22, T.C.gold, 0.02); r.win:SetAllPoints()
    r.cells = {}
    for j, c in ipairs(COLS) do
      local t = T.text(r, "small", c[3]); t:SetPoint("LEFT", c[1], 0); t:SetWidth(c[2])
      r.cells[j] = t
    end
    LM.rows[i] = r
  end
  f.status = T.text(f, "muted"); f.status:SetPoint("BOTTOMLEFT", 22, 58); f.status:SetPoint("RIGHT", -22, 0)
  f.status:SetWordWrap(true); f.status:SetJustifyV("BOTTOM")
  f.primary = T.button(f, "Start roll", 180, function() LM.primary() end)
  f.primary:SetPoint("BOTTOMLEFT", 22, 20)
  f.second = T.button(f, "Reroll", 100, function() LM.startRoll() end, "tab")
  f.second:SetPoint("LEFT", f.primary, "RIGHT", 10, 0)
  f.cancel = T.button(f, "Skip", 90, function() LM.state = "idle"; f:Hide() end, "tab")
  f.cancel:SetPoint("BOTTOMRIGHT", -22, 20)
  f:SetScript("OnUpdate", function(_, elapsed)
    if LM.state ~= "rolling" then return end
    LM.tick = (LM.tick or 0) + elapsed
    if LM.tick < 0.25 then return end
    LM.tick = 0
    local left = math.ceil(LM.ends - GetTime())
    if left <= 0 then LM.state = "done"; LM.render() else f.timer:SetText(left .. " s") end
  end)
end

-- Fills the window for the current state: "list" (contested), "idle" (not rolled yet), "rolling", "done".
function LM.render()
  if not f then return end
  local it = LM.item
  f.icon.tex:SetTexture(try(C_Item and C_Item.GetItemIconByID, it.id) or 134400)
  f.item:SetText(itemLink())
  f.timer:SetText("")
  for _, r in ipairs(LM.rows) do r:Hide() end
  local function row(i, cells, win)
    local r = LM.rows[i]
    if not r then return end
    for j = 1, 5 do r.cells[j]:SetText(cells[j] or "") end
    r.win:SetShown(win and true or false)
    r:Show()
  end
  if LM.state == "list" then
    local c, here = LM.contested, raidNames()
    local st = ns.pityStandings()
    f.lane:SetText(color(T.HEX.pale, "Contested list") .. "  ·  " .. safe(c.raid or "") .. "  ·  first one here in priority order")
    local heads = { "Priority", "Here", "", "", "" }
    for i, h in ipairs(f.heads) do h:SetText((heads[i] or ""):upper()) end
    LM.pick = nil
    for i, n in ipairs(c.order or {}) do
      local has = c.got == n or (st[n] and st[n].c and st[n].c ~= tonumber(c.it))
      local ok = here[n] and not has
      if ok and not LM.pick then LM.pick = n end
      row(i, { i .. ". " .. safe(n), here[n] and color(T.HEX.ok, "yes") or color(T.HEX.dim, "no"), has and color(T.HEX.dim, "has one") or "" }, LM.pick == n)
    end
    f.status:SetText(LM.pick and safe(c.why or "") or "Nobody on the list is in the raid: roll it instead.")
    f.primary.label:SetText(LM.pick and ("AWARD TO " .. firstName(LM.pick):upper()) or "ROLL IT")
    f.primary:SetUsable(true)
    f.second:SetShown(false)
    return
  end
  f.lane:SetText(color(T.HEX.gold, "Pity roll") .. "  ·  main spec /roll 100, off spec /roll 99")
  local heads = { "Raider", "Roll", "Pity", "Total", "Spec" }
  for i, h in ipairs(f.heads) do h:SetText(heads[i]:upper()) end
  local scored, winner = ns.scoreRolls(LM.rolls)
  LM.scored, LM.winner = scored, winner
  for i, s in ipairs(scored) do
    row(i, { safe(s.n), tostring(s.r), s.b > 0 and color(T.HEX.gold, "+" .. s.b) or color(T.HEX.dim, "—"),
      s.spec == "ms" and color(T.HEX.pale, tostring(s.total)) or color(T.HEX.muted, tostring(s.total)),
      s.spec == "ms" and "MS" or color(T.HEX.muted, "OS") }, LM.state == "done" and s == winner)
  end
  f.second:SetShown(LM.state ~= "idle")
  if LM.state == "idle" then
    f.status:SetText("Posts the roll to raid warning and collects rolls for " .. ROLL_TIME .. " seconds. Pity bonuses are added for you.")
    f.primary.label:SetText("START ROLL")
    f.primary:SetUsable(true)
  elseif LM.state == "rolling" then
    f.status:SetText(#scored .. (#scored == 1 and " roll" or " rolls") .. " so far. Rolls of 50 or a second roll don't count.")
    f.primary.label:SetText("END ROLL NOW")
    f.primary:SetUsable(true)
  else
    if winner then
      local ms = 0
      for _, s in ipairs(scored) do if s.spec == "ms" and s ~= winner then ms = ms + 1 end end
      f.status:SetText(firstName(winner.n) .. " wins " .. (winner.spec == "ms" and "on main spec" or "on off spec") ..
        (winner.spec == "ms" and ms > 0 and (". " .. ms .. " main-spec " .. (ms == 1 and "roll" or "rolls") .. " lost: +" .. ((ns.lootPlan() and ns.lootPlan().step) or ns.PITY_STEP) .. " each.") or "."))
      f.primary.label:SetText("AWARD TO " .. firstName(winner.n):upper())
      f.primary:SetUsable(true)
    else
      f.status:SetText("Nobody rolled. Roll again, or skip it (leftovers go to the guild bank).")
      f.primary.label:SetText("AWARD")
      f.primary:SetUsable(false, "Nobody rolled.")
    end
  end
end

-- Opens the window for an item: { id, name, q }.
function LM.open(item)
  if not f then build() end
  LM.item = item
  LM.rolls = {}
  LM.contested = ns.contestedFor(item.id)
  LM.state = LM.contested and "list" or "idle"
  f:SetScale(T.scale())
  f:Show()
  LM.render()
end

function LM.startRoll()
  if not LM.item then return end
  LM.rolls, LM.state, LM.ends, LM.tick = {}, "rolling", GetTime() + ROLL_TIME, 1
  LM.contested = nil
  say("Roll for " .. itemLink() .. ": main spec /roll 100, off spec /roll 99. " .. ROLL_TIME .. " seconds. Your pity bonus is added.", "RAID_WARNING")
  LM.render()
end

function LM.award(name, lane)
  local it = LM.item
  local a = { it = it.id, name = it.name, q = it.q, n = name, lane = lane }
  if lane == "roll" then
    local w = LM.winner
    a.spec = w and w.spec or "ms"
    a.rolls, a.losers = {}, {}
    for _, s in ipairs(LM.scored or {}) do
      a.rolls[#a.rolls + 1] = { n = s.n, r = s.r, b = s.b }
      if s ~= w and s.spec == "ms" and a.spec == "ms" then a.losers[#a.losers + 1] = s.n end
    end
    local beat = {}
    for i, s in ipairs(LM.scored or {}) do
      if s ~= w and i <= 4 then beat[#beat + 1] = firstName(s.n) .. " " .. s.r .. (s.b > 0 and ("+" .. s.b) or "") end
    end
    say(firstName(name) .. " wins " .. itemLink() .. " (" .. (w and (w.r .. (w.b > 0 and ("+" .. w.b) or "")) or "?") .. ", " .. (a.spec == "ms" and "main spec" or "off spec") .. ")"
      .. (#beat > 0 and (". " .. table.concat(beat, ", ")) or "") .. (#a.losers > 0 and ". Pity +" .. ((ns.lootPlan() and ns.lootPlan().step) or ns.PITY_STEP) .. " for the rest of main spec." or "."))
  else
    say(firstName(name) .. " gets " .. itemLink() .. " from the contested list.")
  end
  ns.recordAward(a)
  ns.onLootChat(string.format(LOOT_ITEM or "%s receives loot: %s.", name:gsub(" ", "-"), itemLink())) -- into the loot log now; the real loot line adds nothing new
  -- Hand it over: master loot when the client offers it, else a reminder to trade it.
  local given = false
  if GiveMasterLoot and GetNumLootItems and GetMasterLootCandidate then
    for slot = 1, (try(GetNumLootItems) or 0) do
      local link = try(GetLootSlotLink, slot)
      if link and ns.itemIdFrom(link) == it.id then
        for c = 1, 40 do
          local cand = try(GetMasterLootCandidate, slot, c)
          if cand and ns.playerKey(cand) == name then given = pcall(GiveMasterLoot, slot, c) break end
        end
      end
    end
  end
  if not given then print("|cffd4af37Perpetua|r: give " .. itemLink() .. " to " .. name .. " (trade it if master loot didn't).") end
  LM.state = "idle"
  f:Hide()
end

function LM.primary()
  if LM.state == "list" then
    if LM.pick then LM.award(LM.pick, "list") else LM.state = "idle"; LM.contested = nil; LM.render() end
  elseif LM.state == "idle" then LM.startRoll()
  elseif LM.state == "rolling" then LM.state = "done"; LM.render()
  elseif LM.state == "done" and LM.winner then LM.award(LM.winner.n, "roll") end
end

-- A /roll while the window is collecting (Loot.lua passes every roll it sees in the group).
function LM.onRoll(e)
  if LM.state ~= "rolling" then return end
  LM.rolls[#LM.rolls + 1] = e
  LM.render()
end

-- Master loot: the loot window opened with an epic and we're the loot master. Officers only.
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "LOOT_OPENED")
ev:SetScript("OnEvent", function()
  if not (ns.selfName and ns.isOfficer and ns.isOfficer(ns.selfName)) then return end
  local method, partyMaster, raidMaster = try(C_PartyInfo and C_PartyInfo.GetLootMethod or GetLootMethod)
  local master = (method == "master" or method == 2) and (partyMaster == 0 or raidMaster == try(UnitInRaid, "player"))
  if not master then return end
  for slot = 1, (try(GetNumLootItems) or 0) do
    local link = try(GetLootSlotLink, slot)
    local _, name, _, _, q = try(GetLootSlotInfo, slot)
    if link and (q or 0) >= 4 then
      LM.open({ id = ns.itemIdFrom(link), name = name or link:match("%[(.-)%]"), q = q })
      return
    end
  end
end)

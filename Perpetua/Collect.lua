-- Reads this character: gear, talents, stats, professions, attunements, reputations, and (from profession
-- windows) recipes. Forever runs the retail client on the Vanilla world, so the retail APIs come first and the
-- old Classic ones are kept as fallbacks. Each section runs in its own pcall: if Blizzard changes one API, the
-- rest still works and the failure is listed under "errors" for us to fix.
--
-- A character's data travels as two parts: the profile (everything but recipes, small, changes often) and the
-- recipes (big, change rarely). merge() puts them back together for the site and the Character tab.
local _, ns = ...
local try, num, text, itemIdFrom = ns.try, ns.num, ns.text, ns.itemIdFrom

local function collectCharacter(d)
  local name, second = UnitName("player")
  local race, raceFile = UnitRace("player")
  local class, classFile = UnitClass("player")
  local guild, guildRank = try(GetGuildInfo, "player")
  d.char = {
    name = text(name),
    surname = ns.FOREVER and text(second) or nil,
    realm = text(try(GetNormalizedRealmName)) or text(try(GetRealmName)) or (not ns.FOREVER and text(second) or nil),
    level = num(UnitLevel("player")),
    race = text(race), raceFile = text(raceFile),
    class = text(class), classFile = text(classFile),
    sex = num(try(UnitSex, "player")),
    faction = text(try(UnitFactionGroup, "player")),
    guild = text(guild), guildRank = text(guildRank),
  }
end

local function collectSpecAndTalents(d)
  local S = C_SpecializationInfo
  local index = try(S and S.GetSpecialization) or try(GetSpecialization)
  if index then
    local id, name, _, _, role = try(S and S.GetSpecializationInfo or GetSpecializationInfo, index)
    if id then d.spec = { id = num(id), n = text(name), role = text(role) } end
  end

  d.talents = { list = {} }
  local C, T = C_ClassTalents, C_Traits
  local config = C and try(C.GetActiveConfigID)
  if config and T then
    d.talents.string = text(try(T.GenerateImportString, config))
    local info = try(T.GetConfigInfo, config)
    local columns = {} -- every node's x position, to find where one tree ends and the next begins
    for _, tree in ipairs(info and info.treeIDs or {}) do
      for _, nodeID in ipairs(try(T.GetTreeNodes, tree) or {}) do
        local node = try(T.GetNodeInfo, config, nodeID)
        if node and num(node.posX) then columns[#columns + 1] = num(node.posX) end
        local rank = node and num(node.activeRank)
        if rank and rank > 0 and node.activeEntry then
          local entry = try(T.GetEntryInfo, config, node.activeEntry.entryID)
          local def = entry and entry.definitionID and try(T.GetDefinitionInfo, entry.definitionID)
          local spell = def and (num(def.spellID) or num(def.overriddenSpellID))
          local name = def and text(def.overrideName)
            or (spell and (text(try(C_Spell and C_Spell.GetSpellName, spell)) or text(try(GetSpellInfo, spell))))
          if name then
            d.talents.list[#d.talents.list + 1] = { sp = spell, n = name, r = rank, m = num(node.maxRanks), x = num(node.posX), y = num(node.posY) }
          end
        end
      end
    end
    ns.nameSpecFromTrees(d, columns)
  elseif GetNumTalentTabs then
    -- Classic talent trees: points per tree, plus each talent with a rank.
    d.talents.trees = {}
    for tab = 1, (try(GetNumTalentTabs) or 0) do
      local a, b = try(GetTalentTabInfo, tab)
      local treeName = type(a) == "string" and a or b
      local points = 0
      for i = 1, (try(GetNumTalents, tab) or 0) do
        local name, _, tier, column, rank, maxRank = try(GetTalentInfo, tab, i)
        if rank and rank > 0 then
          points = points + rank
          d.talents.list[#d.talents.list + 1] = { n = text(name), r = rank, m = maxRank, x = column, y = tier }
        end
      end
      d.talents.trees[#d.talents.trees + 1] = { n = text(treeName), pts = points }
    end
  end
end

-- The enchant line from the item's tooltip, when the client offers tooltip data (retail).
local function enchantText(slot)
  if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem and Enum and Enum.TooltipDataLineType) then return end
  local tip = try(C_TooltipInfo.GetInventoryItem, "player", slot)
  local kind = Enum.TooltipDataLineType.ItemEnchantmentPermanent
  for _, line in ipairs(tip and tip.lines or {}) do
    if kind and line.type == kind then return text(line.leftText) end
  end
end

local function collectGear(d)
  d.gear = {}
  for slot = 1, 19 do
    local link = text(try(GetInventoryItemLink, "player", slot))
    local id = itemIdFrom(link)
    if id then
      -- item:id:enchant:gem1:gem2:gem3:gem4:suffix:...
      local fields = { strsplit(":", link:match("item:([%-%d:]+)") or "") }
      local ilvl = num(try(C_Item and C_Item.GetDetailedItemLevelInfo, link)) or num(try(GetDetailedItemLevelInfo, link))
        or num(select(4, try(C_Item and C_Item.GetItemInfo or GetItemInfo, link)))
      d.gear[#d.gear + 1] = {
        s = slot, id = id, n = text(link:match("%[(.-)%]")),
        q = num(try(GetInventoryItemQuality, "player", slot)), il = ilvl,
        e = tonumber(fields[2]), sf = tonumber(fields[7]), en = enchantText(slot),
      }
    end
  end
end

local function collectProfessions(d)
  d.profs = {}
  local seen = {}
  local function add(name, rank, max, line, primary)
    name = text(name)
    if not name or seen[name] then return end
    seen[name] = true
    d.profs[#d.profs + 1] = { n = name, r = num(rank), m = num(max), line = num(line), p = primary and 1 or 0 }
  end
  if GetProfessions then
    local list = { try(GetProfessions) } -- prof1, prof2, archaeology, fishing, cooking (any may be nil)
    for i = 1, 6 do
      if list[i] then
        local name, _, rank, max, _, _, line = try(GetProfessionInfo, list[i])
        add(name, rank, max, line, i <= 2)
      end
    end
  end
  if #d.profs == 0 and GetNumSkillLines then
    -- Classic skill list: everything under the Professions / Secondary Skills headers.
    local header
    for i = 1, (try(GetNumSkillLines) or 0) do
      local name, isHeader, _, rank, _, _, max = try(GetSkillLineInfo, i)
      if isHeader then header = name
      elseif header == PROFESSIONS_TITLE or header == "Professions" then add(name, rank, max, nil, true)
      elseif header == SECONDARY_SKILLS or header == "Secondary Skills" then add(name, rank, max, nil, false)
      end
    end
  end
end

local function collectAttunements(d)
  d.quests, d.items = {}, {}
  local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
  for _, id in ipairs(ns.WATCH_QUESTS) do
    if try(done, id) == true then d.quests[#d.quests + 1] = id end
  end
  local count = C_Item and C_Item.GetItemCount or GetItemCount
  for _, id in ipairs(ns.WATCH_ITEMS) do
    local n = num(try(count, id, true))
    if n and n > 0 then d.items[tostring(id)] = n end
  end
end

local function collectReputation(d)
  d.rep = {}
  local R = C_Reputation
  if R and R.GetNumFactions and R.GetFactionDataByIndex then
    -- Collapsed headers hide their factions from the list, so open them all to read it, then close again the ones
    -- the player had closed (bottom up, so the indexes don't shift under us).
    local closed = {}
    for i = 1, (try(R.GetNumFactions) or 0) do
      local f = try(R.GetFactionDataByIndex, i)
      if f and f.isHeader and f.isCollapsed and f.factionID then closed[f.factionID] = true end
    end
    if next(closed) then try(R.ExpandAllFactionHeaders) end
    for i = 1, (try(R.GetNumFactions) or 0) do
      local f = try(R.GetFactionDataByIndex, i)
      if f and (not f.isHeader or f.isHeaderWithRep) then
        local low, high, cur = num(f.currentReactionThreshold), num(f.nextReactionThreshold), num(f.currentStanding)
        d.rep[#d.rep + 1] = {
          id = num(f.factionID), n = text(f.name), s = num(f.reaction),
          v = cur and low and cur - low or nil, m = high and low and high - low or nil,
        }
      end
    end
    if next(closed) and R.CollapseFactionHeader then
      for i = (try(R.GetNumFactions) or 0), 1, -1 do
        local f = try(R.GetFactionDataByIndex, i)
        if f and f.isHeader and not f.isCollapsed and closed[f.factionID] then try(R.CollapseFactionHeader, i) end
      end
    end
    -- Opening and closing headers fires UPDATE_FACTION; Core.lua ignores the echo for a moment so this read
    -- doesn't schedule itself again.
    if next(closed) then ns.repReadAt = GetTime() end
  elseif GetNumFactions then
    for i = 1, (try(GetNumFactions) or 0) do
      local name, _, standing, low, high, value, _, _, isHeader, _, hasRep, _, _, factionID = try(GetFactionInfo, i)
      if name and (not isHeader or hasRep) then
        d.rep[#d.rep + 1] = { id = num(factionID), n = text(name), s = num(standing), v = value and low and value - low, m = high and low and high - low }
      end
    end
  end
end

local function collectStats(d)
  local function stat(i) local _, effective = try(UnitStat, "player", i) return num(effective) end
  local _, armor = try(UnitArmor, "player")
  d.stats = {
    str = stat(1), agi = stat(2), sta = stat(3), int = stat(4), spi = stat(5),
    armor = num(armor), hp = num(try(UnitHealthMax, "player")), mp = num(try(UnitPowerMax, "player")),
  }
  local _, power = try(UnitPowerType, "player")
  d.powerType = text(power)
  local function res(i) local base, total = try(UnitResistance, "player", i) return num(total) or num(base) end
  d.res = { fire = res(2), nature = res(3), frost = res(4), shadow = res(5), arcane = res(6) }
  local rank = num(try(UnitPVPRank, "player"))
  if rank and rank > 0 then d.pvp = { rank = rank, n = text(try(GetPVPRankInfo, rank)) } end
end

-- The three trees sit side by side in the talent layout, so the two widest gaps between node columns are where
-- one tree ends and the next begins. Points are counted per tree, and the tree with the most names the spec
-- (Forever's own specialization is just the class name).
function ns.nameSpecFromTrees(d, columns)
  local names = ns.TREES[d.char and d.char.classFile or ""]
  if not names or #columns < 3 or #d.talents.list == 0 then return end
  table.sort(columns)
  local gaps = {}
  for i = 2, #columns do
    if columns[i] > columns[i - 1] then gaps[#gaps + 1] = { size = columns[i] - columns[i - 1], at = (columns[i] + columns[i - 1]) / 2 } end
  end
  if #gaps < 2 then return end
  table.sort(gaps, function(a, b) return a.size > b.size end)
  local cut1, cut2 = math.min(gaps[1].at, gaps[2].at), math.max(gaps[1].at, gaps[2].at)
  local points = { 0, 0, 0 }
  for _, t in ipairs(d.talents.list) do
    local tree = (t.x or 0) < cut1 and 1 or (t.x or 0) < cut2 and 2 or 3
    t.tr = tree
    points[tree] = points[tree] + (t.r or 0)
  end
  d.talents.trees = {}
  local best = 1
  for i = 1, 3 do
    d.talents.trees[i] = { n = names[i], pts = points[i] }
    if points[i] > points[best] then best = i end
  end
  d.spec = d.spec or {}
  d.spec.class = d.spec.n -- what the game called it
  d.spec.n = names[best]
  d.spec.role = ns.treeRole(names[best])
end

-- Each section, and the profile fields it fills. Stats change all the time (buffs) and are cheap, so they're always
-- read; the rest are read again only when an event says they may have changed (ns.markDirty, from Core.lua), and
-- otherwise reused from the last read. Talents (hundreds of nodes) and reputations were the expensive ones.
local SECTIONS = {
  { "character", collectCharacter, { "char" } },
  { "talents", collectSpecAndTalents, { "spec", "talents" } },
  { "gear", collectGear, { "gear" } },
  { "professions", collectProfessions, { "profs" } },
  { "attunements", collectAttunements, { "quests", "items" } },
  { "reputation", collectReputation, { "rep" } },
  { "stats", collectStats, { "stats", "powerType", "res", "pvp" }, always = true },
}

local cached, dirty = {}, nil -- dirty = nil: everything
local EMPTY_MEANS_UNLOADED = { gear = "gear", professions = "profs" }
local emptyReads = {}
function ns.markDirty(section)
  if dirty then dirty[section] = true end
end

-- This character's profile, without recipes and without a time stamp (so it can be hashed).
function ns.collectProfile()
  local build, _, _, toc = GetBuildInfo()
  local d = { v = 1, addon = ns.VERSION, build = build and (build .. " (" .. tostring(toc) .. ")") }
  local errors, retry = {}, false
  for _, s in ipairs(SECTIONS) do
    local name, fn, fields = s[1], s[2], s[3]
    local c = cached[name]
    if s.always or not dirty or dirty[name] or not c then
      local ok, err = pcall(fn, d)
      -- Gear or professions that read empty after a good read usually mean the character isn't fully loaded
      -- (loading screens, logging out). Keep the last good read, don't cache the empty one, and look again shortly.
      -- (Only when the last read had something: a new character really can have no professions.)
      local key = EMPTY_MEANS_UNLOADED[name]
      -- After three empty reads in a row it's real (they took everything off), and that's what gets saved.
      if ok and key and #(d[key] or {}) == 0 and c and #(c[key] or {}) > 0 and (emptyReads[name] or 0) < 3 then
        emptyReads[name] = (emptyReads[name] or 0) + 1
        for _, f in ipairs(fields) do d[f] = c[f] end
        retry = true
      elseif ok then
        emptyReads[name] = nil
        c = {}
        for _, f in ipairs(fields) do c[f] = d[f] end
        cached[name] = c
      else
        errors[#errors + 1] = name .. ": " .. tostring(err):sub(1, 200)
        cached[name] = nil -- try again next time
      end
    else
      for _, f in ipairs(fields) do d[f] = c[f] end
    end
  end
  dirty = {}
  if retry then
    for name in pairs(EMPTY_MEANS_UNLOADED) do dirty[name] = true end
    ns.scheduleRefresh(10)
  end
  if #errors > 0 then d.errors = errors end
  return d
end

-- Profile + recipes as one table, the shape the site takes. recipes = { [profession] = { list, t, r, m } }.
-- Doesn't change either input.
function ns.merge(profile, recipes)
  if not profile then return nil end
  local d = {}
  for k, v in pairs(profile) do d[k] = v end
  d.profs = {}
  local seen = {}
  for _, p in ipairs(profile.profs or {}) do
    local saved = recipes and recipes[p.n]
    local copy = {}
    for k, v in pairs(p) do copy[k] = v end
    if saved then copy.recipes, copy.seen = saved.list, saved.t end
    d.profs[#d.profs + 1] = copy
    seen[p.n] = true
  end
  -- Recipes from a profession the summary didn't list (renamed, or read from a craft window).
  for name, saved in pairs(recipes or {}) do
    if not seen[name] and type(saved) == "table" then
      d.profs[#d.profs + 1] = { n = name, recipes = saved.list, seen = saved.t, r = saved.r, m = saved.m, p = 1 }
    end
  end
  return d
end

-- ---------- guildmates' data, kept small ----------
-- A guildmate's full profile (gear, talents, stats, reputations) and recipes are only needed when someone opens
-- their Character page or the Crafters page, so they're kept as the compressed strings guild sync delivered
-- (rec.pz, rec.rz: "PERP1Z:..." from ns.pack) and rec.profile holds just this summary, which the lists read.
-- Your own characters keep full tables: they're what you send.
local SUMMARY_CHAR = { "name", "surname", "class", "classFile", "level", "race", "raceFile", "faction", "guild", "guildRank" }
-- What guild sync hands us is someone else's data: keep only the right types, so one odd profile can't break the
-- pages that list everyone.
local function str(v, max) return type(v) == "string" and v:sub(1, max or 64) or nil end
local function n(v) return type(v) == "number" and v or nil end
local function list(v, max, fn)
  local out = {}
  if type(v) ~= "table" then return out end
  for _, x in ipairs(v) do
    local y = fn(x)
    if y ~= nil then out[#out + 1] = y end
    if #out >= max then break end
  end
  return out
end

function ns.summarize(p)
  local c, out = type(p.char) == "table" and p.char or {}, {}
  for _, k in ipairs(SUMMARY_CHAR) do out[k] = k == "level" and n(c[k]) or str(c[k]) end
  local spec = type(p.spec) == "table" and { n = str(p.spec.n), role = str(p.spec.role), class = str(p.spec.class) } or nil
  local items = {}
  for k, v in pairs(type(p.items) == "table" and p.items or {}) do
    if type(k) == "string" and n(v) then items[k] = v end
  end
  local profs = list(p.profs, 12, function(x)
    return type(x) == "table" and str(x.n) and { n = str(x.n), r = n(x.r), m = n(x.m), p = n(x.p) } or nil
  end)
  local summary = {
    v = n(p.v), addon = str(p.addon, 24), t = n(p.t), char = out, spec = spec, profs = profs, items = items,
    quests = list(p.quests, 200, n),
    alts = list(p.alts, 30, function(a) return type(a) == "table" and str(a.n) and { n = str(a.n), s = str(a.s), c = str(a.c), sp = str(a.sp), l = n(a.l) } or nil end),
    signups = list(p.signups, 30, function(x) return type(x) == "table" and n(x.e) and { e = n(x.e), s = str(x.s, 16), r = str(x.r, 16), t = n(x.t) } or nil end),
    summary = true,
  }
  local ok, il = pcall(ns.avgItemLevel, p) -- their gear list could be malformed too
  summary.il = ok and n(il) or nil
  return summary
end

-- The whole profile + recipes for a player, merged (the Character page). The last one unpacked is kept, so
-- redraws don't unpack it again.
local lastFull = {}
function ns.fullProfile(rec)
  if type(rec) ~= "table" then return nil end
  if not rec.pz then return ns.merge(rec.profile, rec.recipes) end
  if lastFull.pz ~= rec.pz or lastFull.rz ~= rec.rz then
    local p = ns.unpack(rec.pz, 600000)
    local r = rec.rz and ns.unpack(rec.rz, 600000)
    lastFull = { pz = rec.pz, rz = rec.rz, data = type(p) == "table" and ns.merge(p, type(r) == "table" and r.r or rec.recipes) or nil }
  end
  return lastFull.data
end

-- A player's recipes ({ [profession] = { list, t, r, m } }), unpacked if need be. Not kept: the Crafters page
-- builds its index from these and holds that instead.
function ns.recipesOf(rec)
  if type(rec) ~= "table" then return nil end
  if rec.recipes then return rec.recipes end
  local r = rec.rz and ns.unpack(rec.rz, 600000)
  return type(r) == "table" and type(r.r) == "table" and r.r or nil
end

-- Saved data from before 2.13 kept every guildmate's full tables; turn those into the compact form once.
function ns.compactPlayers()
  for _, g in pairs(PerpetuaDB.guilds or {}) do
    for _, rec in pairs(g.players or {}) do
      if type(rec) == "table" and not rec.self then
        local p = rec.profile
        if type(p) == "table" and not p.summary then
          local full = {}
          for k, v in pairs(p) do full[k] = v end
          full.t = full.t or rec.pt
          rec.pz = ns.pack(full)
          rec.profile = ns.summarize(full)
        end
        if type(rec.recipes) == "table" then
          rec.rz = ns.pack({ t = rec.rt, r = rec.recipes })
          rec.recipes = nil
        end
      end
    end
  end
end

-- ---------- recipes (profession windows) ----------

local function sameList(a, b)
  if not (a and b) or #a ~= #b then return false end
  for i = 1, #a do if a[i].id ~= b[i].id or a[i].n ~= b[i].n then return false end end
  return true
end

local function saveRecipes(name, list, rank, max)
  name = text(name)
  if not name or #list == 0 then return end
  PerpetuaCharDB.recipes = PerpetuaCharDB.recipes or {}
  local old = PerpetuaCharDB.recipes[name]
  -- Nothing new learned and the same skill: leave it (crafting fires these events after every craft). The time
  -- stamp still moves on once a day, so the site sees the list is current.
  if old and old.r == num(rank) and old.m == num(max) and sameList(old.list, list) and ns.now() - (old.t or 0) < 86400 then return end
  PerpetuaCharDB.recipes[name] = { list = list, t = ns.now(), r = num(rank), m = num(max) }
  if ns.onRecipesChanged then ns.onRecipesChanged() end
end

-- The output item of each recipe already read, so a rescan doesn't fetch every schematic again.
local function knownOutputs(name)
  local out = {}
  local old = PerpetuaCharDB.recipes and name and PerpetuaCharDB.recipes[name]
  for _, r in ipairs(old and old.list or {}) do if r.id then out[r.id] = r.it or false end end
  return out
end

function ns.scanTradeSkill()
  local T = C_TradeSkillUI
  if T and T.GetAllRecipeIDs then
    -- Only our own professions: not someone's linked profession, a guild list, or an NPC crafting window.
    if try(T.IsTradeSkillLinked) or try(T.IsTradeSkillGuild) or try(T.IsNPCCrafting) then return end
    local info = try(T.GetBaseProfessionInfo)
    local name, rank, max = info and info.professionName, info and info.skillLevel, info and info.maxSkillLevel
    if not text(name) and T.GetTradeSkillLine then
      local _
      _, name, rank, max = try(T.GetTradeSkillLine)
    end
    local list, known = {}, knownOutputs(text(name))
    for _, id in ipairs(try(T.GetAllRecipeIDs) or {}) do
      local r = try(T.GetRecipeInfo, id)
      if r and r.learned then
        local it = known[id]
        if it == nil then
          local schematic = try(T.GetRecipeSchematic, id, false)
          it = schematic and num(schematic.outputItemID) or itemIdFrom(text(try(T.GetRecipeItemLink, id))) or false
        end
        list[#list + 1] = { id = id, n = text(r.name), it = it or nil }
      end
    end
    return saveRecipes(name, list, rank, max)
  end
  if GetNumTradeSkills and GetTradeSkillLine then
    local name, rank, max = try(GetTradeSkillLine)
    local list = {}
    for i = 1, (try(GetNumTradeSkills) or 0) do
      local recipeName, kind = try(GetTradeSkillInfo, i)
      if recipeName and kind ~= "header" and kind ~= "subheader" then
        local link = text(try(GetTradeSkillRecipeLink, i))
        list[#list + 1] = { id = link and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)")), n = text(recipeName), it = itemIdFrom(text(try(GetTradeSkillItemLink, i))) }
      end
    end
    saveRecipes(name, list, rank, max)
  end
end

-- Classic's separate craft window (Enchanting).
function ns.scanCraft()
  if not (GetNumCrafts and GetCraftDisplaySkillLine) then return end
  local name, rank, max = try(GetCraftDisplaySkillLine)
  local list = {}
  for i = 1, (try(GetNumCrafts) or 0) do
    local recipeName, _, kind = try(GetCraftInfo, i)
    if recipeName and kind ~= "header" then
      local link = text(try(GetCraftItemLink, i))
      list[#list + 1] = { id = link and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)")), n = text(recipeName) }
    end
  end
  saveRecipes(name, list, rank, max)
end

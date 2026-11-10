-- Game data the addon and the site both read. Keep the attunement list in step with ATTUNEMENTS in
-- src/profile.html on the site.
local _, ns = ...

-- From Perpetua.toc's ## Version, so it can't fall behind (2.8.2-2.8.4 shipped saying "2.8.1", which hid every
-- update notice). The fallback is only for clients without the metadata API.
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata or function() end)("Perpetua", "Version") or "2.9.0"
ns.SITE = "perpetua.gg"
ns.GUILD = "Perpetua" -- the addon only works for characters in this guild (ns.locked)

-- Raids officers can schedule in game (Calendar tab), with their size. Same names and order as INSTANCES in the
-- site's worker/raids.js: Forever's raids first, then the classic ones Blizzard brings back later.
ns.RAIDS = {
  { "Barrow Deeps", 10 }, { "Hyjal Summit", 20 }, { "Onyxia's Lair", 40 },
  { "Molten Core", 40 }, { "Blackwing Lair", 40 }, { "Zul'Gurub", 20 }, { "Ruins of Ahn'Qiraj", 20 },
  { "Temple of Ahn'Qiraj", 40 }, { "Naxxramas", 40 }, { "Dungeon", 5 }, { "Other", 40 },
}

-- quests: any one completed counts; per faction where the two sides differ. items: holding one counts.
-- short: column heading in the Attunements tab.
ns.ATTUNEMENTS = {
  { group = "Raids", short = "Ony", name = "Onyxia's Lair", quests = { Alliance = { 6502 }, Horde = { 6602 } }, items = { 16309 }, how = "Drakefire Amulet" },
  { group = "Raids", short = "MC", name = "Molten Core", quests = { 7848 }, how = "Attunement to the Core" },
  { group = "Raids", short = "BWL", name = "Blackwing Lair", quests = { 7761 }, how = "Blackhand's Command" },
  { group = "Raids", short = "Naxx", name = "Naxxramas", quests = { 9121, 9122, 9123 }, how = "The Dread Citadel" },
  { group = "Keys", short = "UBRS", name = "Upper Blackrock Spire", quests = { 4743 }, items = { 12344 }, how = "Seal of Ascension" },
  { group = "Keys", short = "Scholo", name = "Scholomance", quests = { Alliance = { 5505 }, Horde = { 5511 } }, items = { 13704 }, how = "Skeleton Key" },
  { group = "Keys", short = "Strat", name = "Stratholme", items = { 12382 }, how = "Key to the City" },
  { group = "Keys", short = "BRD", name = "Blackrock Depths", items = { 11000 }, how = "Shadowforge Key" },
  { group = "Keys", short = "DM", name = "Dire Maul", items = { 18249 }, how = "Crescent Key" },
  { group = "Keys", short = "Runes", name = "Molten Core runes", items = { 17333, 22754 }, how = "Aqual or Eternal Quintessence" },
}

-- What the addon checks. Built from the list above plus the Prison Cell Key and the other dungeon keys the
-- site may show later.
ns.WATCH_QUESTS, ns.WATCH_ITEMS = {}, {}
do
  local seenQ, seenI = {}, {}
  for _, a in ipairs(ns.ATTUNEMENTS) do
    for k, v in pairs(a.quests or {}) do
      for _, q in ipairs(type(v) == "table" and v or { v }) do
        if not seenQ[q] then seenQ[q] = true; ns.WATCH_QUESTS[#ns.WATCH_QUESTS + 1] = q end
      end
    end
    for _, i in ipairs(a.items or {}) do
      if not seenI[i] then seenI[i] = true; ns.WATCH_ITEMS[#ns.WATCH_ITEMS + 1] = i end
    end
  end
  for _, i in ipairs({ 11140, 6893, 7146, 9240 }) do -- Prison Cell Key, Workshop Key, Scarlet Key, Mallet of Zul'Farrak
    if not seenI[i] then ns.WATCH_ITEMS[#ns.WATCH_ITEMS + 1] = i end
  end
end

-- Whether a profile shows this attunement done.
function ns.attuned(profile, a)
  if not profile then return false end
  local faction = profile.char and profile.char.faction
  local done = {}
  for _, q in ipairs(profile.quests or {}) do done[q] = true end
  local qs = a.quests or {}
  if qs[1] == nil then qs = qs[faction] or {} end
  for _, q in ipairs(qs) do if done[q] then return true end end
  for _, i in ipairs(a.items or {}) do
    if profile.items and ((profile.items[tostring(i)] or 0) > 0) then return true end
  end
  return false
end

ns.SLOTS = {
  { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 4, "Shirt" }, { 19, "Tabard" }, { 9, "Wrist" },
  { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Finger" }, { 12, "Finger" }, { 13, "Trinket" }, { 14, "Trinket" },
  { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" },
}

-- Factions raiders care about, shown in the Character tab.
ns.RAID_FACTIONS = { 749, 529, 270, 910, 609, 576, 59 }
ns.STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
ns.STANDING_COLOR = { "cc3333", "e0573f", "ee8a3f", "e8d65a", "7fd46a", "4fd49a", "3fd0c8", "5fd8ff" }
ns.ROLE = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

-- Classic's three talent trees per class, left to right as the talent frame lays them out. Forever reports one
-- "specialization" per class, named after the class, so the addon names the spec after the tree with the most
-- points instead (Collect.lua).
ns.TREES = {
  DRUID = { "Balance", "Feral Combat", "Restoration" }, HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
  MAGE = { "Arcane", "Fire", "Frost" }, PALADIN = { "Holy", "Protection", "Retribution" },
  PRIEST = { "Discipline", "Holy", "Shadow" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
  SHAMAN = { "Elemental", "Enhancement", "Restoration" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
  WARRIOR = { "Arms", "Fury", "Protection" },
}
local TREE_ROLE = { Protection = "TANK", Holy = "HEALER", Discipline = "HEALER", Restoration = "HEALER" }
function ns.treeRole(tree) return TREE_ROLE[tree] or "DAMAGER" end

-- The roles each class can fill in Classic (same as CLASS_ROLES on the site).
ns.CLASS_ROLES = {
  DRUID = { "Tank", "Healer", "DPS" }, HUNTER = { "DPS" }, MAGE = { "DPS" }, PALADIN = { "Tank", "Healer", "DPS" }, PRIEST = { "Healer", "DPS" },
  ROGUE = { "DPS" }, SHAMAN = { "Healer", "DPS" }, WARLOCK = { "DPS" }, WARRIOR = { "Tank", "DPS" },
}
function ns.classRoles(classFile)
  return ns.CLASS_ROLES[classFile or ""] or { "Tank", "Healer", "DPS" }
end
function ns.canTake(classFile, role)
  for _, r in ipairs(ns.classRoles(classFile)) do if r == role then return true end end
  return false
end

-- Gathering professions have no recipe window.
ns.NO_RECIPES = { Herbalism = true, Skinning = true, Fishing = true, Archaeology = true, Mining = true }

ns.QUALITY = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff", "00ccff" }

-- Class colours for text. Official Shaman blue and Warlock purple are too dark to read on navy, so text uses the
-- site's lighter ones (perpetua.js TEXT_COLOR); ns.classRGB gives the real colour for bars and edges.
local TEXT_COLOR = { SHAMAN = "4aa3ff", WARLOCK = "a3a4ff" }
function ns.classColor(classFile)
  if classFile and TEXT_COLOR[classFile] then return TEXT_COLOR[classFile] end
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if not c then return "ffd100" end
  if c.colorStr then return c.colorStr:sub(-6) end
  return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

function ns.classRGB(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if not c then return { 0.831, 0.686, 0.216 } end
  return { c.r, c.g, c.b }
end

-- Average item level of equipped gear (shirt and tabard left out).
function ns.avgItemLevel(profile)
  if profile and profile.il then return profile.il end -- a guildmate's summary carries it
  local total, n = 0, 0
  for _, g in ipairs(profile and profile.gear or {}) do
    if g.il and g.s ~= 4 and g.s ~= 19 then total = total + g.il; n = n + 1 end
  end
  return n > 0 and math.floor(total / n + 0.5) or nil
end

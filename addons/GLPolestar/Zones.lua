-- GLPolestar - zone names as Guidelime guides write them -> uiMapID.
-- Guidelime guides name zones in English ("[G 42.1,65.9 Elwynn Forest]"). The
-- table covers the classic zones; anything else is looked up by name in the
-- client's own map list (so new zones work on an English client).
local _, ns = ...

local Z = {}
ns.Zones = Z

local MAPS = {
  ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Kalimdor"] = 1414,
  ["Eastern Kingdoms"] = 1415, ["Alterac Mountains"] = 1416, ["Arathi Highlands"] = 1417,
  ["Badlands"] = 1418, ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420,
  ["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423,
  ["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426,
  ["Searing Gorge"] = 1427, ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429,
  ["Deadwind Pass"] = 1430, ["Duskwood"] = 1431, ["Loch Modan"] = 1432,
  ["Redridge Mountains"] = 1433, ["Stranglethorn Vale"] = 1434, ["Swamp of Sorrows"] = 1435,
  ["Westfall"] = 1436, ["Wetlands"] = 1437, ["Teldrassil"] = 1438, ["Darkshore"] = 1439,
  ["Ashenvale"] = 1440, ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442,
  ["Desolace"] = 1443, ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446,
  ["Azshara"] = 1447, ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450,
  ["Silithus"] = 1451, ["Winterspring"] = 1452, ["Stormwind City"] = 1453,
  ["Orgrimmar"] = 1454, ["Ironforge"] = 1455, ["Thunder Bluff"] = 1456,
  ["Darnassus"] = 1457, ["Undercity"] = 1458, ["Alterac Valley"] = 1459,
  ["Warsong Gulch"] = 1460, ["Arathi Basin"] = 1461,
}

-- Other spellings seen in guides.
local ALIASES = {
  ["Stormwind"] = "Stormwind City", ["Barrens"] = "The Barrens", ["Hinterlands"] = "The Hinterlands",
  ["Stranglethorn"] = "Stranglethorn Vale", ["Ungoro Crater"] = "Un'Goro Crater",
  ["Un'Goro"] = "Un'Goro Crater", ["Ungoro"] = "Un'Goro Crater", ["Hillsbrad"] = "Hillsbrad Foothills",
  ["Redridge"] = "Redridge Mountains", ["Stonetalon"] = "Stonetalon Mountains",
  ["Dustwallow"] = "Dustwallow Marsh", ["Arathi"] = "Arathi Highlands", ["Alterac"] = "Alterac Mountains",
  ["Tirisfal"] = "Tirisfal Glades", ["Silverpine"] = "Silverpine Forest", ["Elwynn"] = "Elwynn Forest",
  ["Needles"] = "Thousand Needles", ["Swamp of Sorrow"] = "Swamp of Sorrows",
  ["WPL"] = "Western Plaguelands", ["EPL"] = "Eastern Plaguelands", ["STV"] = "Stranglethorn Vale",
}

local function key(name)
  return (name:lower():gsub("[%s'%-]", ""))
end

local byKey = {}
for name, id in pairs(MAPS) do byKey[key(name)] = id end
for alias, name in pairs(ALIASES) do byKey[key(alias)] = MAPS[name] end

local scanned = false
-- The client's own zone list (Azeroth's descendants), by name in the client's language.
local function scan()
  scanned = true
  if not (C_Map and C_Map.GetMapChildrenInfo) then return end
  for _, root in ipairs({ 947, 1414, 1415 }) do
    local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
    if ok and type(list) == "table" then
      for _, info in ipairs(list) do
        if info.name and info.mapID then
          local k = key(info.name)
          if byKey[k] == nil then byKey[k] = info.mapID end
        end
      end
    end
  end
end

-- "Elwynn Forest" -> 1429, or nil.
function Z.MapID(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil end
  local id = byKey[key(name)]
  if id == nil and not scanned then
    scan()
    id = byKey[key(name)]
  end
  return id
end

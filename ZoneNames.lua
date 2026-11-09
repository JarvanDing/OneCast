-- OneCast zone names in the player's language. The zone tables (ZoneLevels.lua, FishData.lua)
-- are written with English names, and what the game reports as your zone, and what's saved
-- from it, is in the client's language. So on other clients this swaps every English name for
-- the game's own, by area ID, and everything else simply compares names as usual.
--
-- Area IDs are from Forever's AreaTable on wago.tools (build 1.60.1.70862): the top-level area
-- of that name on Eastern Kingdoms or Kalimdor. A zone added to those tables needs an ID here.

local _, ns = ...

ns.ZONE_AREA_IDS = {
	["Alterac Mountains"] = 36,
	["Arathi Highlands"] = 45,
	["Ashenvale"] = 331,
	["Azshara"] = 16,
	["Badlands"] = 3,
	["Blasted Lands"] = 4,
	["Burning Steppes"] = 46,
	["Darkshore"] = 148,
	["Darnassus"] = 1657,
	["Deadwind Pass"] = 41,
	["Desolace"] = 405,
	["Dun Morogh"] = 1,
	["Durotar"] = 14,
	["Duskwood"] = 10,
	["Dustwallow Marsh"] = 15,
	["Eastern Plaguelands"] = 139,
	["Elwynn Forest"] = 12,
	["Felwood"] = 361,
	["Feralas"] = 357,
	["Gilneas"] = 17065,
	["Hillsbrad Foothills"] = 267,
	["Ironforge"] = 1537,
	["Loch Modan"] = 38,
	["Moonglade"] = 493,
	["Mount Hyjal"] = 616,
	["Mulgore"] = 215,
	["Orgrimmar"] = 1637,
	["Redridge Mountains"] = 44,
	["Riverglades"] = 16591,
	["Searing Gorge"] = 51,
	["Shen'dralas"] = 16651,
	["Silithus"] = 1377,
	["Silverpine Forest"] = 130,
	["Stonetalon Mountains"] = 406,
	["Stormwind City"] = 1519,
	["Stranglethorn Vale"] = 33,
	["Swamp of Sorrows"] = 8,
	["Tanaris"] = 440,
	["Teldrassil"] = 141,
	["The Barrens"] = 17,
	["The Hinterlands"] = 47,
	["Thousand Needles"] = 400,
	["Thunder Bluff"] = 1638,
	["Tirisfal Glades"] = 85,
	["Un'Goro Crater"] = 490,
	["Undercity"] = 1497,
	["Western Plaguelands"] = 28,
	["Westfall"] = 40,
	["Wetlands"] = 11,
	["Winterspring"] = 618,
}

local locale = GetLocale()
if locale == "enUS" or locale == "enGB" then
	return
end

-- The game's name for it, or the English one if the game doesn't know the area.
local function Translate(zone)
	local areaID = ns.ZONE_AREA_IDS[zone]
	local name = areaID and C_Map.GetAreaInfo(areaID)
	if name and name ~= "" then
		return name
	end
	return zone
end

local function TranslateKeys(map)
	local translated = {}
	for zone, value in pairs(map) do
		translated[Translate(zone)] = value
	end
	return translated
end

ns.ZONE_FISHING_SKILL = TranslateKeys(ns.ZONE_FISHING_SKILL)
ns.ZONE_FISHING_NOTE = TranslateKeys(ns.ZONE_FISHING_NOTE)
for i, zone in ipairs(ns.ZONE_FISHING_UNKNOWN) do
	ns.ZONE_FISHING_UNKNOWN[i] = Translate(zone)
end
for _, fish in ipairs(ns.FISH) do
	for i, zone in ipairs(fish.zones or {}) do
		fish.zones[i] = Translate(zone)
	end
	for _, extra in ipairs(fish.more or {}) do
		extra[1] = Translate(extra[1])
	end
end
ns.Extravaganza.ZONE = Translate(ns.Extravaganza.ZONE)

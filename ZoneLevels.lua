-- Fishing skill needed in each zone so that no fish get away, from Classic Era data
-- (zone fishing level + 95). Lure and pole bonuses count towards it. Zone skill is set
-- by the server, not the game data, and no source has published Forever's own numbers as
-- of launch (4 November 2026), so these stay Classic's until someone measures them. The
-- stats window also counts real getaways per zone, with the skill they happened at: they judge
-- zones missing from this table, overrule ZONE_FISHING_NOTE, and overrule this table too when
-- a fish gets away at or above your current skill.
-- Keyed by English zone name; ZoneNames.lua swaps them for the client's own at load.
-- ZONE_LABEL / ZONE_ALIAS keep Chinese display names and map GetRealZoneText() back for lookups.

local _, ns = ...

local LEVELS = {
	[25] = {
		"Dun Morogh", "Durotar", "Elwynn Forest", "Mulgore", "Teldrassil", "Tirisfal Glades",
		"Stormwind City", "Orgrimmar", "Ironforge", "Thunder Bluff", "Undercity", "Darnassus",
	},
	[75] = {
		"The Barrens", "Darkshore", "Loch Modan", "Silverpine Forest", "Westfall",
	},
	[150] = {
		"Ashenvale", "Duskwood", "Hillsbrad Foothills", "Redridge Mountains",
		"Stonetalon Mountains", "Wetlands",
	},
	[225] = {
		"Alterac Mountains", "Arathi Highlands", "Badlands", "Desolace", "Dustwallow Marsh",
		"Stranglethorn Vale", "Swamp of Sorrows", "Thousand Needles",
	},
	[300] = {
		"Azshara", "Blasted Lands", "Burning Steppes", "Deadwind Pass", "Eastern Plaguelands",
		"Felwood", "Feralas", "Moonglade", "Searing Gorge", "Silithus", "Tanaris",
		"The Hinterlands", "Un'Goro Crater", "Western Plaguelands", "Winterspring",
	},
}

-- English (data key) → Chinese display name.
ns.ZONE_LABEL = {
	["Dun Morogh"] = "丹莫罗",
	["Durotar"] = "杜隆塔尔",
	["Elwynn Forest"] = "艾尔文森林",
	["Mulgore"] = "莫高雷",
	["Teldrassil"] = "泰达希尔",
	["Tirisfal Glades"] = "提瑞斯法林地",
	["Stormwind City"] = "暴风城",
	["Orgrimmar"] = "奥格瑞玛",
	["Ironforge"] = "铁炉堡",
	["Thunder Bluff"] = "雷霆崖",
	["Undercity"] = "幽暗城",
	["Darnassus"] = "达纳苏斯",
	["The Barrens"] = "贫瘠之地",
	["Darkshore"] = "黑海岸",
	["Loch Modan"] = "洛克莫丹",
	["Silverpine Forest"] = "银松森林",
	["Westfall"] = "西部荒野",
	["Ashenvale"] = "灰谷",
	["Duskwood"] = "暮色森林",
	["Hillsbrad Foothills"] = "希尔斯布莱德丘陵",
	["Redridge Mountains"] = "赤脊山",
	["Stonetalon Mountains"] = "石爪山脉",
	["Wetlands"] = "湿地",
	["Alterac Mountains"] = "奥特兰克山脉",
	["Arathi Highlands"] = "阿拉希高地",
	["Badlands"] = "荒芜之地",
	["Desolace"] = "凄凉之地",
	["Dustwallow Marsh"] = "尘泥沼泽",
	["Stranglethorn Vale"] = "荆棘谷",
	["Swamp of Sorrows"] = "悲伤沼泽",
	["Thousand Needles"] = "千针石林",
	["Azshara"] = "艾萨拉",
	["Blasted Lands"] = "诅咒之地",
	["Burning Steppes"] = "燃烧平原",
	["Deadwind Pass"] = "逆风小径",
	["Eastern Plaguelands"] = "东瘟疫之地",
	["Felwood"] = "费伍德森林",
	["Feralas"] = "菲拉斯",
	["Moonglade"] = "月光林地",
	["Searing Gorge"] = "灼热峡谷",
	["Silithus"] = "希利苏斯",
	["Tanaris"] = "塔纳利斯",
	["The Hinterlands"] = "辛特兰",
	["Un'Goro Crater"] = "安戈洛环形山",
	["Western Plaguelands"] = "西瘟疫之地",
	["Winterspring"] = "冬泉谷",
	-- Forever zones (no Classic level yet).
	["Riverglades"] = "河湾泽地",
	["Shen'dralas"] = "辛德拉拉斯",
	["Mount Hyjal"] = "海加尔山",
	["Gilneas"] = "吉尔尼斯",
}

-- Chinese (and any alias) → English data key.
ns.ZONE_ALIAS = {}
for en, zh in pairs(ns.ZONE_LABEL) do
	ns.ZONE_ALIAS[zh] = en
end

function ns.ZoneCanon(zone)
	if not zone or zone == "" then
		return zone
	end
	return ns.ZONE_ALIAS[zone] or zone
end

function ns.ZoneLabel(zone)
	if not zone or zone == "" then
		return zone
	end
	local canon = ns.ZoneCanon(zone)
	return ns.ZONE_LABEL[canon] or zone
end

function ns.SameZone(a, b)
	if not a or not b then
		return a == b
	end
	return a == b or ns.ZoneCanon(a) == ns.ZoneCanon(b)
end

ns.ZONE_FISHING_SKILL = {}
for skill, zones in pairs(LEVELS) do
	for _, zone in ipairs(zones) do
		ns.ZONE_FISHING_SKILL[zone] = skill
	end
end

function ns.ZoneSkill(zone)
	if not zone then
		return nil
	end
	return ns.ZONE_FISHING_SKILL[zone] or ns.ZONE_FISHING_SKILL[ns.ZoneCanon(zone)]
end

-- Zones new in Forever (Riverglades, Shen'dralas, Mount Hyjal, Gilneas) have no Classic
-- level and no published Forever one, so they're left out above: the stats window judges
-- them from your own catches and getaways. The book's Zones view lists them all the same.
ns.ZONE_FISHING_UNKNOWN = { "Riverglades", "Shen'dralas", "Mount Hyjal", "Gilneas" }

-- Notes shown instead of a level, until a getaway in that zone proves them wrong.
ns.ZONE_FISHING_NOTE = {
	-- Forever bug report (ClassicWoWCommunity/forever-bugs#189, Sept 2026, still open at
	-- launch): skill 1 catches every time here, though its fish are 225+ tier. Blizzard
	-- may add a minimum at any time.
	["Riverglades"] = "据报无最低技能要求（已知漏洞，可能已修复）",
}

function ns.ZoneNote(zone)
	if not zone then
		return nil
	end
	return ns.ZONE_FISHING_NOTE[zone] or ns.ZONE_FISHING_NOTE[ns.ZoneCanon(zone)]
end

-- Fishing skill needed in each zone so that no fish get away: the zone's fishing level + 95.
-- Lure and pole bonuses count towards it. Zone skill is set by the server, not the game data,
-- and no source has published Forever's own numbers yet (10 November 2026), so these are
-- Classic's, from CMaNGOS's Classic 1.12 world database (skill_fishing_base_level), which
-- AzerothCore's matches for every Classic zone. Badlands, Blasted Lands and Searing Gorge have
-- no level there: they have no water to fish. The stats window also counts real getaways per
-- zone, with the skill they happened at: they judge zones missing from this table, overrule
-- ZONE_FISHING_NOTE, and overrule this table too when a fish gets away at or above your
-- current skill.
-- Keyed by English zone name; ZoneNames.lua swaps them for the client's own at load.
-- ZONE_LABEL / ZONE_ALIAS keep Chinese display names and map GetRealZoneText() back for lookups.

local _, ns = ...

local LEVELS = {
	[25] = {
		"Dun Morogh", "Durotar", "Elwynn Forest", "Mulgore", "Teldrassil", "Tirisfal Glades",
	},
	[75] = {
		"The Barrens", "Darkshore", "Loch Modan", "Silverpine Forest", "Westfall",
		-- Orgrimmar's 75 is confirmed in Forever by a player's report (10 November 2026): 3 got away at
		-- skill 50-74, none in 178 catches from 75 up.
		"Stormwind City", "Orgrimmar", "Ironforge", "Thunder Bluff", "Undercity", "Darnassus",
		"The Deadmines", "Wailing Caverns", "Blackfathom Deeps",
	},
	[150] = {
		"Ashenvale", "Duskwood", "Hillsbrad Foothills", "Redridge Mountains",
		"Stonetalon Mountains", "Wetlands",
	},
	[225] = {
		"Alterac Mountains", "Arathi Highlands", "Desolace", "Dustwallow Marsh",
		"Stranglethorn Vale", "Swamp of Sorrows", "Thousand Needles", "Scarlet Monastery",
		-- Forever's own, from a player's /onecast report (10 November 2026), fishing Eastwind
		-- Shore: 3 got away at skill 150-174, none in 17 catches at 225-249. Its coast gives the
		-- same catches as Classic's 225 zones (Rockscale Cod, Spotted Yellowtail, Sturdy Locked
		-- Chest). Not a Classic number: a getaway above 225 would overrule it, as for any zone.
		"Riverglades",
	},
	[300] = {
		"Azshara", "Felwood", "Feralas", "Moonglade", "Tanaris", "The Hinterlands",
		"Un'Goro Crater", "Western Plaguelands", "Sunken Temple", "Maraudon",
	},
	[425] = {
		"Burning Steppes", "Deadwind Pass", "Eastern Plaguelands", "Silithus", "Winterspring",
		"Zul'Gurub", "Stratholme", "Scholomance",
	},
}

-- Dungeons by instance map ID (GetInstanceInfo), with the name used in the tables above. The
-- game's own name for a dungeon can differ from its area's: Forever calls Wailing Caverns "The
-- Wailing Caverns". So inside one, OneCast files everything under this name instead.
ns.INSTANCE_ZONES = {
	[36] = "The Deadmines",
	[43] = "Wailing Caverns",
	[48] = "Blackfathom Deeps",
	[189] = "Scarlet Monastery",
	[109] = "Sunken Temple",
	[349] = "Maraudon",
	[309] = "Zul'Gurub",
	[329] = "Stratholme",
	[289] = "Scholomance",
}

-- Names the game has been seen to use for those dungeons, moved under the tables' name.
ns.INSTANCE_ALIASES = {
	["The Wailing Caverns"] = "Wailing Caverns",
}

-- Waters inside a zone with a level of their own, keyed by the sub-zone's name (what
-- GetSubZoneText says while you stand there). Same source as above.
ns.SPOT_FISHING_SKILL = {
	["Jaguero Isle"] = 300,      -- Stranglethorn Vale
	["Jademir Lake"] = 425,      -- Feralas
	["Bay of Storms"] = 425,     -- Azshara
	["Hetaera's Clutch"] = 425,  -- Azshara
	["Scalebeard's Cave"] = 425, -- Azshara
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
	["Zephras Isle"] = "泽弗拉斯岛",
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

-- Zones new in Forever with no level yet (Shen'dralas, Mount Hyjal, Gilneas, Zephras Isle): the
-- stats window judges them from your own catches and getaways. The book's Zones view lists them
-- all the same. Riverglades was here until a player's report measured it (see 225 above).
ns.ZONE_FISHING_UNKNOWN = { "Shen'dralas", "Mount Hyjal", "Gilneas", "Zephras Isle" }

-- Notes shown instead of a level, until a getaway in that zone proves them wrong:
-- { [zone] = "text" }. Riverglades' "no minimum skill" (forever-bugs#189) was dropped when a
-- player's report showed fish getting away there below 175.
ns.ZONE_FISHING_NOTE = {}

function ns.ZoneNote(zone)
	if not zone then
		return nil
	end
	return ns.ZONE_FISHING_NOTE[zone] or ns.ZONE_FISHING_NOTE[ns.ZoneCanon(zone)]
end

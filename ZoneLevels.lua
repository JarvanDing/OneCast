-- Fishing skill needed in each zone so that no fish get away, from Classic Era data
-- (zone fishing level + 95). Lure and pole bonuses count towards it. Zone skill is set
-- by the server, not the game data, and no source has published Forever's own numbers as
-- of launch (4 November 2026), so these stay Classic's until someone measures them. The
-- stats window also counts real getaways per zone, with the skill they happened at: they judge
-- zones missing from this table, overrule ZONE_FISHING_NOTE, and overrule this table too when
-- a fish gets away at or above your current skill.
-- Keyed by English zone name (GetRealZoneText); other client languages show "unknown".

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

ns.ZONE_FISHING_SKILL = {}
for skill, zones in pairs(LEVELS) do
	for _, zone in ipairs(zones) do
		ns.ZONE_FISHING_SKILL[zone] = skill
	end
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

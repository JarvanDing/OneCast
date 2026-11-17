-- OneCast's Fisherman's Journey. Ranks: the four Fishing ranks, where you stand,
-- and what's next: each rank's cap, whether you have it, how and where to learn it (with a
-- waypoint), what it needs, and where to fish while you're at it. Gear: every fishing pole and
-- piece of fishing gear, its bonus and where it comes from.
--
-- From Forever's game data (wago.tools, 13 November 2026): the ranks are Classic's
-- (Apprentice 75, Journeyman 150, Expert 225, Artisan 300); Expert is learned from "Expert
-- Fishing - The Bass and You" (level 20, Fishing 125, 1 gold), sold in Stranglethorn Vale by Old
-- Man Heming <Fisherman> (Wowhead's Forever data); Artisan is Nat Pagle's quest "Nat Pagle,
-- Angler Extreme" in Dustwallow Marsh, for one each of four special fish. What Forever's data
-- doesn't hold (trainers and quests are the server's) is Classic's, from CMaNGOS's world
-- database: trainers teach Apprentice at level 5 for 1 silver and Journeyman at Fishing 50 for
-- 5 silver, with no level; Nat's quest needs level 35 and Fishing 225. The waypoints are
-- Classic's spots for Heming and Nat.

local _, ns = ...

local Journey = {}
ns.Journey = Journey

local WIDTH = 660
local EDGE, GAP = 10, 8
local CARD_HEIGHT = 98
local GOOD, GREY, GOLD = "|cff20ff20", "|cff9d9d9d", "|cffffd100"
local GearCard, PaintGearCard, GearBest, PaintGearBest -- the Gear view's cards, below

-- Nat Pagle's four fish, for Artisan.
local NAT_FISH = { 16970, 16968, 16967, 16969 }

Journey.RANKS = {
	{ key = "apprentice", name = "学徒", cap = 75, from = 1, icon = "Interface\\Icons\\Trade_Fishing",
		how = "任意钓鱼训练师教授，1 银；各大主城及许多城镇均有。",
		needs = { level = 5 }, fishFrom = 1, fishTo = 74 },
	{ key = "journeyman", name = "熟练", cap = 150, from = 75, icon = "Interface\\Icons\\Trade_Fishing",
		how = "钓鱼达到 50 后，任意钓鱼训练师教授，5 银。",
		needs = { skill = 50 }, fishFrom = 75, fishTo = 149 },
	{ key = "expert", name = "专家", cap = 225, from = 150, item = 16083, icon = "Interface\\Icons\\INV_Misc_Book_09",
		how = "阅读《中级钓鱼教材 - 鲈鱼与你》：荆棘谷藏宝海湾老人海明处购买，1 金。",
		needs = { level = 20, skill = 125 }, fishFrom = 150, fishTo = 224,
		where = { zone = "Stranglethorn Vale", x = 0.276, y = 0.774, label = "老人海明，藏宝海湾" } },
	{ key = "artisan", name = "工匠", cap = 300, from = 225, icon = "Interface\\Icons\\INV_Misc_Fish_14",
		how = "纳特·帕格任务「纳特·帕格，钓鱼大师」：尘泥沼泽小岛，向他交出下列四种鱼各一条。",
		needs = { level = 35, skill = 225 }, fishFrom = 225, fishTo = 425, natFish = true,
		where = { zone = "Dustwallow Marsh", x = 0.586, y = 0.602, label = "纳特·帕格，尘泥沼泽" } },
}

-- A zone's name in the client's language.
local function LocalZone(english)
	local id = ns.ZONE_AREA_IDS and ns.ZONE_AREA_IDS[english]
	local name = id and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
	return (name and name ~= "") and name or english
end

-- Your rank: the index into RANKS for your cap, 0 before you've learned Fishing.
function Journey.Current()
	if not ns.Stats then
		return 0, nil, nil
	end
	local rank, maxRank = ns.Stats.FishingSkill()
	if not (rank and maxRank) then
		return 0, rank, maxRank
	end
	local index = 0
	for i, r in ipairs(Journey.RANKS) do
		if maxRank >= r.cap then
			index = i
		end
	end
	return index, rank, maxRank
end

-- Where to fish at a rank: zones whose level falls in its range, easiest first.
local function ZonesFor(r)
	local list = {}
	for zone, needed in pairs(ns.ZONE_FISHING_SKILL or {}) do
		if needed >= r.fishFrom and needed <= r.fishTo then
			list[#list + 1] = { zone = zone, needed = needed }
		end
	end
	table.sort(list, function(a, b)
		if a.needed ~= b.needed then
			return a.needed < b.needed
		end
		return a.zone < b.zone
	end)
	return list
end

local function ZoneText(r, most)
	local list = ZonesFor(r)
	local names = {}
	for i, z in ipairs(list) do
		if i > (most or 4) then
			names[#names + 1] = string.format("另有 %d 个", #list - (most or 4))
			break
		end
		names[#names + 1] = z.zone .. " " .. GREY .. z.needed .. "|r"
	end
	return #names > 0 and table.concat(names, ", ") or (GREY .. "暂无收录|r")
end

-- The zones on one line: as many as fit it (four at most), then "and N more". Long names
-- (Stranglethorn Vale, Dustwallow Marsh) would otherwise run off the end of the card.
local function SetZones(fs, r)
	for most = 4, 1, -1 do
		fs:SetText(GOLD .. "适合钓点：|r " .. ZoneText(r, most))
		local room = fs:GetWidth() or 0
		local wide = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or 0
		if room <= 0 or wide <= room then
			return
		end
	end
end

-- What a rank needs that you don't have yet, as text, or nil when you're ready.
local function Missing(r, rank)
	local parts = {}
	local level = UnitLevel("player") or 0
	if r.needs.level and level < r.needs.level then
		parts[#parts + 1] = string.format("等级 %d（你 %d 级）", r.needs.level, level)
	end
	if r.needs.skill and (rank or 0) < r.needs.skill then
		parts[#parts + 1] = string.format("钓鱼 %d（你 %d）", r.needs.skill, rank or 0)
	end
	return #parts > 0 and table.concat(parts, " and ") or nil
end

local function NeedsText(r)
	local parts = {}
	if r.needs.level then
		parts[#parts + 1] = "等级 " .. r.needs.level
	end
	if r.needs.skill then
		parts[#parts + 1] = "钓鱼 " .. r.needs.skill
	end
	return #parts > 0 and table.concat(parts, "，") or "无"
end

local function Card(parent, r, y)
	local c = CreateFrame("Frame", nil, parent)
	c:SetPoint("TOPLEFT", EDGE, y)
	c:SetPoint("TOPRIGHT", -EDGE, y)
	c:SetHeight(CARD_HEIGHT - 6)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	c.bg:SetColorTexture(1, 1, 1, 0.04)
	c.edge = c:CreateTexture(nil, "BORDER")
	c.edge:SetPoint("TOPLEFT")
	c.edge:SetPoint("BOTTOMLEFT")
	c.edge:SetWidth(3)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(40, 40)
	c.icon:SetPoint("TOPLEFT", 12, -8)
	c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	c.icon:SetTexture(r.item and C_Item.GetItemIconByID(r.item) or r.icon)
	c.check = c:CreateTexture(nil, "OVERLAY")
	c.check:SetSize(18, 18)
	c.check:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 4, -4)
	if ns.UI.HasAtlas("UI-LFG-ReadyMark") then
		c.check:SetAtlas("UI-LFG-ReadyMark")
	else
		c.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	end
	c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 12, 0)
	c.status = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	c.status:SetPoint("TOPRIGHT", -12, -10)
	c.status:SetJustifyH("RIGHT")
	c.how = c:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	c.how:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -6)
	c.how:SetPoint("RIGHT", -130, 0)
	c.how:SetJustifyH("LEFT")
	c.how:SetWordWrap(true)
	c.zones = c:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	c.zones:SetPoint("TOPLEFT", c.how, "BOTTOMLEFT", 0, -4)
	c.zones:SetPoint("RIGHT", -12, 0)
	c.zones:SetJustifyH("LEFT")
	c.zones:SetWordWrap(false)
	c.extra = c:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	c.extra:SetPoint("TOPLEFT", c.zones, "BOTTOMLEFT", 0, -4)
	c.extra:SetPoint("RIGHT", -12, 0)
	c.extra:SetJustifyH("LEFT")
	c.extra:SetWordWrap(false)
	if r.where then
		c.map = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
		c.map:SetSize(112, 22)
		c.map:SetPoint("TOPRIGHT", c.status, "BOTTOMRIGHT", 2, -6)
		c.map:SetText("地图显示")
		c.map:SetScript("OnClick", function()
			local zone = LocalZone(r.where.zone)
			local mapID = ns.Book and ns.Book.ZoneMapID and ns.Book.ZoneMapID(zone)
			ns.UI.ShowOnMap(mapID, r.where.x, r.where.y, r.where.label)
		end)
		c.map:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(r.where.label)
			GameTooltip:AddLine("在地图上打开此处并设置路径点。坐标来自经典版，Forever 可能略有出入。", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		c.map:SetScript("OnLeave", GameTooltip_Hide)
	end
	-- Expert's book, and Nat's fish: hover for the item.
	c:EnableMouse(true)
	c:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if r.item then
			GameTooltip:SetItemByID(r.item)
			GameTooltip:AddLine(" ")
		else
			GameTooltip:SetText(r.name .. " 钓鱼")
		end
		-- Every zone to fish at this rank, with the Fishing each needs.
		GameTooltip:AddLine("适合钓点", 1, 0.82, 0)
		for _, z in ipairs(ZonesFor(r)) do
			GameTooltip:AddDoubleLine(z.zone, tostring(z.needed), 1, 1, 1, 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", GameTooltip_Hide)
	c.rank = r
	return c
end

local function Paint(c, index, current, rank)
	local r = c.rank
	local learned = index <= current
	local nextUp = index == current + 1
	c.title:SetText(r.name .. "  " .. GREY .. "钓鱼上限 " .. r.cap .. "|r")
	c.check:SetShown(learned)
	c.icon:SetDesaturated(not learned and not nextUp)
	local color
	if learned then
		c.status:SetText(GOOD .. "已学|r")
		color = { 0.12, 1, 0 }
	elseif nextUp then
		local missing = Missing(r, rank)
		c.status:SetText(missing and (GOLD .. "下一级：还需 " .. missing .. "|r") or (GOOD .. "下一级：可以学习！|r"))
		color = { 1, 0.82, 0 }
	else
		c.status:SetText(GREY .. "尚未|r")
		color = { 0.5, 0.5, 0.5 }
	end
	c.edge:SetColorTexture(color[1], color[2], color[3], 0.9)
	c.bg:SetColorTexture(color[1], color[2], color[3], nextUp and 0.1 or 0.04)
	c.how:SetText((learned and GREY or "|cffffffff") .. r.how .. "|r")
	SetZones(c.zones, r)
	if r.natFish then
		local parts = {}
		for _, id in ipairs(NAT_FISH) do
			local fish = ns.FISH_BY_ID and ns.FISH_BY_ID[id]
			local caught = ns.Collection and ns.Collection.Get(id).total > 0
			local icon = C_Item.GetItemIconByID(id)
			parts[#parts + 1] = (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "")
				.. (caught and GOOD or GREY) .. (C_Item.GetItemNameByID(id) or (fish and fish.name) or "?") .. "|r"
		end
		c.extra:SetText(GOLD .. "纳特的鱼：|r " .. table.concat(parts, "  "))
	else
		c.extra:SetText(GOLD .. "需求：|r " .. NeedsText(r))
	end
end

-- Fishing gear: poles first, then what you wear. `from` is where it comes from: Forever's own
-- where Wowhead's Forever data has it (marked forever), else Classic's from CMaNGOS's world
-- database (vendors, quest rewards and loot). The bonus is read from the game's own tooltip, so
-- it's Forever's.
Journey.GEAR = {
	{ id = 6256, short = "各地钓鱼商人", kind = "Pole", from = "艾泽拉斯各地钓鱼商人出售。", forever = true },
	{ id = 6365, short = "钓鱼商人，藏宝海湾", kind = "Pole", from = "部分钓鱼商人出售，含藏宝海湾老人海明。", forever = true },
	{ id = 12225, short = "联盟任务，黑海岸", faction = "Alliance", kind = "Pole", from = "联盟黑海岸任务「家族与鱼竿」奖励（10 级）。",
		where = { map = 1439, x = 0.360, y = 0.448, label = "Gubber Blump, Auberdine" }, source = { "quest", 1141, "The Family and the Fishing Pole" } },
	{ id = 6367, short = "贝壳陷阱", kind = "Pole", from = "偶尔可在水下贝壳陷阱中开出。" },
	{ id = 19022, short = "部落任务，辛特兰", faction = "Horde", kind = "Pole", from = "部落辛特兰任务「答录机，伙计！」奖励（44 级）。",
		where = { map = 1425, x = 0.802, y = 0.814, label = "Katoom the Angler, Revantusk Village" }, source = { "quest", 7815, "Snapjaws, Mon!" } },
	{ id = 19970, short = "钓鱼大赛：前 50 名", kind = "Pole", from = "荆棘谷钓鱼大赛奖品：本规则集前 50 名各向林格·巴斯贝特交 40 条斑点可口鱼，可得此竿、盛典币与一周「钓鱼大师！」头衔。",
		where = { map = 1434, x = 0.274, y = 0.768, label = "Riggle Bassbait, Booty Bay" }, source = { "quest", 8193, "Master Angler" } },
	{ id = 285094, short = "钓鱼领主，尘泥沼泽", kind = "Pole", from = "Forever 新增：尘泥海湾沉船旁稀有 44 级「钓鱼领主」掉落（约四分之一几率）。", forever = true,
		where = { map = 1445, x = 0.560, y = 0.618, label = "Lord Angler (rare), Dustwallow Marsh" }, source = { "npc", 14236, "Lord Angler" } },
	{ id = 276203, short = "商人，河林", kind = "Pole", from = "Forever 新增：河林地区商人出售。", forever = true, ifBonus = true },
	{ id = 276272, short = "大赛币，摊主 Jang", kind = "Head", from = "Forever 新增：藏宝海湾 Jang 用钓鱼大赛优胜者的盛典硬币兑换。", forever = true,
		where = { map = 1434, x = 0.274, y = 0.768, label = "Jang, Booty Bay" }, source = { "npc", 15078, "Jang" } },
	{ id = 259846, short = "来源尚不明", kind = "Head", from = "Forever 新增：获取途径尚未确认。", forever = true, ifBonus = true },
	{ id = 244229, short = "来源尚不明", kind = "Shoulder", from = "Forever 新增：获取途径尚未确认。", forever = true, ifBonus = true },
	{ id = 19972, short = "大赛：奇弗兰神仙鱼", kind = "Head", from = "荆棘谷钓鱼大赛：向藏宝海湾 Fishbot 5000 交纳奇弗兰神仙鱼。",
		where = { map = 1434, x = 0.274, y = 0.768, label = "Fishbot 5000, Booty Bay" }, source = { "quest", 8221, "Rare Fish - Keefer's Angelfish" } },
	{ id = 19969, short = "大赛：布隆奈尔刺鱼", kind = "Feet", from = "荆棘谷钓鱼大赛：向藏宝海湾 Fishbot 5000 交纳布隆奈尔蓝带刺鱼。",
		where = { map = 1434, x = 0.274, y = 0.768, label = "Fishbot 5000, Booty Bay" }, source = { "quest", 8225, "Rare Fish - Brownell's Blue Striped Racer" } },
	{ id = 19971, short = "大赛：德兹拉皇后鱼", kind = "Line", bonus = 5, from = "荆棘谷钓鱼大赛：向 Fishbot 5000 交纳德兹拉皇后鱼。永久为鱼竿 +5 钓鱼。",
		where = { map = 1434, x = 0.274, y = 0.768, label = "Fishbot 5000, Booty Bay" }, source = { "quest", 8224, "Rare Fish - Dezian Queenfish" } },
	{ id = 273495, short = "附魔师（附魔 145）", kind = "Hands", from = "手套 +2 钓鱼附魔：附魔 145 的附魔师使用「附魔手套 - 钓鱼」配方可附。Forever 中该附魔物品目前主要在测试服。", forever = true,
		source = { "item", 11152, "Formula: Enchant Gloves - Fishing" } },
}
-- where: { map = uiMapID, x, y, label }, the spot to go to for it; source: { "quest", "npc" or
-- "item", ID, name }, the Wowhead page for where it comes from.
-- ifBonus: Forever's new items whose Fishing bonus its data doesn't say. They show once the
-- game's tooltip for them has one, so a cosmetic hat or mantle never joins the list.
-- bonus: the Fishing bonus where the tooltip doesn't give it as "+N" (the fishing line's).

-- Who sells the vendor poles: CMaNGOS's Classic vendors, at their spots in Wowhead's Forever data
-- (16 November 2026). [item] = { { npc, name, side (A, H or B), uiMapID, x, y }, ... }.
Journey.VENDORS = {
	[6256] = {
		{ 66, "Tharynn Bouden", "A", 1429, 0.418, 0.670 },
		{ 777, "Amy Davenport", "A", 1433, 0.238, 0.476 },
		{ 843, "Gina MacGregor", "A", 1436, 0.574, 0.540 },
		{ 989, "Banalash", "H", 1435, 0.444, 0.570 },
		{ 1148, "Nerrist", "H", 1434, 0.326, 0.292 },
		{ 1286, "Edna Mullby", "A", 1453, 0.580, 0.606 },
		{ 1465, "Drac Roughcut", "A", 1432, 0.354, 0.488 },
		{ 1678, "Vernon Hale", "A", 1433, 0.222, 0.476 },
		{ 1684, "Khara Deepwater", "A", 1432, 0.394, 0.392 },
		{ 2383, "Lindea Rabonne", "A", 1424, 0.500, 0.624 },
		{ 2626, "Old Man Heming", "B", 1434, 0.274, 0.770 },
		{ 2810, "Hammon Karwn", "A", 1417, 0.464, 0.474 },
		{ 2821, "Keena", "H", 1417, 0.740, 0.324 },
		{ 3029, "Sewa Mistrunner", "H", 1456, 0.552, 0.480 },
		{ 3178, "Stuart Fleming", "A", 1437, 0.080, 0.582 },
		{ 3333, "Shankys", "H", 1454, 0.694, 0.290 },
		{ 3367, "Felika", "H", 1454, 0.526, 0.576 },
		{ 3482, "Tari'qa", "H", 1413, 0.516, 0.300 },
		{ 3497, "Kilxx", "B", 1413, 0.628, 0.382 },
		{ 3499, "Ranik", "B", 1413, 0.618, 0.386 },
		{ 3550, "Martine Tramblay", "H", 1420, 0.658, 0.594 },
		{ 3556, "Andrew Hilbert", "H", 1421, 0.430, 0.404 },
		{ 3572, "Zizzek", "B", 1413, 0.620, 0.390 },
		{ 3779, "Syurana", "A", 1452, 0.514, 0.298 },
		{ 3954, "Dalria", "A", 1440, 0.350, 0.520 },
		{ 3955, "Shandrina", "A", 1440, 0.494, 0.670 },
		{ 4222, "Voloren", "A", 1457, 0.464, 0.560 },
		{ 4229, "Mythrin'dir", "A", 1457, 0.610, 0.174 },
		{ 4561, "Daniel Bartlett", "H", 1458, 0.640, 0.388 },
		{ 4574, "Lizbeth Cromwell", "H", 1458, 0.810, 0.292 },
		{ 4775, "Felicia Doan", "H", 1458, 0.638, 0.492 },
		{ 4897, "Helenia Olden", "A", 1445, 0.664, 0.514 },
		{ 5162, "Tansy Puddlefizz", "A", 1455, 0.478, 0.064 },
		{ 5163, "Burbik Gearspanner", "A", 1455, 0.464, 0.272 },
		{ 5494, "Catherine Leland", "A", 1453, 0.454, 0.576 },
		{ 5817, "Shimra", "H", 1454, 0.478, 0.806 },
		{ 5940, "Harn Longcast", "H", 1412, 0.466, 0.592 },
		{ 5942, "Zansoa", "H", 1411, 0.560, 0.734 },
		{ 6301, "Gorbold Steelhand", "A", 1439, 0.380, 0.412 },
		{ 7945, "Savanne", "A", 1444, 0.310, 0.460 },
		{ 7947, "Vivianna", "A", 1444, 0.312, 0.434 },
		{ 8145, "Sheendra Tallgrass", "H", 1444, 0.744, 0.428 },
		{ 8363, "Shadi Mistrunner", "H", 1456, 0.404, 0.634 },
		{ 8508, "Gretta Ganter", "A", 1426, 0.314, 0.446 },
		{ 8934, "Christopher Hewen", "A", 1436, 0.522, 0.528 },
		{ 10118, "Nessa Shadowsong", "A", 1438, 0.562, 0.924 },
		{ 10216, "Gubber Blump", "A", 1439, 0.360, 0.448 },
		{ 11189, "Qia", "B", 1452, 0.612, 0.372 },
		{ 12022, "Lorelae Wintersong", "B", 1450, 0.484, 0.402 },
		{ 12028, "Lah'Mawhani", "H", 1443, 0.230, 0.716 },
		{ 12031, "Mai'Lahii", "H", 1443, 0.226, 0.720 },
		{ 12043, "Kulwia", "H", 1442, 0.454, 0.594 },
		{ 12245, "Vendor-Tron 1000", "B", 1443, 0.602, 0.382 },
		{ 12941, "Jase Farlane", "B", 1423, 0.804, 0.576 },
		{ 12957, "Blimo Gadgetspring", "B", 1447, 0.452, 0.908 },
		{ 12958, "Gigget Zipcoil", "B", 1425, 0.344, 0.384 },
		{ 12962, "Wik'Tar", "H", 1440, 0.118, 0.340 },
		{ 14740, "Katoom the Angler", "H", 1425, 0.802, 0.814 },
		{ 15179, "Mishta", "B", 1451, 0.498, 0.364 },
	},
	[6365] = {
		{ 1678, "Vernon Hale", "A", 1433, 0.222, 0.476 },
		{ 1684, "Khara Deepwater", "A", 1432, 0.394, 0.392 },
		{ 2383, "Lindea Rabonne", "A", 1424, 0.500, 0.624 },
		{ 2626, "Old Man Heming", "B", 1434, 0.274, 0.770 },
		{ 3029, "Sewa Mistrunner", "H", 1456, 0.552, 0.480 },
		{ 3178, "Stuart Fleming", "A", 1437, 0.080, 0.582 },
		{ 3333, "Shankys", "H", 1454, 0.694, 0.290 },
		{ 3497, "Kilxx", "B", 1413, 0.628, 0.382 },
		{ 3550, "Martine Tramblay", "H", 1420, 0.658, 0.594 },
		{ 3572, "Zizzek", "B", 1413, 0.620, 0.390 },
		{ 4222, "Voloren", "A", 1457, 0.464, 0.560 },
		{ 4574, "Lizbeth Cromwell", "H", 1458, 0.810, 0.292 },
		{ 5162, "Tansy Puddlefizz", "A", 1455, 0.478, 0.064 },
		{ 5494, "Catherine Leland", "A", 1453, 0.454, 0.576 },
		{ 5940, "Harn Longcast", "H", 1412, 0.466, 0.592 },
		{ 5942, "Zansoa", "H", 1411, 0.560, 0.734 },
		{ 7945, "Savanne", "A", 1444, 0.310, 0.460 },
		{ 8508, "Gretta Ganter", "A", 1426, 0.314, 0.446 },
		{ 10118, "Nessa Shadowsong", "A", 1438, 0.562, 0.924 },
		{ 12031, "Mai'Lahii", "H", 1443, 0.226, 0.720 },
		{ 12962, "Wik'Tar", "H", 1440, 0.118, 0.340 },
		{ 14740, "Katoom the Angler", "H", 1425, 0.802, 0.814 },
	},
}

-- Your position on its continent, for the nearest vendor. Nil where the game won't say.
local function PlayerWorld()
	local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pos = here and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(here, "player")
	if not (pos and C_Map.GetWorldPosFromMapPos) then
		return nil
	end
	local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, here, pos)
	if ok and continent and world then
		return continent, world
	end
end

local function Distance(continent, world, mapID, x, y)
	if not (continent and CreateVector2D) then
		return math.huge
	end
	local ok, c, w = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not (ok and c == continent and w) then
		return math.huge
	end
	local dx, dy = w.x - world.x, w.y - world.y
	return dx * dx + dy * dy
end

-- Where to go for a piece of gear: its one spot, or for the vendor poles the nearest vendor
-- on your side (the first listed when the game can't say where you are). Nil if neither.
function Journey.GearSpot(g)
	if g.where then
		return g.where
	end
	local list = Journey.VENDORS[g.id]
	if not list then
		return nil
	end
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	local mine = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
	local continent, world = PlayerWorld()
	local best, bestDistance
	for _, v in ipairs(list) do
		if not mine or v[3] == "B" or v[3] == mine then
			local d = Distance(continent, world, v[4], v[5], v[6])
			if not best or d < bestDistance then
				best, bestDistance = v, d
			end
		end
	end
	if best then
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(best[4])
		return { map = best[4], x = best[5], y = best[6], nearest = true,
			label = best[2] .. (info and info.name and (", " .. info.name) or "") }
	end
end

local function ShowGearSpot(spot)
	if spot and ns.UI and ns.UI.ShowOnMap then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ns.UI.ShowOnMap(spot.map, spot.x, spot.y, spot.label)
	end
end

-- A gear card's menu: the map, its Wowhead page and its source's, and a chat link.
local function GearMenu(g)
	local name = C_Item.GetItemNameByID(g.id) or ("item " .. g.id)
	local entries = {}
	local spot = Journey.GearSpot(g)
	if spot then
		entries[#entries + 1] = { "地图显示：" .. spot.label, function() ShowGearSpot(spot) end }
	end
	entries[#entries + 1] = { "Wowhead：" .. name, function() ns.UI.ShowWowhead("item", g.id, name) end }
	if g.source then
		entries[#entries + 1] = { "Wowhead：" .. g.source[3], function()
			ns.UI.ShowWowhead(g.source[1], g.source[2], g.source[3])
		end }
	end
	local _, link = C_Item.GetItemInfo(g.id)
	if link and ns.InsertChatLink then
		entries[#entries + 1] = { "发到聊天", function() ns.InsertChatLink(link) end }
	end
	ns.UI.ShowMenu(name, entries)
end

local frame

-- The Legacy Challenges' own art ---------------------------------------------------------------
-- The game's atlases for its challenge cards, drawn as its Legacy Challenges window draws them
-- (Blizzard_LegacySystem), for the Gear tab's cards. Plain fills where they're missing.

local function Atlas(texture, name, useSize)
	local UI = ns.UI
	for _, candidate in ipairs({ name, name .. "-c60" }) do
		if UI.HasAtlas(candidate) then
			texture:SetAtlas(candidate, useSize)
			return true
		end
	end
	return false
end

-- Gear cards ------------------------------------------------------------------------------------
-- A piece of fishing gear on the Legacy Challenges' card: its icon in the game's frame, its name
-- in its quality's colour, where it comes from in a few words, and its Fishing bonus large on the
-- right with whether you have it under it. The full source is in its tooltip.
local SLOT_ORDER = { "Pole", "Head", "Hands", "Feet" }
local SLOT_LABEL = { Pole = "鱼竿", Head = "头部", Hands = "手部", Feet = "脚部" }

GearCard = function(parent, g)
	local card = CreateFrame("Button", nil, parent)
	card.gear = g
	card.bg = card:CreateTexture(nil, "BACKGROUND")
	card.bg:SetAllPoints()
	card.selected = card:CreateTexture(nil, "BORDER")
	card.selected:SetAllPoints()
	if not Atlas(card.selected, "Legacy-Challenge-Cards-selected") then
		card.selected:SetColorTexture(1, 0.82, 0, 0.12)
	end
	card.selected:Hide()
	card.icon = card:CreateTexture(nil, "ARTWORK", nil, 1)
	card.icon:SetSize(34, 34)
	card.icon:SetPoint("LEFT", 12, 0)
	card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	card.iconFrame = card:CreateTexture(nil, "OVERLAY")
	card.iconFrame:SetSize(44, 44)
	card.iconFrame:SetPoint("CENTER", card.icon, "CENTER")
	card.check = card:CreateTexture(nil, "OVERLAY", nil, 2)
	card.check:SetSize(16, 14)
	card.check:SetPoint("BOTTOMRIGHT", card.icon, "BOTTOMRIGHT", 6, -4)
	if not Atlas(card.check, "worldquest-tracker-checkmark") then
		card.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	end
	card.bonus = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	card.bonus:SetPoint("TOPRIGHT", -12, -9)
	card.status = card:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	card.status:SetPoint("TOPRIGHT", card.bonus, "BOTTOMRIGHT", 0, -2)
	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -1)
	card.name:SetPoint("RIGHT", -64, 0)
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.from = card:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	card.from:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
	card.from:SetPoint("RIGHT", -64, 0)
	card.from:SetJustifyH("LEFT")
	card.from:SetWordWrap(false)
	card:SetScript("OnEnter", function(self)
		self.selected:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.gear.id)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(self.gear.from, 1, 1, 1, true)
		GameTooltip:AddLine(self.gear.forever and "来源：Forever 客户端数据。" or "来源：经典版，Forever 可能不同。",
			0.6, 0.6, 0.6, true)
		local spot = Journey.GearSpot(self.gear)
		if spot then
			GameTooltip:AddLine("点击：路径点至 " .. spot.label .. (spot.nearest and "（离你最近）" or ""), 0.6, 0.8, 1, true)
		end
		GameTooltip:AddLine("右键：Wowhead 与更多", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function(self)
		self.selected:Hide()
		GameTooltip:Hide()
	end)
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:SetScript("OnClick", function(self, button)
		local _, link = C_Item.GetItemInfo(self.gear.id)
		if link and IsModifiedClick and IsModifiedClick("CHATLINK") and ns.InsertChatLink then
			ns.InsertChatLink(link)
			return
		end
		local spot = button ~= "RightButton" and Journey.GearSpot(self.gear)
		if spot then
			ShowGearSpot(spot)
		else
			GearMenu(self.gear)
		end
	end)
	return card
end

PaintGearCard = function(card, bonus, owned, equipped)
	local g = card.gear
	Atlas(card.bg, owned and "Legacy-Challenge-Cards" or "Legacy-Challenge-Cards-Disable")
	Atlas(card.iconFrame, owned and "Legacy-Tree-Frame-icon-frame" or "Legacy-Tree-Frame-icon-frame-disable")
	card.icon:SetTexture(C_Item.GetItemIconByID(g.id))
	card.icon:SetDesaturated(not owned)
	local name, _, quality = C_Item.GetItemInfo(g.id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	card.name:SetText((color and color.hex or "|cffffffff") .. (name or "...") .. "|r")
	card.name:SetAlpha(owned and 1 or 0.75)
	local kindCN = ({ Pole = "鱼竿", Head = "头部", Hands = "手部", Feet = "脚部", Shoulder = "肩部", Line = "鱼线" })[g.kind] or g.kind
	card.from:SetText((g.kind ~= "Pole" and (kindCN .. "  ·  ") or "") .. (g.short or g.from))
	card.from:SetTextColor(owned and 0.85 or 0.6, owned and 0.85 or 0.6, owned and 0.85 or 0.6)
	card.bonus:SetText(bonus and bonus > 0 and ("+" .. bonus) or "")
	if owned then
		card.bonus:SetTextColor(0.12, 1, 0)
	else
		card.bonus:SetTextColor(0.45, 0.65, 0.4)
	end
	card.status:SetText(equipped and (GOOD .. "已装备|r") or owned and (GOOD .. "在背包|r") or "")
	card.check:SetShown(owned and ns.db.collectionTicks ~= false)
end

-- Under the worn gear: the best of each you have, and the Fishing all of it adds up to.
GearBest = function(parent)
	local p = CreateFrame("Frame", nil, parent)
	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.3)
	p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", 10, -8)
	p.title:SetText("你拥有的最佳")
	p.lines = {}
	for i, slot in ipairs(SLOT_ORDER) do
		local left = p:CreateFontString(nil, "OVERLAY", "OneCastFontNormalSmall")
		left:SetPoint("TOPLEFT", 10, -10 - i * 16)
		left:SetText(SLOT_LABEL[slot] or slot)
		local right = p:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
		right:SetPoint("TOPRIGHT", -10, -10 - i * 16)
		right:SetPoint("LEFT", left, "RIGHT", 10, 0)
		right:SetJustifyH("RIGHT")
		right:SetWordWrap(false)
		p.lines[slot] = right
	end
	p.total = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.total:SetPoint("BOTTOMRIGHT", -10, 8)
	p.height = 10 + (#SLOT_ORDER + 1) * 16 + 30
	p:SetHeight(p.height)
	return p
end

PaintGearBest = function(p, best)
	local total = 0
	for _, slot in ipairs(SLOT_ORDER) do
		local b = best[slot]
		if b then
			total = total + b.bonus
			p.lines[slot]:SetText((C_Item.GetItemNameByID and C_Item.GetItemNameByID(b.gear.id) or "?") .. "  " .. GOOD
				.. "+" .. b.bonus .. "|r")
		else
			p.lines[slot]:SetText(GREY .. "尚无|r")
		end
	end
	p.total:SetText(string.format("合计：%s钓鱼 +%d|r", GOOD, total))
end

local function CreateWindow()
	local UI = ns.UI
	local f, inset = UI.CreateShell("OneCastJourneyFrame", "渔夫之路",
		C_Item.GetItemIconByID(16083) or "Interface\\Icons\\INV_Misc_Book_09")
	f:SetSize(WIDTH, ns.UI.PAGE_HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	UI.RememberPosition(f, "journey")


	-- Where you stand: your rank, your skill along it, and what it takes to the cap.
	f.headline = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.headline:SetPoint("TOPLEFT", EDGE + 4, -GAP - 2)
	-- The stats page's own bar: Forever's Fishing bar.
	f.progress = UI.RankBar(inset, ns.GetFishingName and ns.GetFishingName() or "钓鱼")
	f.progress:ClearAllPoints()
	f.progress:SetPoint("TOPLEFT", EDGE, -GAP - 26)
	f.progress:SetPoint("TOPRIGHT", -EDGE, -GAP - 26)
	f.togo = inset:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	f.togo:SetPoint("TOPRIGHT", -EDGE - 4, -GAP - 4)
	f.togo:SetJustifyH("RIGHT")

	f.cards = {}
	local y = -GAP - 66
	f.ranksView = CreateFrame("Frame", nil, inset)
	f.ranksView:SetAllPoints()
	for i, r in ipairs(Journey.RANKS) do
		f.cards[i] = Card(f.ranksView, r, y)
		y = y - CARD_HEIGHT
	end

	f:SetScript("OnShow", Journey.Refresh)
	local events = CreateFrame("Frame", nil, f)
	events:RegisterEvent("SKILL_LINES_CHANGED")
	events:RegisterEvent("PLAYER_LEVEL_UP")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	-- A swap or a loot fires these in bursts: one refresh for the lot, a moment later.
	local pending = false
	events:SetScript("OnEvent", function()
		if f:IsShown() and not pending then
			pending = true
			C_Timer.After(0.1, function()
				pending = false
				Journey.Refresh()
			end)
		end
	end)
	f:Hide()
	ns.Hub.Attach("journey", f)
	return f
end

function Journey.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local current, rank, maxRank = Journey.Current()
	if not (rank and maxRank) then
		frame.headline:SetText("你尚未学习钓鱼")
		frame.progress:SetRank(0, "0/0")
		frame.togo:SetText("")
		frame.togo:SetText(GREY .. "向任意钓鱼训练师学习学徒钓鱼即可开始。|r")
	else
		local r = Journey.RANKS[current]
		frame.headline:SetText((r and r.name or "") .. " 钓鱼")
		frame.progress:SetRank(maxRank > 0 and rank / maxRank or 0, string.format("%d/%d", rank, maxRank))
		local nextRank = Journey.RANKS[current + 1]
		if rank >= maxRank and nextRank then
			frame.togo:SetText(GOLD .. "已达当前上限：学习 " .. nextRank.name .. " 才能继续提升。|r")
		elseif rank < maxRank then
			local catches = ns.Stats.CatchesToGo and ns.Stats.CatchesToGo(rank, maxRank - rank)
			frame.togo:SetText(string.format("%s距上限还差 %d 点%s|r", GREY, maxRank - rank,
				catches and string.format("，约需钓 %d 次", catches) or ""))
		else
			frame.togo:SetText(GOOD .. "各级均已学完。|r")
		end
	end
	for i, c in ipairs(frame.cards) do
		Paint(c, i, current, rank)
	end
end

-- The gear catalogue -------------------------------------------------------------------------
-- Every fishing pole and piece of fishing gear as cards: poles on the left, what you wear on the
-- right, each under the window's header, and under the worn gear the best you have for each
-- slot. Each card bright and ticked if you have it (on, or in your bags), dimmed if not, laid
-- out down its column as tall as the column allows. Held by the wardrobe's Gear guide tab.
local GEAR_HEADER, GEAR_CARD, GEAR_GAP = 24, 56, 4
local GEAR_TOP = -GAP - 26 -- under the summary line

local function PaintGearView(v)
	local columns = { pole = {}, worn = {} }
	local have, shown = 0, 0
	local best = {} -- slot -> { gear, bonus } of the best you have
	for _, card in ipairs(v.cards) do
		local g = card.gear
		local bonus = ns.Gear and ns.Gear.ItemBonus and ns.Gear.ItemBonus(g.id)
		if g.bonus and (bonus or 0) == 0 then
			bonus = g.bonus
		end
		local equipped = C_Item.IsEquippedItem and C_Item.IsEquippedItem(g.id) or false
		local owned = equipped or (C_Item.GetItemCount and C_Item.GetItemCount(g.id, true) or 0) > 0
		-- New gear only once its bonus is known; the other faction's quest rewards only if you have one.
		local show = (not g.ifBonus or (bonus and bonus > 0)) and (owned or Journey.ForYourFaction(g))
		card:SetShown(show and true or false)
		if show then
			local list = columns[g.kind == "Pole" and "pole" or "worn"]
			list[#list + 1] = card
			shown = shown + 1
		end
		card.owned = owned
		PaintGearCard(card, bonus, owned, equipped)
		if show and owned then
			have = have + 1
			if bonus and bonus > 0 and (not best[g.kind] or bonus > best[g.kind].bonus) then
				best[g.kind] = { gear = g, bonus = bonus }
			end
		end
	end
	-- The cards as tall as fits: the poles' column, and the worn gear's with the best under it.
	local room = ns.UI.PAGE_HEIGHT - 88 + GEAR_TOP - EDGE - GEAR_HEADER - 4
	local bestHeight = v.best.height or 120
	local height = math.min(GEAR_CARD + GEAR_GAP,
		math.floor(room / math.max(#columns.pole, 1)),
		math.floor((room - bestHeight - 8) / math.max(#columns.worn, 1)))
	local half = (v:GetWidth() > 0 and v:GetWidth() or (v.width - 10)) / 2
	for key, list in pairs(columns) do
		local left = key == "pole" and EDGE or (half + 5)
		local right = key == "pole" and -(half + 5) or -EDGE
		local header = v.headers[key]
		local owned = 0
		for _, card in ipairs(list) do
			owned = owned + (card.owned and 1 or 0)
		end
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", left, GEAR_TOP)
		header:SetPoint("TOPRIGHT", right, GEAR_TOP)
		header.text:SetText(string.format("%s  %s（%d/%d）|r", key == "pole" and "钓鱼竿" or "穿戴装备",
			GREY, owned, #list))
		local y = GEAR_TOP - GEAR_HEADER - 4
		for _, card in ipairs(list) do
			card:SetHeight(height - GEAR_GAP)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", left, y)
			card:SetPoint("TOPRIGHT", right, y)
			y = y - height
		end
		if key == "worn" then
			v.best:ClearAllPoints()
			v.best:SetPoint("TOPLEFT", left, y - 4)
			v.best:SetPoint("TOPRIGHT", right, y - 4)
		end
	end
	PaintGearBest(v.best, best)
	v.summary:SetText(string.format("%s你已拥有 %d/%d 件钓鱼装备。悬停可查看获取方式。|r",
		GREY, have, shown))
end

-- Gear any character can get, or one of your faction's.
function Journey.ForYourFaction(g)
	if not g.faction then
		return true
	end
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return not faction or faction == g.faction
end

-- A catalogue on `parent` (filling it), for a window `width` wide. v:Paint() redraws it.
function Journey.GearView(parent, width)
	local UI = ns.UI
	local v = CreateFrame("Frame", nil, parent)
	v:SetAllPoints()
	v.width = width
	v.summary = v:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	v.summary:SetPoint("TOPLEFT", EDGE + 4, -GAP - 2)
	v.summary:SetPoint("RIGHT", -EDGE, 0)
	v.summary:SetJustifyH("LEFT")
	v.headers = { pole = UI.SectionHeader(v, 0), worn = UI.SectionHeader(v, 0) }
	v.cards = {}
	for i, g in ipairs(Journey.GEAR) do
		v.cards[i] = GearCard(v, g)
	end
	v.best = GearBest(v)
	v.Paint = PaintGearView
	return v
end

function Journey.Show()
	frame = frame or CreateWindow()
	frame:Show()
end

-- Open on a view: the ranks here, or all the fishing gear in the wardrobe.
function Journey.ShowView(view)
	if view == "gear" and ns.Wardrobe and ns.Wardrobe.ShowGear then
		ns.Wardrobe.ShowGear()
		return
	end
	Journey.Show()
end

-- Finds for the data report -----------------------------------------------------------------
-- What Forever's data can't tell, found as you play: where a Fishing rank is learned (the
-- trainer, or the quest), fishing gear the Gear view doesn't list, and how Find Fish and Bait
-- and Tackle are learned. Each with where it came from: the trainer or vendor you had open, the
-- quest you'd just handed in, or loot.
-- OneCastCharDB.journeyFinds = { ranks = { [cap] = find }, gear = { [itemID] = find },
--   spells = { [spellID] = find } }; find = { zone, how, name, npc, quest, bonus }

local TRACKED_SPELLS = { [43308] = "Find Fish", [1278067] = "Bait and Tackle" }
local RECENT = 10        -- seconds a quest hand-in or loot still explains what turns up
local TRAINER_RECENT = 120
local context = {}       -- what you were last doing: trainer, vendor, quest, loot
local checked = {}       -- items already looked at this session, for new gear
local lastCap

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function NpcHere()
	local guid = UnitGUID and UnitGUID("npc")
	local name = UnitName and UnitName("npc")
	if Secret(guid) or Secret(name) then
		return nil
	end
	local id = type(guid) == "string" and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)") or "")
	return { name = name, npc = id, at = GetTime() }
end

local function Finds()
	if not OneCastCharDB then
		return nil
	end
	OneCastCharDB.journeyFinds = OneCastCharDB.journeyFinds or { ranks = {}, gear = {}, spells = {} }
	return OneCastCharDB.journeyFinds
end

-- Where something you just got came from: whichever of the trainer you had open, a vendor, a
-- quest you handed in or loot happened last, within its window.
local function Source(trainerToo)
	local now = GetTime()
	local find = { zone = GetRealZoneText() or "?", how = "unknown" }
	local c = context
	local best
	local function Consider(how, entry, window)
		if entry and now - entry.at <= window and (not best or entry.at >= best.entry.at) then
			best = { how = how, entry = entry }
		end
	end
	if trainerToo then
		Consider("trainer", c.trainer, TRAINER_RECENT)
	end
	Consider("quest", c.quest, RECENT)
	if c.vendor then
		Consider("vendor", c.vendor, c.vendorOpen and math.huge or RECENT)
	end
	Consider("loot", c.loot, RECENT)
	if best then
		local e = best.entry
		find.how, find.name, find.npc, find.quest = best.how, e.name or e.title, e.npc, e.id
	end
	return find
end
Journey.Source = Source

local function Changed()
	if ns.Report and ns.Report.Check then
		ns.Report.Check()
	end
end

-- A rank learned: your cap went up. Expert's book is confirmed from Forever's data; the others
-- aren't, so where they're learned is worth knowing.
local function CheckRank()
	local stats = ns.Stats
	if not (stats and stats.FishingSkill) then
		return
	end
	local _, cap = stats.FishingSkill()
	if not cap then
		return
	end
	if lastCap and cap > lastCap and cap ~= 225 then
		local finds = Finds()
		if finds and not finds.ranks[cap] then
			finds.ranks[cap] = Source(true)
			Changed()
		end
	end
	lastCap = cap
end

-- Fishing gear the Gear view doesn't list: a pole, or anything with a Fishing bonus.
local LISTED
local function Listed(id)
	if not LISTED then
		LISTED = {}
		for _, g in ipairs(Journey.GEAR) do
			LISTED[g.id] = true
		end
	end
	return LISTED[id]
end

local function CheckItem(id, link)
	if checked[id] or Listed(id) then
		return
	end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
	if classID ~= 2 and classID ~= 4 then
		checked[id] = true
		return
	end
	local bonus = ns.Gear and ns.Gear.ItemBonus and ns.Gear.ItemBonus(id)
	if bonus == nil then
		return -- still loading: looked at again on the next bag change
	end
	checked[id] = true
	local pole = classID == 2 and subclassID == 20
	if bonus > 0 or pole then
		local finds = Finds()
		if finds and not finds.gear[id] then
			local find = Source(false)
			find.bonus, find.item = bonus, C_Item.GetItemNameByID(id) or (link and link:match("%[(.-)%]"))
			finds.gear[id] = find
			Changed()
		end
	end
end

local function ScanGear()
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				CheckItem(info.itemID, info.hyperlink)
			end
		end
	end
	for _, slot in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 15, 16 }) do
		local id = GetInventoryItemID("player", slot)
		if id then
			CheckItem(id)
		end
	end
end
Journey.ScanGear = ScanGear

local tracker = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "TRAINER_SHOW", "MERCHANT_SHOW", "MERCHANT_CLOSED",
	"QUEST_TURNED_IN", "LOOT_READY", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
	tracker:RegisterEvent(event)
end
if ns.RegisterAnyEvent then
	ns.RegisterAnyEvent(tracker, { "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB" })
end
tracker:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		local stats = ns.Stats
		if stats and stats.FishingSkill then
			local _, cap = stats.FishingSkill()
			lastCap = cap
		end
		C_Timer.After(5, ScanGear)
	elseif event == "SKILL_LINES_CHANGED" then
		CheckRank()
	elseif event == "TRAINER_SHOW" then
		context.trainer = NpcHere()
	elseif event == "MERCHANT_SHOW" then
		context.vendor, context.vendorOpen = NpcHere(), true
	elseif event == "MERCHANT_CLOSED" then
		context.vendorOpen = false
		if context.vendor then
			context.vendor.at = GetTime()
		end
	elseif event == "QUEST_TURNED_IN" then
		local questID = ...
		if type(questID) == "number" and not Secret(questID) then
			local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
			context.quest = { id = questID, title = not Secret(title) and title or nil, at = GetTime() }
		end
	elseif event == "LOOT_READY" then
		local guid = GetLootSourceInfo and GetLootSourceInfo(1)
		local npc = not Secret(guid) and type(guid) == "string" and guid:match("^Creature") and
			tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)") or "")
		context.loot = { npc = npc or nil, at = GetTime() }
	elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
		ScanGear()
	else
		-- A spell learned: Find Fish or Bait and Tackle.
		local spellID = ...
		if type(spellID) == "number" and not Secret(spellID) and TRACKED_SPELLS[spellID] then
			local finds = Finds()
			if finds and not finds.spells[spellID] then
				finds.spells[spellID] = Source(true)
				Changed()
			end
		end
	end
end)

-- Report lines for what's been found: { key, text } each.
local function FromText(f)
	local who = f.name and (f.npc and string.format("%s [%d]", f.name, f.npc) or f.name) or (f.npc and ("creature " .. f.npc))
	if f.how == "trainer" then
		return "from the trainer " .. (who or "?")
	elseif f.how == "vendor" then
		return "bought from " .. (who or "a vendor")
	elseif f.how == "quest" then
		return string.format("from the quest %s[%s]", f.name and (f.name .. " ") or "", tostring(f.quest))
	elseif f.how == "loot" then
		return who and ("looted from " .. who) or "from loot"
	end
	return "source not seen"
end

-- The same, for the player: no ids in brackets.
local function PlainFrom(f)
	local text = FromText(f):gsub("%s*%[[^%]]*%]", "")
	return text == "source not seen" and "somewhere" or text
end

function Journey.Findings()
	local out = {}
	local finds = OneCastCharDB and OneCastCharDB.journeyFinds
	if not finds then
		return out
	end
	local caps = {}
	for cap in pairs(finds.ranks or {}) do
		caps[#caps + 1] = cap
	end
	table.sort(caps)
	for _, cap in ipairs(caps) do
		local f = finds.ranks[cap]
		local rankName = "Fishing"
		for _, r in ipairs(Journey.RANKS) do
			if r.cap == cap then
				rankName = r.name .. " Fishing"
			end
		end
		out[#out + 1] = { key = "journey:rank:" .. cap, text = string.format("Learned %s (up to %d) %s in %s",
			rankName, cap, FromText(f), f.zone or "?"), title = rankName,
			detail = string.format("You learned it %s in %s. Where it's taught in Forever isn't known yet.", PlainFrom(f), f.zone or "?") }
	end
	local ids = {}
	for id in pairs(finds.gear or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local f = finds.gear[id]
		out[#out + 1] = { key = "journey:gear:" .. id, id = id, text = string.format("Fishing gear OneCast doesn't list: %s (%d)%s, %s in %s",
			f.item or ("item " .. id), id, (f.bonus or 0) > 0 and string.format(", +%d Fishing", f.bonus) or "",
			FromText(f), f.zone or "?"), title = f.item or ("Item " .. id),
			detail = string.format("%sFishing gear the Gear tab doesn't list: you got it %s in %s.",
				(f.bonus or 0) > 0 and string.format("+%d Fishing. ", f.bonus) or "", PlainFrom(f), f.zone or "?") }
	end
	for spellID, f in pairs(finds.spells or {}) do
		out[#out + 1] = { key = "journey:spell:" .. spellID, text = string.format("Learned %s (%d) %s in %s",
			TRACKED_SPELLS[spellID] or "a fishing spell", spellID, FromText(f), f.zone or "?"),
			title = TRACKED_SPELLS[spellID] or "A fishing spell",
			detail = string.format("You learned it %s in %s. Where it's taught isn't known yet.", PlainFrom(f), f.zone or "?") }
	end
	return out
end

-- Global for the "Fisherman's journey" key binding.
function OneCast_ToggleJourney()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Journey.Show()
	end
end

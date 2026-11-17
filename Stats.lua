-- OneCast stats: casts, catches, fish per hour, value and what was caught, per character.
-- The window has three tabs: Now (this session, your skill's progress and what's biting),
-- Farm (this zone and its spots, or where one fish bites best) and Records (personal bests,
-- notable catches and lifetime totals).
--
-- A cast is counted when the Fishing channel starts (OneCast.lua calls Stats.OnCast).
-- A catch is counted on the first LOOT_READY after that cast where IsFishingLoot() is
-- true, so a reel that loses the fish counts as a cast without a catch. "Your fish got
-- away" (ERR_FISH_ESCAPED) is counted separately: it means your skill is too low here.
--
-- Each zone's totals also keep `spots` by sub-zone (GetSubZoneText at the cast), lifetime
-- items keep `hours` (catches by realm hour, for the book's time of day), and `charDB.skill`
-- counts catches since the last Fishing skill-up to estimate the next one.

local ADDON, ns = ...

local Stats = {}
ns.Stats = Stats

local ACTIVE_GAP = 2 * 60         -- gaps between casts longer than this aren't fishing time
local LOG_SIZE = 100
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 50, 200, 5 -- percent

-- Layout, in pixels from the top of the inset panel: the skill bar, the zone strip, the section
-- header, three headline tiles, a few detail rows, then the list, which takes the rest.
-- One set of spacings throughout: EDGE from the sides, GAP between parts, HEADER_GAP from a
-- section header to what's under it, and PAD for text inside a row.
local WINDOW_WIDTH, WINDOW_HEIGHT = 340, 580 -- every page of the window is 580 tall (ns.UI.PAGE_HEIGHT)
local INSET_WIDTH, INSET_HEIGHT = WINDOW_WIDTH - 10, WINDOW_HEIGHT - 60 - 28
local EDGE, GAP, HEADER_GAP, PAD = 10, 8, 4, 6
local HEADER_HEIGHT = 24
local BAR_TOP, BAR_HEIGHT = -GAP, 29 -- the professions window's bar art is 29 tall
local STRIP_TOP, STRIP_HEIGHT = BAR_TOP - BAR_HEIGHT - GAP, 22
local SUMMARY_TOP = STRIP_TOP - STRIP_HEIGHT - GAP
local TILES_TOP, TILE_HEIGHT, TILE_GAP = SUMMARY_TOP - HEADER_HEIGHT - HEADER_GAP, 44, 5
local STATS_TOP = TILES_TOP - TILE_HEIGHT - HEADER_GAP
local STAT_ROWS, STAT_HEIGHT = 8, 17
local MAX_ROWS, ITEM_HEIGHT = 14, 22
local LATEST_HEIGHT = 40 -- the latest catch's card, above the session's list
local VIEWS = {
	{ key = "session", label = "会话", width = 74 },
	{ key = "farm", label = "地点", width = 64 },
	{ key = "records", label = "历史记录", width = 126 },
}
local TABS_LEFT, TAB_GAP = 62, 2 -- top tabs start right of the portrait; widths fit their names
local NOTABLE_SIZE = 40
local BEST_MIN_TIME = 15 * 60 -- fishing in a session before its rates can be a personal best

local charDB
local awaitingLoot = false
local FULL_REDRAW_SECONDS = 30 -- the open session tab redraws in full this often
local CLEAN_CATCHES = 10 -- catches in a row with no getaway that clear a zone's getaways
local castLured = "without" -- which of charDB.lureRates this cast counts towards
local castZone, castSpot -- where the line went out, for the catch it brings in
local summaryTimer
local autoLootOffered = false -- once per login
local frame -- the stats window, created on first open
-- Set when the player closes the window on purpose (X button, minimap button, /onecast
-- stats); it then stays closed on cast until they take a break from fishing. Escape,
-- Alt+Z and cutscenes also hide it but don't count.
local dismissed = false
-- Set when the window opened by itself on a cast: only then does it close itself when the
-- weapons go back on (closeOnDone). Opening it any other way clears it.
local autoOpened = false

local function NewTotals()
	return { casts = 0, catches = 0, escapes = 0, activeTime = 0, items = {}, zones = {} }
end

local function Session()
	return charDB.session
end

-- The dungeon you're in, by its map ID, under the name the zone tables use (ns.INSTANCE_ZONES).
function Stats.InstanceZone()
	if not (GetInstanceInfo and ns.INSTANCE_ZONES) then
		return nil
	end
	local _, instanceType, _, _, _, _, _, mapID = GetInstanceInfo()
	if instanceType and instanceType ~= "none" and mapID then
		return ns.INSTANCE_ZONES[mapID]
	end
end

-- Empty while the zone is still loading; never key stats under "".
local function CurrentZone()
	local zone = GetRealZoneText()
	local dungeon = Stats.InstanceZone()
	if dungeon then
		-- Stats kept under the game's own name for it before 0.7.0 move across once.
		if charDB and zone and zone ~= dungeon and charDB.zoneStats[zone] and not charDB.zoneStats[dungeon] then
			charDB.zoneStats[dungeon], charDB.zoneStats[zone] = charDB.zoneStats[zone], nil
		end
		return dungeon
	end
	if not zone or zone == "" then
		return UNKNOWN or "未知"
	end
	return zone
end

local function ZoneTotals(zone)
	local totals = charDB.zoneStats[zone]
	if not totals then
		totals = NewTotals()
		charDB.zoneStats[zone] = totals
	end
	return totals
end

-- The named spot within the zone (a lake, a coast), or the zone itself where there's none.
local function CurrentSpot(zone)
	local sub = GetSubZoneText and GetSubZoneText()
	if not sub or sub == "" or sub == zone then
		return zone
	end
	return sub
end

local function SpotTotals(zoneTotals, spot)
	zoneTotals.spots = zoneTotals.spots or {}
	local t = zoneTotals.spots[spot]
	if not t then
		t = { casts = 0, catches = 0, activeTime = 0, items = {} }
		zoneTotals.spots[spot] = t
	end
	return t
end

local function RefreshIfShown()
	if frame and frame:IsShown() then
		Stats.Refresh()
	end
	if ns.Mini then
		ns.Mini.Refresh()
	end
end
Stats.RefreshIfShown = RefreshIfShown

-- For events that come in bursts (item data loading, skill lines): one redraw shortly after.
local refreshPending = false
function Stats.ScheduleRefresh()
	if refreshPending or not (frame and frame:IsShown()) then
		return
	end
	refreshPending = true
	C_Timer.After(0.2, function()
		refreshPending = false
		RefreshIfShown()
	end)
end

local ArchiveSession -- below: keeps the session in the history before it's replaced

function Stats.ResetSession()
	if ArchiveSession then
		ArchiveSession(charDB.session)
	end
	charDB.session = NewTotals()
	awaitingLoot = false
	RefreshIfShown()
end

function Stats.FormatDuration(seconds)
	seconds = math.floor(seconds or 0)
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	if h > 0 then
		return string.format("%d小时 %d分", h, m)
	end
	return string.format("%dm %02ds", m, seconds % 60)
end

local function PerHour(totals)
	if totals.activeTime < 60 then
		return nil
	end
	return totals.catches / totals.activeTime * 3600
end

function Stats.QualityColor(quality)
	return quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
end

-- The wanted list, per character: what you're fishing for. A fish on it gets an alert when you
-- catch it, or, with a number ("20 Stonescale Eels"), a count towards it, a word halfway and an
-- alert when it's reached. Shown on its rows in the stats (a gold star, or the count) and on the
-- mini bar. Catch goals and the account's wanted marks from before 1.0 come over at login.
-- charDB.wanted[itemID] = { name, got (since it was added), target (optional) }
local function Wanted(itemID)
	return charDB and charDB.wanted and charDB.wanted[itemID]
end

local function IsWanted(itemID)
	return Wanted(itemID) ~= nil
end

-- Older lists: catch goals (this character's) and wanted marks (the account's) become wanted.
local function MigrateWanted()
	charDB.wanted = charDB.wanted or {}
	for id, g in pairs(charDB.goals or {}) do
		charDB.wanted[id] = { name = g.name, got = g.got or 0, target = g.target }
	end
	charDB.goals = nil
	if ns.db and ns.db.wanted and not charDB.wantedFromAccount then
		for id in pairs(ns.db.wanted) do
			charDB.wanted[id] = charDB.wanted[id] or { got = 0 }
		end
		charDB.wantedFromAccount = true
	end
end

function Stats.ToggleWanted(itemID, name)
	charDB.wanted = charDB.wanted or {}
	if charDB.wanted[itemID] then
		charDB.wanted[itemID] = nil
		ns.Print((name or ("物品 " .. itemID)) .. " 已从想要列表移除。")
	else
		charDB.wanted[itemID] = { name = name, got = 0 }
		ns.Print((name or ("物品 " .. itemID)) .. " 已加入想要列表：钓到时会提醒你。")
	end
	RefreshIfShown()
end

-- A row's wanted mark: the count towards its number, or a gold star.
local function WantedText(itemID)
	local w = Wanted(itemID)
	if not w then
		return ""
	elseif not w.target then
		return " |cffffd100*|r"
	end
	return w.got >= w.target and string.format(" |cff20ff20%d/%d|r", w.got, w.target)
		or string.format(" |cff71d5ff%d/%d|r", w.got, w.target)
end

-- How many you want: a number puts it on the list too; 0 (or nothing) keeps it on, no number.
local function SetWantedCount(itemID, target, name)
	charDB.wanted = charDB.wanted or {}
	local w = charDB.wanted[itemID] or { name = name }
	charDB.wanted[itemID] = w
	w.name, w.got = w.name or name, 0
	if target and target > 0 then
		w.target = target
		ns.Print(string.format("想要：%d 条%s。进度会显示在统计行和迷你条上。", target,
			name or ("物品 " .. itemID)))
	else
		w.target = nil
		ns.Print((name or ("物品 " .. itemID)) .. " 已加入想要列表，无数量目标。")
	end
	RefreshIfShown()
end

local function CountWanted(loot)
	for _, l in ipairs(loot) do
		local w = Wanted(l.id)
		if w then
			local before = w.got or 0
			w.got = before + (l.quantity or 1)
			local name = w.name or l.name or "?"
			if ns.db and ns.db.goalAlerts == false then
				-- Counted, but quietly.
			elseif not w.target then
				ns.RaidWarning("钓到 " .. name .. "!")
				PlaySound(SOUNDKIT.RAID_WARNING)
				ns.Print("想要的渔获：" .. (l.link or name))
			elseif before < w.target and w.got >= w.target then
				ns.RaidWarning(string.format("已钓到想要的 %d 条%s！", w.target, name))
				PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or SOUNDKIT.RAID_WARNING)
				ns.Print(string.format("你已钓到想要的 %d 条%s。右键可继续设置数量，或从列表移除。",
					w.target, name))
			elseif before < w.target / 2 and w.got >= w.target / 2 and w.target >= 6 then
				ns.Print(string.format("过半：%d/%d %s。", w.got, w.target, name))
			end
		end
	end
end

StaticPopupDialogs["ONECAST_GOAL"] = {
	text = "想要钓多少条 %s？（0 表示不设数量）",
	button1 = OKAY or "OK",
	button2 = CANCEL or "取消",
	hasEditBox = true,
	OnShow = function(self, data)
		local box = (self.GetEditBox and self:GetEditBox()) or self.editBox
		if box then
			box:SetNumeric(true)
			box:SetText(tostring(data and data.default or 20))
			box:HighlightText()
		end
	end,
	OnAccept = function(self, data)
		local box = (self.GetEditBox and self:GetEditBox()) or self.editBox
		if data then
			SetWantedCount(data.itemID, tonumber(box and box:GetText() or ""), data.name)
		end
	end,
	-- The game hands these the dialog's data: the edit box's parent isn't always the dialog.
	EditBoxOnEnterPressed = function(self, data)
		if data then
			SetWantedCount(data.itemID, tonumber(self:GetText() or ""), data.name)
		end
		StaticPopup_Hide("ONECAST_GOAL")
	end,
	EditBoxOnEscapePressed = function()
		StaticPopup_Hide("ONECAST_GOAL")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Fishing skill: rank, max rank and bonus (lure, pole), or nil if not found.
local function FishingSkill()
	if GetProfessions and GetProfessionInfo then
		local _, _, _, fishing = GetProfessions()
		if fishing then
			local _, _, rank, maxRank, _, _, _, modifier = GetProfessionInfo(fishing)
			if rank then
				return rank, maxRank, modifier or 0
			end
		end
	end
	-- Classic-style skill list, in case Forever keeps fishing there.
	local fishingName = ns.GetFishingName and ns.GetFishingName()
	if fishingName and GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank, _, modifier, maxRank = GetSkillLineInfo(i)
			if not isHeader and name == fishingName then
				return rank, maxRank, modifier or 0
			end
		end
	end
end

-- Rough catches per Fishing skill point, the long-standing Classic estimate: one each up
-- to 75, then one more for every 25 points (about 10 per point near 300).
function Stats.CatchesPerPoint(rank)
	if rank <= 75 then
		return 1
	end
	return math.ceil((rank - 75) / 25) + 1
end

-- Effective skill (lure and pole included) in steps of 25, for the record of what happened at
-- which skill in each zone: { [bucket] = count } under totals.skillCatches and .skillGetaways.
-- Kept for good (a clean run doesn't clear it), as evidence of a zone's real level.
local SKILL_STEP = 25
function Stats.CountAtSkill(totals, key)
	local rank, _, modifier = FishingSkill()
	if not rank then
		return
	end
	local bucket = math.floor((rank + modifier) / SKILL_STEP) * SKILL_STEP
	totals[key] = totals[key] or {}
	totals[key][bucket] = (totals[key][bucket] or 0) + 1
end
Stats.SKILL_STEP = SKILL_STEP

-- "Fast loot": with auto loot on, every slot taken at once the moment the loot window is ready,
-- instead of the game's one at a time. Fishing loot and what fished-up containers held only, and
-- only once OneCast has read what it was.
function Stats.FastLoot(autoLoot)
	if not (ns.db and ns.db.fastLoot and autoLoot and LootSlot) then
		return
	end
	for slot = GetNumLootItems(), 1, -1 do
		LootSlot(slot)
	end
end

-- Notice skill-ups: the catch count toward the next point starts again at each one.
local function CheckSkill()
	local rank = FishingSkill()
	if not rank then
		return
	end
	local track = charDB.skill
	if track.rank ~= rank then
		-- A skill-up: say so on screen (not on the first look, when there's nothing to compare).
		if track.rank and rank > track.rank and ns.Mini and ns.Mini.SkillToast then
			local _, maxRank = FishingSkill()
			ns.Mini.SkillToast(rank - track.rank, rank, maxRank)
		end
		track.rank, track.catches = rank, 0
	end
	track.catches = track.catches or 0
end

-- About how many catches until the skill reaches `rank + points`.
local function CatchesToGo(rank, points)
	local total = 0
	for i = 0, points - 1 do
		total = total + Stats.CatchesPerPoint(rank + i)
	end
	return math.max(1, total - (charDB.skill.rank == rank and charDB.skill.catches or 0))
end

local function SkillGained(s)
	local rank = FishingSkill()
	return rank and s.skillStart and rank - s.skillStart or 0
end

-- Coin values. Vendor price comes from the item data; auction price from Auctionator
-- or TradeSkillMaster when one is installed, since the game has no price API of its own.
local function Coins(copper)
	local format = GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
	return format and format(math.floor(copper)) or string.format("%.2fg", copper / 10000)
end

local itemRequests = {} -- itemID -> true while loading, false if it can't be loaded
local function VendorPrice(itemID)
	local sellPrice = select(11, C_Item.GetItemInfo(itemID))
	if sellPrice == nil and C_Item.RequestLoadItemDataByID and itemRequests[itemID] == nil then
		itemRequests[itemID] = true
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return sellPrice
end

-- Naowh Forever's auction prices: its own scans and the prices it ships for every auction
-- house (NaowhForever_QoL's Auction Prices), read straight from its namespace.
local function NaowhPrices()
	local naowh = _G.NaowhForever
	return type(naowh) == "table" and type(naowh.AuctionPrice) == "function" and naowh or nil
end

-- Auctionator itself, not Naowh Forever's stand-in for it ("Prices for Other Addons"), which
-- answers Auctionator's API when Auctionator isn't installed: those prices are Naowh's.
function Stats.RealAuctionator()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Auctionator")
	return Auctionator and Auctionator.API and (loaded or not NaowhPrices()) and Auctionator.API.v1
end

-- Each source: whether it's installed, and an item's price from it.
local SOURCES = {
	{ key = "auctionator", name = "Auctionator",
		installed = function() return Stats.RealAuctionator() ~= nil and Stats.RealAuctionator() ~= false end,
		price = function(itemID)
			local api = Stats.RealAuctionator()
			if api and api.GetAuctionPriceByItemID then
				local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
				return ok and price or nil
			end
		end },
	{ key = "tsm", name = "TSM",
		installed = function() return TSM_API ~= nil end,
		price = function(itemID)
			if TSM_API and TSM_API.GetCustomPriceValue then
				local ok, price = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
				return ok and price or nil
			end
		end },
	{ key = "naowh", name = "Naowh Forever",
		installed = function() return NaowhPrices() ~= nil end,
		price = function(itemID)
			local naowh = NaowhPrices()
			if naowh then
				local ok, price = pcall(naowh.AuctionPrice, itemID)
				return ok and type(price) == "number" and price > 0 and price or nil
			end
		end },
}

-- The installed price addons, in the automatic order, for the options' list.
function Stats.PriceSources()
	local list = {}
	for _, source in ipairs(SOURCES) do
		if source.installed() then
			list[#list + 1] = source
		end
	end
	return list
end

-- Auction price per unit and where it came from: the first price addon with a price for it,
-- Auctionator, then TradeSkillMaster, then Naowh Forever.
local function AuctionPrice(itemID)
	for _, source in ipairs(SOURCES) do
		local price = source.price(itemID)
		if price then
			return price, source.name
		end
	end
end

-- Total value of `items`, whether any were unpriced, and the price sources used.
-- What's inside the catch -------------------------------------------------------------------
-- Trunks, crates, clams and bloated fish are opened from the bags, a loot of their own that isn't
-- fishing loot. OneCast notes which bag item was just used (a hook on the game's own function,
-- after it runs), and if it's one of those catches, the loot that follows is its contents. In
-- the session that caught it, and in the all-time totals, the contents' worth then stands in
-- for the container's own (which is usually nothing): totals.opened[containerID] = how many were
-- opened, totals.contents[itemID] = { count, name, quality }. Coins inside aren't counted: the
-- game gives them only as text. Every opening is kept for the data report as well, by container:
-- charDB.containerLoot[containerID] = { opened, items = { [itemID] = { count, name } } }.
local Containers = {} -- the pending opening, the loot handler and the count of what's opened
local Worth           -- below: the items to price for a set of totals
do
local openable -- itemID -> true for fished-up containers, from the collection's data
local function Openable(itemID)
	if not openable then
		openable = {}
		for _, fish in ipairs(ns.FISH or {}) do
			local name = fish.name or ""
			if fish.cat == "treasure" or fish.cat == "bloated" or (name:find("Clam") and not name:find("Meat")) then
				openable[fish.id] = true
			end
		end
	end
	return itemID and openable[itemID] or false
end

Containers.WINDOW = 3 -- seconds from using it to its loot

-- The fished-up container just used from the bags: Containers.pending = { id, at }.
local function NoteOpened(bag, slot)
	local id = C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot)
	if Openable(id) then
		Containers.pending = { id = id, at = GetTime() }
	end
end
if C_Container and C_Container.UseContainerItem then
	hooksecurefunc(C_Container, "UseContainerItem", NoteOpened)
end
Stats.NoteOpened = NoteOpened -- for the tests

-- The items to price for a set of totals: the containers that were opened swapped for what they held.
Worth = function(totals)
	if not (totals.opened or totals.contents) then
		return totals.items
	end
	local items = {}
	for id, item in pairs(totals.items) do
		local count = item.count - (totals.opened and totals.opened[id] or 0)
		if count > 0 then
			items[id] = { count = count, name = item.name, quality = item.quality }
		end
	end
	for id, item in pairs(totals.contents or {}) do
		local entry = items[id] or { count = 0, name = item.name, quality = item.quality }
		entry.count = entry.count + item.count
		items[id] = entry
	end
	return items
end

Stats.Worth = Worth -- for the tests

-- How many containers a set of totals has had opened.
function Containers.OpenedCount(totals)
	local n = 0
	for _, count in pairs(totals.opened or {}) do
		n = n + count
	end
	return n
end

function Containers.Loot(containerID)
	local loot = {}
	for slot = 1, GetNumLootItems() do
		if GetLootSlotType(slot) == Enum.LootSlotType.Item then
			local _, name, quantity, _, quality = GetLootSlotInfo(slot)
			local link = GetLootSlotLink(slot)
			local id = link and tonumber(link:match("item:(%d+)"))
			if id then
				loot[#loot + 1] = { id = id, name = name, quality = quality, quantity = quantity or 1 }
			end
		end
	end
	-- Counted where the container was: this session's catch, and the character's all-time.
	local function Add(totals)
		local caught = totals.items[containerID]
		totals.opened = totals.opened or {}
		if not caught or (totals.opened[containerID] or 0) >= caught.count then
			return
		end
		totals.opened[containerID] = (totals.opened[containerID] or 0) + 1
		totals.contents = totals.contents or {}
		totals.inside = totals.inside or {}
		totals.inside[containerID] = totals.inside[containerID] or {}
		local held = totals.inside[containerID]
		for _, l in ipairs(loot) do
			local entry = totals.contents[l.id] or { count = 0, name = l.name, quality = l.quality }
			entry.count = entry.count + l.quantity
			totals.contents[l.id] = entry
			local mine = held[l.id] or { count = 0, name = l.name, quality = l.quality }
			mine.count = mine.count + l.quantity
			held[l.id] = mine
		end
	end
	Add(Session())
	Add(charDB.lifetime)
	-- And for the report, by container.
	charDB.containerLoot = charDB.containerLoot or {}
	local record = charDB.containerLoot[containerID] or { opened = 0, items = {} }
	charDB.containerLoot[containerID] = record
	record.opened = record.opened + 1
	for _, l in ipairs(loot) do
		local entry = record.items[l.id] or { count = 0, name = l.name }
		entry.count = entry.count + l.quantity
		record.items[l.id] = entry
	end
	RefreshIfShown()
end
end

local WhatCaught -- below
local function TotalValue(items, priceOf)
	local total, missing, sources = 0, false, {}
	for id, item in pairs(items) do
		local price, source = priceOf(id)
		if price then
			total = total + price * item.count
			if source then
				sources[source] = true
			end
		else
			missing = true
		end
	end
	return total, missing, sources
end

local function AddCatch(totals, zone, loot)
	totals.catches = totals.catches + 1
	totals.zones[zone] = (totals.zones[zone] or 0) + 1
	for _, l in ipairs(loot) do
		local item = totals.items[l.id]
		if not item then
			item = { name = l.name, icon = l.icon, quality = l.quality, count = 0 }
			totals.items[l.id] = item
		end
		item.count = item.count + l.quantity
	end
end

local function AddToLog(zone, loot)
	local now = GetServerTime()
	for _, l in ipairs(loot) do
		table.insert(charDB.log, 1, { time = now, zone = zone, id = l.id, name = l.name,
			icon = l.icon, quality = l.quality, quantity = l.quantity })
		charDB.lastCaught[l.id] = { time = now, zone = zone }
	end
	for i = #charDB.log, LOG_SIZE + 1, -1 do
		charDB.log[i] = nil
	end
end

-- Worth remembering on the Records tab: uncommon or better, wanted, or new for the collection.
function Stats.NotableReason(l, isNew)
	if isNew then
		return "new"
	elseif IsWanted(l.id) then
		return "wanted"
	elseif l.quality and l.quality >= 2 then
		return "rare"
	end
end

-- This session's catches that were new for the collection, newest first, from the notable list.
function Stats.SessionNew(s)
	local list = {}
	for _, n in ipairs(charDB.notable or {}) do
		if n.why == "new" and s.start and n.time >= s.start then
			list[#list + 1] = n
		end
	end
	return list
end

local function AddNotable(zone, l, why)
	table.insert(charDB.notable, 1, { time = GetServerTime(), zone = zone, id = l.id, name = l.name,
		icon = l.icon, quality = l.quality, quantity = l.quantity, why = why })
	for i = #charDB.notable, NOTABLE_SIZE + 1, -1 do
		charDB.notable[i] = nil
	end
end

-- Personal bests, kept as the session goes: { value, time, zone } under charDB.bests.
local function Best(key, value, zone)
	if not value or value <= 0 then
		return
	end
	local best = charDB.bests[key]
	if not best or value > best.value then
		charDB.bests[key] = { value = value, time = GetServerTime(), zone = zone }
	end
end

local function UpdateBests(zone)
	local s = Session()
	if s.activeTime >= BEST_MIN_TIME then
		Best("rate", PerHour(s), zone)
		Best("vendor", TotalValue(Worth(s), VendorPrice) / s.activeTime * 3600, zone)
	end
	Best("skill", SkillGained(s), zone)
	Best("time", s.activeTime, zone)
end

-- Rare catch alert: anything at or above the alert quality (wanted fish have their own).
local function AlertIfRare(loot)
	local db = ns.db
	if not db or not db.alert then
		return
	end
	for _, l in ipairs(loot) do
		if not IsWanted(l.id) and l.quality and l.quality >= db.alertQuality then
			local color = Stats.QualityColor(l.quality)
			local text = (color and color.hex or "|cffffffff") .. (l.name or "?") .. " 脱钩|r"
			ns.RaidWarning("钓到 " .. text .. "!")
			if db.alertSound ~= false then
				PlaySound(SOUNDKIT.RAID_WARNING)
			end
			ns.Print("稀有渔获：" .. (l.link or text))
		end
	end
end

-- Sum up the session in chat once the player has stopped for a while.
function Stats.SessionSummaryText(s)
	local parts = { string.format("%d catch%s", s.catches, s.catches == 1 and "" or "es") }
	local rate = PerHour(s)
	if rate then
		parts[#parts + 1] = string.format("%.0f/时", rate)
	end
	local vendor = TotalValue(Worth(s), VendorPrice)
	if vendor > 0 then
		parts[#parts + 1] = Coins(vendor) .. " 商人售价"
	end
	local gained = SkillGained(s)
	if gained > 0 then
		parts[#parts + 1] = string.format("+%d %s", gained, ns.GetFishingName and ns.GetFishingName() or "钓鱼")
	end
	if (s.newFish or 0) > 0 then
		parts[#parts + 1] = string.format("%d 条图鉴新鱼", s.newFish)
	end
	return table.concat(parts, ", ")
end

-- Session history: each finished session, newest first, for the All-time records tab. A session
-- ends when a new one starts (after a long break, or a reset).
-- charDB.history = { { start, time, casts, catches, zone, vendor, skill, best, top, items }, ... }
local HISTORY_MAX = 40
ArchiveSession = function(s)
	if not s or (s.catches or 0) == 0 then
		return
	end
	local zone, most = nil, 0
	for z, n in pairs(s.zones or {}) do
		local count = type(n) == "table" and (n.catches or n.count or 0) or n
		if type(count) == "number" and count > most then
			zone, most = z, count
		end
	end
	local top, topCount, best, bestScore = nil, 0, nil, nil
	local items = {}
	for id, item in pairs(s.items or {}) do
		items[#items + 1] = { id = id, count = item.count }
		if item.count > topCount then
			top, topCount = id, item.count
		end
		-- The best catch: the highest quality, then the rarest by Classic's odds.
		local r = ns.Rarity and ns.Rarity(id)
		local score = (item.quality or 1) * 1000 - (r and r.pct or 100)
		if not bestScore or score > bestScore then
			best, bestScore = id, score
		end
	end
	table.sort(items, function(a, b)
		return a.count > b.count
	end)
	for i = #items, 7, -1 do
		items[i] = nil
	end
	charDB.history = charDB.history or {}
	table.insert(charDB.history, 1, {
		start = s.start, time = s.activeTime, casts = s.casts, catches = s.catches, zone = zone,
		vendor = TotalValue(Worth(s), VendorPrice), skill = SkillGained(s), best = best, top = top, items = items,
	})
	for i = #charDB.history, HISTORY_MAX + 1, -1 do
		charDB.history[i] = nil
	end
end

-- Done fishing: the session so far summed up in chat (whatever "Session summary in chat" says:
-- you asked). With `close`, the stats put away; without, kept open, even through the weapons
-- going back on. The session itself carries on until you reset it.
function Stats.EndSession(close)
	if summaryTimer then
		summaryTimer:Cancel()
		summaryTimer = nil
	end
	local s = Session()
	if s.catches > 0 then
		ns.Print("完成钓鱼。目前会话：" .. Stats.SessionSummaryText(s) .. ".")
	end
	if close and frame and frame:IsShown() then
		frame:Hide()
	end
	-- Kept open: no longer one that closes itself when the weapons go back on.
	autoOpened = false
end

function Stats.PrintSessionSummary()
	summaryTimer = nil
	local s = Session()
	if not (ns.db and ns.db.sessionSummary) or s.catches <= (s.summarized or 0) then
		return
	end
	local lead = (s.summarized or 0) > 0 and "目前会话：" or "会话："
	s.summarized = s.catches
	ns.Print(lead .. Stats.SessionSummaryText(s) .. ".")
end

StaticPopupDialogs["ONECAST_RESET_SESSION"] = {
	text = "重置本次会话的统计？\n\n其中的渔获仍会计入区域和生涯总计。",
	button1 = RESET or "重置",
	button2 = CANCEL or "取消",
	OnAccept = function()
		Stats.ResetSession()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["ONECAST_AUTOLOOT"] = {
	text = "自动拾取未开启，每次渔获都会弹出战利品窗口需要点击。\n\n是否开启自动拾取，让渔获直接进包？可在 选项 > 控制 中改回。",
	button1 = "开启",
	button2 = "暂不",
	button3 = "不再询问",
	OnAccept = function()
		ns.db.autoLootFishing = true
		if ns.UpdateLoot then
			ns.UpdateLoot()
		end
		ns.Print("钓鱼期间已开启自动拾取。可在「哇，大鱼」选项的「钓鱼」中修改。")
	end,
	OnAlt = function()
		ns.db.autoLootHint = false
		ns.Print("将不再提示自动拾取。可在「哇，大鱼」选项中重新开启此提示。")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function Stats.OfferAutoLoot(autoLooted)
	if autoLootOffered or autoLooted or not (ns.db and ns.db.autoLootHint) or ns.db.autoLootFishing then
		return
	end
	if C_CVar.GetCVar("autoLootDefault") == "1" then
		return
	end
	autoLootOffered = true
	StaticPopup_Show("ONECAST_AUTOLOOT")
end

function Stats.OnCast()
	local now = GetServerTime()
	local s = Session()
	if not s.lastCast or now - s.lastCast > ACTIVE_GAP then
		dismissed = false -- back from a break: open again
		if ns.Mini then
			ns.Mini.dismissed = false
		end
	end
	castZone = CurrentZone()
	castSpot = CurrentSpot(castZone)
	local zoneTotals = ZoneTotals(castZone)
	local spotTotals = SpotTotals(zoneTotals, castSpot)
	-- Where in the spot you fish from, averaged over your casts (up to the last 50), so the spot
	-- can be shown on the map with a waypoint.
	local mapID, px, py
	if ns.Pools and ns.Pools.ZonePosition then
		mapID, px, py = ns.Pools.ZonePosition()
	end
	if mapID then
		if spotTotals.mapID ~= mapID or not spotTotals.x then
			spotTotals.mapID, spotTotals.x, spotTotals.y, spotTotals.fixes = mapID, px, py, 1
		else
			local n = math.min((spotTotals.fixes or 1) + 1, 50)
			spotTotals.x = spotTotals.x + (px - spotTotals.x) / n
			spotTotals.y = spotTotals.y + (py - spotTotals.y) / n
			spotTotals.fixes = n
		end
	end
	if s.lastCast and now - s.lastCast <= ACTIVE_GAP then
		local gap = now - s.lastCast
		s.activeTime = s.activeTime + gap
		charDB.lifetime.activeTime = charDB.lifetime.activeTime + gap
		zoneTotals.activeTime = zoneTotals.activeTime + gap
		spotTotals.activeTime = spotTotals.activeTime + gap
	end
	-- Fish per hour with and without a lure: this stretch counts as whatever is on now.
	local lured = ns.Lure and ns.Lure.IsActive()
	castLured = lured and "with" or "without"
	local rates = charDB.lureRates
	if s.lastCast and now - s.lastCast <= ACTIVE_GAP then
		rates[castLured].time = rates[castLured].time + (now - s.lastCast)
	end
	s.start = s.start or now
	s.lastCast = now
	s.casts = s.casts + 1
	charDB.lifetime.casts = charDB.lifetime.casts + 1
	zoneTotals.casts = zoneTotals.casts + 1
	spotTotals.casts = spotTotals.casts + 1
	if s.skillStart == nil then
		s.skillStart = FishingSkill()
	end
	awaitingLoot = true

	if summaryTimer then
		summaryTimer:Cancel()
	end
	summaryTimer = C_Timer.NewTimer(ACTIVE_GAP + 1, Stats.PrintSessionSummary)

	-- Open on cast, unless the player closed it during this stretch of fishing. In mini mode, the
	-- slim bar opens instead.
	if ns.db and ns.db.statsMini and ns.Mini then
		if ns.db.openOnCast and not dismissed then
			ns.Mini.OnCast()
		end
		RefreshIfShown()
	elseif ns.db and ns.db.openOnCast and not dismissed and not (frame and frame:IsShown())
		and not ns.Hub.IsOpen() then
		Stats.Show()
		autoOpened = true
	else
		RefreshIfShown()
	end
end

local function OnLootReady(autoLooted)
	if not awaitingLoot or not IsFishingLoot() then
		return
	end
	awaitingLoot = false

	local loot = {}
	for slot = 1, GetNumLootItems() do
		if GetLootSlotType(slot) == Enum.LootSlotType.Item then
			local icon, name, quantity, _, quality = GetLootSlotInfo(slot)
			local link = GetLootSlotLink(slot)
			local id = link and tonumber(link:match("item:(%d+)"))
			if id then
				loot[#loot + 1] = { id = id, name = name, icon = icon, quality = quality,
					quantity = quantity or 1, link = link }
			end
		end
	end

	local zone = CurrentZone()
	local s = Session()
	AddCatch(s, zone, loot)
	AddCatch(charDB.lifetime, zone, loot)
	AddCatch(ZoneTotals(zone), zone, loot)
	local zoneTotals = ZoneTotals(zone)
	zoneTotals.cleanCatches = (zoneTotals.cleanCatches or 0) + 1
	Stats.CountAtSkill(zoneTotals, "skillCatches")
	AddToLog(zone, loot)
	if ns.Camp then
		ns.Camp.OnCatch(zone, loot)
	end

	-- The spot the line went out at, and the realm hour, for each item.
	local spot = SpotTotals(ZoneTotals(zone), zone == castZone and castSpot or CurrentSpot(zone))
	spot.catches = spot.catches + 1
	local hour = GetGameTime()
	for _, l in ipairs(loot) do
		spot.items[l.id] = spot.items[l.id] or { count = 0 }
		spot.items[l.id].count = spot.items[l.id].count + l.quantity
		local item = charDB.lifetime.items[l.id]
		item.hours = item.hours or {}
		item.hours[hour + 1] = (item.hours[hour + 1] or 0) + 1
	end

	CheckSkill()
	charDB.skill.catches = (charDB.skill.catches or 0) + 1
	charDB.lureRates[castLured].catches = charDB.lureRates[castLured].catches + 1

	-- Which are new for the collection, asked before the catch is added to it.
	local new = {}
	if ns.Collection then
		for _, l in ipairs(loot) do
			new[l.id] = ns.Collection.IsFish(l.id) and ns.Collection.Get(l.id).total == 0
		end
		s.newFish = (s.newFish or 0) + (ns.Collection.OnCatch(loot, zone) or 0)
	end
	for _, l in ipairs(loot) do
		local why = Stats.NotableReason(l, new[l.id])
		if why then
			AddNotable(zone, l, why)
		end
	end
	UpdateBests(zone)
	if ns.Extravaganza then
		ns.Extravaganza.OnCatch(loot)
	end
	AlertIfRare(loot)
	CountWanted(loot)
	Stats.OfferAutoLoot(autoLooted)
	if ns.Report then
		ns.Report.Check()
	end
	RefreshIfShown()
end

-- Which fishing message this is, if any: "escaped" (a fish got away) or "notHooked" (reeled
-- before a bite). By the game's own ID for the message where it gives one, which holds in every
-- language, else by its text.
local MESSAGE_IDS = { ERR_FISH_ESCAPED = "escaped", ERR_FISH_NOT_HOOKED = "notHooked" }

local function GameMessageKind(messageType, message)
	if messageType and GetGameMessageInfo and not (issecretvalue and issecretvalue(messageType)) then
		local ok, id = pcall(GetGameMessageInfo, messageType)
		if ok and id and MESSAGE_IDS[id] then
			return MESSAGE_IDS[id]
		end
	end
	if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then
		return nil
	end
	if ERR_FISH_ESCAPED and message == ERR_FISH_ESCAPED then
		return "escaped"
	elseif ERR_FISH_NOT_HOOKED and message == ERR_FISH_NOT_HOOKED then
		return "notHooked"
	end
end

-- Other fishing messages that arrive while a line is out, kept (the last few) for the report:
-- if a fishing message is ever missed, it shows there and can be matched. Only ones about
-- fishing, by the game's ID for them or their words, so a zone being discovered or a key pressed
-- out of turn doesn't fill it up.
local MAX_NOTED = 8
local FISHY = { "fish", "hook", "bobber", "lure", "catch", "caught", "line", "reel", "bite", "pool", "school" }

local function AboutFishing(id, message)
	if id and id:find("FISH") then
		return true
	end
	local lower = message:lower()
	-- A cast that couldn't see its target, not a fishing line: the game's own text for it.
	if (SPELL_FAILED_LINE_OF_SIGHT and message == SPELL_FAILED_LINE_OF_SIGHT) or lower:find("line of sight", 1, true) then
		return false
	end
	-- Fishing in the client's own words ("Angeln", "Pêche"), then the English ones.
	local fishing = ns.GetFishingName and ns.GetFishingName()
	if type(fishing) == "string" and fishing ~= "" and lower:find(fishing:lower(), 1, true) then
		return true
	end
	for _, word in ipairs(FISHY) do
		if lower:find(word, 1, true) then
			return true
		end
	end
	return false
end

local function NoteMessage(event, messageType, message)
	if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) or message == "" then
		return
	end
	local okID, id = false, nil
	if messageType and GetGameMessageInfo then
		okID, id = pcall(GetGameMessageInfo, messageType)
	end
	id = okID and type(id) == "string" and id or nil
	if not AboutFishing(id, message) then
		return
	end
	charDB.messagesWhileFishing = charDB.messagesWhileFishing or {}
	local list = charDB.messagesWhileFishing
	for _, seen in ipairs(list) do
		if seen.text == message then
			seen.count = seen.count + 1
			return
		end
	end
	table.insert(list, 1, { text = message, event = event, id = id, count = 1 })
	list[MAX_NOTED + 1] = nil
end

local function OnFishEscaped()
	if not awaitingLoot then
		return
	end
	awaitingLoot = false
	local s = Session()
	s.escapes = (s.escapes or 0) + 1
	charDB.lifetime.escapes = (charDB.lifetime.escapes or 0) + 1
	local zone = CurrentZone()
	local rank, _, modifier = FishingSkill()
	-- Short of a sub-zone's own higher level, a getaway is expected there and says nothing
	-- about the rest of the zone. The spot is where the line went out, not where you are now.
	local spot = zone == castZone and castSpot or CurrentSpot(zone)
	local spotNeeded = ns.SPOT_FISHING_SKILL and ns.SPOT_FISHING_SKILL[spot]
	if spotNeeded and rank and rank + modifier < spotNeeded then
		RefreshIfShown()
		return
	end
	local z = ZoneTotals(zone)
	z.escapes = (z.escapes or 0) + 1
	Stats.CountAtSkill(z, "skillGetaways")
	-- The highest skill a fish has got away at, lure included: later skill-ups can outgrow it.
	-- An old value a clean run has already cleared doesn't count.
	if (z.cleanCatches or 0) >= CLEAN_CATCHES then
		z.escapeSkill = nil
	end
	z.cleanCatches = 0
	if rank then
		z.escapeSkill = math.max(z.escapeSkill or 0, rank + modifier)
	end
	if ns.Report then
		ns.Report.Check()
	end
	RefreshIfShown()
end

-- Fish per hour with and without a lure, each only after enough fishing to mean something.
local LURE_RATE_MIN_TIME = 5 * 60

function Stats.LureRates()
	local rates = { }
	for _, key in ipairs({ "with", "without" }) do
		local r = charDB.lureRates[key]
		if r.time >= LURE_RATE_MIN_TIME then
			rates[key] = r.catches / r.time * 3600
		end
	end
	return rates
end

-- The session for the minimap tooltip: "12 of 15 caught · 40/hr", or nil before the first cast.
function Stats.Summary()
	local s = Session()
	if s.casts == 0 then
		return nil
	end
	local rate = PerHour(s)
	return string.format("钓获 %d / %d%s", s.catches, s.casts,
		rate and string.format("  ·  %.0f/时", rate) or "")
end

local function SortedItems(items)
	local list = {}
	for id, item in pairs(items) do
		list[#list + 1] = { id = id, name = item.name, icon = item.icon, quality = item.quality, count = item.count }
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

-- Summary rows for a view: { label, value } pairs, shown like the character sheet's stats.
local GREY = "|cff9d9d9d"
local GREEN = "|cff20ff20"
local RED = "|cffff2020"
local SEP = GREY .. "  ·  |r"

-- Rates per place need some fishing behind them to mean anything.
local MIN_RATE_TIME = 5 * 60
local function Rate(count, seconds)
	if count and count > 0 and seconds and seconds >= MIN_RATE_TIME then
		return count / seconds * 3600
	end
end

-- "12m", "2h 40m": for estimates, where seconds would be false precision.
local function ShortDuration(seconds)
	local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
	if minutes < 60 then
		return minutes .. "分钟"
	end
	return string.format("%d小时 %d分", math.floor(minutes / 60), minutes % 60)
end

local function Ago(time)
	local seconds = math.max(0, GetServerTime() - time)
	if seconds < 3600 then
		return math.max(1, math.floor(seconds / 60)) .. " 分钟前"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. " 小时前"
	end
	return math.floor(seconds / 86400) .. " 天前"
end

-- The latest catch this session: { id, name, icon, quality, quantity, time }, or nil.
function Stats.LatestCatch()
	local s = Session()
	local last = charDB and charDB.log and charDB.log[1]
	if not (last and s.start and last.time and last.time >= s.start) then
		return nil
	end
	return last
end

-- "just now" for the first minute, then as Ago.
function Stats.Since(time)
	if GetServerTime() - time < 60 then
		return "刚刚"
	end
	return Ago(time)
end

local function Append(list, more)
	for _, entry in ipairs(more) do
		list[#list + 1] = entry
	end
	return list
end

local function CountKeys(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

local function ItemTotal(items)
	local n = 0
	for _, item in pairs(items) do
		n = n + item.count
	end
	return n
end

-- A headline number for the tiles under the skill bar: { value, caption, tooltip }.
local function Tile(value, caption, tooltip)
	return { value = value or (GREY .. "-|r"), caption = caption, tooltip = tooltip }
end

-- Gold for a big number: "4.1g", "35s", "80c", in the coins' own colours.
local function ShortGold(copper)
	if copper >= 1000000 then
		return string.format("|cffffd100%.0fg|r", copper / 10000)
	elseif copper >= 10000 then
		return string.format("|cffffd100%.1fg|r", copper / 10000)
	elseif copper >= 100 then
		return string.format("|cffc7c7cf%ds|r", math.floor(copper / 100))
	end
	return string.format("|cffeda55f%dc|r", math.floor(copper))
end

local function PriceSources(sources)
	local names = {}
	for _, source in ipairs({ "Auctionator", "TSM", "Naowh Forever" }) do
		if sources[source] then
			names[#names + 1] = source
		end
	end
	return table.concat(names, " 与 ")
end

-- What the session's value covers: its catch, and what was inside what you opened.
WhatCaught = function(s)
	local opened = Containers.OpenedCount(s)
	if opened == 0 then
		return "本次会话的渔获"
	end
	return string.format("本次会话渔获（含你打开的 %d 个宝箱%s、蛤蜊%s 或浮肿鱼中的内容）",
		opened, opened == 1 and "" or "s", opened == 1 and "" or "s")
end

-- Gold per hour of fishing: at auction prices where an addon has them, else the vendor's.
local function GoldTile(items, seconds, what)
	local ah, _, sources = TotalValue(items, AuctionPrice)
	local auction = next(sources) ~= nil
	local copper = auction and ah or TotalValue(items, VendorPrice)
	local value = copper > 0 and seconds and seconds >= 60 and ShortGold(copper / seconds * 3600)
	return Tile(value, auction and "金币/时（拍卖）" or "金币/时（商人）",
		"的拍卖价值，按每小时钓鱼计算。价格来自 " .. what .. "每小时钓鱼价值（" .. (auction and "auction" or "vendor") .. " prices."
		.. (auction and ("\n\n拍卖价来源：" .. PriceSources(sources)) or "安装 Auctionator 或 TSM 后可显示拍卖价。"))
end

-- Vendor and auction gold per hour of fishing, as two tiles.
local function VendorTile(items, seconds, what)
	local copper = TotalValue(items, VendorPrice)
	return Tile(copper > 0 and seconds and seconds >= 60 and ShortGold(copper / seconds * 3600), "商人价/时",
		"的拍卖价值，按每小时钓鱼计算。价格来自 " .. what .. "每小时卖给商人：")
end


local function AuctionTile(items, seconds, what)
	local copper, unpriced, sources = TotalValue(items, AuctionPrice)
	local priced = next(sources) ~= nil
	local tip = "需要 Auctionator 或 TradeSkillMaster，并已在拍卖行扫描过价格。"
	if priced then
		tip = "的拍卖价值，按每小时钓鱼计算。价格来自 " .. what .. "拍卖价值（每小时钓鱼）：\n\n价格来源：" .. PriceSources(sources)
			.. (unpriced and "部分物品没有拍卖价，未计入。" or "")
	elseif #Stats.PriceSources() > 0 then
		local names = {}
		for _, source in ipairs(Stats.PriceSources()) do
			names[#names + 1] = source.name
		end
		tip = "尚无拍卖价：" .. what .. "。价格插件：" .. table.concat(names, ", ")
			.. "。在拍卖行扫描以补全价格。"
	end
	return Tile(priced and copper > 0 and seconds and seconds >= 60 and ShortGold(copper / seconds * 3600),
		"拍卖价/时", tip)
end

-- What items are worth, to a vendor and at auction: "1g 73s vendor  ·  9g 75s AH".
local function WorthText(items)
	local vendor, missing = TotalValue(items, VendorPrice)
	local text = Coins(vendor) .. GREY .. (missing and " 商人（加载中）|r" or " 商人|r")
	local ah, _, sources = TotalValue(items, AuctionPrice)
	if next(sources) then
		text = text .. SEP .. Coins(ah) .. GREY .. " 拍卖|r"
	elseif next(items) and ns.Prices and ns.Prices.CanScan() then
		text = text .. SEP .. GREY .. "请在拍卖行扫描|r"
	end
	return text
end

-- About how long `catches` more will take, at this session's pace (or your usual one).
local function CatchesAndTime(catches)
	local text = string.format("约 %d 次钓获", catches, catches == 1 and "" or "es")
	local rate = PerHour(Session()) or PerHour(charDB.lifetime)
	if rate and rate > 0 then
		text = text .. GREY .. "  (" .. ShortDuration(catches / rate * 3600) .. ")|r"
	end
	return text
end

-- What a stack is worth, short: at auction if a price addon has it, else the vendor's. "" if nothing.
local function StackWorth(itemID, count)
	local price = AuctionPrice(itemID) or VendorPrice(itemID)
	if not price or price <= 0 then
		return ""
	end
	return "  " .. ShortGold(price * count)
end

-- Items as rows with their count, share of the catch and worth: "x43  77%  1.2g".
local function ShareRows(items)
	local list = SortedItems(items)
	local total = ItemTotal(items)
	for _, r in ipairs(list) do
		r.right = string.format("x%d" .. GREY .. "  %d%%|r", r.count, math.floor(r.count / math.max(total, 1) * 100 + 0.5))
			.. StackWorth(r.id, r.count)
	end
	return list
end

-- The catch's rows with what each container held under it, indented: { child = true }, the last
-- of each { last = true }, for the list to draw as a tree.
local function WithContents(rows, totals)
	local out = {}
	for _, r in ipairs(rows) do
		out[#out + 1] = r
		local held = totals.inside and totals.inside[r.id]
		if held then
			local children = SortedItems(held)
			for i, c in ipairs(children) do
				c.icon = c.icon or C_Item.GetItemIconByID(c.id)
				c.child, c.last = true, i == #children
				c.right = string.format("x%d", c.count) .. StackWorth(c.id, c.count)
				out[#out + 1] = c
			end
		end
	end
	return out
end

-- What was inside what you opened, under the catch: "x2  inside  45s". For what was opened
-- before OneCast kept it by container.
local function ContentRows(totals)
	local list = SortedItems(totals.contents or {})
	for _, r in ipairs(list) do
		r.icon = r.icon or C_Item.GetItemIconByID(r.id)
		r.right = string.format("x%d" .. GREY .. "  inside|r", r.count) .. StackWorth(r.id, r.count)
	end
	return list
end

-- Each spot in a zone, best fish per hour first: { name, icon, right, spot, zone }.
local function SpotRows(z, zone)
	local rows = {}
	for name, t in pairs(z.spots or {}) do
		if t.casts > 0 then
			local topID, topCount
			for id, item in pairs(t.items) do
				if not topCount or item.count > topCount then
					topID, topCount = id, item.count
				end
			end
			local rate = PerHour(t)
			rows[#rows + 1] = { name = name, spot = t, zone = zone, rate = rate,
				icon = topID and C_Item.GetItemIconByID(topID) or "Interface\\Icons\\INV_Misc_Fish_68",
				right = string.format("%d 条%s", t.catches, rate and string.format("  %.0f/时", rate) or "") }
		end
	end
	table.sort(rows, function(a, b)
		if (a.rate or -1) ~= (b.rate or -1) then
			return (a.rate or -1) > (b.rate or -1)
		end
		return a.spot.catches > b.spot.catches
	end)
	return rows
end

-- Where one item has been caught, best rate first: zones, and spots (each with its zone).
local function PlacesFor(itemID)
	local zones, spots = {}, {}
	local function ByRate(a, b)
		if (a.rate or -1) ~= (b.rate or -1) then
			return (a.rate or -1) > (b.rate or -1)
		end
		return a.count > b.count
	end
	for zoneName, z in pairs(charDB.zoneStats) do
		local item = z.items and z.items[itemID]
		if item and item.count > 0 then
			zones[#zones + 1] = { name = zoneName, count = item.count, rate = Rate(item.count, z.activeTime) }
		end
		for spotName, t in pairs(z.spots or {}) do
			local s = t.items and t.items[itemID]
			if s and s.count > 0 then
				spots[#spots + 1] = { name = spotName, zone = zoneName, spot = t, count = s.count,
					rate = Rate(s.count, t.activeTime) }
			end
		end
	end
	table.sort(zones, ByRate)
	table.sort(spots, ByRate)
	return zones, spots
end

local function PlaceText(place)
	if not place then
		return GREY .. "-|r"
	end
	return place.name .. GREY .. "  " .. (place.rate and string.format("%.0f/时", place.rate) or ("x" .. place.count)) .. " 脱钩|r"
end

-- Returns a view's section title, summary pairs, item rows, list title and empty-list text.
-- A row is { id, name, icon, quality, right } where `right` is the right-hand text; spot rows
-- have `spot` and `zone`, fish to pick have `pick`, fish not caught yet have `missing`.
local function SessionTitle(s)
	return "会话  " .. Stats.FormatDuration(s.start and GetServerTime() - s.start or 0)
end

-- Now: this session, your skill's progress, and what's biting.
local function NowView(zone)
	local s = Session()
	local rank, maxRank = FishingSkill()
	local gained = SkillGained(s)
	local rate = PerHour(s)
	local skillRate = gained > 0 and Rate(gained, s.activeTime)
	-- What's priced: the catch, with what was inside what you opened in place of the containers.
	local worth, what = Worth(s), WhatCaught(s)
	-- The fish an hour, against your best.
	local best = charDB.bests and charDB.bests.rate
	local rateTip = "本次会话每小时钓获数。超过 2 分钟的间隔不计入。"
	if best then
		rateTip = rateTip .. string.format("\n\n你的最佳：%.0f/时，%s%s。", best.value, date("%d %b %Y", best.time) or "?",
			best.zone and ("，地点：" .. best.zone) or "")
		if rate and s.activeTime >= BEST_MIN_TIME then
			rateTip = rateTip .. (rate >= best.value and "\n本次会话是你的最佳记录。"
				or string.format("\n占你的最佳：%.0f%%。", rate / best.value * 100))
		end
	end
	local tiles = {
		Tile(rate and string.format("%.0f", rate), "鱼/时", rateTip),
		VendorTile(worth, s.activeTime, what),
		AuctionTile(worth, s.activeTime, what),
	}

	-- Caught, and how many got away: the share of bites lost says if the zone's too much for you.
	local caught = string.format("%d / %d 次抛竿", s.catches, s.casts)
	local escapes = s.escapes or 0
	if escapes > 0 then
		caught = caught .. SEP .. RED .. string.format("%d 次脱钩（%d%%）", escapes,
			math.floor(escapes / math.max(escapes + s.catches, 1) * 100 + 0.5)) .. " 脱钩|r"
	end
	local stats = { { "钓获", caught } }
	-- What's new for the collection this session, each fish on hover.
	local news = Stats.SessionNew(s)
	if #news > 0 then
		stats[#stats + 1] = { "图鉴新鱼", GREEN .. #news .. " new|r", {
			tip = function(tooltip)
				tooltip:SetText("图鉴新鱼")
				for _, n in ipairs(news) do
					local color = Stats.QualityColor(n.quality)
					tooltip:AddLine((n.icon and ("|T" .. n.icon .. ":14:14|t ") or "") .. (color and color.hex or "|cffffffff")
						.. (n.name or "?") .. " 脱钩|r", 1, 1, 1)
				end
				tooltip:AddLine(" ")
				tooltip:AddLine("点击：打开图鉴", 0.6, 0.8, 1)
			end,
			click = function()
				if ns.Book then
					ns.Book.Show()
					if news[1] then
						ns.Book.ShowFish(news[1].id)
					end
				end
			end,
		} }
	end
	if rank then
		stats[#stats + 1] = { "技能提升", (gained > 0 and (GREEN .. "+" .. gained .. " 脱钩|r") or "+0")
			.. (skillRate and (SEP .. string.format("%.0f/时", skillRate)) or "") }
	end
	if rank and rank >= maxRank then
		stats[#stats + 1] = { "技能上限", GREY .. "已达 " .. maxRank .. "：需学习新等级才能继续提升|r" }
	elseif rank then
		stats[#stats + 1] = { "下一点", CatchesAndTime(CatchesToGo(rank, 1)) }
		stats[#stats + 1] = { "升至 " .. maxRank, CatchesAndTime(CatchesToGo(rank, maxRank - rank)) }
	end
	-- What it's worth, vendor and auction in one row.
	stats[#stats + 1] = { "价值", WorthText(worth) }
	local contest = ns.Extravaganza and ns.Extravaganza.StatusLine(zone)
	if contest then
		stats[#stats + 1] = { "钓鱼大赛", contest }
	end
	local camp = ns.Camp and ns.Camp.StatusText()
	if camp then
		stats[#stats + 1] = { "营地", GREEN .. camp .. " 脱钩|r" }
	end

	local rows, listTitle
	if s.catches > 0 then
		rows, listTitle = ShareRows(s.items), "本次会话渔获"
		-- What was inside the trunks, crates and clams you opened: under each, as a tree.
		if s.inside then
			rows = WithContents(rows, s)
		else
			Append(rows, ContentRows(s))
		end

	else
		local z = charDB.zoneStats[zone]
		rows, listTitle = z and ShareRows(z.items) or {}, "此处以往渔获"
	end
	return SessionTitle(s), tiles, stats, rows, listTitle, "此处尚未钓到任何东西。抛竿开始吧。"
end

-- Farm, for one fish: where it comes up most, and how it's going here.
local function FarmTargetView(itemID, zone)
	local life = charDB.lifetime.items[itemID]
	local name = life and life.name or C_Item.GetItemNameByID(itemID) or ("物品 " .. itemID)
	local color = Stats.QualityColor(life and life.quality or C_Item.GetItemQualityByID(itemID))
	local zones, spots = PlacesFor(itemID)

	local z = charDB.zoneStats[zone]
	local hereCount = z and z.items[itemID] and z.items[itemID].count or 0
	local hereRate = z and Rate(hereCount, z.activeTime)
	local share = z and hereCount > 0 and math.floor(hereCount / math.max(ItemTotal(z.items), 1) * 100 + 0.5)
	local best = zones[1]
	local tiles = {
		Tile(hereRate and string.format("%.0f", hereRate), "此处每小时",
			"你在" .. zone .. "每小时钓鱼能钓到多少条。在此钓鱼满 5 分钟后显示。"),
		Tile(share and (share .. "%"), "占此处渔获", "它占你在" .. zone .. "."),
		Tile(best and best.rate and string.format("%.0f", best.rate), "最佳每小时",
			best and ("最适合钓它的区域：" .. best.name .. ".") or "你钓到它最多的地方，按每小时计算。"),
	}

	local s = Session()
	local sessionCount = s.items[itemID] and s.items[itemID].count or 0
	local sessionRate = Rate(sessionCount, s.activeTime)
	local last = charDB.lastCaught and charDB.lastCaught[itemID]
	local price = VendorPrice(itemID)
	local ah = AuctionPrice(itemID)
	local stats = {
		{ "本次会话", "x" .. sessionCount .. (sessionRate and (SEP .. string.format("%.0f/时", sessionRate)) or "") },
		{ "最佳区域", PlaceText(zones[1]) },
		{ "最佳地点", PlaceText(spots[1]) },
		{ "已钓到", tostring(life and life.count or 0)
			.. (last and (SEP .. "最近 " .. Ago(last.time) .. GREY .. ", " .. (last.zone or "?") .. " 脱钩|r") or "") },
		{ "单价", (price and Coins(price) or "-") .. (ah and (SEP .. Coins(ah) .. GREY .. " 拍卖|r") or "") },
	}

	local icon = life and life.icon or C_Item.GetItemIconByID(itemID)
	local rows = {}
	for _, place in ipairs(spots) do
		rows[#rows + 1] = { name = place.name, spot = place.spot, zone = place.zone, icon = icon,
			label = place.name ~= place.zone and (place.name .. GREY .. "  " .. place.zone .. " 脱钩|r") or place.name,
			right = (place.rate and string.format("%.0f/时  ", place.rate) or "") .. "x" .. place.count }
	end
	local title = (color and color.hex or "|cffffffff") .. name .. " 脱钩|r"
	return title, tiles, stats, rows, "咬钩地点，最佳优先", "尚未在任何地点钓到。"
end

-- Farm: is this zone worth it, its spots, or a fish to farm.
local function FarmView(zone)
	if charDB.farmTarget then
		return FarmTargetView(charDB.farmTarget, zone)
	end
	local z = charDB.zoneStats[zone] or NewTotals()
	local rate = PerHour(z)
	local spots = SpotRows(z, zone)
	local bestSpot = spots[1]
	local tiles = {
		Tile(rate and string.format("%.0f", rate), "此处鱼/时",
			"你在" .. zone .. "."),
		GoldTile(z.items, z.activeTime, "此处的渔获"),
		Tile(bestSpot and bestSpot.rate and string.format("%.0f", bestSpot.rate), "最佳地点/时",
			bestSpot and ("此处最佳地点：" .. bestSpot.name .. ".") or "此处最佳地点，按每小时计算。"),
	}
	local caught = tostring(z.catches) .. SEP .. Stats.FormatDuration(z.activeTime) .. " 钓鱼"
	if (z.escapes or 0) > 0 then
		caught = caught .. SEP .. RED .. z.escapes .. " 次脱钩|r"
	end
	local stats = {
		{ "此处钓获", caught },
		{ "最佳地点", bestSpot and bestSpot.name or (GREY .. "-|r") },
		{ "价值", WorthText(z.items) },
	}

	if charDB.farmList == "fish" then
		local rows = SortedItems(charDB.lifetime.items)
		for _, r in ipairs(rows) do
			local best = PlacesFor(r.id)[1]
			r.pick = true
			r.right = best and (best.name .. GREY .. "  " .. (best.rate and string.format("%.0f/时", best.rate) or ("x" .. best.count)) .. " 脱钩|r")
				or ("x" .. r.count)
		end
		return zone, tiles, stats, rows, "选择要刷的鱼", "尚未钓到任何东西。"
	end
	return zone, tiles, stats, spots, "此处地点，最佳优先", "此处暂无地点记录。抛竿开始吧。"
end

-- Records: personal bests, the notable catches, and lifetime totals.
local function BestTip(text, best)
	if not best then
		return text .. "单次会话钓鱼满 15 分钟后记录。"
	end
	return text .. string.format("创下于 %s%s。", date("%d %b %Y", best.time), best.zone and ("，地点：" .. best.zone) or "")
end

local function RecordsView()
	local life = charDB.lifetime
	local bests = charDB.bests or {}
	local tiles = {
		Tile(bests.rate and string.format("%.0f", bests.rate.value), "最高鱼/时",
			BestTip("单次会话中每小时钓获最多的纪录。", bests.rate)),
		Tile(bests.vendor and ShortGold(bests.vendor.value), "最高金币/时",
			BestTip("单次会话中每小时商人售价最高的纪录。", bests.vendor)),
		Tile(bests.skill and (GREEN .. "+" .. bests.skill.value .. " 脱钩|r"), "最多技能提升",
			BestTip("单次会话中钓鱼技能提升最多的纪录。", bests.skill)),
	}
	local rate = PerHour(life)
	local stats = {
		{ "已钓鱼数", tostring(life.catches) .. (rate and (SEP .. string.format("%.0f/时", rate)) or "") },
		{ "钓鱼时间", Stats.FormatDuration(life.activeTime) },
		{ "最长会话", bests.time and (Stats.FormatDuration(bests.time.value) .. GREY .. "  " .. date("暂无记录。稀有渔获、想要的鱼和图鉴新鱼会显示在这里。", bests.time.time) .. " 脱钩|r")
			or (GREY .. "-|r") },
	}
	local zonesText = CountKeys(life.zones) .. " 个区域钓过"
	if ns.Collection then
		local caught, total = ns.Collection.Progress()
		stats[#stats + 1] = { "图鉴", string.format("%d / %d 种鱼", caught, total) .. SEP .. zonesText }
	else
		stats[#stats + 1] = { "区域", zonesText }
	end
	local rows = {}
	if charDB.recordsList == "sessions" then
		-- Recent sessions: when and where, catches and fish per hour; the rest in the tooltip.
		for i, h in ipairs(charDB.history or {}) do
			local rate = h.time and h.time >= 60 and h.catches / h.time * 3600
			rows[i] = { icon = h.top and C_Item.GetItemIconByID(h.top) or 133888, session = h,
				name = (h.start and date("%a %d %b", h.start) or "?") .. GREY .. "  " .. (h.zone or "?") .. " 脱钩|r",
				right = tostring(h.catches) .. (rate and (SEP .. string.format("%.0f/时", rate)) or "") }
		end
		return "历史记录", tiles, stats, rows, "最近会话",
			"暂无已结束的会话。重置时结束（「重置会话」按钮，或 /onecast reset）。"
	end
	for i, e in ipairs(charDB.notable or {}) do
		rows[i] = { id = e.id, icon = e.icon, quality = e.quality, right = date("暂无记录。稀有渔获、想要的鱼和图鉴新鱼会显示在这里。", e.time),
			name = (e.name or "?") .. (e.quantity and e.quantity > 1 and (" x" .. e.quantity) or ""),
			note = (e.why == "new" and "图鉴新鱼。" or e.why == "wanted" and "想要的鱼。" or "")
				.. "钓于" .. (e.zone or "?") .. ", " .. date("%d %b %H:%M", e.time) .. "." }
	end
	return "历史记录", tiles, stats, rows, "值得纪念的渔获",
		"暂无记录。稀有渔获、想要的鱼和图鉴新鱼会显示在这里。"
end

-- The tabs' names in /onecast commands.
local VIEW_ALIAS = { spots = "farm", alltime = "records" }
local function CurrentView()
	local view = charDB.view or "session"
	view = VIEW_ALIAS[view] or view
	if view ~= "farm" and view ~= "records" then
		view = "session"
	end
	return view
end

local function BuildView(view)
	local zone = CurrentZone()
	if view == "farm" then
		return FarmView(zone)
	elseif view == "records" then
		return RecordsView()
	end
	return NowView(zone)
end

-- What's known about fishing in a zone, for this character. `kind` is:
--   "note"     a reported quirk (ZONE_FISHING_NOTE), until a fish gets away there
--   "getaways" fish have got away here at this skill or higher, whatever the level says
--   "outgrown" no known level, and fish got away, but only at lower skill than this
--   "clear"    no known level, and 10 or more catches with no getaways
--   "unknown"  no known level, and too little to go on
--   "level"    a known level, but this character's skill can't be read
--   "ok"       skill meets the known level
--   "short"    skill is `short` points below the known level
-- Shared by the stats window and the book's Zones view, so the two can't disagree. `spot`,
-- the sub-zone you're standing in, uses its own level where it has one (SPOT_FISHING_SKILL);
-- `place` is then the spot's name rather than the zone's.
function Stats.ZoneStatus(zone, spot)
	local rank, _, modifier = FishingSkill()
	local here = charDB.zoneStats[zone]
	-- Enough catches in a row since the last getaway and it no longer counts against the zone:
	-- it could have come from a lure's bonus, or from before a skill-up.
	local cleared = here and (here.cleanCatches or 0) >= CLEAN_CATCHES
	local spotNeeded = spot and ns.SPOT_FISHING_SKILL and ns.SPOT_FISHING_SKILL[spot]
	local status = {
		place = spotNeeded and spot or zone,
		needed = spotNeeded or ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone],
		note = ns.ZONE_FISHING_NOTE and ns.ZONE_FISHING_NOTE[zone],
		escapes = not cleared and here and here.escapes or 0,
		catches = here and here.catches or 0,
		escapeSkill = not cleared and here and here.escapeSkill or nil, -- nil for getaways from before 0.5.0
	}
	local effective = rank and rank + modifier
	local outgrown = status.escapeSkill and effective and effective > status.escapeSkill
	if status.note and status.escapes == 0 then
		-- A reported quirk, not a measured level, so it gives way to real getaways.
		status.kind = "note"
	elseif not status.needed then
		-- No data for this zone: judge from what has actually happened here.
		if outgrown then
			status.kind = "outgrown"
		elseif status.escapes > 0 then
			status.kind = "getaways"
		elseif status.catches >= 10 then
			status.kind = " 种鱼|r"
		else
			status.kind = "unknown"
		end
	elseif not rank then
		status.kind = "level"
	elseif effective >= status.needed then
		-- The level is Classic's: a getaway at this skill or higher says Forever's is higher.
		if status.escapeSkill and effective <= status.escapeSkill then
			status.kind = "getaways"
		else
			status.kind = "ok"
		end
	else
		status.kind = "short"
		status.short = status.needed - rank - modifier
	end
	return status
end

-- The zone's status as a coloured sentence, for dark backgrounds.
function Stats.ZoneVerdict(zone, spot)
	local rank, maxRank = FishingSkill()
	if not rank then
		return GREY .. "未找到钓鱼技能。|r"
	end
	local status = Stats.ZoneStatus(zone, spot)
	zone = status.place
	if status.kind == "note" then
		return string.format("|cff20ff20%s: %s.|r", zone, status.note)
	elseif status.kind == "getaways" and status.needed then
		return string.format("|cffff4040%s 标注需要 %d，但在 %d 技能时此处仍脱钩：实际可能更高。|r",
			zone, status.needed, status.escapeSkill)
	elseif status.kind == "getaways" then
		return string.format("|cffff4040%s：等级未知，但此处已脱钩 %d 次：技能不足。|r",
			zone, status.escapes)
	elseif status.kind == "outgrown" then
		return string.format("%s%s：等级未知。此前在 %d 技能时脱钩过，你现在已超过该技能。|r",
			GREY, zone, status.escapeSkill)
	elseif status.kind == " 种鱼|r" then
		return string.format("|cff1eff00%s：等级未知，但 %d 次钓获均未脱钩。|r",
			zone, status.catches)
	elseif status.kind == "unknown" then
		return GREY .. zone .. "：钓鱼等级未知。若此处脱钩，会提示技能是否不足。|r"
	elseif status.kind == "ok" then
		return string.format("|cff1eff00%s 需要 %d：鱼不应脱钩。|r", zone, status.needed)
	end
	-- A lure in the bags that would close the gap is the more useful thing to say.
	local hint = ns.Lure and ns.Lure.CoverHint(status.short)
	if hint then
		return string.format("|cffff4040%s 需要 %d：还差 %d，鱼会脱钩。|r |cffffd100%s|r",
			zone, status.needed, status.short, hint)
	end
	return string.format("|cffff4040%s 需要 %d：还差 %d，鱼会脱钩。|r %s约还需 %d 次钓获%s。|r",
		zone, status.needed, status.short, GREY, CatchesToGo(rank, status.short),
		rank + status.short > maxRank and "（请先学技能）" or "")
end

-- The zone's status in short parts, for the strip under the skill bar: `mood` ("good", "bad",
-- "warn" or "unknown"), the place, what it needs, and a word or two on how you stand. The full
-- sentence (ZoneVerdict) goes in its tooltip.
function Stats.ZoneBadge(zone, spot)
	local status = Stats.ZoneStatus(zone, spot)
	local badge = { place = status.place, needed = status.needed }
	local kind = status.kind
	if status.needed and kind ~= "getaways" then
		badge.need = "需要 " .. status.needed
	elseif status.needed then
		badge.need = "标注 " .. status.needed
	elseif kind ~= "note" then
		badge.need = "等级未知"
	end
	if kind == "ok" then
		badge.mood, badge.status = "good", "已就绪"
	elseif kind == "short" then
		if ns.Lure and ns.Lure.CoverHint(status.short) then
			badge.mood, badge.status = "warn", status.short .. "还差 " -- yellow: a lure in your bags covers it
		else
			badge.mood, badge.status = "bad", status.short .. "还差 "
		end
	elseif kind == "getaways" then
		badge.mood, badge.status = "bad", "鱼会脱钩"
	elseif kind == " 种鱼|r" then
		badge.mood, badge.status = "good", "无脱钩"
	elseif kind == "note" then
		badge.mood, badge.status = "good", "无要求"
	elseif kind == "outgrown" then
		badge.mood, badge.status = "unknown", "已超过上次脱钩"
	elseif kind == "level" then
		badge.mood, badge.status = "unknown", "技能未知"
	else
		badge.mood, badge.status = "unknown", "未知"
	end
	return badge
end

Stats.FishingSkill = FishingSkill
Stats.CatchesToGo = CatchesToGo
Stats.CurrentZone = CurrentZone

-- Skill bar fraction and value text.
local function SkillStatus()
	local rank, maxRank, modifier = FishingSkill()
	if not rank then
		return 0, "?"
	end
	local value = modifier > 0 and string.format("%d|cff20ff20+%d|r/%d", rank, modifier, maxRank)
		or string.format("%d/%d", rank, maxRank)
	return rank / math.max(maxRank, 1), value
end

local function SelectView(view)
	charDB.view = view
	Stats.Refresh()
end

-- Window ----------------------------------------------------------------------------
-- Built from Blizzard's own templates (portrait frame, inset, red panel buttons, top tabs,
-- character-sheet section headers), so it wears Forever's bronze skin like the native
-- Options and Character windows. Each template falls back to a plain look if missing.

local function TryCreate(frameType, name, parent, template)
	local ok, f = pcall(CreateFrame, frameType, name, parent, template)
	if ok then
		return f
	end
end

local function HasAtlas(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function SetTitle(f, text)
	if f.SetTitle then
		f:SetTitle(text)
	elseif f.TitleContainer and f.TitleContainer.TitleText then
		f.TitleContainer.TitleText:SetText(text)
	elseif f.TitleText then
		f.TitleText:SetText(text)
	end
end

-- Share of the portrait circle the icon fills. A square fits wholly inside a circle at
-- 1/sqrt(2) of its diameter, so nothing of the picture is cut off.
local PORTRAIT_ICON_SCALE = 0.7

local function SetPortrait(f, texture)
	-- Black circle in the portrait, the icon drawn smaller on top, so the whole picture shows
	-- inside the ring instead of the icon being cropped to the circle.
	local portrait = (f.PortraitContainer and f.PortraitContainer.portrait) or f.portrait
	if portrait and portrait.GetParent then
		local holder = portrait:GetParent()
		local layer, sublevel = portrait:GetDrawLayer()
		portrait:SetColorTexture(0, 0, 0, 1)
		local icon = holder:CreateTexture(nil, layer, nil, math.min(7, (sublevel or 0) + 1))
		icon:SetPoint("CENTER", portrait)
		local width = portrait:GetWidth()
		local size = (width > 10 and width or 60) * PORTRAIT_ICON_SCALE -- templates use 60
		icon:SetSize(size, size)
		icon:SetTexture(texture)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's own bevelled border
		-- Masked to the portrait's own circle, not the icon's, so only the ring bounds it.
		local mask = holder:CreateMaskTexture()
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(portrait)
		icon:AddMaskTexture(mask)
		return
	end
	if f.SetPortraitToAsset then
		f:SetPortraitToAsset(texture)
	elseif f.portrait and SetPortraitToTexture then
		SetPortraitToTexture(f.portrait, texture)
	end
end
ns.SetPortrait = SetPortrait -- shared with the collection book

-- The game's close button (X) closes its window through the game's panel manager (HideUIPanel),
-- which an addon's window can't use in combat: "Interface action failed because of an AddOn".
-- A window's own close callback comes first; this one just hides the window, which is fine then.
local function CloseOwn(frame)
	frame.onCloseCallback = function()
		frame:Hide()
		return false -- closed: the panel manager isn't needed
	end
end

local function CreateShell(name, titleText, icon)
	local f = TryCreate("Frame", name, UIParent, "ButtonFrameTemplate")
	if f then
		CloseOwn(f)
		SetTitle(f, titleText)
		SetPortrait(f, icon)
		f.Inset:ClearAllPoints()
		f.Inset:SetPoint("TOPLEFT", 4, -60)
		f.Inset:SetPoint("BOTTOMRIGHT", -6, 28)
		return f, f.Inset
	end

	-- Fallback: classic dialog frame with a plain inset.
	f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	CloseOwn(f)
	f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 } })
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -12)
	title:SetText(titleText)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	f.CloseButton = close
	local inset = TryCreate("Frame", nil, f, "InsetFrameTemplate") or CreateFrame("Frame", nil, f)
	inset:SetPoint("TOPLEFT", 10, -60)
	inset:SetPoint("BOTTOMRIGHT", -10, 32)
	return f, inset
end

-- Profession rank bar, after Forever's professions window: gold title above a blue bar
-- with "Fishing 188/225" centred on it and a bright glint at the fill's edge. Recreated
-- here because Blizzard's bar belongs to its professions UI. Animated: the glint pulses,
-- a shine sweeps along the fill now and then, and a skill-up slides the bar and flashes.
local RANK_BLUE = { 0.16, 0.36, 0.86 }
local SHINE_EVERY = 4    -- seconds between shine sweeps
local GROW_TIME = 0.6    -- seconds for the bar to slide to a new rank

-- Forever's own profession rank bar, for Fishing: the professions window's frame and backing,
-- with Fishing's animated water fill (a 60-frame flipbook) and the bright flare at its edge,
-- revealed up to your skill by the bar's mask. Built from the game's atlases, after
-- Blizzard_ProfessionsRankBar.xml, since that template belongs to the professions UI.
local WATER_FILL, WATER_FLARE = "Skillbar_Fill_Flipbook_Fishing", "Skillbar_Flare_Fishing"
local WATER_FRAME_HEIGHT = 34 -- each flipbook frame's height in the atlas
local WATER_SLIDE_TIME = 0.5

local function WaterBar(parent, name)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("TOPLEFT", EDGE, BAR_TOP)
	holder:SetPoint("TOPRIGHT", -EDGE, BAR_TOP)
	holder:SetHeight(BAR_HEIGHT)

	local back = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	back:SetAtlas("Professions-skillbar-bg")
	back:SetPoint("TOPLEFT")
	back:SetPoint("BOTTOMRIGHT")

	local fill = holder:CreateTexture(nil, "ARTWORK", nil, 2)
	fill:SetAtlas(WATER_FILL)
	fill:SetPoint("TOPLEFT", 5, -3)
	fill:SetPoint("TOPRIGHT", -7, -3)
	fill:SetHeight(18)

	local flare = holder:CreateTexture(nil, "ARTWORK", nil, 2)
	flare:SetSize(53, 16)
	flare:SetBlendMode("ADD")
	if HasAtlas(WATER_FLARE) then
		flare:SetAtlas(WATER_FLARE)
	else
		flare:Hide()
	end

	-- A flash over the water on a skill-up.
	local surge = holder:CreateTexture(nil, "ARTWORK", nil, 2)
	surge:SetAllPoints(fill)
	surge:SetTexture("Interface\\Buttons\\WHITE8x8")
	surge:SetBlendMode("ADD")
	surge:SetVertexColor(0.55, 0.85, 1)
	surge:SetAlpha(0)

	-- The mask shows the water up to your skill; it has its own soft right edge.
	local mask = holder:CreateMaskTexture()
	mask:SetAtlas("Professions-skillbar-mask", true, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetPoint("LEFT", fill, "LEFT", 1, 0)
	fill:AddMaskTexture(mask)
	flare:AddMaskTexture(mask)
	surge:AddMaskTexture(mask)
	flare:SetPoint("RIGHT", mask, "RIGHT", 0, 0)

	local border = holder:CreateTexture(nil, "ARTWORK", nil, 3)
	border:SetAtlas("Professions-skillbar-frame")
	border:SetPoint("TOPLEFT")
	border:SetPoint("BOTTOMRIGHT")

	local textHolder = CreateFrame("Frame", nil, holder)
	textHolder:SetAllPoints(fill)
	textHolder:SetFrameLevel(holder:GetFrameLevel() + 5)
	local text = textHolder:CreateFontString(nil, "OVERLAY", Number12FontOutline and "Number12FontOutline" or "OneCastFontHighlightSmall")
	text:SetPoint("CENTER", 0, 0)

	-- The water flows on a loop while the window is open (hidden frames don't animate).
	local flow = holder:CreateAnimationGroup()
	flow:SetLooping("REPEAT")
	local flipbook = flow:CreateAnimation("FlipBook")
	flipbook:SetTarget(fill)
	flipbook:SetDuration(2)
	flipbook:SetFlipBookColumns(2)
	flipbook:SetFlipBookFrameWidth(0)
	flipbook:SetFlipBookFrameHeight(0)

	-- Fishing's own water: a flipbook of 2 columns of 34-pixel frames.
	do
		fill:SetAtlas(WATER_FILL)
		local info = C_Texture.GetAtlasInfo(WATER_FILL)
		local rows = info and info.height and math.max(1, math.floor(info.height / WATER_FRAME_HEIGHT + 0.5)) or 30
		flipbook:SetFlipBookRows(rows)
		flipbook:SetFlipBookFrames(rows * 2)
		if HasAtlas(WATER_FLARE) then
			flare:SetAtlas(WATER_FLARE)
		end
		surge:SetVertexColor(0.55, 0.85, 1)
		if not ns.ReduceMotion() then
			flow:Play()
		end
	end

	local flash = surge:CreateAnimationGroup()
	local flashIn = flash:CreateAnimation("Alpha")
	flashIn:SetFromAlpha(0)
	flashIn:SetToAlpha(0.6)
	flashIn:SetDuration(0.15)
	flashIn:SetOrder(1)
	local flashOut = flash:CreateAnimation("Alpha")
	flashOut:SetFromAlpha(0.6)
	flashOut:SetToAlpha(0)
	flashOut:SetDuration(0.9)
	flashOut:SetSmoothing("OUT")
	flashOut:SetOrder(2)

	local current, target, from, started
	local function Place(fraction)
		-- As Blizzard's bar: the mask is the bar's width times your progress.
		mask:SetWidth(math.max(1, holder:GetWidth() * fraction))
		flare:SetShown(fraction > 0.01 and fraction < 1 and HasAtlas(WATER_FLARE))
	end
	local function Slide(self)
		local t = math.min(1, (GetTime() - started) / WATER_SLIDE_TIME)
		current = from + (target - from) * (1 - (1 - t) ^ 3)
		Place(current)
		if t >= 1 then
			started = nil
			self:SetScript("OnUpdate", nil)
		end
	end

	function holder:SetRank(fraction, valueText)
		text:SetText(name .. " " .. valueText)
		if target == fraction then
			return
		end
		if target and fraction > target and not ns.ReduceMotion() then
			flash:Stop()
			flash:Play()
		end
		from = current or 0
		target = fraction
		if ns.ReduceMotion() then
			current = fraction -- straight there
			Place(fraction)
			return
		end
		started = GetTime()
		self:SetScript("OnUpdate", Slide)
	end

	holder:SetScript("OnSizeChanged", function()
		if current then
			Place(current)
		end
	end)
	holder:HookScript("OnShow", function()
		if ns.ReduceMotion() then
			flow:Stop()
		elseif not flow:IsPlaying() then
			flow:Play()
		end
	end)
	holder.water = true
	return holder
end

local function RankBar(parent, name)
	if HasAtlas(WATER_FILL) and HasAtlas("Professions-skillbar-frame") and HasAtlas("Professions-skillbar-mask") then
		return WaterBar(parent, name)
	end
	-- Without those atlases: a bar of our own in the same spirit.
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("TOPLEFT", EDGE, BAR_TOP)
	holder:SetPoint("TOPRIGHT", -EDGE, BAR_TOP)
	holder:SetHeight(BAR_HEIGHT)

	local frameBorder = CreateFrame("Frame", nil, holder, "BackdropTemplate")
	frameBorder:SetAllPoints()
	frameBorder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1 })
	frameBorder:SetBackdropColor(0.02, 0.02, 0.03, 0.9)
	frameBorder:SetBackdropBorderColor(0.55, 0.55, 0.58, 1)

	local bar = CreateFrame("StatusBar", nil, frameBorder)
	bar:SetPoint("TOPLEFT", 2, -2)
	bar:SetPoint("BOTTOMRIGHT", -2, 2)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(RANK_BLUE[1], RANK_BLUE[2], RANK_BLUE[3])
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local fill = bar:GetStatusBarTexture()

	-- Sheen on the top half of the fill, so it reads as glass rather than flat.
	local sheen = bar:CreateTexture(nil, "ARTWORK", nil, 1)
	sheen:SetTexture("Interface\\Buttons\\WHITE8x8")
	sheen:SetPoint("TOPLEFT", fill, "TOPLEFT")
	sheen:SetPoint("BOTTOMRIGHT", fill, "RIGHT")
	if sheen.SetGradient and CreateColor then
		sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.22))
	else
		sheen:SetVertexColor(1, 1, 1, 0.1)
	end

	-- Shine: a soft white band that sweeps along the fill, clipped to it.
	local clip = CreateFrame("Frame", nil, bar)
	clip:SetPoint("TOPLEFT", fill, "TOPLEFT")
	clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	clip:SetClipsChildren(true)
	local shine = CreateFrame("Frame", nil, clip)
	shine:SetSize(40, 20)
	shine:SetPoint("RIGHT", clip, "LEFT")
	for i, alphas in ipairs({ { 0, 0.35 }, { 0.35, 0 } }) do
		local half = shine:CreateTexture(nil, "OVERLAY")
		half:SetTexture("Interface\\Buttons\\WHITE8x8")
		half:SetBlendMode("ADD")
		half:SetSize(20, 20)
		half:SetPoint("LEFT", (i - 1) * 20, 0)
		if half.SetGradient and CreateColor then
			half:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, alphas[1]), CreateColor(1, 1, 1, alphas[2]))
		else
			half:SetVertexColor(1, 1, 1, 0.15)
		end
	end
	local sweep = shine:CreateAnimationGroup()
	local move = sweep:CreateAnimation("Translation")
	move:SetDuration(1.1)
	move:SetSmoothing("IN_OUT")
	sweep:SetScript("OnFinished", function()
		C_Timer.After(SHINE_EVERY, function()
			local width = fill:GetWidth()
			if holder:IsVisible() and width > 30 and ns.ReduceMotion() then
				sweep:GetScript("OnFinished")() -- not now: look again later
			elseif holder:IsVisible() and width > 30 then
				move:SetOffset(width + 40, 0)
				sweep:Play()
			elseif holder:IsVisible() then
				sweep:GetScript("OnFinished")()
			else
				holder.sweeping = false
			end
		end)
	end)

	-- Glint at the edge of the fill, gently pulsing.
	local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetBlendMode("ADD")
	spark:SetSize(20, 34)
	spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
	local pulse = spark:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.45)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	pulse:Play()

	-- Flash over the whole bar on a skill-up.
	local glow = bar:CreateTexture(nil, "OVERLAY", nil, 3)
	glow:SetAllPoints(fill)
	glow:SetTexture("Interface\\Buttons\\WHITE8x8")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(0.6, 0.8, 1, 1)
	glow:SetAlpha(0)
	local flash = glow:CreateAnimationGroup()
	local flashIn = flash:CreateAnimation("Alpha")
	flashIn:SetFromAlpha(0)
	flashIn:SetToAlpha(0.7)
	flashIn:SetDuration(0.15)
	flashIn:SetOrder(1)
	local flashOut = flash:CreateAnimation("Alpha")
	flashOut:SetFromAlpha(0.7)
	flashOut:SetToAlpha(0)
	flashOut:SetDuration(0.8)
	flashOut:SetOrder(2)

	local text = bar:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	text:SetPoint("CENTER", 0, 0)
	text:SetShadowOffset(1, -1)

	-- Slide towards the target rank rather than jumping.
	local current, target, from, started
	local function Slide(self)
		local t = math.min(1, (GetTime() - started) / GROW_TIME)
		current = from + (target - from) * (1 - (1 - t) ^ 3)
		self:SetValue(current)
		spark:SetShown(current > 0.005 and current < 0.995)
		if t >= 1 then
			started = nil
			self:SetScript("OnUpdate", nil) -- idle until the next change
		end
	end

	function holder:SetRank(fraction, valueText)
		text:SetText(name .. " " .. valueText)
		if target == fraction then
			return
		end
		if target and fraction > target then
			flash:Stop()
			flash:Play()
		end
		from = current or 0
		target = fraction
		started = GetTime()
		bar:SetScript("OnUpdate", Slide)
		if not self.sweeping then
			self.sweeping = true
			sweep:GetScript("OnFinished")()
		end
	end

	holder:HookScript("OnShow", function(self)
		if not self.sweeping and target then
			self.sweeping = true
			sweep:GetScript("OnFinished")()
		end
	end)

	return holder
end

-- Character-sheet style section header ("General", "Primary Attributes").
local function SectionHeader(parent, y)
	local h = CreateFrame("Frame", nil, parent)
	h:SetPoint("TOPLEFT", EDGE, y)
	h:SetPoint("TOPRIGHT", -EDGE, y)
	h:SetHeight(HEADER_HEIGHT)
	local bg = h:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if HasAtlas("UI-Character-Info-Title") then
		bg:SetAtlas("UI-Character-Info-Title")
	else
		bg:SetColorTexture(0.25, 0.18, 0.10, 0.9)
	end
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h.text:SetPoint("CENTER", 0, 1)
	return h
end

-- Alternating row background, as on the character sheet's stat lines.
local function RowBackground(row, index)
	if index % 2 == 0 then
		return
	end
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if HasAtlas("UI-Character-Info-Line-Bounce") then
		bg:SetAtlas("UI-Character-Info-Line-Bounce")
		bg:SetAlpha(0.3)
	else
		bg:SetColorTexture(1, 1, 1, 0.04)
	end
end

-- A headline number with a small caption under it, and a tooltip saying what it is.
local function StatTile(parent, index, top)
	local width = math.floor((INSET_WIDTH - 2 * EDGE - 2 * TILE_GAP) / 3)
	local t = CreateFrame("Frame", nil, parent)
	t:SetSize(width, TILE_HEIGHT)
	t:SetPoint("TOPLEFT", EDGE + (index - 1) * (width + TILE_GAP), top or TILES_TOP)
	t:EnableMouse(true)
	local bg = t:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if HasAtlas("UI-Character-Info-Line-Bounce") then
		bg:SetAtlas("UI-Character-Info-Line-Bounce")
		bg:SetAlpha(0.5)
	else
		bg:SetColorTexture(1, 1, 1, 0.06)
	end
	t.value = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	t.value:SetPoint("TOP", 0, -6)
	t.value:SetWidth(width - 6)
	t.value:SetWordWrap(false)
	t.caption = t:CreateFontString(nil, "OVERLAY", "OneCastFontNormalSmall")
	t.caption:SetPoint("BOTTOM", 0, 6)
	t.caption:SetWidth(width - 6)
	t.caption:SetWordWrap(false)
	t:SetScript("OnEnter", function(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.caption:GetText())
			GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	t:SetScript("OnLeave", GameTooltip_Hide)
	return t
end

-- The zone strip under the skill bar: a status icon, the place and what it needs, and how you
-- stand on the right, on a band tinted to match. Hover for the whole story.
local MOODS = {
	good = { color = { 0.12, 1, 0 }, atlas = "UI-LFG-ReadyMark", file = "Interface\\RaidFrame\\ReadyCheck-Ready" },
	bad = { color = { 1, 0.25, 0.25 }, atlas = "UI-LFG-DeclineMark", file = "Interface\\RaidFrame\\ReadyCheck-NotReady" },
	warn = { color = { 1, 0.82, 0 }, atlas = "UI-LFG-PendingMark", file = "Interface\\RaidFrame\\ReadyCheck-Waiting" },
	unknown = { color = { 0.6, 0.6, 0.6 }, atlas = "UI-LFG-PendingMark", file = "Interface\\RaidFrame\\ReadyCheck-Waiting" },
}
local PLACE_MAX_WIDTH = 150

local function ZoneStrip(parent)
	local strip = CreateFrame("Frame", nil, parent)
	strip:SetPoint("TOPLEFT", EDGE, STRIP_TOP)
	strip:SetPoint("TOPRIGHT", -EDGE, STRIP_TOP)
	strip:SetHeight(STRIP_HEIGHT)
	strip:EnableMouse(true)
	-- The window's own art: the character sheet's gilded line as the base, a glow in the mood's
	-- colour fading out from the left, and bronze hairlines above and below, like a plaque.
	strip.base = strip:CreateTexture(nil, "BACKGROUND", nil, 0)
	strip.base:SetAllPoints()
	if HasAtlas("UI-Character-Info-Line-Bounce") then
		strip.base:SetAtlas("UI-Character-Info-Line-Bounce")
		strip.base:SetAlpha(0.7)
	else
		strip.base:SetColorTexture(0, 0, 0, 0.35)
	end
	strip.band = strip:CreateTexture(nil, "BACKGROUND", nil, 1)
	strip.band:SetPoint("TOPLEFT")
	strip.band:SetPoint("BOTTOMLEFT")
	strip.band:SetPoint("RIGHT", strip, "CENTER", 40, 0)
	strip.band:SetTexture("Interface\\Buttons\\WHITE8x8")
	strip.band:SetBlendMode("ADD")
	strip.lines = {}
	for i, point in ipairs({ "TOP", "BOTTOM" }) do
		local line = strip:CreateTexture(nil, "BORDER")
		line:SetPoint(point .. "LEFT")
		line:SetPoint(point .. "RIGHT")
		line:SetHeight(1)
		line:SetColorTexture(0.62, 0.48, 0.24, 0.7)
		strip.lines[i] = line
	end
	strip.icon = strip:CreateTexture(nil, "ARTWORK")
	strip.icon:SetSize(14, 14)
	strip.icon:SetPoint("LEFT", PAD, 0)
	strip.place = strip:CreateFontString(nil, "OVERLAY", "OneCastFontNormalSmall")
	strip.place:SetPoint("LEFT", strip.icon, "RIGHT", 5, 0)
	strip.place:SetWordWrap(false)
	strip.need = strip:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	strip.need:SetTextColor(0.78, 0.78, 0.78)
	strip.need:SetPoint("LEFT", strip.place, "RIGHT", 6, 0)
	strip.need:SetWordWrap(false)
	strip.status = strip:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	strip.status:SetPoint("RIGHT", -PAD, 0)
	strip.status:SetWordWrap(false)

	function strip:Update(zone, spot)
		local badge = Stats.ZoneBadge(zone, spot)
		local mood = MOODS[badge.mood]
		local r, g, b = mood.color[1], mood.color[2], mood.color[3]
		if self.band.SetGradient and CreateColor then
			self.band:SetVertexColor(1, 1, 1, 1)
			self.band:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.22), CreateColor(r, g, b, 0))
		else
			self.band:SetVertexColor(r, g, b, 0.1)
		end
		if HasAtlas(mood.atlas) then
			self.icon:SetAtlas(mood.atlas)
		else
			self.icon:SetTexture(mood.file)
		end
		-- A long place name is cut short rather than running into the status.
		self.place:SetWidth(0)
		self.place:SetText(badge.place)
		self.need:SetText(badge.need or "")
		self.status:SetText(badge.status)
		-- The place gets what the level and status leave (before the first layout, its usual most).
		local width = self:GetWidth() or 0
		local room = width > 0 and (width - PAD - 14 - 5 - 6 - (self.need:GetStringWidth() or 0) - 12
			- (self.status:GetStringWidth() or 0) - PAD) or PLACE_MAX_WIDTH
		self.place:SetWidth(math.max(40, math.min(self.place:GetStringWidth() or 0, PLACE_MAX_WIDTH, room)))
		self.status:SetTextColor(r, g, b)
		self.badge = badge
		self.tip = Stats.ZoneVerdict(zone, spot)
	end

	strip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(self.badge and self.badge.place or "")
		local rank, _, modifier = FishingSkill()
		if self.badge and self.badge.needed then
			GameTooltip:AddDoubleLine("所需钓鱼技能", tostring(self.badge.needed), 1, 0.82, 0, 1, 1, 1)
		end
		if rank then
			GameTooltip:AddDoubleLine("你的技能", modifier > 0 and string.format("%d + %d", rank, modifier) or tostring(rank),
				1, 0.82, 0, 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(self.tip or "", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	strip:SetScript("OnLeave", GameTooltip_Hide)
	return strip
end

local function StatRowClick(self, button)
	local extra = self.extra
	if extra and extra.click and button == "LeftButton" then
		extra.click()
	end
end

local function StatRow(parent, index, y)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 10, y)
	row:SetPoint("TOPRIGHT", -10, y)
	row:SetHeight(STAT_HEIGHT)
	RowBackground(row, index)
	row.label = row:CreateFontString(nil, "OVERLAY", "OneCastFontNormalSmall") -- gold, like "Health:"
	row.label:SetPoint("LEFT", PAD, 0)
	row.value = row:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	row.value:SetPoint("RIGHT", -PAD, 0)
	row.value:SetJustifyH("RIGHT")
	-- A row with more to say (`extra`: tip and click) takes the mouse; the others don't.
	row:SetScript("OnEnter", function(self)
		local extra = self.extra
		if extra and extra.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			extra.tip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

-- Where a named area is on its zone map (ns.AREA_PLACES), by the name the game gives it in any
-- language: uiMapID, x, y, or nil. Some names are used in more than one zone, so the one on
-- `zoneMapID` wins when given. Names are matched to area IDs once, on first use.
local placesByName
function Stats.AreaPlace(name, zoneMapID)
	if not (name and ns.AREA_PLACES) then
		return nil
	end
	if not placesByName then
		placesByName = {}
		for areaID, place in pairs(ns.AREA_PLACES) do
			local areaName = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
			if areaName and areaName ~= "" then
				placesByName[areaName] = placesByName[areaName] or {}
				table.insert(placesByName[areaName], place)
			end
		end
	end
	local list = placesByName[name]
	if not list then
		return nil
	end
	local place = list[1]
	for _, candidate in ipairs(list) do
		if candidate[1] == zoneMapID then
			place = candidate
		end
	end
	return place[1], place[2], place[3]
end

-- The world map at mapID, and with x and y (0 to 1 on that map) the game's own waypoint there,
-- tracked so its arrow shows. `label` names it in chat. False if it couldn't be opened.
local function ShowOnMap(mapID, x, y, label)
	if not mapID then
		return false
	end
	if InCombatLockdown() then
		ns.Print("战斗中无法在此打开地图。")
		return false
	end
	if x and y and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
		and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(mapID)) then
		local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y))
		if ok then
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
			end
			if label then
				ns.Print(string.format("已设置路径点：%s（%.0f, %.0f）。", label, x * 100, y * 100))
			end
		end
	end
	if OpenWorldMap then
		OpenWorldMap(mapID)
	elseif WorldMapFrame then
		ShowUIPanel(WorldMapFrame)
		WorldMapFrame:SetMapID(mapID)
	end
	return true
end

-- Addons can't open a browser, so show the Wowhead address selected in a popup to copy.
local WOWHEAD_URL = "https://www.wowhead.com/forever/%s=%d" -- kind: "item", "spell", "npc" or "quest"

StaticPopupDialogs["ONECAST_WOWHEAD"] = {
	text = "%s 的 Wowhead 页面\n按 Ctrl+C 复制，再到浏览器中粘贴。",
	button1 = CLOSE or "关闭",
	hasEditBox = true,
	editBoxWidth = 280,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(self, url)
		local box = self.EditBox or self.editBox
		box:SetText(url)
		box:HighlightText()
		box:SetFocus()
	end,
	-- Keep the address intact and selected if a key other than Ctrl+C is pressed.
	EditBoxOnTextChanged = function(box, url)
		if box:GetText() ~= url then
			box:SetText(url)
			box:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(box)
		box:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(box)
		box:GetParent():Hide()
	end,
}

-- Wowhead's WoW Forever page for an item, spell, NPC or quest, in a popup to copy.
local function ShowWowhead(kind, id, name)
	if not name then
		name = kind == "spell" and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or C_Item.GetItemNameByID(id)
	end
	StaticPopup_Show("ONECAST_WOWHEAD", name or (kind .. " " .. id), nil, string.format(WOWHEAD_URL, kind, id))
end

local function ShowWowheadLink(itemID, name)
	ShowWowhead("item", itemID, name)
end

-- Right-click on any catch, here or in the collection: everything you can do with it, in one
-- small menu like the minimap button's. A click anywhere else, or Escape, closes it.
local itemMenu
local MENU_WIDTH, MENU_ROW, MENU_PAD = 190, 20, 10

local function InCollection(itemID)
	return (ns.FISH_BY_ID and ns.FISH_BY_ID[itemID]) and true or false
end

local function ItemMenuFrame()
	if itemMenu then
		return itemMenu
	end
	local f = TryCreate("Frame", "OneCastItemMenu", UIParent, "TooltipBackdropTemplate")
		or CreateFrame("Frame", "OneCastItemMenu", UIParent, "BackdropTemplate")
	if not f.NineSlice and f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	end
	-- The tooltip backdrop is see-through, and the list under the menu showed through its text:
	-- a solid backing inside the border.
	local backing = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	backing:SetPoint("TOPLEFT", 3, -3)
	backing:SetPoint("BOTTOMRIGHT", -3, 3)
	backing:SetColorTexture(0.04, 0.04, 0.06, 1)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	ns.UI.EscapeCloses(f)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", MENU_PAD + 2, -MENU_PAD)
	f.title:SetPoint("RIGHT", -MENU_PAD, 0)
	f.title:SetJustifyH("LEFT")
	f.title:SetWordWrap(false)
	f.buttons = {}
	f:SetScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	f:SetScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	f:SetScript("OnEvent", function(self)
		if not self:IsMouseOver() then
			self:Hide()
		end
	end)
	itemMenu = f
	return f
end

-- Show the menu at the mouse with these entries: { label, function }.
local function ShowMenu(title, entries)
	local f = ItemMenuFrame()
	f.title:SetText(title)
	local y = -MENU_PAD - 18
	for i, entry in ipairs(entries) do
		local b = f.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, f)
			b:SetHeight(MENU_ROW)
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			b.text:SetPoint("LEFT", 4, 0)
			f.buttons[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", MENU_PAD - 2, y)
		b:SetPoint("TOPRIGHT", -MENU_PAD + 2, y)
		b.text:SetText(entry[1])
		b.label = entry[1]
		b:SetScript("OnClick", function()
			f:Hide()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			entry[2]()
		end)
		b:Show()
		y = y - MENU_ROW
	end
	for i = #entries + 1, #f.buttons do
		f.buttons[i]:Hide()
	end
	-- As wide as the longest line needs, so nothing is cut off.
	local width = MENU_WIDTH
	for i = 1, #entries do
		width = math.max(width, f.buttons[i].text:GetStringWidth() + 2 * MENU_PAD + 8)
	end
	f.title:SetWordWrap(false)
	width = math.max(width, f.title:GetStringWidth() + 2 * MENU_PAD + 4)
	f:SetSize(math.min(width, 320), -y + MENU_PAD)
	local scale = UIParent:GetEffectiveScale()
	local x, cy = GetCursorPosition()
	f:ClearAllPoints()
	-- With a controller there's no mouse to open at: by the selected button.
	local anchor = ns.Controller and ns.Controller.MenuAnchor()
	if anchor then
		f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 24, 6)
	else
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / scale + 4, (cy or 0) / scale - 4)
	end
	if ns.Controller then
		ns.Controller.Navigate(f, true)
	end
	f:Show()
	return f
end

-- The menu for one item: open it in the collection, where it bites best, wanted, Wowhead, chat.
local function ShowItemMenu(itemID, name)
	name = name or C_Item.GetItemNameByID(itemID) or ("物品 " .. itemID)
	local entries = {}
	if InCollection(itemID) then
		entries[#entries + 1] = { "在图鉴中打开", function()
			ns.Book.Show()
			ns.Book.ShowFish(itemID)
		end }
	end
	if charDB and charDB.lifetime.items[itemID] then
		entries[#entries + 1] = { "咬钩地点，最佳优先", function()
			Stats.Farm(itemID)
		end }
	end
	local wanted = Wanted(itemID)
	entries[#entries + 1] = { wanted and "从想要列表移除" or "加入想要列表", function()
		Stats.ToggleWanted(itemID, name)
	end }
	entries[#entries + 1] = { wanted and wanted.target and string.format("想改数量（%d/%d）…", wanted.got, wanted.target)
		or "想设定数量…", function()
		StaticPopup_Show("ONECAST_GOAL", name, nil, { itemID = itemID, name = name, default = wanted and wanted.target or 20 })
	end }
	entries[#entries + 1] = { "Wowhead 链接", function()
		ShowWowhead("item", itemID, name)
	end }
	entries[#entries + 1] = { "在聊天中链接", function()
		ns.InsertChatLink(ns.ItemLink(itemID))
	end }
	return ShowMenu(name, entries)
end
Stats.ShowItemMenu = ShowItemMenu
-- For mini mode: the wanted list.
function Stats.Wanted()
	return charDB and charDB.wanted or {}
end

-- A row inside a container's: its icon a step in, and a line from the container's icon down and
-- across to it (stopping at the last), as the game's own trees draw it.
local TREE_STEP = 16
function Stats.TreeRow(row, child, last)
	local size = ITEM_HEIGHT - 2
	local lineX = PAD + math.floor(size / 2)
	if not row.treeDown then
		row.treeDown = row:CreateTexture(nil, "ARTWORK")
		row.treeAcross = row:CreateTexture(nil, "ARTWORK")
		for _, t in ipairs({ row.treeDown, row.treeAcross }) do
			t:SetColorTexture(0.62, 0.48, 0.24, 0.8)
		end
	end
	row.icon:ClearAllPoints()
	if child then
		row.icon:SetSize(size - 4, size - 4)
		row.icon:SetPoint("LEFT", PAD + TREE_STEP, 0)
		row.treeDown:ClearAllPoints()
		row.treeDown:SetPoint("TOPLEFT", row, "TOPLEFT", lineX, 0)
		row.treeDown:SetWidth(1)
		row.treeDown:SetHeight(last and ITEM_HEIGHT / 2 or ITEM_HEIGHT)
		row.treeAcross:ClearAllPoints()
		row.treeAcross:SetPoint("LEFT", row, "LEFT", lineX, 0)
		row.treeAcross:SetSize(PAD + TREE_STEP - lineX - 2, 1)
		row.treeDown:Show()
		row.treeAcross:Show()
	else
		row.icon:SetSize(size, size)
		row.icon:SetPoint("LEFT", PAD, 0)
		row.treeDown:Hide()
		row.treeAcross:Hide()
	end
end

local function ItemRow(parent, index, y)
	local row = CreateFrame("Button", nil, parent)
	row:SetPoint("TOPLEFT", 10, y)
	row:SetPoint("TOPRIGHT", -10, y)
	row:SetHeight(ITEM_HEIGHT)
	row.padMore = true -- with a controller, X opens its menu
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	RowBackground(row, index)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ITEM_HEIGHT - 2, ITEM_HEIGHT - 2)
	row.icon:SetPoint("LEFT", PAD, 0)
	row.border = row:CreateTexture(nil, "OVERLAY")
	row.border:SetAllPoints(row.icon)
	row.border:SetTexture("Interface\\Common\\WhiteIconFrame")

	row.name = row:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.right = row:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	row.right:SetPoint("RIGHT", -6, 0)
	row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row:SetScript("OnClick", function(self, mouseButton)
		if self.spot then
			-- A spot: the world map there, with a waypoint where you fished from.
			local t = self.spot
			if t.x then
				ShowOnMap(t.mapID, t.x, t.y, self.itemName)
				return
			end
			local zoneMap = ns.Book and ns.Book.ZoneMapID and ns.Book.ZoneMapID(self.zone or CurrentZone())
			local placeMap, px, py = Stats.AreaPlace(self.itemName, zoneMap)
			if placeMap then
				ShowOnMap(placeMap, px, py, self.itemName)
				return
			end
			ShowOnMap(zoneMap, nil, nil, self.itemName)
			return
		end
		if not self.itemID then
			return
		end
		-- The same clicks as in the collection: right-click for everything you can do with it,
		-- Shift-click to link it, and a plain click opens its page.
		if mouseButton == "RightButton" then
			ShowItemMenu(self.itemID, self.itemName)
			return
		end
		local link = select(2, C_Item.GetItemInfo(self.itemID))
		if link and HandleModifiedItemClick and IsModifiedClick("CHATLINK") and HandleModifiedItemClick(link) then
			return
		end
		if self.pick or IsControlKeyDown() then
			Stats.Farm(self.itemID)
			return
		end
		if InCollection(self.itemID) then
			ns.Book.Show()
			ns.Book.ShowFish(self.itemID)
		else
			ShowWowheadLink(self.itemID, self.itemName)
		end
	end)
	row:SetScript("OnEnter", function(self)
		local t = self.spot
		local h = self.session
		if h then
			-- A past session: everything it was.
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText((h.start and date("%A %d %B, %H:%M", h.start) or "会话") .. "  ·  " .. (h.zone or "?"))
			GameTooltip:AddDoubleLine("钓获", string.format("%d of %d", h.catches, h.casts or h.catches), 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("钓鱼时间", Stats.FormatDuration(h.time), 1, 0.82, 0, 1, 1, 1)
			local rate = h.time and h.time >= 60 and h.catches / h.time * 3600
			GameTooltip:AddDoubleLine("每小时鱼数", rate and string.format("%.0f", rate) or "-", 1, 0.82, 0, 1, 1, 1)
			if (h.vendor or 0) > 0 then
				GameTooltip:AddDoubleLine("商人售价", Coins(h.vendor), 1, 0.82, 0, 1, 1, 1)
			end
			if (h.skill or 0) > 0 then
				GameTooltip:AddDoubleLine("技能提升", "+" .. h.skill, 1, 0.82, 0, 0.12, 1, 0)
			end
			if h.best then
				local name = C_Item.GetItemNameByID(h.best) or ("物品 " .. h.best)
				local color = Stats.QualityColor(C_Item.GetItemQualityByID(h.best))
				GameTooltip:AddDoubleLine("最佳渔获", name, 1, 0.82, 0, color and color.r or 1, color and color.g or 1,
					color and color.b or 1)
			end
			if h.items and #h.items > 0 then
				GameTooltip:AddLine(" ")
				for _, it in ipairs(h.items) do
					local name = C_Item.GetItemNameByID(it.id) or ("物品 " .. it.id)
					local color = Stats.QualityColor(C_Item.GetItemQualityByID(it.id))
					GameTooltip:AddDoubleLine(name, "x" .. it.count, color and color.r or 1, color and color.g or 1,
						color and color.b or 1, 1, 1, 1)
				end
			end
			GameTooltip:Show()
		elseif t then
			-- A spot on the Farm tab: its numbers and what bites there.
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.itemName)
			GameTooltip:AddDoubleLine("钓获", string.format("%d of %d", t.catches, t.casts), 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("钓鱼时间", Stats.FormatDuration(t.activeTime), 1, 0.82, 0, 1, 1, 1)
			local rate = PerHour(t)
			GameTooltip:AddDoubleLine("每小时鱼数", rate and string.format("%.0f", rate) or "-", 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("商人售价", Coins(TotalValue(t.items, VendorPrice)), 1, 0.82, 0, 1, 1, 1)
			local list = {}
			for id, item in pairs(t.items) do
				list[#list + 1] = { id = id, count = item.count }
			end
			table.sort(list, function(a, b)
				return a.count > b.count
			end)
			if #list > 0 then
				GameTooltip:AddLine(" ")
			end
			for i = 1, math.min(#list, 6) do
				local name = C_Item.GetItemNameByID(list[i].id) or ("物品 " .. list[i].id)
				local color = Stats.QualityColor(C_Item.GetItemQualityByID(list[i].id))
				GameTooltip:AddDoubleLine(name, "x" .. list[i].count, color and color.r or 1, color and color.g or 1,
					color and color.b or 1, 1, 1, 1)
			end
			GameTooltip:AddLine(" ")
			if t.x or Stats.AreaPlace(self.itemName) then
				GameTooltip:AddLine("点击：在地图上显示并设置路径点", 0.6, 0.8, 1)
			else
				GameTooltip:AddLine("点击：在地图上显示该区域", 0.6, 0.8, 1)
				GameTooltip:AddLine("再在此处钓一次鱼即可添加路径点。", 0.6, 0.6, 0.6, true)
			end
			GameTooltip:Show()
		elseif self.missing then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("图鉴中还没有，但本区域能钓到。", 1, 1, 1, true)
			GameTooltip:AddLine("点击：在图鉴中查看", 0.6, 0.8, 1)
			GameTooltip:AddLine("右键：更多", 0.6, 0.8, 1)
			GameTooltip:Show()
		elseif self.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			if self.note then
				GameTooltip:AddLine(self.note, 1, 1, 1, true)
			end
			GameTooltip:AddLine(" ")
			if self.pick then
				GameTooltip:AddLine("点击：查看最佳咬钩地点", 0.6, 0.8, 1)
			elseif InCollection(self.itemID) then
				GameTooltip:AddLine("点击：在图鉴中打开", 0.6, 0.8, 1)
			else
				GameTooltip:AddLine("点击：Wowhead 链接", 0.6, 0.8, 1)
			end
			GameTooltip:AddLine("右键：更多（想要、咬钩地点、Wowhead）", 0.6, 0.8, 1)
			GameTooltip:AddLine("Shift+点击：在聊天中链接", 0.6, 0.8, 1)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

-- Square gold-framed icon button, the native UIPanelSquareButton (like the Character
-- frame's arrow button). `art` names a glyph in Media.
local ICON_BUTTON_SIZE = 24

-- OneCast's own glyphs (Media\*.tga): white with a dark outline, tinted Blizzard gold
-- like the Character frame's model-control glyphs, and brighter on hover.
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local GLYPH_GOLD = { 1, 0.82, 0 }
local GLYPH_HOVER = { 1, 0.95, 0.6 }

local function SetIconArt(tex, art)
	tex:SetTexture(MEDIA .. art)
	tex:SetTexCoord(0, 1, 0, 1)
	tex:SetVertexColor(GLYPH_GOLD[1], GLYPH_GOLD[2], GLYPH_GOLD[3])
end

-- The game's own icon for each button, where it has one: its refresh arrow, the quest log's cog
-- and lore book, crossed swords and the search glass. OneCast's glyph where it hasn't.
local NATIVE_ICONS = {
	Reset = { "UI-RefreshButton", 0.7 },
	Options = { "questlog-icon-setting", 0.62 },
	Book = { "campaign-questlog-lorebook", 0.72 },
	Weapons = { "pvptalents-warmode-swords", 0.72 },
	Scan = { "common-search-magnifyingglass", 0.66 },
}

local function IconButton(parent, art, tooltip, onClick)
	local b = TryCreate("Button", nil, parent, "UIPanelSquareButton")
	if b then
		b.icon = b.icon or b.Icon
	else
		b = CreateFrame("Button", nil, parent, "BackdropTemplate")
		b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
		b:SetBackdropColor(0.1, 0.08, 0.05, 1)
		b:SetBackdropBorderColor(1, 0.82, 0)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	end
	if not b.icon then
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("CENTER")
	end
	b:SetSize(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE)
	b.icon:ClearAllPoints()
	b.icon:SetPoint("CENTER")
	local native = NATIVE_ICONS[art]
	if native and HasAtlas(native[1]) then
		-- On a texture of its own: the template's icon is set up for its sheet of arrows and draws
		-- an atlas as nothing. It moves as the button's pressed, as the template's would.
		b.icon:Hide()
		local icon = b:CreateTexture(nil, "OVERLAY")
		icon:SetAtlas(native[1])
		local size = math.floor(ICON_BUTTON_SIZE * native[2] + 0.5)
		icon:SetSize(size, size)
		icon:SetPoint("CENTER")
		b.icon = icon
		b.native = true
	else
		b.icon:SetSize(ICON_BUTTON_SIZE - 6, ICON_BUTTON_SIZE - 6)
		SetIconArt(b.icon, art)
	end
	b:SetScript("OnClick", function(self, ...)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		onClick(self, ...)
	end)
	b:SetScript("OnEnter", function(self)
		if not self.native then
			self.icon:SetVertexColor(GLYPH_HOVER[1], GLYPH_HOVER[2], GLYPH_HOVER[3])
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tooltip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		if not self.native then
			self.icon:SetVertexColor(GLYPH_GOLD[1], GLYPH_GOLD[2], GLYPH_GOLD[3])
		end
		GameTooltip:Hide()
	end)
	return b
end

-- Font object, at a given size. The font comes from the object, not the string: a reused string
-- can keep the font it was last given, which would put a heading's font on body text.
local function SizedFont(fs, fontObject, size)
	if ns.LargerText and ns.LargerText() and size < 15 then
		size = size + 2 -- "放大文字"
	end
	fs:SetFontObject(fontObject)
	local path, _, flags = fontObject:GetFont()
	if path then
		fs:SetFont(path, size, flags)
	end
end

-- A window that opens where you last dragged it, for every character (OneCastDB.windowPoints).
-- It's placed at `key`'s saved point, or left where the caller put it the first time.
local function RememberPosition(frame, key)
	local saved = ns.db and ns.db.windowPoints and ns.db.windowPoints[key]
	if saved then
		frame:ClearAllPoints()
		frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	end
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		if ns.db and point then
			ns.db.windowPoints = ns.db.windowPoints or {}
			ns.db.windowPoints[key] = { point, relPoint, x, y }
		end
	end)
end

-- The window's building blocks, shared by every window so they always match.
ns.UI = {
	PAGE_HEIGHT = WINDOW_HEIGHT, -- every page of the window: switching tabs only changes the width
	CloseOwn = CloseOwn,
	RememberPosition = RememberPosition,
	ShowOnMap = ShowOnMap,
	TryCreate = TryCreate,
	HasAtlas = HasAtlas,
	SizedFont = SizedFont,
	CreateShell = CreateShell,
	RankBar = function(parent, name) return RankBar(parent, name) end, -- Forever's Fishing bar: (parent, name), then :SetRank(fraction, "186/225")
	SectionHeader = SectionHeader,
	RowBackground = RowBackground,
	StatRow = StatRow,
	IconButton = IconButton,
	ShowWowhead = ShowWowhead,
	ShowMenu = ShowMenu,
	StatTile = StatTile, -- a headline number: (parent, 1 to 3, top), with .value, .caption and .tooltip
	ShowItemMenu = ShowItemMenu,
}

-- Top tabs like the Options window's Game / AddOns, else classic tabs under the frame.
local function CreateTabs(f, inset)
	f.Tabs = {}
	local top = true
	for i, v in ipairs(VIEWS) do
		local tab = TryCreate("Button", "OneCastStatsFrameTab" .. i, f, "PanelTopTabButtonTemplate")
		if not tab then
			top = false
			tab = CreateFrame("Button", "OneCastStatsFrameTab" .. i, f, "PanelTabButtonTemplate")
		end
		tab:SetID(i)
		tab:SetText(v.label)
		tab.view = v.key
		tab:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			SelectView(v.key)
		end)
		-- Top tabs get a fixed width (FitTabs) so all four fit beside the portrait.
		if not top and PanelTemplates_TabResize then
			pcall(PanelTemplates_TabResize, tab, 0)
		end
		if i == 1 then
			if top then
				tab:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", TABS_LEFT, 0)
			else
				tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
			end
		else
			tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", top and TAB_GAP or -14, 0)
		end
		f.Tabs[i] = tab
	end
	if PanelTemplates_SetNumTabs then
		PanelTemplates_SetNumTabs(f, #VIEWS)
	end
	f.topTabs = top
end

-- The tab templates resize each tab to its text whenever tabs are shown or selected, which
-- is too wide for four tabs beside the portrait; force the fixed width back afterwards.
local function FitTabs(f)
	if not f.topTabs then
		return
	end
	for i, tab in ipairs(f.Tabs) do
		tab:SetWidth(VIEWS[i].width)
		local text = tab.Text or tab:GetFontString()
		if text then
			text:SetWidth(VIEWS[i].width - 10)
		end
	end
end

local function CreateWindow()
	local f, inset = CreateShell("OneCastStatsFrame", "OneCast  " .. GREY .. "v" .. (ns.VERSION or "?") .. " 脱钩|r",
		"Interface\\Icons\\INV_Misc_Fish_68")
	f:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		charDB.windowPoint = { point, relPoint, x, y }
	end)
	f:SetScale((ns.db and ns.db.statsScale or 100) / 100)
	local p = charDB.windowPoint
	if p then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("CENTER")
	end
	if f.CloseButton then
		f.CloseButton:HookScript("OnClick", function()
			dismissed = true
		end)
	end

	CreateTabs(f, inset)

	-- Fishing skill: the professions window's rank bar, then the verdict for this zone.
	f.skillBar = RankBar(inset, ns.GetFishingName and ns.GetFishingName() or "钓鱼")

	f.zoneStrip = ZoneStrip(inset)

	f.summaryHeader = SectionHeader(inset, SUMMARY_TOP)
	f.tiles = {}
	for i = 1, 3 do
		f.tiles[i] = StatTile(inset, i)
	end
	f.stats = {}
	for i = 1, STAT_ROWS do
		f.stats[i] = StatRow(inset, i, STATS_TOP - (i - 1) * STAT_HEIGHT)
	end

	-- Placed on each redraw, under however many detail rows the tab has.
	f.listHeader = SectionHeader(inset, STATS_TOP)
	-- With a controller, the right stick scrolls the list while the selection is in it.
	f.padScrollOwns = function(button)
		if button == f.latest or button == f.moreButton then
			return true
		end
		for _, row in ipairs(f.rows) do
			if row == button then
				return true
			end
		end
		return false
	end
	-- Farm tab: switch the list between this zone's spots and your fish, or leave a fish.
	f.listToggle = CreateFrame("Button", nil, f.listHeader, "UIPanelButtonTemplate")
	f.listToggle:SetSize(64, 18)
	f.listToggle:SetPoint("RIGHT", -4, 1)
	f.listToggle:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if CurrentView() == "records" then
			charDB.recordsList = charDB.recordsList ~= "sessions" and "sessions" or nil
		elseif charDB.farmTarget then
			charDB.farmTarget, charDB.farmList = nil, "fish"
		else
			charDB.farmList = charDB.farmList ~= "fish" and "fish" or nil
		end
		Stats.Refresh()
	end)
	f.listToggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if CurrentView() == "records" then
			GameTooltip:SetText(charDB.recordsList == "sessions" and "显示值得纪念的渔获"
				or "显示最近会话")
		elseif charDB.farmTarget then
			GameTooltip:SetText("返回全部鱼类")
		elseif charDB.farmList == "fish" then
			GameTooltip:SetText("显示本区域各地点，按每小时鱼数排序")
		else
			GameTooltip:SetText("选择一种鱼，查看它最佳咬钩地点")
		end
		GameTooltip:Show()
	end)
	f.listToggle:SetScript("OnLeave", GameTooltip_Hide)
	f.rows = {}
	f.latest = ItemRow(inset, 1, 0)
	f.latest:SetHeight(LATEST_HEIGHT)
	f.latest.icon:SetSize(LATEST_HEIGHT - 6, LATEST_HEIGHT - 6)
	f.latest.name:SetFontObject("GameFontHighlight")
	f.latest.name:ClearAllPoints()
	f.latest.name:SetPoint("TOPLEFT", f.latest.icon, "TOPRIGHT", 8, -3)
	f.latest.name:SetPoint("RIGHT", -8, 0)
	f.latest.sub = f.latest:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	f.latest.sub:SetTextColor(0.78, 0.78, 0.78)
	f.latest.sub:SetPoint("BOTTOMLEFT", f.latest.icon, "BOTTOMRIGHT", 8, 3)
	f.latest.sub:SetPoint("RIGHT", -8, 0)
	f.latest.sub:SetJustifyH("LEFT")
	f.latest:Hide()
	for i = 1, MAX_ROWS do
		f.rows[i] = ItemRow(inset, i, 0)
	end
	f.more = inset:CreateFontString(nil, "OVERLAY", "OneCastFontDisableSmall")
	f.more:SetWordWrap(true)
	f.moreButton = CreateFrame("Button", nil, inset)
	f.moreButton:SetScript("OnClick", function()
		local capacity = f.listCapacity or 1
		f.listOffset = (f.listOffset or 0) >= (f.listMax or 0) and 0 or (f.listOffset or 0) + capacity
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Stats.Refresh()
	end)
	f.moreButton:SetScript("OnEnter", function()
		f.more:SetTextColor(1, 0.82, 0)
	end)
	f.moreButton:SetScript("OnLeave", function()
		f.more:SetTextColor(0.5, 0.5, 0.5)
	end)
	f.moreButton:Hide()
	-- The list's scroll bar: the game's minimal one, its track and thumb.
	f.scrollTrack = inset:CreateTexture(nil, "ARTWORK")
	f.scrollTrack:SetColorTexture(0, 0, 0, 0.35)
	f.scrollThumb = inset:CreateTexture(nil, "OVERLAY")
	if HasAtlas("minimal-scrollbar-small-thumb-middle") then
		f.scrollThumb:SetAtlas("minimal-scrollbar-small-thumb-middle")
	else
		f.scrollThumb:SetColorTexture(1, 0.82, 0, 0.6)
	end

	-- Bottom bar: square icon buttons, like the Character frame's model controls.
	local options = IconButton(f, "选项", "选项", function()
		ns.Hub.ShowOptions()
	end)
	options:SetPoint("BOTTOMRIGHT", -22, 3)
	f.gear = IconButton(f, "Weapons", "换回武器", function()
		OneCast_DoneFishing()
	end)
	f.scan = IconButton(f, "Scan", "用 Auctionator 扫描价格", function()
		ns.Prices.Scan()
	end)
	f.reset = IconButton(f, "重置", "重置会话", function()
		StaticPopup_Show("ONECAST_RESET_SESSION")
	end)
	local book = IconButton(f, "Book", "钓鱼图鉴", function()
		ns.Book.Toggle()
	end)
	f.bottomButtons = { options, book, f.gear, f.scan, f.reset }

	-- The resize grip in the bottom-right corner is the hub's, on every page (Hub.Attach).

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() then
			if not (ns.db and ns.db.lockWindow) then
				Stats.SetScale(f:GetScale() * 100 + delta * SCALE_STEP)
			end
			return
		end
		-- The wheel scrolls the list, three rows at a time.
		local before = f.listOffset or 0
		f.listOffset = math.max(0, math.min(before - delta * 3, f.listMax or 0))
		if f.listOffset ~= before then
			Stats.Refresh()
		end
	end)

	-- Keep the session's elapsed time ticking. The other tabs change only on events.
	local elapsed = 0
	-- The session clock ticks every second. Only its title changes that often: the rest, which
	-- prices every item, redraws on events and now and then for the Extravaganza countdown.
	local sinceFull = 0
	-- Fading while fishing: towards see-through while the mouse is elsewhere and a cast was recent.
	local FADED, FADE_SPEED = 0.6, 2.5
	local alpha = 1
	local function Fade(dt)
		if alpha == 1 and not (ns.db and ns.db.fadeStats) then
			return -- off, and already solid: nothing to do each frame
		end
		local s = Session()
		local fishing = s.lastCast and GetServerTime() - s.lastCast <= ACTIVE_GAP
		local target = (ns.db and ns.db.fadeStats and fishing and not f:IsMouseOver() and not ns.Hub.IsMouseOverTabs())
			and FADED or 1
		if alpha ~= target then
			alpha = target < alpha and math.max(target, alpha - dt * FADE_SPEED) or math.min(target, alpha + dt * FADE_SPEED)
			f:SetAlpha(alpha)
			ns.Hub.SetTabsAlpha(f, alpha)
		end
	end
	f:HookScript("OnHide", function(self)
		alpha = 1
		self:SetAlpha(1)
		autoOpened = false
	end)
	f:SetScript("OnUpdate", function(_, dt)
		Fade(dt)
		elapsed = elapsed + dt
		if elapsed >= 1 then
			elapsed = 0
			if CurrentView() == "session" then
				sinceFull = sinceFull + 1
				if sinceFull >= FULL_REDRAW_SECONDS then
					sinceFull = 0
					Stats.Refresh()
				else
					f.summaryHeader.text:SetText(SessionTitle(Session()))
				end
			end
		end
	end)

	f.inset = inset
	f:Hide()
	ns.Hub.Attach("session", f)
	return f
end

-- Lay out the visible bottom buttons right to left from Options.
local function LayoutBottomButtons(view)
	frame.gear:SetShown(ns.Gear and ns.Gear.HasSaved() or false)
	frame.scan:SetShown(ns.Prices and ns.Prices.IsAuctionOpen() and ns.Prices.CanScan() or false)
	frame.reset:SetShown(view == "session")
	local previous = frame.bottomButtons[1]
	for i = 2, #frame.bottomButtons do
		local b = frame.bottomButtons[i]
		if b:IsShown() then
			b:ClearAllPoints()
			b:SetPoint("RIGHT", previous, "LEFT", -4, 0)
			previous = b
		end
	end
end

function Stats.Refresh()
	local view = CurrentView()
	local title, tiles, stats, rows, listTitle, emptyText = BuildView(view)

	for i, tab in ipairs(frame.Tabs) do
		if tab.view == view then
			if PanelTemplates_SetTab then
				PanelTemplates_SetTab(frame, i)
			else
				tab:LockHighlight()
			end
		elseif not PanelTemplates_SetTab then
			tab:UnlockHighlight()
		end
	end
	FitTabs(frame)

	local fraction, value = SkillStatus()
	frame.skillBar:SetRank(fraction, value)
	local zone = CurrentZone()
	frame.zoneStrip:Update(zone, CurrentSpot(zone))

	frame.summaryHeader.text:SetText(title)
	for i, tile in ipairs(frame.tiles) do
		local t = tiles[i]
		tile.value:SetText(t.value)
		tile.caption:SetText(t.caption)
		tile.tooltip = t.tooltip
	end
	local shownStats = 0
	for i, row in ipairs(frame.stats) do
		local pair = stats[i]
		if pair then
			row.label:SetText(pair[1] .. ":")
			row.value:SetText(pair[2])
			row.extra = pair[3]
			row:EnableMouse(pair[3] ~= nil)
			-- A controller stops on anything with a click handler: only on rows that do something.
			row:SetScript("OnMouseUp", pair[3] and pair[3].click and StatRowClick or nil)
			row:Show()
			shownStats = i
		else
			row:Hide()
		end
	end

	-- The list starts under the detail rows and fills the rest of the window.
	local listTop = STATS_TOP - shownStats * STAT_HEIGHT - GAP
	local rowsTop = listTop - HEADER_HEIGHT - HEADER_GAP
	-- This session's latest catch, as a card above the list.
	local last = view == "session" and Session().catches > 0 and Stats.LatestCatch()
	local card = frame.latest
	if last then
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", EDGE, rowsTop)
		card:SetPoint("TOPRIGHT", -EDGE, rowsTop)
		card.itemID, card.itemName = last.id, last.name
		card.spot, card.zone, card.pick, card.missing, card.note, card.session = nil, nil, nil, nil, nil, nil
		card.icon:SetTexture(last.icon)
		local color = Stats.QualityColor(last.quality)
		card.name:SetText(last.name or ("物品:" .. last.id))
		card.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
		card.border:SetVertexColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
		card.sub:SetText("最新渔获  ·  " .. Stats.Since(last.time) .. ((last.quantity or 1) > 1 and ("  ·  x" .. last.quantity) or ""))
		card.right:SetText("")
		card:Show()
		rowsTop = rowsTop - LATEST_HEIGHT - 4
	else
		card.itemID = nil
		card:Hide()
	end
	frame.listHeader:ClearAllPoints()
	frame.listHeader:SetPoint("TOPLEFT", EDGE, listTop)
	frame.listHeader:SetPoint("TOPRIGHT", -EDGE, listTop)
	local capacity = math.min(MAX_ROWS, math.floor((INSET_HEIGHT + rowsTop - 18) / ITEM_HEIGHT))
	frame.listHeader.text:SetText(listTitle)
	-- Scrolled with the mouse wheel; back to the top when the list itself changes.
	local listKey = view .. ":" .. tostring(charDB.farmTarget) .. ":" .. tostring(charDB.farmList) .. ":" .. tostring(charDB.recordsList)
	if frame.listKey ~= listKey then
		frame.listKey, frame.listOffset = listKey, 0
	end
	local maxOffset = math.max(0, #rows - capacity)
	frame.listOffset = math.max(0, math.min(frame.listOffset or 0, maxOffset))
	frame.listCapacity, frame.listMax = capacity, maxOffset
	local offset = frame.listOffset
	frame.listToggle:SetShown(view == "farm" or view == "records")
	if view == "records" then
		frame.listToggle:SetText(charDB.recordsList == "sessions" and "Notable" or "Sessions")
	else
		frame.listToggle:SetText(charDB.farmTarget and "返回" or charDB.farmList == "fish" and "地点" or "鱼类")
	end
	for i, row in ipairs(frame.rows) do
		local r = i <= capacity and rows[offset + i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", EDGE, rowsTop - (i - 1) * ITEM_HEIGHT)
		row:SetPoint("TOPRIGHT", -EDGE, rowsTop - (i - 1) * ITEM_HEIGHT)
		if r then
			local color = Stats.QualityColor(r.quality)
			row.itemID = r.id
			row.itemName = r.name
			row.spot, row.zone, row.pick, row.missing, row.note, row.session = r.spot, r.zone, r.pick, r.missing, r.note, r.session
			row.icon:SetTexture(r.icon)
			row.icon:SetDesaturated(r.missing or false)
			Stats.TreeRow(row, r.child, r.last)
			row.name:SetText((r.label or r.name or ("物品:" .. r.id)) .. (r.id and not r.spot and WantedText(r.id) or ""))
			if r.missing then
				row.name:SetTextColor(0.6, 0.6, 0.6)
				row.border:SetVertexColor(0.5, 0.5, 0.5)
			elseif color then
				row.name:SetTextColor(color.r, color.g, color.b)
				row.border:SetVertexColor(color.r, color.g, color.b)
			else
				row.name:SetTextColor(1, 1, 1)
				row.border:SetVertexColor(1, 1, 1)
			end
			row.right:SetText(r.right)
			row:Show()
		else
			row.itemID, row.spot, row.zone, row.pick, row.missing, row.note, row.session = nil, nil, nil, nil, nil, nil, nil
			row:Hide()
		end
	end

	frame.more:ClearAllPoints()
	if #rows == 0 then
		-- An empty list: the message centred in the space, wrapped to fit.
		frame.more:SetPoint("TOPLEFT", EDGE + 2 * PAD, rowsTop - 2 * PAD)
		frame.more:SetPoint("RIGHT", frame.inset, "RIGHT", -(EDGE + 2 * PAD), 0)
		frame.more:SetJustifyH("CENTER")
		frame.more:SetText(emptyText)
	elseif #rows > capacity then
		frame.more:SetPoint("TOPLEFT", EDGE + PAD, rowsTop - capacity * ITEM_HEIGHT - HEADER_GAP)
		frame.more:SetPoint("RIGHT", frame.inset, "RIGHT", -(EDGE + PAD), 0)
		frame.more:SetJustifyH("LEFT")
		local below = #rows - capacity - offset
		frame.more:SetText(below > 0 and string.format("下方还有 %d 项：滚动查看，或点击此处", below)
			or "回到顶部：点击此处")
	else
		frame.more:SetText("")
	end
	-- Clicking the line under the list pages down, or back to the top at the end.
	frame.moreButton:SetShown(#rows > capacity)
	frame.moreButton:ClearAllPoints()
	frame.moreButton:SetPoint("TOPLEFT", frame.more, "TOPLEFT", -2, 2)
	frame.moreButton:SetPoint("BOTTOMRIGHT", frame.more, "BOTTOMRIGHT", 2, -2)
	-- A slim scroll bar beside the rows, showing how far down the list is.
	local track, thumb = frame.scrollTrack, frame.scrollThumb
	track:SetShown(#rows > capacity)
	thumb:SetShown(#rows > capacity)
	if #rows > capacity then
		local height = capacity * ITEM_HEIGHT
		track:ClearAllPoints()
		track:SetPoint("TOPRIGHT", frame.inset, "TOPRIGHT", -3, rowsTop)
		track:SetSize(4, height)
		local thumbH = math.max(12, height * capacity / #rows)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -(height - thumbH) * offset / math.max(1, maxOffset))
		thumb:SetSize(6, thumbH)
	end

	LayoutBottomButtons(view)
end

function Stats.Show(view)
	autoOpened = false
	frame = frame or CreateWindow()
	if view then
		charDB.view = view
	end
	Stats.Refresh()
	frame:Show()
	FitTabs(frame) -- the tabs' own OnShow just resized them
end

-- The Farm tab for one item: where it bites best.
function Stats.Farm(itemID)
	charDB.farmTarget = itemID
	Stats.Show("farm")
end

function Stats.Toggle(view)
	if frame and frame:IsShown() and not view then
		dismissed = true
		frame:Hide()
	else
		Stats.Show(view)
	end
end

function Stats.Reset()
	Stats.ResetSession()
end

-- Scale the whole window, every page, to `percent`, keeping its top-left corner where it is. While dragging
-- the grip (`live`), only the window changes; otherwise the setting is saved too, which
-- also keeps the options slider in step.
function Stats.SetScale(percent, live)
	percent = math.max(SCALE_MIN, math.min(SCALE_MAX, percent))
	if not live then
		percent = math.floor(percent / SCALE_STEP + 0.5) * SCALE_STEP
	end
	if frame then
		frame:SetScale(percent / 100)
	end
	ns.Hub.SetScale(percent / 100)
	if not live and ns.db and ns.db.statsScale ~= percent then
		if ns.scaleSetting then
			ns.scaleSetting:SetValue(percent) -- calls back into Stats.SetScale, now a no-op
		else
			ns.db.statsScale = percent
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("LOOT_READY")
-- Using an item from the bags locks it for a moment, whatever opened it (the game's bags, a bag
-- addon's secure button, a macro): the one way to see which fished-up container was opened.
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:RegisterEvent("UI_INFO_MESSAGE")
events:RegisterEvent("SYSMSG")
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED") -- a new sub-zone: a lake can have its own level
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			OneCastCharDB = OneCastCharDB or {}
			charDB = OneCastCharDB
			charDB.session = charDB.session or NewTotals()
			charDB.lifetime = charDB.lifetime or NewTotals()
			charDB.zoneStats = charDB.zoneStats or {}
			charDB.lureRates = charDB.lureRates or { with = { time = 0, catches = 0 }, without = { time = 0, catches = 0 } }
			charDB.log = charDB.log or {}
			charDB.skill = charDB.skill or {}
			charDB.bests = charDB.bests or {}
			MigrateWanted()
			-- Notable catches and when each item was last caught start from the catch log.
			if not charDB.notable then
				charDB.notable = {}
				for _, e in ipairs(charDB.log) do
					if #charDB.notable < NOTABLE_SIZE and (e.quality or 0) >= 2 then
						charDB.notable[#charDB.notable + 1] = { time = e.time, zone = e.zone, id = e.id, name = e.name,
							icon = e.icon, quality = e.quality, quantity = e.quantity, why = "rare" }
					end
				end
			end
			if not charDB.lastCaught then
				charDB.lastCaught = {}
				for i = #charDB.log, 1, -1 do
					local e = charDB.log[i]
					if e.id then
						charDB.lastCaught[e.id] = { time = e.time, zone = e.zone }
					end
				end
			end
			-- Before 0.7.0's release, every message was kept: keep only the fishing ones.
			if charDB.messagesWhileFishing then
				for i = #charDB.messagesWhileFishing, 1, -1 do
					local m = charDB.messagesWhileFishing[i]
					if not AboutFishing(m.id, m.text) then
						table.remove(charDB.messagesWhileFishing, i)
					end
				end
			end
			-- Stats filed under a dungeon's other name before 0.7.0 join the tables' one.
			for old, new in pairs(ns.INSTANCE_ALIASES or {}) do
				local stats = charDB.zoneStats
				if stats[old] and not stats[new] then
					stats[new], stats[old] = stats[old], nil
				end
				for _, totals in ipairs({ charDB.lifetime, charDB.session }) do
					if totals.zones[old] then
						totals.zones[new] = (totals.zones[new] or 0) + totals.zones[old]
						totals.zones[old] = nil
					end
				end
			end
			ns.Lure.OnChange(Stats.ScheduleRefresh) -- a lure changes the zone verdict
		end
	elseif event == "LOOT_READY" then
		-- A fished-up container opened from the bags, a moment ago: its contents.
		local autoLoot = ...
		local pending = Containers.pending
		local source = GetLootSourceInfo and GetLootSourceInfo(1)
		local fromItem = type(source) ~= "string" or (issecretvalue and issecretvalue(source)) or source:find("^Item") ~= nil
		if pending and GetTime() - pending.at <= Containers.WINDOW and not (IsFishingLoot and IsFishingLoot()) and fromItem then
			Containers.pending = nil
			Containers.Loot(pending.id)
			Stats.FastLoot(autoLoot)
			return
		end
		local fishy = IsFishingLoot and IsFishingLoot()
		OnLootReady(...)
		if fishy then
			Stats.FastLoot(autoLoot)
		end
	elseif event == "UI_ERROR_MESSAGE" or event == "UI_INFO_MESSAGE" or event == "SYSMSG" then
		-- The game can show a message as a red error, a yellow notice or a system line, so all
		-- three are watched. SYSMSG carries the text alone.
		local messageType, message
		if event == "SYSMSG" then
			message = ...
		else
			messageType, message = ...
		end
		local kind = GameMessageKind(messageType, message)
		if kind == "escaped" then
			OnFishEscaped()
		elseif kind == "notHooked" then
			if awaitingLoot and charDB then
				-- Reeled before a bite: an empty cast that says nothing about the zone's level.
				local z = ZoneTotals(CurrentZone())
				z.early = (z.early or 0) + 1
			end
		elseif awaitingLoot and charDB then
			NoteMessage(event, messageType, message)
		end
	elseif event == "ITEM_LOCK_CHANGED" then
		local bag, slot = ...
		if slot and Stats.NoteOpened then
			Stats.NoteOpened(bag, slot)
		end
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		-- Every addon's items report here: only ours matter, and a failed one isn't retried.
		local itemID, success = ...
		if itemRequests[itemID] then
			if success then
				itemRequests[itemID] = nil
				Stats.ScheduleRefresh()
			else
				itemRequests[itemID] = false
			end
		end
	else
		-- The skill, zone or gear changed: redraw.
		if event == "SKILL_LINES_CHANGED" and charDB then
			CheckSkill()
		end
		-- Weapons back on after fishing: a window that opened itself closes itself.
		if event == "PLAYER_EQUIPMENT_CHANGED" and autoOpened and ns.db and ns.db.closeOnDone then
			C_Timer.After(0.2, function()
				if autoOpened and frame and frame:IsShown() and ns.HasFishingPole and not ns.HasFishingPole() then
					frame:Hide()
				end
			end)
		end
		Stats.ScheduleRefresh()
	end
end)

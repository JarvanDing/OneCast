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

local NEW_SESSION_AFTER = 30 * 60 -- a cast after this long idle starts a new session
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
local VIEWS = {
	{ key = "session", label = "Session", width = 74 },
	{ key = "farm", label = "Spots", width = 64 },
	{ key = "records", label = "All-time records", width = 126 },
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
local function InstanceZone()
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
	local dungeon = InstanceZone()
	if dungeon then
		-- Stats kept under the game's own name for it before 0.7.0 move across once.
		if charDB and zone and zone ~= dungeon and charDB.zoneStats[zone] and not charDB.zoneStats[dungeon] then
			charDB.zoneStats[dungeon], charDB.zoneStats[zone] = charDB.zoneStats[zone], nil
		end
		return dungeon
	end
	if not zone or zone == "" then
		return UNKNOWN or "Unknown"
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
end
Stats.RefreshIfShown = RefreshIfShown

-- For events that come in bursts (item data loading, skill lines): one redraw shortly after.
local refreshPending = false
local function ScheduleRefresh()
	if refreshPending or not (frame and frame:IsShown()) then
		return
	end
	refreshPending = true
	C_Timer.After(0.2, function()
		refreshPending = false
		RefreshIfShown()
	end)
end

local function ResetSession()
	charDB.session = NewTotals()
	awaitingLoot = false
	RefreshIfShown()
end

local function FormatDuration(seconds)
	seconds = math.floor(seconds or 0)
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%dm %02ds", m, seconds % 60)
end

local function PerHour(totals)
	if totals.activeTime < 60 then
		return nil
	end
	return totals.catches / totals.activeTime * 3600
end

local function QualityColor(quality)
	return quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
end

local function IsWanted(itemID)
	return ns.db and ns.db.wanted and ns.db.wanted[itemID]
end

local function ToggleWanted(itemID, name)
	ns.db.wanted = ns.db.wanted or {}
	ns.db.wanted[itemID] = not ns.db.wanted[itemID] or nil
	ns.Print((name or ("item:" .. itemID)) .. (ns.db.wanted[itemID]
		and " marked as wanted: you'll get an alert when you catch it."
		or " is no longer wanted."))
	RefreshIfShown()
end

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
local function CatchesPerPoint(rank)
	if rank <= 75 then
		return 1
	end
	return math.ceil((rank - 75) / 25) + 1
end

-- Effective skill (lure and pole included) in steps of 25, for the record of what happened at
-- which skill in each zone: { [bucket] = count } under totals.skillCatches and .skillGetaways.
-- Kept for good (a clean run doesn't clear it), as evidence of a zone's real level.
local SKILL_STEP = 25
local function CountAtSkill(totals, key)
	local rank, _, modifier = FishingSkill()
	if not rank then
		return
	end
	local bucket = math.floor((rank + modifier) / SKILL_STEP) * SKILL_STEP
	totals[key] = totals[key] or {}
	totals[key][bucket] = (totals[key][bucket] or 0) + 1
end
Stats.SKILL_STEP = SKILL_STEP

-- Notice skill-ups: the catch count toward the next point starts again at each one.
local function CheckSkill()
	local rank = FishingSkill()
	if not rank then
		return
	end
	local track = charDB.skill
	if track.rank ~= rank then
		track.rank, track.catches = rank, 0
	end
	track.catches = track.catches or 0
end

-- About how many catches until the skill reaches `rank + points`.
local function CatchesToGo(rank, points)
	local total = 0
	for i = 0, points - 1 do
		total = total + CatchesPerPoint(rank + i)
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

-- Auction price per unit and where it came from: Auctionator, then TradeSkillMaster.
local function AuctionPrice(itemID)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetAuctionPriceByItemID then
		local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
		if ok and price then
			return price, "Auctionator"
		end
	end
	if TSM_API and TSM_API.GetCustomPriceValue then
		local ok, price = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
		if ok and price then
			return price, "TSM"
		end
	end
end

-- Total value of `items`, whether any were unpriced, and the price sources used.
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
local function NotableReason(l, isNew)
	if isNew then
		return "new"
	elseif ns.db and ns.db.wanted and ns.db.wanted[l.id] then
		return "wanted"
	elseif l.quality and l.quality >= 2 then
		return "rare"
	end
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
		Best("vendor", TotalValue(s.items, VendorPrice) / s.activeTime * 3600, zone)
	end
	Best("skill", SkillGained(s), zone)
	Best("time", s.activeTime, zone)
end

-- Rare catch alert: anything at or above the alert quality, or marked as wanted.
local function AlertIfRare(loot)
	local db = ns.db
	if not db or not db.alert then
		return
	end
	for _, l in ipairs(loot) do
		if IsWanted(l.id) or (l.quality and l.quality >= db.alertQuality) then
			local color = QualityColor(l.quality)
			local text = (color and color.hex or "|cffffffff") .. (l.name or "?") .. "|r"
			if RaidNotice_AddMessage and RaidWarningFrame then
				RaidNotice_AddMessage(RaidWarningFrame, "Caught " .. text .. "!", ChatTypeInfo.RAID_WARNING)
			end
			PlaySound(SOUNDKIT.RAID_WARNING)
			ns.Print("rare catch: " .. (l.link or text))
		end
	end
end

-- Sum up the session in chat once the player has stopped for a while.
local function SessionSummaryText(s)
	local parts = { string.format("%d catch%s", s.catches, s.catches == 1 and "" or "es") }
	local rate = PerHour(s)
	if rate then
		parts[#parts + 1] = string.format("%.0f/hr", rate)
	end
	local vendor = TotalValue(s.items, VendorPrice)
	if vendor > 0 then
		parts[#parts + 1] = Coins(vendor) .. " vendor"
	end
	local gained = SkillGained(s)
	if gained > 0 then
		parts[#parts + 1] = string.format("+%d %s", gained, ns.GetFishingName and ns.GetFishingName() or "Fishing")
	end
	if (s.newFish or 0) > 0 then
		parts[#parts + 1] = string.format("%d new for your collection", s.newFish)
	end
	return table.concat(parts, ", ")
end

local function PrintSessionSummary()
	summaryTimer = nil
	local s = Session()
	if not (ns.db and ns.db.sessionSummary) or s.catches <= (s.summarized or 0) then
		return
	end
	local lead = (s.summarized or 0) > 0 and "session so far: " or "session: "
	s.summarized = s.catches
	ns.Print(lead .. SessionSummaryText(s) .. ".")
end

StaticPopupDialogs["ONECAST_RESET_SESSION"] = {
	text = "Reset this session's stats?\n\nIts catches still count towards your zone and lifetime totals.",
	button1 = RESET or "Reset",
	button2 = CANCEL or "Cancel",
	OnAccept = function()
		ResetSession()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["ONECAST_AUTOLOOT"] = {
	text = "Auto loot is off, so every catch opens a loot window you have to click.\n\nTurn on auto loot so catches go straight to your bags? You can change it back in Options > Controls.",
	button1 = "Turn on",
	button2 = "Not now",
	button3 = "Don't ask again",
	OnAccept = function()
		C_CVar.SetCVar("autoLootDefault", "1")
		ns.Print("auto loot is on.")
	end,
	OnAlt = function()
		ns.db.autoLootHint = false
		ns.Print("won't offer auto loot again. Turn the offer back on in OneCast's options.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function OfferAutoLoot(autoLooted)
	if autoLootOffered or autoLooted or not (ns.db and ns.db.autoLootHint) then
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
	end
	if s.lastCast and now - s.lastCast > NEW_SESSION_AFTER then
		ResetSession()
		s = Session()
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
	summaryTimer = C_Timer.NewTimer(ACTIVE_GAP + 1, PrintSessionSummary)

	-- Open on cast, unless the player closed it during this stretch of fishing.
	if ns.db and ns.db.openOnCast and not dismissed and not (frame and frame:IsShown())
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
	CountAtSkill(zoneTotals, "skillCatches")
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
		local why = NotableReason(l, new[l.id])
		if why then
			AddNotable(zone, l, why)
		end
	end
	UpdateBests(zone)
	if ns.Extravaganza then
		ns.Extravaganza.OnCatch(loot)
	end
	AlertIfRare(loot)
	OfferAutoLoot(autoLooted)
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
	CountAtSkill(z, "skillGetaways")
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
	return string.format("%d of %d caught%s", s.catches, s.casts,
		rate and string.format("  ·  %.0f/hr", rate) or "")
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
local GREEN = "|cff1eff00"
local RED = "|cffff4040"
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
		return minutes .. "m"
	end
	return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

local function Ago(time)
	local seconds = math.max(0, GetServerTime() - time)
	if seconds < 3600 then
		return math.max(1, math.floor(seconds / 60)) .. "m ago"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h ago"
	end
	return math.floor(seconds / 86400) .. "d ago"
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

-- Gold per hour of fishing: at auction prices where an addon has them, else the vendor's.
local function GoldTile(items, seconds, what)
	local ah, _, sources = TotalValue(items, AuctionPrice)
	local auction = next(sources) ~= nil
	local copper = auction and ah or TotalValue(items, VendorPrice)
	local value = copper > 0 and seconds and seconds >= 60 and ShortGold(copper / seconds * 3600)
	return Tile(value, auction and "gold/hr (AH)" or "gold/hr (vendor)",
		"What " .. what .. " is worth per hour of fishing, at " .. (auction and "auction" or "vendor") .. " prices."
		.. (auction and "" or " Auctionator or TSM add auction prices."))
end

-- Vendor and auction gold per hour of fishing, as two tiles.
local function VendorTile(items, seconds, what)
	local copper = TotalValue(items, VendorPrice)
	return Tile(copper > 0 and seconds and seconds >= 60 and ShortGold(copper / seconds * 3600), "vendor/hr",
		"What " .. what .. " sells to a vendor for, per hour of fishing.")
end

local function PriceSources(sources)
	local names = {}
	for _, source in ipairs({ "Auctionator", "TSM" }) do
		if sources[source] then
			names[#names + 1] = source
		end
	end
	return table.concat(names, " and ")
end

local function AuctionTile(items, seconds, what)
	local copper, unpriced, sources = TotalValue(items, AuctionPrice)
	local priced = next(sources) ~= nil
	local tip = "Needs Auctionator or TradeSkillMaster, with prices scanned at the auction house."
	if priced then
		tip = "What " .. what .. " is worth at auction, per hour of fishing. Prices from " .. PriceSources(sources) .. "."
			.. (unpriced and " Some of it has no auction price, so it isn't counted." or "")
	end
	return Tile(priced and copper > 0 and seconds and seconds >= 60 and ShortGold(copper / seconds * 3600),
		"auction/hr", tip)
end

-- Each value as its own row, with why there's none: vendor, then auction.
local function ValueRows(items)
	local vendor, vendorMissing = TotalValue(items, VendorPrice)
	local rows = { { "Vendor value", Coins(vendor) .. (vendorMissing and (GREY .. " (loading)|r") or "") } }
	local ah, _, sources = TotalValue(items, AuctionPrice)
	local auction
	if next(sources) then
		auction = Coins(ah) -- where the prices come from is in the auction tile's tooltip
	elseif not next(items) then
		auction = GREY .. "-|r"
	elseif (Auctionator and Auctionator.API) or TSM_API then
		auction = GREY .. (ns.Prices and ns.Prices.CanScan() and "no prices yet: scan at the AH" or "no prices yet") .. "|r"
	else
		auction = GREY .. "needs Auctionator or TSM|r"
	end
	rows[2] = { "Auction value", auction }
	return rows
end

-- What items are worth, to a vendor and at auction: "1g 73s vendor  ·  9g 75s AH".
local function WorthText(items)
	local vendor, missing = TotalValue(items, VendorPrice)
	local text = Coins(vendor) .. GREY .. (missing and " vendor (loading)|r" or " vendor|r")
	local ah, _, sources = TotalValue(items, AuctionPrice)
	if next(sources) then
		text = text .. SEP .. Coins(ah) .. GREY .. " AH|r"
	elseif next(items) and ns.Prices and ns.Prices.CanScan() then
		text = text .. SEP .. GREY .. "scan at the AH|r"
	end
	return text
end

-- About how long `catches` more will take, at this session's pace (or your usual one).
local function CatchesAndTime(catches)
	local text = string.format("about %d catch%s", catches, catches == 1 and "" or "es")
	local rate = PerHour(Session()) or PerHour(charDB.lifetime)
	if rate and rate > 0 then
		text = text .. GREY .. "  (" .. ShortDuration(catches / rate * 3600) .. ")|r"
	end
	return text
end

-- Items as rows with their count and share of the catch: "x43  77%".
local function ShareRows(items)
	local list = SortedItems(items)
	local total = ItemTotal(items)
	for _, r in ipairs(list) do
		r.right = string.format("x%d" .. GREY .. "  %d%%|r", r.count, math.floor(r.count / math.max(total, 1) * 100 + 0.5))
	end
	return list
end

-- Fish the zone holds that no character of yours has caught yet.
local function MissingHere(zone)
	local list = {}
	if not (ns.FISH and ns.Collection) then
		return list
	end
	for _, fish in ipairs(ns.FISH) do
		local here = false
		for _, z in ipairs(fish.zones or {}) do
			here = here or z == zone
		end
		for _, m in ipairs(fish.more or {}) do
			here = here or m[1] == zone
		end
		if here and ns.Collection.Get(fish.id).total == 0 then
			list[#list + 1] = { id = fish.id, name = fish.name, missing = true,
				icon = C_Item.GetItemIconByID(fish.id) or "Interface\\Icons\\INV_Misc_QuestionMark",
				right = GREY .. "not caught yet|r" }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
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
				right = string.format("%d caught%s", t.catches, rate and string.format("  %.0f/hr", rate) or "") }
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
	return place.name .. GREY .. "  " .. (place.rate and string.format("%.0f/hr", place.rate) or ("x" .. place.count)) .. "|r"
end

-- Returns a view's section title, summary pairs, item rows, list title and empty-list text.
-- A row is { id, name, icon, quality, right } where `right` is the right-hand text; spot rows
-- have `spot` and `zone`, fish to pick have `pick`, fish not caught yet have `missing`.
local function SessionTitle(s)
	return "Session  " .. FormatDuration(s.start and GetServerTime() - s.start or 0)
end

-- Now: this session, your skill's progress, and what's biting.
local function NowView(zone)
	local s = Session()
	local rank, maxRank = FishingSkill()
	local gained = SkillGained(s)
	local rate = PerHour(s)
	local skillRate = gained > 0 and Rate(gained, s.activeTime)
	local tiles = {
		Tile(rate and string.format("%.0f", rate), "fish/hr",
			"Catches per hour of fishing this session. Breaks of over 2 minutes don't count."),
		VendorTile(s.items, s.activeTime, "this session's catch"),
		AuctionTile(s.items, s.activeTime, "this session's catch"),
	}

	local caught = string.format("%d of %d casts", s.catches, s.casts)
	if (s.escapes or 0) > 0 then
		caught = caught .. SEP .. RED .. s.escapes .. " got away|r"
	end
	local stats = { { "Caught", caught } }
	if rank then
		stats[#stats + 1] = { "Skill gained", (gained > 0 and (GREEN .. "+" .. gained .. "|r") or "+0")
			.. (skillRate and (SEP .. string.format("%.0f/hr", skillRate)) or "") }
	end
	if rank and rank >= maxRank then
		stats[#stats + 1] = { "Skill cap", GREY .. "at " .. maxRank .. ": train to go higher|r" }
	elseif rank then
		stats[#stats + 1] = { "Next point", CatchesAndTime(CatchesToGo(rank, 1)) }
		stats[#stats + 1] = { "To " .. maxRank, CatchesAndTime(CatchesToGo(rank, maxRank - rank)) }
	end
	Append(stats, ValueRows(s.items))
	local contest = ns.Extravaganza and ns.Extravaganza.StatusLine(zone)
	if contest then
		stats[#stats + 1] = { "Extravaganza", contest }
	end
	local camp = ns.Camp and ns.Camp.StatusText()
	if camp then
		stats[#stats + 1] = { "Camp", GREEN .. camp .. "|r" }
	end

	local rows, listTitle
	if s.catches > 0 then
		rows, listTitle = ShareRows(s.items), "Caught this session"
	else
		local z = charDB.zoneStats[zone]
		rows, listTitle = z and ShareRows(z.items) or {}, "Caught here before"
	end
	Append(rows, MissingHere(zone))
	return SessionTitle(s), tiles, stats, rows, listTitle, "Nothing caught here yet. Cast to start."
end

-- Farm, for one fish: where it comes up most, and how it's going here.
local function FarmTargetView(itemID, zone)
	local life = charDB.lifetime.items[itemID]
	local name = life and life.name or C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
	local color = QualityColor(life and life.quality or C_Item.GetItemQualityByID(itemID))
	local zones, spots = PlacesFor(itemID)

	local z = charDB.zoneStats[zone]
	local hereCount = z and z.items[itemID] and z.items[itemID].count or 0
	local hereRate = z and Rate(hereCount, z.activeTime)
	local share = z and hereCount > 0 and math.floor(hereCount / math.max(ItemTotal(z.items), 1) * 100 + 0.5)
	local best = zones[1]
	local tiles = {
		Tile(hereRate and string.format("%.0f", hereRate), "per hour here",
			"How many you catch per hour of fishing in " .. zone .. ". Shows after 5 minutes of fishing here."),
		Tile(share and (share .. "%"), "of catches here", "Its share of everything you've caught in " .. zone .. "."),
		Tile(best and best.rate and string.format("%.0f", best.rate), "per hour at best",
			best and ("Your best zone for it: " .. best.name .. ".") or "Where you've caught it most often, per hour."),
	}

	local s = Session()
	local sessionCount = s.items[itemID] and s.items[itemID].count or 0
	local sessionRate = Rate(sessionCount, s.activeTime)
	local last = charDB.lastCaught and charDB.lastCaught[itemID]
	local price = VendorPrice(itemID)
	local ah = AuctionPrice(itemID)
	local stats = {
		{ "This session", "x" .. sessionCount .. (sessionRate and (SEP .. string.format("%.0f/hr", sessionRate)) or "") },
		{ "Best zone", PlaceText(zones[1]) },
		{ "Best spot", PlaceText(spots[1]) },
		{ "Caught", tostring(life and life.count or 0)
			.. (last and (SEP .. "last " .. Ago(last.time) .. GREY .. ", " .. last.zone .. "|r") or "") },
		{ "Price each", (price and Coins(price) or "-") .. (ah and (SEP .. Coins(ah) .. GREY .. " AH|r") or "") },
	}

	local icon = life and life.icon or C_Item.GetItemIconByID(itemID)
	local rows = {}
	for _, place in ipairs(spots) do
		rows[#rows + 1] = { name = place.name, spot = place.spot, zone = place.zone, icon = icon,
			label = place.name ~= place.zone and (place.name .. GREY .. "  " .. place.zone .. "|r") or place.name,
			right = (place.rate and string.format("%.0f/hr  ", place.rate) or "") .. "x" .. place.count }
	end
	local title = (color and color.hex or "|cffffffff") .. name .. "|r"
	return title, tiles, stats, rows, "Where it bites, best first", "Not caught at a spot yet."
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
		Tile(rate and string.format("%.0f", rate), "fish/hr here",
			"Catches per hour of all your fishing in " .. zone .. "."),
		GoldTile(z.items, z.activeTime, "your catch here"),
		Tile(bestSpot and bestSpot.rate and string.format("%.0f", bestSpot.rate), "best spot/hr",
			bestSpot and ("Your best spot here: " .. bestSpot.name .. ".") or "Your best spot here, per hour."),
	}
	local caught = tostring(z.catches) .. SEP .. FormatDuration(z.activeTime) .. " fishing"
	if (z.escapes or 0) > 0 then
		caught = caught .. SEP .. RED .. z.escapes .. " got away|r"
	end
	local stats = {
		{ "Caught here", caught },
		{ "Best spot", bestSpot and bestSpot.name or (GREY .. "-|r") },
		{ "Worth", WorthText(z.items) },
	}

	if charDB.farmList == "fish" then
		local rows = SortedItems(charDB.lifetime.items)
		for _, r in ipairs(rows) do
			local best = PlacesFor(r.id)[1]
			r.pick = true
			r.right = best and (best.name .. GREY .. "  " .. (best.rate and string.format("%.0f/hr", best.rate) or ("x" .. best.count)) .. "|r")
				or ("x" .. r.count)
		end
		return zone, tiles, stats, rows, "Pick a fish to farm", "Nothing caught yet."
	end
	return zone, tiles, stats, spots, "Spots here, best first", "No spots here yet. Cast to start."
end

-- Records: personal bests, the notable catches, and lifetime totals.
local function BestTip(text, best)
	if not best then
		return text .. " Set once a session has 15 minutes of fishing."
	end
	return text .. string.format(" Set %s%s.", date("%d %b %Y", best.time), best.zone and (" in " .. best.zone) or "")
end

local function RecordsView()
	local life = charDB.lifetime
	local bests = charDB.bests or {}
	local tiles = {
		Tile(bests.rate and string.format("%.0f", bests.rate.value), "best fish/hr",
			BestTip("Your most fish per hour in a session.", bests.rate)),
		Tile(bests.vendor and ShortGold(bests.vendor.value), "best gold/hr",
			BestTip("Your most vendor gold per hour in a session.", bests.vendor)),
		Tile(bests.skill and (GREEN .. "+" .. bests.skill.value .. "|r"), "best skill gain",
			BestTip("Your most Fishing skill gained in one session.", bests.skill)),
	}
	local rate = PerHour(life)
	local stats = {
		{ "Fish caught", tostring(life.catches) .. (rate and (SEP .. string.format("%.0f/hr", rate)) or "") },
		{ "Fishing time", FormatDuration(life.activeTime) },
		{ "Longest session", bests.time and (FormatDuration(bests.time.value) .. GREY .. "  " .. date("%d %b", bests.time.time) .. "|r")
			or (GREY .. "-|r") },
	}
	local zonesText = CountKeys(life.zones) .. " zones fished"
	if ns.Collection then
		local caught, total = ns.Collection.Progress()
		stats[#stats + 1] = { "Collection", string.format("%d of %d fish", caught, total) .. SEP .. zonesText }
	else
		stats[#stats + 1] = { "Zones", zonesText }
	end
	local rows = {}
	for i, e in ipairs(charDB.notable or {}) do
		rows[i] = { id = e.id, icon = e.icon, quality = e.quality, right = date("%d %b", e.time),
			name = (e.name or "?") .. (e.quantity and e.quantity > 1 and (" x" .. e.quantity) or ""),
			note = (e.why == "new" and "New for your collection. " or e.why == "wanted" and "Wanted. " or "")
				.. "Caught in " .. (e.zone or "?") .. ", " .. date("%d %b %H:%M", e.time) .. "." }
	end
	return "All-time records", tiles, stats, rows, "Notable catches",
		"Nothing yet. Rare catches, wanted fish and new fish for your collection show here."
end

-- Old view names, from before 0.8.0 and in /onecast commands.
local VIEW_ALIAS = { zone = "farm", lifetime = "records", log = "records", now = "session",
	spots = "farm", alltime = "records" }
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
			status.kind = "clear"
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
		return GREY .. "Fishing skill not found.|r"
	end
	local status = Stats.ZoneStatus(zone, spot)
	zone = status.place
	if status.kind == "note" then
		return string.format("|cff1eff00%s: %s.|r", zone, status.note)
	elseif status.kind == "getaways" and status.needed then
		return string.format("|cffff4040%s is listed at %d, but fish got away here at %d skill: it may need more.|r",
			zone, status.needed, status.escapeSkill)
	elseif status.kind == "getaways" then
		return string.format("|cffff4040%s: level unknown, but %d fish got away here: skill too low.|r",
			zone, status.escapes)
	elseif status.kind == "outgrown" then
		return string.format("%s%s: level unknown. Fish got away at %d skill, and you're above that now.|r",
			GREY, zone, status.escapeSkill)
	elseif status.kind == "clear" then
		return string.format("|cff1eff00%s: level unknown, but no fish got away in %d catches.|r",
			zone, status.catches)
	elseif status.kind == "unknown" then
		return GREY .. zone .. ": fishing level unknown. Getaways here will show if your skill is too low.|r"
	elseif status.kind == "ok" then
		return string.format("|cff1eff00%s needs %d: no fish should get away.|r", zone, status.needed)
	end
	-- A lure in the bags that would close the gap is the more useful thing to say.
	local hint = ns.Lure and ns.Lure.CoverHint(status.short)
	if hint then
		return string.format("|cffff4040%s needs %d: %d short, fish will get away.|r |cffffd100%s|r",
			zone, status.needed, status.short, hint)
	end
	return string.format("|cffff4040%s needs %d: %d short, fish will get away.|r %sabout %d catches to go%s.|r",
		zone, status.needed, status.short, GREY, CatchesToGo(rank, status.short),
		rank + status.short > maxRank and " (train first)" or "")
end

-- The zone's status in short parts, for the strip under the skill bar: `mood` ("good", "bad",
-- "warn" or "unknown"), the place, what it needs, and a word or two on how you stand. The full
-- sentence (ZoneVerdict) goes in its tooltip.
function Stats.ZoneBadge(zone, spot)
	local status = Stats.ZoneStatus(zone, spot)
	local badge = { place = status.place, needed = status.needed }
	local kind = status.kind
	if status.needed and kind ~= "getaways" then
		badge.need = "needs " .. status.needed
	elseif status.needed then
		badge.need = "listed at " .. status.needed
	elseif kind ~= "note" then
		badge.need = "level unknown"
	end
	if kind == "ok" then
		badge.mood, badge.status = "good", "Ready"
	elseif kind == "short" then
		if ns.Lure and ns.Lure.CoverHint(status.short) then
			badge.mood, badge.status = "warn", status.short .. " short" -- yellow: a lure in your bags covers it
		else
			badge.mood, badge.status = "bad", status.short .. " short"
		end
	elseif kind == "getaways" then
		badge.mood, badge.status = "bad", "Fish get away"
	elseif kind == "clear" then
		badge.mood, badge.status = "good", "No getaways"
	elseif kind == "note" then
		badge.mood, badge.status = "good", "No minimum"
	elseif kind == "outgrown" then
		badge.mood, badge.status = "unknown", "Above last getaway"
	elseif kind == "level" then
		badge.mood, badge.status = "unknown", "Skill unknown"
	else
		badge.mood, badge.status = "unknown", "Unknown"
	end
	return badge
end

Stats.FishingSkill = FishingSkill
Stats.CurrentZone = CurrentZone

-- Skill bar fraction and value text.
local function SkillStatus()
	local rank, maxRank, modifier = FishingSkill()
	if not rank then
		return 0, "?"
	end
	local value = modifier > 0 and string.format("%d|cff1eff00+%d|r/%d", rank, modifier, maxRank)
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

local function CreateShell(name, titleText, icon)
	local f = TryCreate("Frame", name, UIParent, "ButtonFrameTemplate")
	if f then
		SetTitle(f, titleText)
		SetPortrait(f, icon)
		f.Inset:ClearAllPoints()
		f.Inset:SetPoint("TOPLEFT", 4, -60)
		f.Inset:SetPoint("BOTTOMRIGHT", -6, 28)
		ns.Theme.Frame(f, f.Inset)
		return f, f.Inset
	end

	-- Fallback: classic dialog frame with a plain inset.
	f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
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
	ns.Theme.Frame(f, inset)
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
	local text = textHolder:CreateFontString(nil, "OVERLAY", Number12FontOutline and "Number12FontOutline" or "GameFontHighlightSmall")
	text:SetPoint("CENTER", 0, 0)

	-- The water flows on a loop while the window is open (hidden frames don't animate).
	local flow = holder:CreateAnimationGroup()
	flow:SetLooping("REPEAT")
	local flipbook = flow:CreateAnimation("FlipBook")
	flipbook:SetTarget(fill)
	flipbook:SetDuration(2)
	local info = C_Texture.GetAtlasInfo(WATER_FILL)
	local rows = info and info.height and math.max(1, math.floor(info.height / WATER_FRAME_HEIGHT + 0.5)) or 30
	flipbook:SetFlipBookRows(rows)
	flipbook:SetFlipBookColumns(2)
	flipbook:SetFlipBookFrames(rows * 2)
	flipbook:SetFlipBookFrameWidth(0)
	flipbook:SetFlipBookFrameHeight(0)
	flow:Play()

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
		if target and fraction > target then
			flash:Stop()
			flash:Play()
		end
		from = current or 0
		target = fraction
		started = GetTime()
		self:SetScript("OnUpdate", Slide)
	end

	holder:SetScript("OnSizeChanged", function()
		if current then
			Place(current)
		end
	end)
	holder:HookScript("OnShow", function()
		if not flow:IsPlaying() then
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
			if holder:IsVisible() and width > 30 then
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

	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
	ns.Theme.Register(bg, "header")
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
local function StatTile(parent, index)
	local width = math.floor((INSET_WIDTH - 2 * EDGE - 2 * TILE_GAP) / 3)
	local t = CreateFrame("Frame", nil, parent)
	t:SetSize(width, TILE_HEIGHT)
	t:SetPoint("TOPLEFT", EDGE + (index - 1) * (width + TILE_GAP), TILES_TOP)
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
	t.caption = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
	strip.band = strip:CreateTexture(nil, "BACKGROUND")
	strip.band:SetAllPoints()
	strip.band:SetTexture("Interface\\Buttons\\WHITE8x8")
	strip.edge = strip:CreateTexture(nil, "BORDER")
	strip.edge:SetPoint("TOPLEFT")
	strip.edge:SetPoint("BOTTOMLEFT")
	strip.edge:SetWidth(2)
	strip.edge:SetTexture("Interface\\Buttons\\WHITE8x8")
	strip.icon = strip:CreateTexture(nil, "ARTWORK")
	strip.icon:SetSize(14, 14)
	strip.icon:SetPoint("LEFT", PAD, 0)
	strip.place = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	strip.place:SetPoint("LEFT", strip.icon, "RIGHT", 5, 0)
	strip.place:SetWordWrap(false)
	strip.need = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	strip.need:SetPoint("LEFT", strip.place, "RIGHT", 6, 0)
	strip.need:SetWordWrap(false)
	strip.status = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	strip.status:SetPoint("RIGHT", -PAD, 0)
	strip.status:SetWordWrap(false)

	function strip:Update(zone, spot)
		local badge = Stats.ZoneBadge(zone, spot)
		local mood = MOODS[badge.mood]
		local r, g, b = mood.color[1], mood.color[2], mood.color[3]
		self.band:SetVertexColor(r, g, b, 0.12)
		self.edge:SetVertexColor(r, g, b, 0.9)
		if HasAtlas(mood.atlas) then
			self.icon:SetAtlas(mood.atlas)
		else
			self.icon:SetTexture(mood.file)
		end
		-- A long place name is cut short rather than running into the status.
		self.place:SetWidth(0)
		self.place:SetText(badge.place)
		self.place:SetWidth(math.min(self.place:GetStringWidth() or 0, PLACE_MAX_WIDTH))
		self.need:SetText(badge.need or "")
		self.status:SetText(badge.status)
		self.status:SetTextColor(r, g, b)
		self.badge = badge
		self.tip = Stats.ZoneVerdict(zone, spot)
	end

	strip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(self.badge and self.badge.place or "")
		local rank, _, modifier = FishingSkill()
		if self.badge and self.badge.needed then
			GameTooltip:AddDoubleLine("Fishing needed", tostring(self.badge.needed), 1, 0.82, 0, 1, 1, 1)
		end
		if rank then
			GameTooltip:AddDoubleLine("Your skill", modifier > 0 and string.format("%d + %d", rank, modifier) or tostring(rank),
				1, 0.82, 0, 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(self.tip or "", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	strip:SetScript("OnLeave", GameTooltip_Hide)
	return strip
end

local function StatRow(parent, index, y)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 10, y)
	row:SetPoint("TOPRIGHT", -10, y)
	row:SetHeight(STAT_HEIGHT)
	RowBackground(row, index)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- gold, like "Health:"
	row.label:SetPoint("LEFT", PAD, 0)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -PAD, 0)
	row.value:SetJustifyH("RIGHT")
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
		ns.Print("the map can't be opened from here in combat.")
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
				ns.Print(string.format("waypoint set: %s (%.0f, %.0f).", label, x * 100, y * 100))
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
local WOWHEAD_ITEM_URL = "https://www.wowhead.com/forever/item=%d"

StaticPopupDialogs["ONECAST_WOWHEAD"] = {
	text = "%s on Wowhead\nPress Ctrl+C to copy, then paste it into your browser.",
	button1 = CLOSE or "Close",
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

local function ShowWowheadLink(itemID, name)
	StaticPopup_Show("ONECAST_WOWHEAD", name or ("item " .. itemID), nil,
		string.format(WOWHEAD_ITEM_URL, itemID))
end

local function ItemRow(parent, index, y)
	local row = CreateFrame("Button", nil, parent)
	row:SetPoint("TOPLEFT", 10, y)
	row:SetPoint("TOPRIGHT", -10, y)
	row:SetHeight(ITEM_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	RowBackground(row, index)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ITEM_HEIGHT - 2, ITEM_HEIGHT - 2)
	row.icon:SetPoint("LEFT", PAD, 0)
	row.border = row:CreateTexture(nil, "OVERLAY")
	row.border:SetAllPoints(row.icon)
	row.border:SetTexture("Interface\\Common\\WhiteIconFrame")

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
		if self.missing then
			-- Not caught yet: its page in the collection, with where it's found.
			ns.Book.Show()
			ns.Book.ShowFish(self.itemID)
			return
		end
		if mouseButton == "RightButton" then
			ToggleWanted(self.itemID, self.itemName)
			return
		end
		if self.pick or IsControlKeyDown() then
			Stats.Farm(self.itemID)
			return
		end
		-- Shift-click links the item in chat, as elsewhere in the UI; plain click: Wowhead.
		local link = select(2, C_Item.GetItemInfo(self.itemID))
		if not (link and HandleModifiedItemClick and HandleModifiedItemClick(link)) then
			ShowWowheadLink(self.itemID, self.itemName)
		end
	end)
	row:SetScript("OnEnter", function(self)
		local t = self.spot
		if t then
			-- A spot on the Farm tab: its numbers and what bites there.
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.itemName)
			GameTooltip:AddDoubleLine("Caught", string.format("%d of %d", t.catches, t.casts), 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("Fishing time", FormatDuration(t.activeTime), 1, 0.82, 0, 1, 1, 1)
			local rate = PerHour(t)
			GameTooltip:AddDoubleLine("Fish per hour", rate and string.format("%.0f", rate) or "-", 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("Vendor value", Coins(TotalValue(t.items, VendorPrice)), 1, 0.82, 0, 1, 1, 1)
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
				local name = C_Item.GetItemNameByID(list[i].id) or ("item " .. list[i].id)
				local color = QualityColor(C_Item.GetItemQualityByID(list[i].id))
				GameTooltip:AddDoubleLine(name, "x" .. list[i].count, color and color.r or 1, color and color.g or 1,
					color and color.b or 1, 1, 1, 1)
			end
			GameTooltip:AddLine(" ")
			if t.x or Stats.AreaPlace(self.itemName) then
				GameTooltip:AddLine("Click: show on the map, with a waypoint", 0.6, 0.8, 1)
			else
				GameTooltip:AddLine("Click: show the zone on the map", 0.6, 0.8, 1)
				GameTooltip:AddLine("Fish here again to add a waypoint.", 0.6, 0.6, 0.6, true)
			end
			GameTooltip:Show()
		elseif self.missing then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Not in your collection yet, and found in this zone.", 1, 1, 1, true)
			GameTooltip:AddLine("Click: see it in the collection", 0.6, 0.8, 1)
			GameTooltip:Show()
		elseif self.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			if self.note then
				GameTooltip:AddLine(self.note, 1, 1, 1, true)
			end
			GameTooltip:AddLine(" ")
			if self.pick then
				GameTooltip:AddLine("Click: where it bites best", 0.6, 0.8, 1)
			else
				GameTooltip:AddLine("Click: Wowhead link", 0.6, 0.8, 1)
				GameTooltip:AddLine("Ctrl-click: where it bites best", 0.6, 0.8, 1)
			end
			GameTooltip:AddLine("Shift-click: link in chat", 0.6, 0.8, 1)
			GameTooltip:AddLine(IsWanted(self.itemID) and "Right-click: unmark wanted"
				or "Right-click: mark as wanted (alert on catch)", 0.6, 0.8, 1)
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
	ns.Theme.Register(b, "button", { [b.icon] = true })
	b.icon:ClearAllPoints()
	b.icon:SetPoint("CENTER")
	b.icon:SetSize(ICON_BUTTON_SIZE - 6, ICON_BUTTON_SIZE - 6)
	SetIconArt(b.icon, art)
	b:SetScript("OnClick", function(self, ...)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		onClick(self, ...)
	end)
	b:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(GLYPH_HOVER[1], GLYPH_HOVER[2], GLYPH_HOVER[3])
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tooltip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(GLYPH_GOLD[1], GLYPH_GOLD[2], GLYPH_GOLD[3])
		GameTooltip:Hide()
	end)
	return b
end

-- Font object, at a given size. The font comes from the object, not the string: a reused string
-- can keep the font it was last given, which would put a heading's font on body text.
local function SizedFont(fs, fontObject, size)
	fs:SetFontObject(fontObject)
	local path, _, flags = fontObject:GetFont()
	if path then
		fs:SetFont(path, size, flags)
	end
end

-- Closing the options goes back to the game menu, which first hides everything in
-- UISpecialFrames, as Escape does. So windows named here step off that list as the options
-- close, and back on the next frame: they stay open, and Escape still closes them.
local keepOpen = {}

local function KeepOpenThroughOptions(frameName)
	keepOpen[frameName] = true
end

if EventRegistry then
	EventRegistry:RegisterCallback("SettingsPanel.OnHide", function()
		local removed = {}
		for i = #UISpecialFrames, 1, -1 do
			if keepOpen[UISpecialFrames[i]] then
				removed[#removed + 1] = table.remove(UISpecialFrames, i)
			end
		end
		if #removed > 0 then
			C_Timer.After(0, function()
				for _, name in ipairs(removed) do
					tinsert(UISpecialFrames, name)
				end
			end)
		end
	end, keepOpen)
end

-- Opening the options does the same: the panel opens as a "center" window, and showing one
-- first closes every window in UISpecialFrames. So when OneCast opens them, its windows step off
-- the list until the panel is up (or a moment has passed, if it never opens), then back on.
local held

local function PutBack()
	if held then
		for _, name in ipairs(held) do
			tinsert(UISpecialFrames, name)
		end
		held = nil
	end
end

local function HoldOpenForOptions()
	if held then
		return
	end
	held = {}
	for i = #UISpecialFrames, 1, -1 do
		if keepOpen[UISpecialFrames[i]] then
			held[#held + 1] = table.remove(UISpecialFrames, i)
		end
	end
	C_Timer.After(1, PutBack)
end

if SettingsPanel then
	SettingsPanel:HookScript("OnShow", function()
		C_Timer.After(0, PutBack)
	end)
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
	KeepOpenThroughOptions = KeepOpenThroughOptions,
	HoldOpenForOptions = HoldOpenForOptions,
	RememberPosition = RememberPosition,
	ShowOnMap = ShowOnMap,
	TryCreate = TryCreate,
	HasAtlas = HasAtlas,
	SizedFont = SizedFont,
	CreateShell = CreateShell,
	SectionHeader = SectionHeader,
	RowBackground = RowBackground,
	StatRow = StatRow,
	IconButton = IconButton,
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
		ns.Theme.Register(tab, "button")
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
	local f, inset = CreateShell("OneCastStatsFrame", "OneCast  " .. GREY .. "v" .. (ns.VERSION or "?") .. "|r",
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
	tinsert(UISpecialFrames, f:GetName()) -- Escape closes it
	KeepOpenThroughOptions(f:GetName())
	if f.CloseButton then
		f.CloseButton:HookScript("OnClick", function()
			dismissed = true
		end)
	end

	CreateTabs(f, inset)

	-- Fishing skill: the professions window's rank bar, then the verdict for this zone.
	f.skillBar = RankBar(inset, ns.GetFishingName and ns.GetFishingName() or "Fishing")

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
	-- Farm tab: switch the list between this zone's spots and your fish, or leave a fish.
	f.listToggle = CreateFrame("Button", nil, f.listHeader, "UIPanelButtonTemplate")
	ns.Theme.Register(f.listToggle, "button")
	f.listToggle:SetSize(64, 18)
	f.listToggle:SetPoint("RIGHT", -4, 1)
	f.listToggle:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if charDB.farmTarget then
			charDB.farmTarget, charDB.farmList = nil, "fish"
		else
			charDB.farmList = charDB.farmList ~= "fish" and "fish" or nil
		end
		Stats.Refresh()
	end)
	f.listToggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if charDB.farmTarget then
			GameTooltip:SetText("Back to all your fish")
		elseif charDB.farmList == "fish" then
			GameTooltip:SetText("Show each spot in this zone, best fish per hour first")
		else
			GameTooltip:SetText("Pick a fish, to see where it bites best")
		end
		GameTooltip:Show()
	end)
	f.listToggle:SetScript("OnLeave", GameTooltip_Hide)
	f.rows = {}
	for i = 1, MAX_ROWS do
		f.rows[i] = ItemRow(inset, i, 0)
	end
	f.more = inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.more:SetWordWrap(true)

	-- Bottom bar: square icon buttons, like the Character frame's model controls.
	local options = IconButton(f, "Options", "Options", function()
		ns.Hub.ShowOptions()
	end)
	options:SetPoint("BOTTOMRIGHT", -22, 3)
	f.gear = IconButton(f, "Weapons", "Re-equip weapons", function()
		OneCast_RestoreWeapons()
	end)
	f.scan = IconButton(f, "Scan", "Scan prices with Auctionator", function()
		ns.Prices.Scan()
	end)
	f.reset = IconButton(f, "Reset", "Reset session", function()
		StaticPopup_Show("ONECAST_RESET_SESSION")
	end)
	local book = IconButton(f, "Book", "Fishing collection", function()
		ns.Book.Toggle()
	end)
	-- Data report, with a small green dot while there's something OneCast doesn't know yet.
	f.report = IconButton(f, "Report", "Data report", function()
		ns.Report.Toggle()
	end)
	f.report.dot = f.report:CreateTexture(nil, "OVERLAY", nil, 3)
	f.report.dot:SetSize(9, 9)
	f.report.dot:SetPoint("CENTER", f.report, "TOPRIGHT", -3, -3)
	f.report.dot:SetTexture("Interface\\COMMON\\Indicator-Green")
	f.report.dot:Hide()
	f.report:HookScript("OnEnter", function()
		local line = ns.Report and ns.Report.TooltipLine()
		GameTooltip:AddLine(line or "Your catches and getaways as text, to share.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.bottomButtons = { options, book, f.report, f.gear, f.scan, f.reset }

	-- The resize grip in the bottom-right corner is the hub's, on every page (Hub.Attach).

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() and not (ns.db and ns.db.lockWindow) then
			Stats.SetScale(f:GetScale() * 100 + delta * SCALE_STEP)
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
	frame.report.dot:SetShown(ns.Report and #ns.Report.Unshared() > 0 or false)
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
			row:Show()
			shownStats = i
		else
			row:Hide()
		end
	end

	-- The list starts under the detail rows and fills the rest of the window.
	local listTop = STATS_TOP - shownStats * STAT_HEIGHT - GAP
	local rowsTop = listTop - HEADER_HEIGHT - HEADER_GAP
	frame.listHeader:ClearAllPoints()
	frame.listHeader:SetPoint("TOPLEFT", EDGE, listTop)
	frame.listHeader:SetPoint("TOPRIGHT", -EDGE, listTop)
	local capacity = math.min(MAX_ROWS, math.floor((INSET_HEIGHT + rowsTop - 18) / ITEM_HEIGHT))
	frame.listHeader.text:SetText(listTitle)
	frame.listToggle:SetShown(view == "farm")
	frame.listToggle:SetText(charDB.farmTarget and "Back" or charDB.farmList == "fish" and "Spots" or "Fish")
	for i, row in ipairs(frame.rows) do
		local r = i <= capacity and rows[i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", EDGE, rowsTop - (i - 1) * ITEM_HEIGHT)
		row:SetPoint("TOPRIGHT", -EDGE, rowsTop - (i - 1) * ITEM_HEIGHT)
		if r then
			local color = QualityColor(r.quality)
			row.itemID = r.id
			row.itemName = r.name
			row.spot, row.zone, row.pick, row.missing, row.note = r.spot, r.zone, r.pick, r.missing, r.note
			row.icon:SetTexture(r.icon)
			row.icon:SetDesaturated(r.missing or false)
			row.name:SetText((r.label or r.name or ("item:" .. r.id)) .. (r.id and IsWanted(r.id) and " |cffffd100*|r" or ""))
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
			row.itemID, row.spot, row.zone, row.pick, row.missing, row.note = nil, nil, nil, nil, nil, nil
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
		frame.more:SetText(string.format("and %d more...", #rows - capacity))
	else
		frame.more:SetText("")
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
	ResetSession()
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
			ns.Lure.OnChange(ScheduleRefresh) -- a lure changes the zone verdict
		end
	elseif event == "LOOT_READY" then
		OnLootReady(...)
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
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		-- Every addon's items report here: only ours matter, and a failed one isn't retried.
		local itemID, success = ...
		if itemRequests[itemID] then
			if success then
				itemRequests[itemID] = nil
				ScheduleRefresh()
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
		ScheduleRefresh()
	end
end)

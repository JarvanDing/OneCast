-- OneCast stats: casts, catches, fish per hour, value and what was caught, per character,
-- shown for the session, the current zone (all time), lifetime, and as a catch log.
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

-- Layout, in pixels from the top of the inset panel.
local STAT_ROWS, STAT_HEIGHT = 8, 17
local MAX_ROWS, ITEM_HEIGHT = 8, 22
local SUMMARY_TOP = -78
local LIST_TOP = SUMMARY_TOP - 28 - STAT_ROWS * STAT_HEIGHT - 6
local WINDOW_WIDTH = 340
local TABS_LEFT, TAB_GAP = 62, 2 -- top tabs start right of the portrait
local TAB_WIDTH = math.floor((WINDOW_WIDTH - TABS_LEFT - 10 - 3 * TAB_GAP) / 4)
local WINDOW_HEIGHT = 60 + (-LIST_TOP + 28 + MAX_ROWS * ITEM_HEIGHT + 22) + 28

local VIEWS = {
	{ key = "session", label = "会话" },
	{ key = "zone", label = "区域" },
	{ key = "lifetime", label = "生涯" },
	{ key = "log", label = "记录" },
}

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

local function NewTotals()
	return { casts = 0, catches = 0, escapes = 0, activeTime = 0, items = {}, zones = {} }
end

local function Session()
	return charDB.session
end

-- Empty while the zone is still loading; never key stats under "".
local function CurrentZone()
	local zone = GetRealZoneText()
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
		and " 已标记为想要：钓到时会提醒。"
		or " 已取消想要标记。"))
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
	end
	for i = #charDB.log, LOG_SIZE + 1, -1 do
		charDB.log[i] = nil
	end
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
				RaidNotice_AddMessage(RaidWarningFrame, "钓到 " .. text .. "！", ChatTypeInfo.RAID_WARNING)
			end
			PlaySound(SOUNDKIT.RAID_WARNING)
			ns.Print("稀有渔获：" .. (l.link or text))
		end
	end
end

-- Sum up the session in chat once the player has stopped for a while.
local function SessionSummaryText(s)
	local parts = { string.format("%d 条渔获", s.catches) }
	local rate = PerHour(s)
	if rate then
		parts[#parts + 1] = string.format("%.0f/时", rate)
	end
	local vendor = TotalValue(s.items, VendorPrice)
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
	return table.concat(parts, "，")
end

local function PrintSessionSummary()
	summaryTimer = nil
	local s = Session()
	if not (ns.db and ns.db.sessionSummary) or s.catches <= (s.summarized or 0) then
		return
	end
	local lead = (s.summarized or 0) > 0 and "目前会话：" or "会话："
	s.summarized = s.catches
	ns.Print(lead .. SessionSummaryText(s) .. "。")
end

StaticPopupDialogs["ONECAST_AUTOLOOT"] = {
	text = "自动拾取未开启，每次渔获都会弹出战利品窗口需要点击。\n\n是否开启自动拾取，让渔获直接进包？可在 选项 > 控制 中改回。",
	button1 = "开启",
	button2 = "暂不",
	button3 = "不再询问",
	OnAccept = function()
		C_CVar.SetCVar("autoLootDefault", "1")
		ns.Print("已开启自动拾取。")
	end,
	OnAlt = function()
		ns.db.autoLootHint = false
		ns.Print("将不再提示自动拾取。可在「哇，大鱼」选项中重新开启此提示。")
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
	if ns.db and ns.db.openOnCast and not dismissed and not (frame and frame:IsShown()) then
		Stats.Show()
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
	AddToLog(zone, loot)

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

	if ns.Collection then
		s.newFish = (s.newFish or 0) + (ns.Collection.OnCatch(loot, zone) or 0)
	end
	if ns.Extravaganza then
		ns.Extravaganza.OnCatch(loot)
	end
	AlertIfRare(loot)
	OfferAutoLoot(autoLooted)
	RefreshIfShown()
end

local function OnFishEscaped()
	if not awaitingLoot then
		return
	end
	awaitingLoot = false
	local s = Session()
	s.escapes = (s.escapes or 0) + 1
	charDB.lifetime.escapes = (charDB.lifetime.escapes or 0) + 1
	local z = ZoneTotals(CurrentZone())
	z.escapes = (z.escapes or 0) + 1
	-- The highest skill a fish has got away at, lure included: later skill-ups can outgrow it.
	-- An old value a clean run has already cleared doesn't count.
	if (z.cleanCatches or 0) >= CLEAN_CATCHES then
		z.escapeSkill = nil
	end
	z.cleanCatches = 0
	local rank, _, modifier = FishingSkill()
	if rank then
		z.escapeSkill = math.max(z.escapeSkill or 0, rank + modifier)
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

-- One-line summary for the minimap tooltip.
function Stats.Summary()
	local s = Session()
	if s.casts == 0 then
		return "本次会话尚未钓鱼"
	end
	local rate = PerHour(s)
	return string.format("会话：%d/%d 钓获%s", s.catches, s.casts,
		rate and string.format("，%.0f/时", rate) or "")
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

local function CatchPairs(totals)
	local rate = PerHour(totals)
	return {
		{ "钓获", string.format("%d / %d%s", totals.catches, totals.casts,
			totals.casts > 0 and string.format("  (%.0f%%)", totals.catches / totals.casts * 100) or "") },
		{ "钓鱼时间", FormatDuration(totals.activeTime) },
		{ "每小时鱼数", rate and string.format("%.0f", rate) or "-" },
	}
end

local function ValuePairs(items)
	local vendor, vendorMissing = TotalValue(items, VendorPrice)
	local pairs_ = {
		{ "商人售价", Coins(vendor) .. (vendorMissing and (GREY .. "（加载中）|r") or "") },
	}
	local ah, ahMissing, sources = TotalValue(items, AuctionPrice)
	if not next(sources) then
		local hint = "-"
		if next(items) then
			hint = (ns.Prices and ns.Prices.CanScan()) and "请在拍卖行扫描" or "需要 Auctionator 或 TSM"
		end
		pairs_[2] = { "拍卖估价", GREY .. hint .. "|r" }
		return pairs_
	end
	local names = {}
	if sources.Auctionator then
		names[#names + 1] = "Auctionator"
	end
	if sources.TSM then
		names[#names + 1] = "TSM"
	end
	pairs_[2] = { "拍卖估价", string.format("%s %s（%s%s）|r", Coins(ah), GREY,
		table.concat(names, "、"), ahMissing and "，部分无价" or "") }
	return pairs_
end

local function CountKeys(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

local function Append(list, more)
	for _, entry in ipairs(more) do
		list[#list + 1] = entry
	end
	return list
end

-- Each spot in a zone, best fish per hour first: { name, icon, right, spot }.
local function SpotRows(z)
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
			rows[#rows + 1] = { name = name, spot = t, rate = rate,
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

local function SkillPair(s)
	local rank, maxRank = FishingSkill()
	if not rank then
		return { "技能提升", "-" }
	end
	local gained = SkillGained(s)
	local text = gained > 0 and string.format("|cff1eff00+%d|r", gained) or "+0"
	if rank >= maxRank then
		text = text .. GREY .. "  （已达当前上限）|r"
	else
		local n = CatchesToGo(rank, 1)
		text = text .. GREY .. string.format("  （约 %d 次后升级）|r", n)
	end
	return { "技能提升", text }
end

local function CountRows(rows)
	for _, r in ipairs(rows) do
		r.right = "x" .. r.count
	end
	return rows
end

-- Returns a view's section title, summary pairs, item rows, list title and empty-list text.
-- A row is { id, name, icon, quality, right } where `right` is the right-hand text.
local function SessionTitle(s)
	return "会话  " .. FormatDuration(s.start and GetServerTime() - s.start or 0)
end

local function BuildView(view)
	local zone = CurrentZone()
	if view == "zone" then
		local z = charDB.zoneStats[zone] or NewTotals()
		local stats = CatchPairs(z)
		stats[#stats + 1] = { "脱钩", tostring(z.escapes or 0) }
		local spots = SpotRows(z)
		local best = spots[1]
		stats[#stats + 1] = { "最佳地点", best and (best.name .. (best.rate and string.format(GREY .. "  %.0f/时|r", best.rate) or ""))
			or (GREY .. "-|r") }
		Append(stats, ValuePairs(z.items))
		if charDB.zoneList == "spots" then
			return zone, stats, spots, "此处地点", "尚无地点记录：需插件 0.3.0 及以后才会记录。"
		end
		return zone, stats, CountRows(SortedItems(z.items)), "此处渔获", "此处尚未钓到任何东西。"
	elseif view == "lifetime" then
		local life = charDB.lifetime
		local stats = CatchPairs(life)
		stats[#stats + 1] = { "钓过的区域", tostring(CountKeys(life.zones)) }
		if ns.Collection then
			local caught, total = ns.Collection.Progress()
			stats[#stats + 1] = { "图鉴", string.format("%d / %d 种鱼", caught, total) }
		end
		Append(stats, ValuePairs(life.items))
		return "生涯", stats, CountRows(SortedItems(life.items)), "渔获", "尚未钓到任何东西。"
	elseif view == "log" then
		local rows = {}
		for i = 1, math.min(#charDB.log, MAX_ROWS) do
			local e = charDB.log[i]
			rows[i] = { id = e.id, icon = e.icon, quality = e.quality, right = date("%H:%M", e.time),
				name = (e.name or "?") .. (e.quantity > 1 and (" x" .. e.quantity) or "") }
		end
		local last = charDB.log[1]
		local stats = {
			{ "已记录", string.format("%d / %d", #charDB.log, LOG_SIZE) },
			{ "最近渔获", last and (date("%H:%M", last.time) .. "  " .. GREY .. last.zone .. "|r") or "-" },
		}
		return "渔获记录", stats, rows, "最近渔获", "尚无渔获记录。"
	end

	local s = Session()
	local stats = CatchPairs(s)
	stats[#stats + 1] = { zone, tostring(s.zones[zone] or 0) }
	stats[#stats + 1] = SkillPair(s)
	Append(stats, ValuePairs(s.items))
	local contest = ns.Extravaganza and ns.Extravaganza.StatusLine(zone)
	if contest then
		stats[#stats + 1] = { "钓鱼大赛", contest }
	end
	return SessionTitle(s), stats,
		CountRows(SortedItems(s.items)), "渔获", "尚未钓到任何东西。"
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
-- Shared by the stats window and the book's Zones view, so the two can't disagree.
function Stats.ZoneStatus(zone)
	local rank, _, modifier = FishingSkill()
	local here = charDB.zoneStats[zone]
	-- Enough catches in a row since the last getaway and it no longer counts against the zone:
	-- it could have come from a lure's bonus, or from before a skill-up.
	local cleared = here and (here.cleanCatches or 0) >= CLEAN_CATCHES
	local status = {
		needed = ns.ZoneSkill and ns.ZoneSkill(zone) or (ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone]),
		note = ns.ZoneNote and ns.ZoneNote(zone) or (ns.ZONE_FISHING_NOTE and ns.ZONE_FISHING_NOTE[zone]),
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
function Stats.ZoneVerdict(zone)
	local rank, maxRank = FishingSkill()
	if not rank then
		return GREY .. "未找到钓鱼技能。|r"
	end
	local name = ns.ZoneLabel and ns.ZoneLabel(zone) or zone
	local status = Stats.ZoneStatus(zone)
	if status.kind == "note" then
		return string.format("|cff1eff00%s：%s。|r", name, status.note)
	elseif status.kind == "getaways" and status.needed then
		return string.format("|cffff4040%s 标注需要 %d，但在 %d 技能时此处仍脱钩：实际可能更高。|r",
			name, status.needed, status.escapeSkill)
	elseif status.kind == "getaways" then
		return string.format("|cffff4040%s：等级未知，但此处已脱钩 %d 次：技能不足。|r",
			name, status.escapes)
	elseif status.kind == "outgrown" then
		return string.format("%s%s：等级未知。此前在 %d 技能时脱钩过，你现在已超过该技能。|r",
			GREY, name, status.escapeSkill)
	elseif status.kind == "clear" then
		return string.format("|cff1eff00%s：等级未知，但 %d 次钓获均未脱钩。|r",
			name, status.catches)
	elseif status.kind == "unknown" then
		return GREY .. name .. "：钓鱼等级未知。若此处脱钩，会提示技能是否不足。|r"
	elseif status.kind == "ok" then
		return string.format("|cff1eff00%s 需要 %d：鱼不应脱钩。|r", name, status.needed)
	end
	-- A lure in the bags that would close the gap is the more useful thing to say.
	local hint = ns.Lure and ns.Lure.CoverHint(status.short)
	if hint then
		return string.format("|cffff4040%s 需要 %d：还差 %d，鱼会脱钩。|r |cffffd100%s|r",
			name, status.needed, status.short, hint)
	end
	return string.format("|cffff4040%s 需要 %d：还差 %d，鱼会脱钩。|r %s约还需 %d 次钓获%s。|r",
		name, status.needed, status.short, GREY, CatchesToGo(rank, status.short),
		rank + status.short > maxRank and "（请先学技能）" or "")
end

Stats.FishingSkill = FishingSkill

-- Skill bar fraction, value text and the verdict for the current zone.
local function SkillStatus()
	local rank, maxRank, modifier = FishingSkill()
	local verdict = Stats.ZoneVerdict(CurrentZone())
	if not rank then
		return 0, "?", verdict
	end
	local value = modifier > 0 and string.format("%d|cff1eff00+%d|r/%d", rank, modifier, maxRank)
		or string.format("%d/%d", rank, maxRank)
	return rank / math.max(maxRank, 1), value, verdict
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

local function RankBar(parent, name)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("TOPLEFT", 14, -6)
	holder:SetPoint("TOPRIGHT", -14, -6)
	holder:SetHeight(40)

	local title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP")
	title:SetText(name)

	local frameBorder = CreateFrame("Frame", nil, holder, "BackdropTemplate")
	frameBorder:SetPoint("TOPLEFT", 0, -18)
	frameBorder:SetPoint("TOPRIGHT", 0, -18)
	frameBorder:SetHeight(20)
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
	h:SetPoint("TOPLEFT", 8, y)
	h:SetPoint("TOPRIGHT", -8, y)
	h:SetHeight(24)
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

local function StatRow(parent, index, y)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 10, y)
	row:SetPoint("TOPRIGHT", -10, y)
	row:SetHeight(STAT_HEIGHT)
	RowBackground(row, index)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- gold, like "Health:"
	row.label:SetPoint("LEFT", 6, 0)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", -6, 0)
	row.value:SetJustifyH("RIGHT")
	return row
end

-- Addons can't open a browser, so show the Wowhead address selected in a popup to copy.
local WOWHEAD_ITEM_URL = "https://www.wowhead.com/forever/item=%d"

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
	row.icon:SetPoint("LEFT", 4, 0)
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
		if not self.itemID then
			return
		end
		if mouseButton == "RightButton" then
			ToggleWanted(self.itemID, self.itemName)
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
			-- A spot on the Zone tab: its numbers and what bites there.
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.itemName)
			GameTooltip:AddDoubleLine("钓获", string.format("%d / %d", t.catches, t.casts), 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("钓鱼时间", FormatDuration(t.activeTime), 1, 0.82, 0, 1, 1, 1)
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
				local name = C_Item.GetItemNameByID(list[i].id) or ("item " .. list[i].id)
				local color = QualityColor(C_Item.GetItemQualityByID(list[i].id))
				GameTooltip:AddDoubleLine(name, "x" .. list[i].count, color and color.r or 1, color and color.g or 1,
					color and color.b or 1, 1, 1, 1)
			end
			GameTooltip:Show()
		elseif self.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("点击：Wowhead 链接", 0.6, 0.8, 1)
			GameTooltip:AddLine("Shift+点击：在聊天中链接", 0.6, 0.8, 1)
			GameTooltip:AddLine(IsWanted(self.itemID) and "右键：取消想要标记"
				or "右键：标记为想要（钓到时提醒）", 0.6, 0.8, 1)
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

-- The window's building blocks, shared by every window so they always match.
ns.UI = {
	KeepOpenThroughOptions = KeepOpenThroughOptions,
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
	for _, tab in ipairs(f.Tabs) do
		tab:SetWidth(TAB_WIDTH)
		local text = tab.Text or tab:GetFontString()
		if text then
			text:SetWidth(TAB_WIDTH - 10)
		end
	end
end

local function CreateWindow()
	local f, inset = CreateShell("OneCastStatsFrame",
		(ns.DISPLAY_NAME or "哇，大鱼") .. "  " .. GREY .. "v" .. (ns.VERSION or "?") .. "|r",
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
	f.skillBar = RankBar(inset, ns.GetFishingName and ns.GetFishingName() or "钓鱼")

	f.verdict = inset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.verdict:SetPoint("TOPLEFT", 14, -50)
	f.verdict:SetPoint("RIGHT", -14, 0)
	f.verdict:SetJustifyH("LEFT")
	f.verdict:SetWordWrap(true)

	f.summaryHeader = SectionHeader(inset, SUMMARY_TOP)
	f.stats = {}
	for i = 1, STAT_ROWS do
		f.stats[i] = StatRow(inset, i, SUMMARY_TOP - 28 - (i - 1) * STAT_HEIGHT)
	end

	f.listHeader = SectionHeader(inset, LIST_TOP)
	-- Zone tab: switch the list between the fish caught here and the spots fished.
	f.listToggle = CreateFrame("Button", nil, f.listHeader, "UIPanelButtonTemplate")
	ns.Theme.Register(f.listToggle, "button")
	f.listToggle:SetSize(64, 18)
	f.listToggle:SetPoint("RIGHT", -4, 1)
	f.listToggle:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		charDB.zoneList = charDB.zoneList ~= "spots" and "spots" or nil
		Stats.Refresh()
	end)
	f.listToggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(charDB.zoneList == "spots" and "显示此处钓到的鱼"
			or "显示本区域各地点，按每小时鱼数排序")
		GameTooltip:Show()
	end)
	f.listToggle:SetScript("OnLeave", GameTooltip_Hide)
	f.rows = {}
	for i = 1, MAX_ROWS do
		f.rows[i] = ItemRow(inset, i, LIST_TOP - 28 - (i - 1) * ITEM_HEIGHT)
	end
	f.more = inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

	-- Bottom bar: square icon buttons, like the Character frame's model controls.
	local options = IconButton(f, "Options", "选项", function()
		if ns.OpenSettings then
			ns.OpenSettings()
		end
	end)
	options:SetPoint("BOTTOMRIGHT", -22, 3)
	f.gear = IconButton(f, "Weapons", "换回武器", function()
		OneCast_RestoreWeapons()
	end)
	f.scan = IconButton(f, "Scan", "用 Auctionator 扫描价格", function()
		ns.Prices.Scan()
	end)
	f.reset = IconButton(f, "Reset", "重置会话", ResetSession)
	local book = IconButton(f, "Book", "钓鱼图鉴", function()
		ns.Book.Toggle()
	end)
	f.bottomButtons = { options, book, f.gear, f.scan, f.reset }

	-- Resize grip: drag the bottom-right corner to scale the whole window.
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", -4, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		local startX = GetCursorPosition() / UIParent:GetEffectiveScale()
		local startWidth = f:GetWidth() * f:GetScale()
		grip:SetScript("OnUpdate", function()
			local x = GetCursorPosition() / UIParent:GetEffectiveScale()
			Stats.SetScale((startWidth + x - startX) / f:GetWidth() * 100, true)
		end)
	end)
	grip:SetScript("OnMouseUp", function()
		grip:SetScript("OnUpdate", nil)
		Stats.SetScale(f:GetScale() * 100)
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("拖动调整大小")
		GameTooltip:AddLine("或在窗口上按 Ctrl + 鼠标滚轮。", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() then
			Stats.SetScale(f:GetScale() * 100 + delta * SCALE_STEP)
		end
	end)

	-- Keep the session's elapsed time ticking. The other tabs change only on events.
	local elapsed = 0
	-- The session clock ticks every second. Only its title changes that often: the rest, which
	-- prices every item, redraws on events and now and then for the Extravaganza countdown.
	local sinceFull = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 1 then
			elapsed = 0
			if (charDB.view or "session") == "session" then
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
	local view = charDB.view or "session"
	local title, stats, rows, listTitle, emptyText = BuildView(view)

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

	local fraction, value, verdict = SkillStatus()
	frame.skillBar:SetRank(fraction, value)
	frame.verdict:SetText(verdict)

	frame.summaryHeader.text:SetText(title)
	for i, row in ipairs(frame.stats) do
		local pair = stats[i]
		if pair then
			row.label:SetText(pair[1] .. ":")
			row.value:SetText(pair[2])
			row:Show()
		else
			row:Hide()
		end
	end

	frame.listHeader.text:SetText(listTitle)
	frame.listToggle:SetShown(view == "zone")
	frame.listToggle:SetText(charDB.zoneList == "spots" and "渔获" or "地点")
	for i, row in ipairs(frame.rows) do
		local r = rows[i]
		if r then
			local color = QualityColor(r.quality)
			row.itemID = r.id
			row.itemName = r.name
			row.spot = r.spot
			row.icon:SetTexture(r.icon)
			row.name:SetText((r.name or ("item:" .. r.id)) .. (IsWanted(r.id) and " |cffffd100*|r" or ""))
			if color then
				row.name:SetTextColor(color.r, color.g, color.b)
				row.border:SetVertexColor(color.r, color.g, color.b)
			else
				row.name:SetTextColor(1, 1, 1)
				row.border:SetVertexColor(1, 1, 1)
			end
			row.right:SetText(r.right)
			row:Show()
		else
			row.itemID, row.spot = nil, nil
			row:Hide()
		end
	end

	frame.more:ClearAllPoints()
	frame.more:SetPoint("TOPLEFT", 16, LIST_TOP - 30 - math.min(#rows, MAX_ROWS) * ITEM_HEIGHT)
	if #rows == 0 then
		frame.more:SetText(emptyText)
	elseif #rows > MAX_ROWS then
		frame.more:SetText(string.format("还有 %d 项…", #rows - MAX_ROWS))
	else
		frame.more:SetText("")
	end

	LayoutBottomButtons(view)
end

function Stats.Show(view)
	frame = frame or CreateWindow()
	if view then
		charDB.view = view
	end
	Stats.Refresh()
	frame:Show()
	FitTabs(frame) -- the tabs' own OnShow just resized them
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

-- Scale the window to `percent`, keeping its top-left corner where it is. While dragging
-- the grip (`live`), only the window changes; otherwise the setting is saved too, which
-- also keeps the options slider in step.
function Stats.SetScale(percent, live)
	percent = math.max(SCALE_MIN, math.min(SCALE_MAX, percent))
	if not live then
		percent = math.floor(percent / SCALE_STEP + 0.5) * SCALE_STEP
	end
	if frame then
		local old = frame:GetScale()
		local left, top = frame:GetLeft(), frame:GetTop()
		local scale = percent / 100
		frame:SetScale(scale)
		if left and top then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
			charDB.windowPoint = { "TOPLEFT", "BOTTOMLEFT", left * old / scale, top * old / scale }
		end
	end
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
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
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
			ns.Lure.OnChange(ScheduleRefresh) -- a lure changes the zone verdict
		end
	elseif event == "LOOT_READY" then
		OnLootReady(...)
	elseif event == "UI_ERROR_MESSAGE" then
		local _, message = ...
		if ERR_FISH_ESCAPED and message == ERR_FISH_ESCAPED then
			OnFishEscaped()
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
		ScheduleRefresh()
	end
end)

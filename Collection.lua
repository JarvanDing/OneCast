-- OneCast collection: which fish you've caught, on which characters, how many, and where.
-- Shared by every character on the account (OneCastDB.collection). Each character's own
-- stats (OneCastCharDB, kept by Stats.lua) are the source of truth: at login and after
-- every catch they are copied in here under that character's name, so catches made
-- before the collection existed count too, and nothing is ever counted twice.

local _, ns = ...

local Collection = {}
ns.Collection = Collection

local function Store()
	ns.db.collection = ns.db.collection or { chars = {}, items = {} }
	return ns.db.collection
end

local function CharKey()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
	return (UnitName("player") or "?") .. "-" .. realm
end

-- A fish is one of the known fish (FishData.lua), or any "Meat" trade good you fish up
-- that isn't in that list yet: new Forever fish join the book as you catch them.
local function IsMeat(itemID)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	return classID == Enum.ItemClass.Tradegoods and subclassID == 8
end

function Collection.IsFish(itemID)
	return (ns.FISH_BY_ID and ns.FISH_BY_ID[itemID] ~= nil) or IsMeat(itemID)
end

local function Entry(itemID)
	local items = Store().items
	items[itemID] = items[itemID] or { byChar = {} }
	return items[itemID]
end

-- Copy this character's catches of `itemID` from its stats into the shared collection.
local function SyncItem(itemID, key, charDB)
	local item = charDB.lifetime.items[itemID]
	if not item then
		return
	end
	local entry = Entry(itemID)
	entry.name = entry.name or item.name
	entry.icon = entry.icon or item.icon
	entry.quality = entry.quality or item.quality
	-- hours[h + 1]: catches at realm hour h, logged from 0.3.0 on.
	local mine = { count = item.count, zones = {}, hours = item.hours }
	for zone, totals in pairs(charDB.zoneStats or {}) do
		local here = totals.items[itemID]
		if here and here.count > 0 then
			mine.zones[zone] = here.count
		end
	end
	entry.byChar[key] = mine
end

function Collection.SyncCharacter()
	local charDB = OneCastCharDB
	if not ns.db or not charDB or not charDB.lifetime then
		return
	end
	local key = CharKey()
	local store = Store()
	store.chars[key] = { class = select(2, UnitClass("player")), name = UnitName("player") }
	for itemID in pairs(charDB.lifetime.items) do
		if Collection.IsFish(itemID) then
			SyncItem(itemID, key, charDB)
		end
	end
end

-- Called by Stats.lua after a catch is counted. Returns how many fish were new.
function Collection.OnCatch(loot, zone)
	if not ns.db or not OneCastCharDB then
		return 0
	end
	local key = CharKey()
	local newFish = {}
	for _, l in ipairs(loot) do
		if Collection.IsFish(l.id) then
			local entry = Entry(l.id)
			-- New only if no character has it yet, including catches from before the book.
			if not next(entry.byChar) then
				entry.firstTime = GetServerTime()
				entry.firstChar = key
				entry.firstZone = zone
				newFish[#newFish + 1] = l
			end
			SyncItem(l.id, key, OneCastCharDB)
		end
	end
	for _, l in ipairs(newFish) do
		ns.Print("图鉴新鱼：" .. (l.link or l.name or "?") .. "！")
	end
	if ns.Book and ns.Book.RefreshIfShown then
		ns.Book.RefreshIfShown()
	end
	return #newFish
end

-- Everything known about one fish across the account:
-- { total, chars = { { key, name, class, count }, ... } most first, zones = { [zone] = n },
--   hours = { [h + 1] = catches at realm hour h }, first = { time, char, zone } or nil }
function Collection.Get(itemID)
	local entry = Store().items[itemID]
	local info = { total = 0, chars = {}, zones = {}, hours = {} }
	if not entry then
		return info
	end
	local chars = Store().chars
	for key, mine in pairs(entry.byChar) do
		if mine.count > 0 then
			info.total = info.total + mine.count
			local who = chars[key] or {}
			info.chars[#info.chars + 1] = { key = key, name = who.name or key, class = who.class, count = mine.count }
			for zone, n in pairs(mine.zones) do
				info.zones[zone] = (info.zones[zone] or 0) + n
			end
			for h, n in pairs(mine.hours or {}) do
				info.hours[h] = (info.hours[h] or 0) + n
			end
		end
	end
	table.sort(info.chars, function(a, b)
		return a.count > b.count
	end)
	if entry.firstTime then
		info.first = { time = entry.firstTime, char = chars[entry.firstChar] and chars[entry.firstChar].name
			or entry.firstChar, zone = entry.firstZone }
	end
	return info
end

-- Fish caught that aren't in FishData.lua, as { id, name, icon, quality } entries.
function Collection.Discovered()
	local list = {}
	for itemID, entry in pairs(Store().items) do
		if not (ns.FISH_BY_ID and ns.FISH_BY_ID[itemID]) and next(entry.byChar) then
			list[#list + 1] = { id = itemID, name = entry.name, icon = entry.icon, quality = entry.quality, discovered = true }
		end
	end
	return list
end

-- Fish collected and fish in the book, counting discovered ones.
function Collection.Progress()
	local caught, total = 0, 0
	for _, fish in ipairs(ns.FISH) do
		total = total + 1
		if Collection.Get(fish.id).total > 0 then
			caught = caught + 1
		end
	end
	local found = #Collection.Discovered()
	return caught + found, total + found
end

-- Every zone any character has caught a fish in.
function Collection.CaughtZones()
	local zones = {}
	for _, entry in pairs(Store().items) do
		for _, mine in pairs(entry.byChar) do
			for zone in pairs(mine.zones) do
				zones[zone] = true
			end
		end
	end
	return zones
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	Collection.SyncCharacter()
end)

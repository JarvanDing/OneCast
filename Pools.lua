-- OneCast pools: remembers where you've found fishing pools, so the collection book's maps can
-- show them. Hover over a pool with a pole in your main hand, then cast: the spot is marked.
--
-- The game gives addons no position for a pool, and a tooltip shows from far beyond casting
-- range, so hovering alone would drop dots away from the water. So the mark is the player's
-- position when the line goes out, which is within casting range of the pool, or right away
-- if the line is already out. Pools are recognised by name: in another client language, the
-- name is put back into English first (ns.POOL_NAMES, in Odds.lua).
-- Account-wide: OneCastDB.pools[uiMapID] = { { x, y, name, seen }, ... }.

local _, ns = ...

local Pools = {}
ns.Pools = Pools

local SAME_PLACE = 0.02   -- closer than this on the zone map counts as the same spot
local HOVER_KEEP = 30     -- seconds a hovered pool waits for a cast
local MAX_PER_MAP = 200

local PATTERNS = {
	" School$", "^School of ", " Swarm$", " Wreckage$", " Debris$", " Flotsam$", "^Oil Spill$",
	"^Patch of Elemental Water$", "Churning Waters?$",
}

-- A pool's English name, whatever the client's language. Anything else comes back as it was.
local localNames = ns.POOL_NAMES and ns.POOL_NAMES[GetLocale()]
local function English(name)
	return localNames and localNames[name] or name
end
Pools.English = English

local function IsPoolName(name)
	name = English(name)
	for _, pattern in ipairs(PATTERNS) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

-- The zone map the player is on, skipping up from any smaller map, with their position on it.
local function ZonePosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	local zoneType = Enum.UIMapType and Enum.UIMapType.Zone or 3
	while mapID do
		local info = C_Map.GetMapInfo(mapID)
		if not info then
			return nil
		end
		if info.mapType == zoneType then
			break
		end
		mapID = info.parentMapID
		if mapID == 0 then
			return nil
		end
	end
	if not mapID then
		return nil
	end
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return nil
	end
	local x, y = position:GetXY()
	if not x or (x == 0 and y == 0) then
		return nil
	end
	return mapID, x, y
end

Pools.ZonePosition = ZonePosition

function Pools.Remember(name)
	local mapID, x, y = ZonePosition()
	if not mapID then
		return false
	end
	ns.db.pools = ns.db.pools or {}
	local list = ns.db.pools[mapID] or {}
	ns.db.pools[mapID] = list
	local now = GetServerTime()
	for _, pool in ipairs(list) do
		if pool.name == name and math.abs(pool.x - x) < SAME_PLACE and math.abs(pool.y - y) < SAME_PLACE then
			pool.seen = now
			return false
		end
	end
	if #list >= MAX_PER_MAP then
		-- Full: the spot not seen for longest makes way.
		local oldest = 1
		for i, pool in ipairs(list) do
			if pool.seen < list[oldest].seen then
				oldest = i
			end
		end
		table.remove(list, oldest)
	end
	list[#list + 1] = { x = x, y = y, name = name, seen = now }
	return true
end

function Pools.ForMap(mapID)
	return ns.db and ns.db.pools and ns.db.pools[mapID] or {}
end

function Pools.Forget()
	if ns.db then
		ns.db.pools = {}
	end
end

local hovered, hoveredAt
local tipPool, tipAt     -- the pool last hovered with a pole on, whether or not spots are remembered
local castPool, castMap  -- the pool a cast went out at, and the zone map, until its loot

local function Commit(name)
	if Pools.Remember(name) and ns.Book and ns.Book.RefreshIfShown then
		ns.Book.RefreshIfShown()
	end
end

-- The line went out: a pool hovered a moment ago is being fished from here.
function Pools.OnCast()
	if hovered and GetTime() - hoveredAt <= HOVER_KEEP then
		Commit(hovered)
	end
	hovered = nil
	castPool, castMap = nil, nil
	if tipPool and GetTime() - tipAt <= HOVER_KEEP then
		castPool, castMap = tipPool, ZonePosition()
	end
end

-- What a pool's trunk and rum are where you fish it, from what it's given you:
-- OneCastDB.poolSeen[uiMapID][pool] = { [itemID] = true }. Forever's own, so it's trusted
-- over Classic's several kinds.
local function SeenHere(mapID, pool)
	local byMap = mapID and ns.db and ns.db.poolSeen and ns.db.poolSeen[mapID]
	return byMap and byMap[pool]
end

-- Fishing loot after a cast at a pool: any of its slot items is what that pool gives here.
function Pools.OnLoot(loot)
	local pool, mapID = castPool, castMap
	castPool, castMap = nil, nil
	local entries = pool and mapID and ns.POOL_LOOT and ns.POOL_LOOT[pool]
	if not entries then
		return
	end
	for _, entry in ipairs(entries) do
		for _, id in ipairs(entry.ids or {}) do
			for _, l in ipairs(loot) do
				if l.id == id then
					ns.db.poolSeen = ns.db.poolSeen or {}
					ns.db.poolSeen[mapID] = ns.db.poolSeen[mapID] or {}
					ns.db.poolSeen[mapID][pool] = ns.db.poolSeen[mapID][pool] or {}
					ns.db.poolSeen[mapID][pool][id] = true
				end
			end
		end
	end
end

-- What a pool gives, on its tooltip, per catch by Classic's odds: each item in its quality's
-- colour, marked if it's in the collection and no character of yours has caught it yet. A
-- trunk or rum that depends on the waters lists the ones it can be, or the one it's been here.
local LOOT_HEADER = "|cff9d9d9dEach catch, by Classic's odds|r"

-- Whether this tooltip already has the lines: our own Show() fires OnShow again.
local function HasLoot(tooltip)
	local n = tooltip.NumLines and tooltip:NumLines() or 0
	for i = 2, n do
		local fs = _G["GameTooltipTextLeft" .. i]
		local text = fs and fs:GetText()
		if not (issecretvalue and issecretvalue(text)) and text == LOOT_HEADER then
			return true
		end
	end
	return false
end

local ICON = ":14:14:0:0:64:64:5:59:5:59|t "

-- An item as a tooltip line's left side: its icon, its name in its quality's colour, and
-- "not caught yet" if it's a collection catch none of your characters has.
local function ItemText(id, indent)
	local fish = ns.FISH_BY_ID and ns.FISH_BY_ID[id]
	local name = C_Item.GetItemNameByID(id) or (fish and fish.name) or (ns.POOL_ITEM_NAMES and ns.POOL_ITEM_NAMES[id])
		or ("item " .. id)
	local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local icon = C_Item.GetItemIconByID(id)
	local missing = fish and ns.Collection and ns.Collection.Get(id).total == 0
	return (indent or "") .. (icon and ("|T" .. icon .. ICON) or "") .. (color and color.hex or "|cffffffff") .. name .. "|r"
		.. (missing and "  |cff20ff20not caught yet|r" or "")
end

-- A trunk or rum on its slot's one line, with the word they share dropped (Iron Bound, Black
-- Label): grey, or green if it's a collection catch none of your characters has.
local function ShortName(id, what)
	local fish = ns.FISH_BY_ID and ns.FISH_BY_ID[id]
	local name = C_Item.GetItemNameByID(id) or (fish and fish.name) or ("item " .. id)
	if what == "trunk" then
		name = name:gsub(" Trunk$", "")
	elseif what == "rum" then
		name = name:gsub("^Rumsey Rum ", "")
	end
	local missing = fish and ns.Collection and ns.Collection.Get(id).total == 0
	return (missing and "|cff20ff20" or "|cffa0a0a0") .. name .. "|r"
end

local function Percent(pct)
	return pct >= 1 and string.format("%s%%", (string.format("%.1f", pct):gsub("%.0$", ""))) or ns.OneIn(pct)
end

local adding = false
-- `show`: call Show after adding, from the OnShow fallback. The game's tooltip data shows the
-- tooltip itself once its post-calls have run.
local function AddPoolLoot(tooltip, name, show)
	local pool = English(name)
	local loot = ns.POOL_LOOT and ns.POOL_LOOT[pool]
	if adding or not loot or not (ns.db and ns.db.poolTooltip ~= false) or HasLoot(tooltip) then
		return
	end
	adding = true
	local seen = SeenHere(ZonePosition(), pool)
	tooltip:AddLine(LOOT_HEADER)
	for _, entry in ipairs(loot) do
		if entry.ids then
			-- A trunk or rum: the one it's been here, or the ones it can be.
			local here = {}
			for _, id in ipairs(entry.ids) do
				if seen and seen[id] then
					here[#here + 1] = id
				end
			end
			if #here > 0 then
				for i, id in ipairs(here) do
					tooltip:AddDoubleLine(ItemText(id), i == 1 and Percent(entry.pct) or "", 1, 1, 1, 0.7, 0.7, 0.7)
				end
			else
				tooltip:AddDoubleLine("|cffbbbbbb" .. (entry.what == "rum" and "A rum, by the waters:" or "A trunk, by the waters:") .. "|r",
					Percent(entry.pct), 1, 1, 1, 0.7, 0.7, 0.7)
				local names = {}
				for _, id in ipairs(entry.ids) do
					names[#names + 1] = ShortName(id, entry.what)
				end
				tooltip:AddLine("    " .. table.concat(names, "|cff808080 · |r"), 0.6, 0.6, 0.6, true)
			end
		else
			tooltip:AddDoubleLine(ItemText(entry[1]), Percent(entry[2]), 1, 1, 1, 0.7, 0.7, 0.7)
		end
	end
	if show then
		tooltip:Show()
	end
	adding = false
end

-- A pool's tooltip: what it gives, and remembering where you fished it.
local function OnPoolTooltip(tooltip, name, show)
	if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or not IsPoolName(name) then
		return
	end
	AddPoolLoot(tooltip, name, show)
	if not ns.Lure.MainHandPole() then
		return
	end
	-- For what its trunk and rum turn out to be here: the next cast is at it.
	tipPool, tipAt = English(name), GetTime()
	if ns.IsFishing and ns.IsFishing() then
		castPool, castMap = tipPool, ZonePosition()
	end
	if not ns.db.rememberPools then
		return
	end
	if ns.IsFishing and ns.IsFishing() then
		Commit(name)
	else
		hovered, hoveredAt = name, GetTime()
	end
end

Pools.OnTooltip = OnPoolTooltip -- for the tests

-- The game fills a world object's tooltip through its tooltip data, clearing it each time and
-- not always hiding it first: moving the mouse from the water onto a pool keeps it shown, so
-- OnShow never fires. A post-call on object tooltips sees every one.
local hooked = false
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType
	and Enum.TooltipDataType.Object then
	hooked = true
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip, data)
		if tooltip ~= GameTooltip or not ns.db or InCombatLockdown() then
			return
		end
		local first = data and data.lines and data.lines[1]
		local name = first and first.leftText
		if not name or (issecretvalue and issecretvalue(name)) then
			local line = _G.GameTooltipTextLeft1
			name = line and line:GetText()
		end
		OnPoolTooltip(tooltip, name, false)
	end)
end

-- Older clients without tooltip data: a world object's tooltip, owned by UIParent, with no
-- unit, item or spell behind it, as it shows.
GameTooltip:HookScript("OnShow", function(self)
	if hooked or not ns.db or InCombatLockdown() then
		return
	end
	if self.IsOwned and not self:IsOwned(UIParent) then
		return
	end
	if (self.GetUnit and self:GetUnit()) or (self.GetItem and self:GetItem()) or (self.GetSpell and self:GetSpell()) then
		return
	end
	local line = _G.GameTooltipTextLeft1
	OnPoolTooltip(self, line and line:GetText(), true)
end)

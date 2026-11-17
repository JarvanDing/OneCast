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
end

-- What a pool gives, on its tooltip: each collection catch with Classic's odds, marked if no
-- character of yours has caught it yet. Up to MAX_LOOT lines, the likeliest first.
local MAX_LOOT = 8
local LOOT_HEADER = "|cff71d5ffOneCast:|r what it gives (Classic's odds)"

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

local adding = false
-- `show`: call Show after adding, from the OnShow fallback. The game's tooltip data shows the
-- tooltip itself once its post-calls have run.
local function AddPoolLoot(tooltip, name, show)
	local loot = ns.POOL_LOOT and ns.POOL_LOOT[English(name)]
	if adding or not loot or not (ns.db and ns.db.poolTooltip ~= false) or HasLoot(tooltip) then
		return
	end
	adding = true
	tooltip:AddLine(LOOT_HEADER, 0.8, 0.8, 0.8)
	for i, entry in ipairs(loot) do
		if i > MAX_LOOT then
			tooltip:AddLine(string.format("  and %d more", #loot - MAX_LOOT), 0.6, 0.6, 0.6)
			break
		end
		local id, pct = entry[1], entry[2]
		local fish = ns.FISH_BY_ID and ns.FISH_BY_ID[id]
		local itemName = C_Item.GetItemNameByID(id) or (fish and fish.name) or ("item " .. id)
		local icon = C_Item.GetItemIconByID(id)
		local caught = ns.Collection and ns.Collection.Get(id).total > 0
		local left = (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. itemName
			.. (caught and "" or "  |cff20ff20not caught yet|r")
		local right = pct >= 1 and string.format("%s%%", (string.format("%.1f", pct):gsub("%.0$", ""))) or ns.OneIn(pct)
		if caught then
			tooltip:AddDoubleLine(left, right, 0.85, 0.85, 0.85, 0.7, 0.7, 0.7)
		else
			tooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
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
	if not ns.db.rememberPools or not ns.Lure.MainHandPole() then
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

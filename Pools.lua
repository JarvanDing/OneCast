-- OneCast pools: remembers where you've found fishing pools, so the collection book's maps can
-- show them. Hover over a pool with a pole in your main hand, then cast: the spot is marked.
--
-- The game gives addons no position for a pool, and a tooltip shows from far beyond casting
-- range, so hovering alone would drop dots away from the water. So the mark is the player's
-- position when the line goes out, which is within casting range of the pool, or right away
-- if the line is already out. Pools are recognised by name, English only.
-- Account-wide: OneCastDB.pools[uiMapID] = { { x, y, name, seen }, ... }.

local _, ns = ...

local Pools = {}
ns.Pools = Pools

local SAME_PLACE = 0.02   -- closer than this on the zone map counts as the same spot
local HOVER_KEEP = 30     -- seconds a hovered pool waits for a cast
local MAX_PER_MAP = 200

local PATTERNS = {
	" School$", "^School of ", " Swarm$", " Wreckage$", " Debris$", " Flotsam$", "^Oil Spill$",
	"^Patch of Elemental Water$", "Churning Waters?$", "^Strange Pool$", "^Pure Water$",
}

local function IsPoolName(name)
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

-- A world object's tooltip: owned by UIParent, with no unit, item or spell behind it.
GameTooltip:HookScript("OnShow", function(self)
	if not ns.db or not ns.db.rememberPools or InCombatLockdown() or not ns.Lure.MainHandPole() then
		return
	end
	if self.IsOwned and not self:IsOwned(UIParent) then
		return
	end
	if (self.GetUnit and self:GetUnit()) or (self.GetItem and self:GetItem()) or (self.GetSpell and self:GetSpell()) then
		return
	end
	local line = _G.GameTooltipTextLeft1
	local name = line and line:GetText()
	if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or not IsPoolName(name) then
		return
	end
	if ns.IsFishing and ns.IsFishing() then
		Commit(name)
	else
		hovered, hoveredAt = name, GetTime()
	end
end)

-- OneCast on the world map: a strip in the map's lower left with the fishing level of the zone
-- on show (or the zone under the mouse, on a continent), how your skill stands against it, and
-- how many of its fish you've caught. Off with "Fishing levels on the world map" (mapStrip).

local _, ns = ...

local WorldMap = {}
ns.WorldMap = WorldMap

local MOOD = { good = "|cff20ff20", warn = "|cffffd100", bad = "|cffff2020", unknown = "|cff9d9d9d" }
local ZONE_TYPE = Enum.UIMapType and Enum.UIMapType.Zone or 3

local strip, hovered, seen

-- "Durotar |cff..(1-10)|r" from the map's label: just "Durotar".
local function ZoneOf(label)
	if type(label) ~= "string" or (issecretvalue and issecretvalue(label)) then
		return nil
	end
	local name = label:gsub("|c%x%x%x%x%x%x%x%x.*$", ""):gsub("%s*%([%d%-]+%)%s*$", "")
	return strtrim and strtrim(name) or name
end

-- What the strip says per zone, for a moment: hovering a continent asks every frame.
local cache, cachedAt = {}, 0
local CACHE_FOR = 2

local function Known(zone)
	if ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone] then
		return true
	end
	for _, unknown in ipairs(ns.ZONE_FISHING_UNKNOWN or {}) do
		if unknown == zone then
			return true
		end
	end
	return false
end

-- "Tanaris  ·  needs 300  ·  Ready  ·  6/14 fish caught", or nil for a zone with no fishing.
local function Text(zone, withName)
	if not zone or not ns.Stats or not OneCastCharDB then
		return nil
	end
	local count = ns.Book and ns.Book.ZoneFishCount and ns.Book.ZoneFishCount(zone) or { caught = 0, total = 0 }
	if not Known(zone) and count.total == 0 then
		return nil
	end
	local parts = { "|cff71d5ffFishing|r" }
	if withName then
		parts[#parts + 1] = zone
	end
	local badge = ns.Stats.ZoneBadge(zone)
	if badge.need then
		parts[#parts + 1] = badge.need
	end
	parts[#parts + 1] = (MOOD[badge.mood] or "") .. badge.status .. "|r"
	if count.total > 0 then
		parts[#parts + 1] = string.format("%d/%d fish caught", count.caught, count.total)
	end
	return table.concat(parts, "  ·  ")
end

function WorldMap.Text(zone, withName)
	if not zone then
		return nil
	end
	local now = GetTime()
	if now - cachedAt > CACHE_FOR then
		cache, cachedAt = {}, now
	end
	local key = zone .. (withName and "+" or "")
	if cache[key] == nil then
		cache[key] = Text(zone, withName) or false
	end
	return cache[key] or nil
end

local function CurrentZoneName()
	local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	if info and info.mapType == ZONE_TYPE then
		return info.name
	end
end

local function Update()
	if not strip then
		return
	end
	local text
	if ns.db and ns.db.mapStrip ~= false then
		if hovered then
			text = WorldMap.Text(hovered, true)
		end
		text = text or WorldMap.Text(CurrentZoneName())
	end
	if not text then
		strip:Hide()
		return
	end
	strip.text:SetText(text)
	strip:SetWidth(strip.text:GetStringWidth() + 20)
	strip:Show()
end
WorldMap.Update = Update

local function Init()
	if strip or not WorldMapFrame then
		return
	end
	local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
	strip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	strip:SetPoint("BOTTOMLEFT", 8, 8)
	strip:SetHeight(22)
	strip:SetFrameLevel(parent:GetFrameLevel() + 50)
	if strip.SetBackdrop then
		strip:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10,
			insets = { left = 2, right = 2, top = 2, bottom = 2 } })
		strip:SetBackdropColor(0, 0, 0, 0.75)
		strip:SetBackdropBorderColor(0.5, 0.5, 0.55, 0.9)
	end
	strip.text = strip:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	strip.text:SetPoint("CENTER")
	strip:Hide()

	if WorldMapFrame.OnMapChanged then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", Update)
	end
	WorldMapFrame:HookScript("OnShow", Update)
	-- On a continent, the zone under the mouse: the map's own area label says which.
	local areaName = MAP_AREA_LABEL_TYPE and MAP_AREA_LABEL_TYPE.AREA_NAME
	for provider in pairs(WorldMapFrame.dataProviders or {}) do
		local label = type(provider) == "table" and provider.Label
		if label and label.SetLabel and label.ClearLabel then
			-- The label clears and sets its area name every frame: note what it says, and redraw
			-- only when that changes (checked once a frame, after the label's own update).
			hooksecurefunc(label, "SetLabel", function(_, labelType, name)
				if labelType == areaName then
					seen = ZoneOf(name)
				end
			end)
			hooksecurefunc(label, "ClearLabel", function(_, labelType)
				if labelType == areaName then
					seen = nil
				end
			end)
			-- A watcher of our own on the map: it runs only while the map is open.
			local watch = CreateFrame("Frame", nil, strip:GetParent())
			watch:SetScript("OnUpdate", function()
				if seen ~= hovered then
					hovered = seen
					Update()
				end
			end)
		end
	end
	Update()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then
		Init()
	end
end)

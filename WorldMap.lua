-- OneCast on the world map: a small card with the fishing level of the zone on show (or the
-- zone under the mouse, on a continent), how your skill stands against it, and how many of its
-- fish you've caught. Drag it anywhere on the map, Ctrl + mouse wheel over it to size it, and
-- right-click to put it back. Off with "Fishing levels on the world map" (mapStrip).
-- Where it sits is kept as a share of the map's width and height (OneCastDB.mapStripPos), so it
-- stays put whether the map is small or full screen; its size is OneCastDB.mapStripScale.

local _, ns = ...

local WorldMap = {}
ns.WorldMap = WorldMap

local MOOD = { good = "|cff20ff20", warn = "|cffffd100", bad = "|cffff2020", unknown = "|cff9d9d9d" }
local ZONE_TYPE = Enum.UIMapType and Enum.UIMapType.Zone or 3
local GREY = "|cff9d9d9d"
local ICON = "Interface\\Icons\\Trade_Fishing"

-- Where it starts: the middle of the map's foot, above where coordinates usually sit.
local DEFAULT_X, DEFAULT_Y = 0.5, 0.075
local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.6, 2, 0.1
local PAD, ICON_SIZE, GAP = 8, 22, 8

local card, anchor, hovered, seen

-- "Durotar |cff..(1-10)|r" from the map's label: just "Durotar".
local function ZoneOf(label)
	if type(label) ~= "string" or (issecretvalue and issecretvalue(label)) then
		return nil
	end
	local name = label:gsub("|c%x%x%x%x%x%x%x%x.*$", ""):gsub("%s*%([%d%-]+%)%s*$", "")
	return strtrim and strtrim(name) or name
end

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

-- What the card says about a zone: { zone, need, status (coloured), caught }, or nil for a zone
-- with no fishing.
local function Parts(zone)
	if not zone or not ns.Stats or not OneCastCharDB then
		return nil
	end
	local count = ns.Book and ns.Book.ZoneFishCount and ns.Book.ZoneFishCount(zone) or { caught = 0, total = 0 }
	if not Known(zone) and count.total == 0 then
		return nil
	end
	local badge = ns.Stats.ZoneBadge(zone)
	return {
		zone = zone,
		need = badge.need,
		status = (MOOD[badge.mood] or "") .. badge.status .. "|r",
		caught = count.total > 0 and string.format("%d/%d fish caught", count.caught, count.total) or nil,
	}
end

-- Per zone, for a moment: hovering a continent asks every frame.
local cache, cachedAt = {}, 0
local CACHE_FOR = 2
local function CachedParts(zone)
	local now = GetTime()
	if now - cachedAt > CACHE_FOR then
		cache, cachedAt = {}, now
	end
	if cache[zone] == nil then
		cache[zone] = Parts(zone) or false
	end
	return cache[zone] or nil
end

-- The card's words in one line: "Tanaris  ·  needs 300  ·  Ready  ·  6/14 fish caught".
function WorldMap.Text(zone, withName)
	local p = zone and CachedParts(zone)
	if not p then
		return nil
	end
	local parts = { "|cff71d5ffFishing|r" }
	if withName then
		parts[#parts + 1] = p.zone
	end
	parts[#parts + 1] = p.need
	parts[#parts + 1] = p.status
	parts[#parts + 1] = p.caught
	return table.concat(parts, "  ·  ")
end

local function CurrentZoneName()
	local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	if info and info.mapType == ZONE_TYPE then
		return info.name
	end
end

-- Where it sits and how big ------------------------------------------------------------------

local function Saved()
	local pos = ns.db and ns.db.mapStripPos
	local x = type(pos) == "table" and tonumber(pos.x) or DEFAULT_X
	local y = type(pos) == "table" and tonumber(pos.y) or DEFAULT_Y
	local scale = ns.db and tonumber(ns.db.mapStripScale) or 1
	return x, y, math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
end

-- The card's centre at its saved share of the map, kept on the map.
local function Place()
	if not card or card.dragging then
		return -- mid-drag (the zone under the mouse changing as it moves), it's left where it is
	end
	local parent = anchor:GetParent()
	local w, h = parent:GetWidth() or 0, parent:GetHeight() or 0
	local x, y, scale = Saved()
	card:SetScale(scale)
	local halfW = (card:GetWidth() or 0) * scale / 2
	local halfH = (card:GetHeight() or 0) * scale / 2
	local px = w > 0 and math.max(halfW, math.min(w - halfW, x * w)) or 0
	local py = h > 0 and math.max(halfH, math.min(h - halfH, y * h)) or 0
	anchor:ClearAllPoints()
	anchor:SetPoint("CENTER", parent, "BOTTOMLEFT", px, py)
	card:ClearAllPoints()
	card:SetPoint("CENTER", anchor, "CENTER")
end

-- Saved as a share of the map, so it stays put at any map size.
function WorldMap.SetPosition(x, y)
	ns.db.mapStripPos = { x = math.max(0, math.min(1, x)), y = math.max(0, math.min(1, y)) }
	Place()
end

function WorldMap.SetScale(scale)
	ns.db.mapStripScale = math.floor(math.max(MIN_SCALE, math.min(MAX_SCALE, scale)) * 100 + 0.5) / 100
	Place()
end

function WorldMap.Reset()
	ns.db.mapStripPos, ns.db.mapStripScale = nil, nil
	Place()
end

-- Dropped: where its centre landed, as a share of the map.
local function Dropped()
	card:StopMovingOrSizing()
	card.dragging = nil
	local parent = anchor:GetParent()
	local cx, cy = card:GetCenter()
	local left, bottom = parent:GetLeft(), parent:GetBottom()
	local w, h = parent:GetWidth(), parent:GetHeight()
	if cx and left and w and w > 0 and h and h > 0 then
		local ratio = card:GetEffectiveScale() / parent:GetEffectiveScale()
		WorldMap.SetPosition((cx * ratio - left) / w, (cy * ratio - bottom) / h)
	else
		Place()
	end
end

-- What it shows ------------------------------------------------------------------------------

local function Update()
	if not card then
		return
	end
	local parts
	if ns.db and ns.db.mapStrip ~= false then
		parts = hovered and CachedParts(hovered) or CachedParts(CurrentZoneName())
	end
	if not parts then
		card:Hide()
		return
	end
	card.zone = parts.zone
	card.top:SetText(parts.zone .. (parts.need and ("  " .. GREY .. parts.need .. "|r") or ""))
	card.bottom:SetText(parts.status .. (parts.caught and (GREY .. "  ·  |r" .. parts.caught) or ""))
	local textWidth = math.max(card.top:GetStringWidth() or 0, card.bottom:GetStringWidth() or 0)
	card:SetWidth(PAD + ICON_SIZE + GAP + textWidth + PAD)
	card:Show()
	Place()
end
WorldMap.Update = Update

local function ShowTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Fishing" .. (self.zone and (": " .. self.zone) or ""))
	if self.zone and ns.Stats and ns.Stats.ZoneVerdict then
		GameTooltip:AddLine(ns.Stats.ZoneVerdict(self.zone), 1, 1, 1, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Drag: move it", 0.6, 0.8, 1)
	GameTooltip:AddLine("Ctrl + mouse wheel: size", 0.6, 0.8, 1)
	GameTooltip:AddLine("Right-click: put it back", 0.6, 0.8, 1)
	GameTooltip:Show()
end

local function Init()
	if card or not WorldMapFrame then
		return
	end
	local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
	-- An unscaled point at the saved spot, and the card (which has its own size) centred on it.
	anchor = CreateFrame("Frame", nil, parent)
	anchor:SetSize(1, 1)
	card = CreateFrame("Frame", "OneCastWorldMapCard", parent, "BackdropTemplate")
	card:SetHeight(PAD + 30 + PAD - 4)
	card:SetFrameLevel(parent:GetFrameLevel() + 50)
	if card.SetBackdrop then
		card:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		card:SetBackdropColor(0.04, 0.04, 0.06, 0.85)
		card:SetBackdropBorderColor(0.6, 0.6, 0.65, 0.9)
	end
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetTexture(ICON)
	card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	card.icon:SetSize(ICON_SIZE, ICON_SIZE)
	card.icon:SetPoint("LEFT", PAD, 0)
	card.top = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.top:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", GAP, 3)
	card.top:SetJustifyH("LEFT")
	card.bottom = card:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	card.bottom:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", GAP, -2)
	card.bottom:SetJustifyH("LEFT")
	card:Hide()

	-- Drag it anywhere on the map; right-click puts it back.
	card:EnableMouse(true)
	card:SetMovable(true)
	card:SetClampedToScreen(true)
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self.dragging = true
		self:StartMoving()
	end)
	card:SetScript("OnDragStop", Dropped)
	card:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			WorldMap.Reset()
		end
	end)
	-- Ctrl + mouse wheel sizes it. Only while Ctrl is held does it take the wheel, so the wheel
	-- still zooms the map under it.
	card:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() then
			local _, _, scale = Saved()
			WorldMap.SetScale(scale + delta * SCALE_STEP)
		end
	end)
	card:SetScript("OnEvent", function(self)
		self:EnableMouseWheel(IsControlKeyDown() and true or false)
	end)
	card:SetScript("OnEnter", function(self)
		self:RegisterEvent("MODIFIER_STATE_CHANGED")
		self:EnableMouseWheel(IsControlKeyDown() and true or false)
		ShowTip(self)
	end)
	card:SetScript("OnLeave", function(self)
		self:UnregisterEvent("MODIFIER_STATE_CHANGED")
		self:EnableMouseWheel(false)
		GameTooltip:Hide()
	end)
	-- The map resized (windowed, maximised): the same share of it.
	parent:HookScript("OnSizeChanged", Place)

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
			local watch = CreateFrame("Frame", nil, parent)
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
WorldMap.Init = Init -- for the tests

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
	if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then
		Init()
	end
end)

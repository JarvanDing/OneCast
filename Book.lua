-- OneCast collection book: every fish (FishData.lua) on two parchment pages, caught ones in
-- colour with a tick and your count, missing ones greyed out. Click a fish for its own
-- spread: the game's flavour text, a summary, your catches by character and time of day,
-- where to catch it with a map of the zone, and the recipes it's used in. The grid filters
-- by category, caught or missing, zone and a name search. The Zones tab lists every zone's
-- fishing level against your skill, and clicking one filters the grid to it. Catch data comes
-- from Collection.lua and is shared by all your characters.

local _, ns = ...

local Book = {}
ns.Book = Book

local WIDTH, HEIGHT = 840, 580
local COLS, ROWS = 4, 3
local PER_PAGE = COLS * ROWS
local CELL_W, CELL_H = 86, 108
local MAX_ZONES, MAX_RECIPES, MAX_CHARS = 6, 4, 4
local MAP_W, MAP_H = 300, 128
-- Zones view, in pixels: the height a page has for rows, and what each kind of line takes.
local ZONES_TOP, ZONES_BOTTOM, ZONES_INTRO = 50, 36, 56
local ZONES_HEIGHT = HEIGHT - 102 - ZONES_TOP - ZONES_BOTTOM
local ZONE_ROW, ZONE_HEADING = 19, 28

local CATEGORIES = {
	{ key = "all", label = "All" },
	{ key = "fish", label = "Fish" },
	{ key = "special", label = "Special" },
	{ key = "trophy", label = "Trophies" },
	{ key = "bloated", label = "Bloated" },
	{ key = "zones", label = "Zones" },
	{ key = "camp", label = "Camp" },
}
local CAT_ORDER = { fish = 1, special = 2, trophy = 3, bloated = 4 }
-- FishData's `when`: fish that bite only at some hours in Classic.
local WHEN_TEXT = {
	night = "In Classic it bites only at night, 18:00-06:00 realm time.",
	day = "In Classic it bites only by day, 06:00-18:00 realm time.",
}
local CAT_NAME = { fish = "Fish", special = "Special catch", trophy = "Trophy fish", bloated = "Bloated fish" }
local CAT_LEAD = {
	fish = "A fish",
	special = "An unusual catch",
	trophy = "A trophy fish, kept for its size rather than eaten",
	bloated = "A bloated fish that can hold a pearl or other treasure when opened",
}
local SHOW = { "all", "caught", "missing" }
local SHOW_LABEL = { all = "Showing: all", caught = "Showing: caught", missing = "Showing: missing" }

-- Parchment ink, as in the What's new window.
local INK = { 0.18, 0.10, 0.02 }
local INK_SOFT = { 0.36, 0.25, 0.14 }
local LEAD = "|cff7a2a00"
local SOFT = "|cff6b5233"
local GOOD = "|cff1f6b1f"
local BAD = "|cffa01c1c"

-- Strings coloured once at creation, redone when the theme changes.
local inkedStrings = {}
local function Ink(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
	inkedStrings[#inkedStrings + 1] = { fontString, color }
end

local function ApplyPalette(theme)
	INK[1], INK[2], INK[3] = theme.ink[1], theme.ink[2], theme.ink[3]
	INK_SOFT[1], INK_SOFT[2], INK_SOFT[3] = theme.inkSoft[1], theme.inkSoft[2], theme.inkSoft[3]
	LEAD, SOFT, GOOD, BAD = theme.lead, theme.soft, theme.good, theme.bad
	for _, entry in ipairs(inkedStrings) do
		local color = entry[2]
		entry[1]:SetTextColor(color[1], color[2], color[3])
	end
end

local frame
-- cat, show, where (zone filter) and search pick the fish; spread is the grid's page pair;
-- fishID and zone are the open fish page and its selected zone.
local state = { cat = "all", show = "all", spread = 1 }

local TryCreate, HasAtlas, SizedFont = ns.UI.TryCreate, ns.UI.HasAtlas, ns.UI.SizedFont

-- Fish data ------------------------------------------------------------------------------

local function FishName(fish)
	return C_Item.GetItemNameByID(fish.id) or fish.name or ("item " .. fish.id)
end

local function FishIcon(fish)
	return C_Item.GetItemIconByID(fish.id) or fish.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function FishQuality(fish)
	return C_Item.GetItemQualityByID(fish.id) or fish.quality or 1
end

-- Lowest zone fishing level among the fish's zones, listed or from elsewhere: its easiest waters.
local function EasiestSkill(fish)
	local best
	local function Consider(zone)
		local skill = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone]
		if skill and skill > 1 and (not best or skill < best) then
			best = skill
		end
	end
	for _, zone in ipairs(fish.zones or {}) do
		Consider(zone)
	end
	for _, extra in ipairs(fish.more or {}) do
		Consider(extra[1])
	end
	return best
end

local function AllFish()
	local list = {}
	for _, fish in ipairs(ns.FISH) do
		list[#list + 1] = fish
	end
	for _, found in ipairs(ns.Collection.Discovered()) do
		found.cat, found.zones = "fish", {}
		list[#list + 1] = found
	end
	return list
end

-- Whether the fish is known to bite in `zone`, or has been caught there.
local function FoundIn(fish, info, zone)
	if info.zones[zone] then
		return true
	end
	for _, z in ipairs(fish.zones or {}) do
		if z == zone then
			return true
		end
	end
	for _, extra in ipairs(fish.more or {}) do
		if extra[1] == zone then
			return true
		end
	end
	return false
end

-- Every zone a fish is known from or has been caught in, for the zone filter.
local function ZoneChoices()
	local set = ns.Collection.CaughtZones()
	for _, fish in ipairs(ns.FISH) do
		for _, z in ipairs(fish.zones or {}) do
			set[z] = true
		end
		for _, extra in ipairs(fish.more or {}) do
			set[extra[1]] = true
		end
	end
	local list = {}
	for z in pairs(set) do
		list[#list + 1] = z
	end
	table.sort(list)
	return list
end

-- The fish on show: chosen category, caught/missing, zone and search, easiest waters first.
local function Filtered()
	local out = {}
	for _, fish in ipairs(AllFish()) do
		if (state.cat == "all" or fish.cat == state.cat)
			and (not state.search or FishName(fish):lower():find(state.search, 1, true)) then
			local info = ns.Collection.Get(fish.id)
			local caught = info.total > 0
			if (state.show == "all" or (state.show == "caught") == caught)
				and (not state.where or FoundIn(fish, info, state.where)) then
				out[#out + 1] = { fish = fish, info = info, skill = EasiestSkill(fish) }
			end
		end
	end
	table.sort(out, function(a, b)
		local ca, cb = CAT_ORDER[a.fish.cat] or 9, CAT_ORDER[b.fish.cat] or 9
		if ca ~= cb then
			return ca < cb
		end
		local sa, sb = a.skill or 999, b.skill or 999
		if sa ~= sb then
			return sa < sb
		end
		return FishName(a.fish) < FishName(b.fish)
	end)
	return out
end

-- The game's own flavour text for the item, if it has any.
local function FlavorText(itemID)
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
		return nil
	end
	local data = C_TooltipInfo.GetItemByID(itemID)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if text and text:match('^".+"$') then
			return text
		end
	end
end

local function Summary(fish)
	local zones, seen = 0, {}
	for _, zone in ipairs(fish.zones or {}) do
		if not seen[zone] then
			seen[zone], zones = true, zones + 1
		end
	end
	for _, extra in ipairs(fish.more or {}) do
		if not seen[extra[1]] then
			seen[extra[1]], zones = true, zones + 1
		end
	end
	local first = (fish.zones and fish.zones[1]) or (fish.more and fish.more[1] and fish.more[1][1])
	local text = CAT_LEAD[fish.cat] or "A catch"
	if zones == 1 then
		text = text .. " found in " .. first
	elseif zones > 1 then
		text = text .. string.format(" found in %d zones, most often in %s", zones, first)
	end
	text = text .. "."
	local skill = EasiestSkill(fish)
	if skill then
		text = text .. string.format(" Its easiest waters need %d Fishing so none get away.", skill)
	end
	if fish.recipes and #fish.recipes > 0 then
		local byProf, order = {}, {}
		for _, recipe in ipairs(fish.recipes) do
			if not byProf[recipe[3]] then
				order[#order + 1] = recipe[3]
			end
			byProf[recipe[3]] = (byProf[recipe[3]] or 0) + 1
		end
		local parts = {}
		for _, prof in ipairs(order) do
			parts[#parts + 1] = string.format("%d %s recipe%s", byProf[prof], prof, byProf[prof] == 1 and "" or "s")
		end
		text = text .. " Used in " .. table.concat(parts, " and ") .. "."
	end
	if fish.when then
		text = text .. " " .. WHEN_TEXT[fish.when]
	end
	if fish.event == "extravaganza" and ns.Extravaganza then
		text = text .. " " .. ns.Extravaganza.Describe()
	end
	if fish.discovered then
		text = text .. " Not in OneCast's records yet: you found this one yourself."
	end
	return text
end

-- When your own catches were made, by realm hour (logged from 0.3.0 on).
local function TimeOfDay(info)
	local day, night = 0, 0
	for h, n in pairs(info.hours or {}) do
		if h - 1 >= 6 and h - 1 < 18 then
			day = day + n
		else
			night = night + n
		end
	end
	local total = day + night
	if total == 0 then
		return nil
	end
	local lead = total == 1 and "Your one logged catch was" or ("All " .. total .. " logged catches were")
	if night == 0 then
		return lead .. " by day (06:00-18:00 realm time)."
	elseif day == 0 then
		return lead .. " at night (18:00-06:00 realm time)."
	end
	return string.format("Caught %d time%s by day and %d at night (realm time).", day, day == 1 and "" or "s", night)
end

-- Zone maps ------------------------------------------------------------------------------

-- Zone name to uiMapID: every zone under Azeroth (947) in one call. A zone not found there
-- (one of Forever's own, say) falls back to a one-time scan of every map ID.
local zoneMaps, scanned
local ZONE_TYPE = Enum.UIMapType and Enum.UIMapType.Zone or 3

local function ScanMaps()
	scanned = true
	for mapID = 1, 3000 do
		local info = C_Map.GetMapInfo(mapID)
		if info and info.name and info.mapType == ZONE_TYPE then
			zoneMaps[info.name] = zoneMaps[info.name] or mapID
		end
	end
end

local function ZoneMapID(zone)
	if not zoneMaps then
		zoneMaps = {}
		for _, info in ipairs(C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(947, ZONE_TYPE, true) or {}) do
			zoneMaps[info.name] = zoneMaps[info.name] or info.mapID
		end
	end
	if zone and not zoneMaps[zone] and not scanned then
		ScanMaps()
	end
	return zoneMaps[zone]
end

-- Explored-area overlays on top of the base art, all of them (MapOverlays.lua), so the map
-- shows fully revealed whatever this character has explored. Laid out as the world map
-- does: 256-pixel tiles, the last row and column cropped from a power-of-two file.
local OVERLAY_TILE = 256

local function FileSize(pixels)
	local size = 16
	while size < pixels do
		size = size * 2
	end
	return size
end

local function DrawOverlays(box, mapID, scale, offX, offY)
	local n = 0
	for _, o in ipairs(ns.MAP_OVERLAYS and ns.MAP_OVERLAYS[mapID] or {}) do
		local width, height, ox, oy = o[1], o[2], o[3], o[4]
		local cols, rows = math.ceil(width / OVERLAY_TILE), math.ceil(height / OVERLAY_TILE)
		for row = 1, rows do
			local h = row < rows and OVERLAY_TILE or height - OVERLAY_TILE * (rows - 1)
			local fileH = row < rows and OVERLAY_TILE or FileSize(h)
			for col = 1, cols do
				local w = col < cols and OVERLAY_TILE or width - OVERLAY_TILE * (cols - 1)
				local fileW = col < cols and OVERLAY_TILE or FileSize(w)
				n = n + 1
				local tex = box.overlays[n]
				if not tex then
					tex = box:CreateTexture(nil, "ARTWORK", nil, 1)
					box.overlays[n] = tex
				end
				tex:SetTexture(o[4 + (row - 1) * cols + col], nil, nil, "TRILINEAR")
				tex:SetTexCoord(0, w / fileW, 0, h / fileH)
				tex:SetSize(w * scale, h * scale)
				tex:ClearAllPoints()
				tex:SetPoint("TOPLEFT", box, "TOPLEFT", offX + (ox + OVERLAY_TILE * (col - 1)) * scale,
					-(offY + (oy + OVERLAY_TILE * (row - 1)) * scale))
				tex:Show()
			end
		end
	end
end

-- Pools you've found (Pools.lua), as dots on the map, each with a dark edge to stand out.
local POOL_DOT = 7

local function PoolDot(box, n, size, r, g, b, sublevel)
	local tex = box.poolDots[n]
	if not tex then
		tex = box:CreateTexture(nil, "OVERLAY", nil, sublevel)
		box.poolDots[n] = tex
	end
	tex:SetColorTexture(r, g, b, 1)
	tex:SetSize(size, size)
	tex:Show()
	return tex
end

-- An invisible button over a pool's dot: what it is, when you were last there, and a click
-- for the world map with a waypoint on it.
local function PoolHotspot(box, n, mapID, pool)
	box.poolButtons = box.poolButtons or {}
	local b = box.poolButtons[n]
	if not b then
		b = CreateFrame("Button", nil, box)
		b:SetSize(POOL_DOT + 6, POOL_DOT + 6)
		b:SetFrameLevel((box:GetFrameLevel() or 0) + 2)
		box.poolButtons[n] = b
	end
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(pool.name)
		GameTooltip:AddLine("A fishing pool you found here" .. (pool.seen and (", last on "
			.. date("%d %B", pool.seen)) or "") .. ". Pools move, so it may not be there now.", 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click: show on the map, with a waypoint", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", function()
		ns.UI.ShowOnMap(mapID, pool.x, pool.y, pool.name)
	end)
	b:Show()
	return b
end

local function DrawPools(box, mapID, width, height, offX, offY)
	local n = 0
	for i, pool in ipairs(ns.Pools.ForMap(mapID)) do
		local x, y = offX + pool.x * width, -(offY + pool.y * height)
		local hot = PoolHotspot(box, i, mapID, pool)
		hot:ClearAllPoints()
		hot:SetPoint("CENTER", box, "TOPLEFT", x, y)
		n = n + 1
		local edge = PoolDot(box, n, POOL_DOT + 2, 0, 0, 0, 1)
		edge:ClearAllPoints()
		edge:SetPoint("CENTER", box, "TOPLEFT", x, y)
		n = n + 1
		local dot = PoolDot(box, n, POOL_DOT, 0.25, 0.7, 1, 2)
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", box, "TOPLEFT", x, y)
	end
end

-- Draw a zone's map art, scaled to fit the box. Returns the map ID, or nil if none.
local function DrawMap(box, zone)
	for _, list in ipairs({ box.tiles, box.overlays, box.poolDots, box.poolButtons or {} }) do
		for _, tex in ipairs(list) do
			tex:Hide()
		end
	end
	local mapID = zone and ZoneMapID(zone)
	local layers = mapID and C_Map.GetMapArtLayers(mapID)
	local layer = layers and layers[1]
	local files = layer and C_Map.GetMapArtLayerTextures(mapID, 1)
	if not (files and #files > 0) then
		box.empty:Show()
		return nil
	end
	box.empty:Hide()
	local cols = math.ceil(layer.layerWidth / layer.tileWidth)
	local scale = math.min(MAP_W / layer.layerWidth, MAP_H / layer.layerHeight)
	local offX = (MAP_W - layer.layerWidth * scale) / 2
	local offY = (MAP_H - layer.layerHeight * scale) / 2
	for i, file in ipairs(files) do
		local tile = box.tiles[i]
		if not tile then
			tile = box:CreateTexture(nil, "ARTWORK", nil, 0)
			box.tiles[i] = tile
		end
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		tile:SetTexture(file)
		tile:SetSize(layer.tileWidth * scale, layer.tileHeight * scale)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", box, "TOPLEFT", offX + col * layer.tileWidth * scale,
			-(offY + row * layer.tileHeight * scale))
		tile:Show()
	end
	DrawOverlays(box, mapID, scale, offX, offY)
	DrawPools(box, mapID, layer.layerWidth * scale, layer.layerHeight * scale, offX, offY)
	return mapID
end

local function OpenZoneMap(mapID, x, y, label)
	return ns.UI.ShowOnMap(mapID, x, y, label)
end

local function OpenZoneByName(zone)
	local mapID = zone and ZoneMapID(zone)
	if not mapID then
		ns.Print("the game has no map for " .. (zone or "that zone") .. ".")
		return false
	end
	return OpenZoneMap(mapID)
end

-- Page text pool -------------------------------------------------------------------------
-- Each detail page reuses its strings, textures and zone buttons between fish.

local function NewPool(page)
	return { page = page, strings = {}, textures = {}, buttons = {}, s = 0, t = 0, b = 0 }
end

local function ResetPool(pool)
	for _, list in ipairs({ pool.strings, pool.textures, pool.buttons }) do
		for _, region in ipairs(list) do
			region:Hide()
		end
	end
	pool.s, pool.t, pool.b = 0, 0, 0
end

local function PoolString(pool, fontObject, size, color)
	pool.s = pool.s + 1
	local fs = pool.strings[pool.s]
	if not fs then
		fs = pool.page:CreateFontString(nil, "OVERLAY")
		pool.strings[pool.s] = fs
	end
	SizedFont(fs, fontObject, size)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowOffset(0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:SetWidth(0)
	fs:ClearAllPoints()
	fs:Show()
	return fs
end

local function PoolTexture(pool)
	pool.t = pool.t + 1
	local tex = pool.textures[pool.t]
	if not tex then
		tex = pool.page:CreateTexture(nil, "ARTWORK")
		pool.textures[pool.t] = tex
	end
	tex:ClearAllPoints()
	tex:SetTexCoord(0, 1, 0, 1)
	tex:SetVertexColor(1, 1, 1, 1)
	tex:SetDesaturated(false)
	tex:Show()
	return tex
end

local function PoolButton(pool)
	pool.b = pool.b + 1
	local b = pool.buttons[pool.b]
	if not b then
		b = CreateFrame("Button", nil, pool.page)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetHeight(18)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(0.55, 0.40, 0.15, 0.25)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b.left = b:CreateFontString(nil, "OVERLAY")
		b.left:SetPoint("LEFT", 6, 0)
		b.right = b:CreateFontString(nil, "OVERLAY")
		b.right:SetPoint("RIGHT", -6, 0)
		b.left:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
		b.left:SetJustifyH("LEFT")
		b.left:SetWordWrap(false)
		for _, fs in ipairs({ b.left, b.right }) do
			SizedFont(fs, QuestFont, 13)
			fs:SetShadowOffset(0, 0)
		end
		pool.buttons[pool.b] = b
	end
	b:ClearAllPoints()
	b:SetHeight(18)
	b.bg:Show()
	for _, script in ipairs({ "OnClick", "OnEnter", "OnLeave" }) do
		b:SetScript(script, nil)
	end
	b:Show()
	return b
end

-- An invisible button over part of a page: hovering shows a tooltip `fill` writes, and a
-- Shift-click links what `link` returns in chat. Text underneath shows through.
local function Hover(pool, x, y, width, height, fill, link)
	local b = PoolButton(pool)
	b:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x - 3, -y + 2)
	b:SetSize(width + 6, height)
	b.bg:Hide()
	b.left:SetText("")
	b.right:SetText("")
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		fill(GameTooltip)
		if link then
			GameTooltip:AddLine("Shift-click to link it in chat", 0.6, 0.8, 1)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", function()
		local text = link and IsModifiedClick("CHATLINK") and link()
		if text then
			ChatEdit_InsertLink(text)
		end
	end)
	return b
end

local function ItemLink(itemID)
	return function()
		return ns.ItemLink(itemID)
	end
end

local function SpellLink(spellID)
	return function()
		return C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(spellID)
	end
end

-- Pieces of text that wrap like one sentence, each with its own tooltip:
-- { text, fill = function(tip), link = function() }, separated by `sep`. Returns the y below.
local function Flow(pool, pieces, x, y, width, size, color, sep)
	local lineHeight = size + 4
	local cx = 0
	for i, piece in ipairs(pieces) do
		local fs = PoolString(pool, QuestFont, size, color)
		fs:SetText(piece.text .. (i < #pieces and (sep or ", ") or ""))
		local w = fs:GetStringWidth() or 0
		if cx > 0 and cx + w > width then
			cx, y = 0, y + lineHeight
		end
		fs:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x + cx, -y)
		if piece.fill then
			Hover(pool, x + cx, y, w, lineHeight, piece.fill, piece.link)
		end
		cx = cx + w
	end
	return y + lineHeight
end

-- Heading with a rule running to the page edge; returns its height.
local function Heading(pool, text, x, y, right)
	local heading = PoolString(pool, QuestTitleFont, 17, INK)
	heading:SetText(text)
	heading:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	local rule = PoolTexture(pool)
	rule:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.45)
	rule:SetHeight(1)
	rule:SetPoint("LEFT", heading, "RIGHT", 10, 0)
	rule:SetPoint("RIGHT", pool.page, "RIGHT", -right, 0)
	return heading:GetStringHeight() + 8
end

-- Grid -----------------------------------------------------------------------------------

local function QualityColor(quality)
	return ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
end

local function CreateCell(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(CELL_W, CELL_H)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(46, 46)
	b.icon:SetPoint("TOP", 0, -4)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	b.border:SetAllPoints(b.icon)
	b.check = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	b.check:SetSize(18, 18)
	b.check:SetPoint("CENTER", b.icon, "TOPRIGHT", -2, -2)
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -2, 2)
	b.name = b:CreateFontString(nil, "OVERLAY")
	SizedFont(b.name, QuestFont, 12)
	b.name:SetShadowOffset(0, 0)
	b.name:SetWidth(CELL_W - 2)
	b.name:SetPoint("TOP", b.icon, "BOTTOM", 0, -5)
	b.name:SetJustifyH("CENTER")
	b.name:SetWordWrap(true)
	if b.name.SetMaxLines then
		b.name:SetMaxLines(3)
	end
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b.icon)
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")
	b:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Book.ShowFish(self.fishID)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.fishID)
		local info = ns.Collection.Get(self.fishID)
		GameTooltip:AddLine(" ")
		if info.total > 0 then
			GameTooltip:AddLine(string.format("Caught %d time%s on %d character%s", info.total,
				info.total == 1 and "" or "s", #info.chars, #info.chars == 1 and "" or "s"), 0.6, 0.8, 1)
		else
			GameTooltip:AddLine("Not caught yet", 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine("Click to open its page", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function FillCell(cell, entry)
	local fish, info = entry.fish, entry.info
	local caught = info.total > 0
	cell.fishID = fish.id
	cell.icon:SetTexture(FishIcon(fish))
	cell.icon:SetDesaturated(not caught)
	cell.icon:SetVertexColor(caught and 1 or 0.55, caught and 1 or 0.55, caught and 1 or 0.55)
	local color = QualityColor(FishQuality(fish))
	if caught and color then
		cell.border:SetVertexColor(color.r, color.g, color.b)
	else
		cell.border:SetVertexColor(0.4, 0.35, 0.3)
	end
	cell.check:SetShown(caught)
	cell.count:SetText(caught and info.total > 1 and info.total or "")
	cell.name:SetText(FishName(fish))
	local ink = caught and INK or INK_SOFT
	cell.name:SetTextColor(ink[1], ink[2], ink[3], caught and 1 or 0.75)
	cell:Show()
end

local function RenderGrid()
	local list = Filtered()
	state.list = list
	local spreads = math.max(1, math.ceil(#list / (PER_PAGE * 2)))
	state.spread = math.min(state.spread, spreads)
	local start = (state.spread - 1) * PER_PAGE * 2
	for p, page in ipairs(frame.pages) do
		for i, cell in ipairs(page.cells) do
			local entry = list[start + (p - 1) * PER_PAGE + i]
			if entry then
				FillCell(cell, entry)
			else
				cell:Hide()
			end
		end
		page.number:SetText((state.spread - 1) * 2 + p)
	end
	local label = state.where and "Fish" or "Fish of Azeroth"
	for _, cat in ipairs(CATEGORIES) do
		if cat.key == state.cat and cat.key ~= "all" then
			label = cat.label
		end
	end
	if state.where then
		label = label .. " of " .. state.where
	end
	frame.pages[1].title:SetText(label)
	frame.pages[2].title:SetText(#list == 0 and "" or string.format("%d shown", #list))
	frame.empty:SetShown(#list == 0)
	if state.show == "missing" and not state.search then
		frame.empty:SetText("Nothing missing here: all caught!")
	elseif state.search or state.where or state.show ~= "all" then
		frame.empty:SetText("No fish match.")
	else
		frame.empty:SetText("Nothing here yet.")
	end
	frame.pageLabel:SetText(string.format("Pages %d-%d of %d", state.spread * 2 - 1, state.spread * 2, spreads * 2))
	frame.prev:SetEnabled(state.spread > 1)
	frame.next:SetEnabled(state.spread < spreads)
end

-- Fish page ------------------------------------------------------------------------------

local function ZoneRows(fish, info)
	local rows, seen = {}, {}
	for _, zone in ipairs(fish.zones or {}) do
		rows[#rows + 1] = { zone = zone }
		seen[zone] = true
	end
	for _, extra in ipairs(fish.more or {}) do
		if not seen[extra[1]] then
			rows[#rows + 1] = { zone = extra[1], tag = extra[2] }
			seen[extra[1]] = true
		end
	end
	for zone in pairs(info.zones) do
		if not seen[zone] then
			rows[#rows + 1] = { zone = zone, tag = "found by you" }
			seen[zone] = true
		end
	end
	return rows
end

local function RenderLeft(fish, info)
	local pool = frame.leftPool
	local page = pool.page
	ResetPool(pool)
	local x, width = 32, math.max(page:GetWidth(), 400) - 64

	local icon = PoolTexture(pool)
	icon:SetTexture(FishIcon(fish))
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetSize(56, 56)
	icon:SetPoint("TOPLEFT", page, "TOPLEFT", x, -30)
	icon:SetDesaturated(info.total == 0)
	local border = PoolTexture(pool)
	border:SetTexture("Interface\\Common\\WhiteIconFrame")
	border:SetAllPoints(icon)
	local color = QualityColor(FishQuality(fish))
	if color then
		border:SetVertexColor(color.r, color.g, color.b)
	end

	local name = PoolString(pool, QuestTitleFont, 22, INK)
	name:SetWidth(width - 70)
	name:SetText(FishName(fish))
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
	local kind = PoolString(pool, QuestFont, 13, INK_SOFT)
	local skill = EasiestSkill(fish)
	kind:SetText((CAT_NAME[fish.cat] or "Catch") .. (skill and ("  ·  " .. skill .. " Fishing") or ""))
	kind:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	Hover(pool, x, 30, width, 56, function(tip)
		tip:SetItemByID(fish.id)
	end, ItemLink(fish.id))

	local y = 30 + 56 + 18
	local function Paragraph(text, color, gap)
		local fs = PoolString(pool, QuestFont, 14, color)
		fs:SetWidth(width)
		fs:SetText(text)
		fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
		y = y + fs:GetStringHeight() + (gap or 10)
	end

	local flavor = FlavorText(fish.id)
	if flavor then
		Paragraph(flavor, INK_SOFT)
	end
	Paragraph(Summary(fish), INK, 18)

	y = y + Heading(pool, "Your catches", x, y, 32)
	if info.total > 0 then
		Paragraph(string.format("Caught %s%d|r time%s on %d character%s.", LEAD, info.total,
			info.total == 1 and "" or "s", #info.chars, #info.chars == 1 and "" or "s"), INK, 6)
		for i, who in ipairs(info.chars) do
			if i > MAX_CHARS then
				Paragraph(string.format("%sand %d more|r", SOFT, #info.chars - MAX_CHARS), INK, 4)
				break
			end
			Paragraph(string.format("%s  %s%d|r", who.name, LEAD, who.count), INK, 4)
		end
		y = y + 6
		if info.first then
			Paragraph(string.format("%sFirst caught on %s by %s%s.|r", SOFT, date("%d %B %Y", info.first.time),
				info.first.char or "?", info.first.zone and (" in " .. info.first.zone) or ""), INK, 4)
		end
		local when = TimeOfDay(info)
		if when then
			Paragraph(SOFT .. when .. "|r", INK)
		end
	else
		local tip = (fish.zones and fish.zones[1]) or (fish.more and fish.more[1] and fish.more[1][1])
		Paragraph("Not caught yet." .. (tip and (" Try " .. tip .. ".") or ""), INK)
	end
end

local function RenderRight(fish, info)
	local pool = frame.rightPool
	local page = pool.page
	ResetPool(pool)
	local x, width = 32, math.max(page:GetWidth(), 400) - 64
	local y = 30

	y = y + Heading(pool, "Where to catch", x, y, 32)
	local rows = ZoneRows(fish, info)
	if not state.zone then
		state.zone = rows[1] and rows[1].zone
	end
	for i, row in ipairs(rows) do
		if i > MAX_ZONES then
			local more = PoolString(pool, QuestFont, 13, INK_SOFT)
			more:SetText(string.format("and %d more zone%s", #rows - MAX_ZONES, #rows - MAX_ZONES == 1 and "" or "s"))
			more:SetPoint("TOPLEFT", page, "TOPLEFT", x + 6, -y)
			y = y + 16
			break
		end
		local b = PoolButton(pool)
		b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
		b:SetWidth(width)
		b.bg:SetShown(row.zone == state.zone)
		b.left:SetText(row.zone .. (row.tag and (" " .. SOFT .. "(" .. row.tag .. ")|r") or ""))
		b.left:SetTextColor(INK[1], INK[2], INK[3])
		local needs = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[row.zone]
		local mine = info.zones[row.zone]
		local right = {}
		if needs and needs > 1 then
			right[#right + 1] = "needs " .. needs
		end
		if mine then
			right[#right + 1] = LEAD .. mine .. " caught|r"
		end
		b.right:SetText(table.concat(right, "  ·  "))
		b.right:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
		local nameWidth = (b.left.GetUnboundedStringWidth and b.left:GetUnboundedStringWidth()) or b.left:GetStringWidth() or 0
		if needs and mine and nameWidth + (b.right:GetStringWidth() or 0) + 20 > width then
			b.right:SetText(LEAD .. mine .. " caught|r")
		end
		b:SetScript("OnClick", function(_, mouseButton)
			if mouseButton == "RightButton" then
				OpenZoneByName(row.zone)
				return
			end
			state.zone = row.zone
			Book.Refresh()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(row.zone)
			GameTooltip:AddLine(ns.Stats.ZoneVerdict(row.zone), 1, 1, 1, true)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Click: show it on the map below", 0.6, 0.8, 1)
			GameTooltip:AddLine("Right-click: open the world map", 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		y = y + 19
	end
	if #rows == 0 then
		local none = PoolString(pool, QuestFont, 14, INK_SOFT)
		none:SetText("No known waters yet. Catch one and OneCast will remember where.")
		none:SetWidth(width)
		none:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
		y = y + none:GetStringHeight() + 6
	end

	-- Map of the selected zone.
	y = y + 8
	local map = frame.map
	map:ClearAllPoints()
	map:SetPoint("TOP", page, "TOP", 0, -y)
	map:Show()
	frame.mapID = DrawMap(map, state.zone)
	local pools = frame.mapID and #ns.Pools.ForMap(frame.mapID) or 0
	frame.mapCaption:SetText((state.zone or "") .. (pools > 0
		and string.format("  ·  %d pool%s found", pools, pools == 1 and "" or "s") or ""))
	frame.openMap:SetEnabled(frame.mapID ~= nil)
	y = y + MAP_H + 34

	y = y + Heading(pool, "Used in", x, y, 32)
	local recipes = fish.recipes or {}
	for i, recipe in ipairs(recipes) do
		if i > MAX_RECIPES then
			local more = PoolString(pool, QuestFont, 13, INK_SOFT)
			more:SetText(string.format("and %d more", #recipes - MAX_RECIPES))
			more:SetPoint("TOPLEFT", page, "TOPLEFT", x + 18, -y)
			break
		end
		local dot = PoolTexture(pool)
		dot:SetTexture("Interface\\QuestFrame\\UI-Quest-BulletPoint")
		dot:SetSize(12, 12)
		dot:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y - 1)
		local line = PoolString(pool, QuestFont, 14, INK)
		local skill = recipe[4] and (" " .. recipe[4]) or ""
		line:SetText(string.format("%s  %s%s%s|r", recipe[2], SOFT, recipe[3], skill))
		line:SetPoint("TOPLEFT", page, "TOPLEFT", x + 18, -y)
		Hover(pool, x + 18, y, line:GetStringWidth() or width, 17, function(tip)
			tip:SetSpellByID(recipe[1])
			if recipe[4] then
				tip:AddLine(string.format("Needs %d %s.", recipe[4], recipe[3]), 1, 0.82, 0)
			end
		end, SpellLink(recipe[1]))
		y = y + 17
	end
	if #recipes == 0 then
		local none = PoolString(pool, QuestFont, 14, INK_SOFT)
		none:SetText("Not used in any recipe.")
		none:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
	end
end

local function RenderFish()
	local entry
	for i, e in ipairs(state.list or {}) do
		if e.fish.id == state.fishID then
			entry, state.index = e, i
		end
	end
	if not entry then
		local fish = ns.FISH_BY_ID[state.fishID]
		if not fish then
			for _, found in ipairs(ns.Collection.Discovered()) do
				if found.id == state.fishID then
					fish = found
					found.cat, found.zones = "fish", {}
				end
			end
		end
		if not fish then
			state.fishID = nil
			return false
		end
		entry, state.index = { fish = fish }, nil
	end
	local info = ns.Collection.Get(entry.fish.id)
	RenderLeft(entry.fish, info)
	RenderRight(entry.fish, info)
	local count = state.list and #state.list or 0
	frame.pageLabel:SetText(state.index and string.format("%d of %d", state.index, count) or "")
	frame.prev:SetEnabled(state.index and state.index > 1 or false)
	frame.next:SetEnabled(state.index and state.index < count or false)
	return true
end

-- Zones view -----------------------------------------------------------------------------

-- Every zone worth listing: those with a level, Forever's new ones, and any with known fish.
local function ZoneGroups()
	local set = {}
	for zone in pairs(ns.ZONE_FISHING_SKILL or {}) do
		set[zone] = true
	end
	for _, zone in ipairs(ns.ZONE_FISHING_UNKNOWN or {}) do
		set[zone] = true
	end
	for _, zone in ipairs(ZoneChoices()) do
		set[zone] = true
	end
	local byLevel, levels = {}, {}
	for zone in pairs(set) do
		local level = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone] or math.huge
		if not byLevel[level] then
			byLevel[level] = {}
			levels[#levels + 1] = level
		end
		table.insert(byLevel[level], zone)
	end
	table.sort(levels)
	local groups = {}
	for _, level in ipairs(levels) do
		table.sort(byLevel[level])
		groups[#groups + 1] = { level = level ~= math.huge and level or nil, zones = byLevel[level] }
	end
	return groups
end

-- Lays the groups out on pages, odd pages being shorter for the intro. A heading is never
-- left alone at the foot of a page.
local function ZonePages(groups)
	local pages, page, used = {}, {}, 0
	local function Room()
		return ZONES_HEIGHT - (#pages % 2 == 0 and ZONES_INTRO or 0)
	end
	local function NextPage()
		pages[#pages + 1] = page
		page, used = {}, 0
	end
	for _, group in ipairs(groups) do
		if used + ZONE_HEADING + ZONE_ROW > Room() then
			NextPage()
		end
		page[#page + 1] = { heading = group.level and (group.level .. " Fishing") or "Level unknown" }
		used = used + ZONE_HEADING
		for _, zone in ipairs(group.zones) do
			if used + ZONE_ROW > Room() then
				NextPage()
			end
			page[#page + 1] = { zone = zone }
			used = used + ZONE_ROW
		end
	end
	pages[#pages + 1] = page
	return pages
end

-- How many known fish each listed zone has, and how many of those you've caught.
local function ZoneCounts(groups)
	local counts = {}
	local fishes = {}
	for _, fish in ipairs(AllFish()) do
		fishes[#fishes + 1] = { fish = fish, info = ns.Collection.Get(fish.id) }
	end
	for _, group in ipairs(groups) do
		for _, zone in ipairs(group.zones) do
			local count = { caught = 0, total = 0 }
			for _, entry in ipairs(fishes) do
				if FoundIn(entry.fish, entry.info, zone) then
					count.total = count.total + 1
					count.caught = count.caught + (entry.info.total > 0 and 1 or 0)
				end
			end
			counts[zone] = count
		end
	end
	return counts
end

-- A row's status, in ink dark enough for parchment.
local function ZoneStatusText(status)
	if status.kind == "ok" then
		return GOOD .. "ready|r"
	elseif status.kind == "short" then
		return BAD .. status.short .. " short|r"
	elseif status.kind == "getaways" then
		return BAD .. "fish get away|r"
	elseif status.kind == "outgrown" then
		return SOFT .. "got away at " .. status.escapeSkill .. "|r"
	elseif status.kind == "clear" then
		return GOOD .. "no getaways|r"
	elseif status.kind == "note" then
		return GOOD .. "no minimum|r"
	end
end

local function RenderZoneRow(pool, zone, count, here, x, y, width, news)
	local b = PoolButton(pool)
	b:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	b:SetWidth(width)
	b.bg:SetShown(zone == here)
	b.left:SetText(zone .. (zone == here and (" " .. SOFT .. "(here)|r") or ""))
	b.left:SetTextColor(INK[1], INK[2], INK[3])
	local right = {}
	if count.total > 0 then
		right[#right + 1] = SOFT .. count.caught .. "/" .. count.total .. " fish|r"
	end
	right[#right + 1] = ZoneStatusText(ns.Stats.ZoneStatus(zone))
	if news then
		right[#right + 1] = GOOD .. "new data|r"
	end
	b.right:SetText(table.concat(right, "  ·  "))
	b.right:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
	b:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			OpenZoneByName(zone)
			return
		end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Book.ShowZoneFish(zone)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(zone)
		GameTooltip:AddLine(ns.Stats.ZoneVerdict(zone), 1, 1, 1, true)
		if count.total > 0 then
			GameTooltip:AddLine(string.format("You've caught %d of the %d fish known here.", count.caught, count.total),
				1, 1, 1, true)
		else
			GameTooltip:AddLine("No fish known here yet.", 0.7, 0.7, 0.7, true)
		end
		if news then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("New to OneCast:", 0.12, 1, 0)
			for _, f in ipairs(news) do
				GameTooltip:AddLine(f.text, 1, 1, 1, true)
			end
			GameTooltip:AddLine("Share your data at the bottom of the book.", 0.6, 0.8, 1, true)
		end
		GameTooltip:AddLine("Click: see its fish", 0.6, 0.8, 1)
		GameTooltip:AddLine("Right-click: open the world map", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
end

local function RenderZones()
	local groups = ZoneGroups()
	local pages = ZonePages(groups)
	local counts = ZoneCounts(groups)
	local spreads = math.max(1, math.ceil(#pages / 2))
	state.spread = math.min(state.spread, spreads)
	local here = ns.Stats.CurrentZone()
	local news = ns.Report and ns.Report.UnsharedByZone() or {}
	for p, page in ipairs(frame.pages) do
		local pool = frame.zonePools[p]
		ResetPool(pool)
		local x, width = 32, math.max(pool.page:GetWidth(), 400) - 64
		local y = ZONES_TOP
		if p == 1 then
			local intro = PoolString(pool, QuestFont, 13, INK_SOFT)
			intro:SetWidth(width)
			intro:SetText("The Fishing skill each zone needs so no fish get away, lures and poles included. "
				.. "These are Classic's numbers: Forever's may differ. Click a zone to see its fish.")
			intro:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
			y = y + ZONES_INTRO
		end
		for _, entry in ipairs(pages[(state.spread - 1) * 2 + p] or {}) do
			if entry.heading then
				Heading(pool, entry.heading, x, y + 6, 32)
				y = y + ZONE_HEADING
			else
				RenderZoneRow(pool, entry.zone, counts[entry.zone], here, x, y, width, news[entry.zone])
				y = y + ZONE_ROW
			end
		end
		page.number:SetText((state.spread - 1) * 2 + p)
	end
	frame.pages[1].title:SetText("Fishing levels by zone")
	local rank, _, modifier = ns.Stats.FishingSkill()
	frame.pages[2].title:SetText(rank and string.format("Your Fishing: %d%s", rank,
		modifier > 0 and (" +" .. modifier) or "") or "")
	frame.pageLabel:SetText(string.format("Pages %d-%d of %d", state.spread * 2 - 1, state.spread * 2, spreads * 2))
	frame.prev:SetEnabled(state.spread > 1)
	frame.next:SetEnabled(state.spread < spreads)
end

-- Camp -----------------------------------------------------------------------------------
-- Forever's fishing crafts for its camps (Camp.lua): what each needs and does on the left,
-- how camps work and what this character has caught under their buffs on the right.

local CAMP_TOP = 50

local function CampText(pool, text, x, y, width, size, color)
	local fs = PoolString(pool, QuestFont, size or 13, color or INK)
	fs:SetWidth(width)
	fs:SetText(text)
	fs:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	return y + fs:GetStringHeight() + 4
end

-- An item's own tooltip, then `extra` lines, over part of the page; Shift-click links it.
local function ItemHover(pool, itemID, extra, x, y, width, height)
	return Hover(pool, x, y, width, height, function(tip)
		tip:SetItemByID(itemID)
		if extra then
			extra(tip)
		end
	end, ItemLink(itemID))
end

local function RenderCraft(pool, craft, x, y, width)
	local Camp = ns.Camp
	local icon = PoolTexture(pool)
	icon:SetTexture(C_Item.GetItemIconByID(craft.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
	icon:SetSize(34, 34)
	icon:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	local name = PoolString(pool, QuestTitleFont, 16, INK)
	name:SetText(craft.name)
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
	local rank = ns.Stats.FishingSkill()
	local parts = { (rank and rank < craft.skill and BAD or SOFT) .. "Needs " .. craft.skill .. " Fishing|r" }
	local known = Camp.Known(craft)
	if known then
		parts[#parts + 1] = GOOD .. "learned|r"
	elseif known == false then
		if craft.blueprint and Camp.Count(craft.blueprint) > 0 then
			parts[#parts + 1] = GOOD .. "Blueprint in your bags: open it to learn|r"
		else
			parts[#parts + 1] = SOFT .. "not learned yet|r"
		end
	end
	local made = Camp.Count(craft.item)
	if made > 0 then
		parts[#parts + 1] = SOFT .. made .. " in your bags|r"
	end
	local status = PoolString(pool, QuestFont, 12, INK_SOFT)
	status:SetText(table.concat(parts, "  ·  "))
	status:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	ItemHover(pool, craft.item, function(tip)
		tip:AddLine(" ")
		if known then
			tip:AddLine("You've learned to make it.", 0.12, 1, 0)
		elseif known == false then
			tip:AddLine("You haven't learned to make it yet.", 1, 0.3, 0.3)
			if craft.blueprintFrom then
				tip:AddLine(craft.blueprintName .. ": " .. craft.blueprintFrom, 1, 1, 1, true)
			end
		end
		if made > 0 then
			tip:AddLine(string.format("You have %d.", made), 1, 1, 1)
		end
	end, x, y, width, 38)
	y = y + 40
	local pieces = { { text = "Makes from: " } }
	for i, r in ipairs(craft.reagents) do
		local have = Camp.Count(r[1])
		pieces[#pieces + 1] = {
			text = (have >= r[2] and GOOD or BAD) .. math.min(have, r[2]) .. "/" .. r[2] .. "|r " .. Camp.ItemName(r[1], r[3])
				.. (i < #craft.reagents and ", " or ""),
			fill = function(tip)
				tip:SetItemByID(r[1])
				tip:AddLine(string.format("You have %d, and it takes %d.", have, r[2]), 1, 1, 1)
			end,
			link = ItemLink(r[1]),
		}
	end
	y = Flow(pool, pieces, x, y, width, 12, INK, "") + 2
	-- Where to get the Blueprint, until it's learned or in the bags.
	if craft.blueprintFrom and known ~= true and Camp.Count(craft.blueprint) == 0 then
		local top = y
		y = CampText(pool, LEAD .. "Blueprint:|r " .. craft.blueprintFrom, x, y, width, 12)
		ItemHover(pool, craft.blueprint, nil, x, top, width, y - top)
	end
	y = CampText(pool, craft.does, x, y, width, 12, INK_SOFT)
	return y + 10
end

local function RenderCamp()
	local Camp = ns.Camp
	for p in ipairs(frame.pages) do
		ResetPool(frame.campPools[p])
	end
	local left, right = frame.campPools[1], frame.campPools[2]
	local x = 32
	local width = math.max(left.page:GetWidth(), 400) - 64

	local y = CAMP_TOP
	for _, craft in ipairs(Camp.CRAFTS) do
		y = RenderCraft(left, craft, x, y, width)
	end

	y = CAMP_TOP
	y = y + Heading(right, "How camps work", x, y, 32)
	y = CampText(right, string.format("Build a campfire with Cooking, then place up to its limit of features beside it. "
		.. "Sit nearby for %d seconds and each feature's benefit lasts an hour. Features stand %d minutes, and all of "
		.. "them share a %d-minute cooldown.", Camp.SIT_SECONDS, Camp.FEATURE_MINUTES, Camp.COOLDOWN_MINUTES), x, y, width, 12)
	local fires = {}
	for i, fire in ipairs(Camp.CAMPFIRES) do
		fires[i] = {
			text = string.format("%s holds %d", fire.name, fire.holds) .. (i < #Camp.CAMPFIRES and ", " or "."),
			fill = function(tip)
				tip:SetSpellByID(fire.recipe)
				tip:AddLine(string.format("A Cooking recipe. Holds up to %d camp features.", fire.holds), 1, 1, 1, true)
			end,
			link = SpellLink(fire.recipe),
		}
	end
	y = Flow(right, fires, x, y, width, 12, INK_SOFT, "") + 8

	y = y + Heading(right, "Right now", x, y, 32)
	local craft, left_ = Camp.ActiveBuff()
	if craft then
		local top = y
		y = CampText(right, string.format("%s%s|r is on%s, from a %s.", GOOD, craft.buffName,
			left_ and string.format(" for %d more minutes", math.ceil(left_ / 60)) or "", craft.name), x, y, width)
		Hover(right, x, top, width, y - top, function(tip)
			tip:SetSpellByID(craft.buff)
		end, SpellLink(craft.buff))
	else
		y = CampText(right, "No camp fishing buff on. Sit by a campfire with a Fishing Rack or Fishing Hut to get one.",
			x, y, width, 13, INK_SOFT)
	end
	y = y + 8

	y = y + Heading(right, "Caught with the buffs", x, y, 32)
	local any = false
	for _, c in ipairs(Camp.CRAFTS) do
		local r = c.buff and Camp.Record(c.key)
		if r and r.catches > 0 then
			any = true
			local items = {}
			for id, n in pairs(r.items) do
				items[#items + 1] = { id = id, n = n }
			end
			table.sort(items, function(a, b)
				return a.n > b.n
			end)
			local top = {}
			for i = 1, math.min(#items, 5) do
				top[i] = string.format("%s x%d", C_Item.GetItemNameByID(items[i].id) or ("item " .. items[i].id), items[i].n)
			end
			y = CampText(right, string.format("%s%s|r: %d catch%s. %s", LEAD, c.buffName, r.catches,
				r.catches == 1 and "" or "es", table.concat(top, ", ")), x, y, width, 12)
		end
	end
	if not any then
		y = CampText(right, "Nothing yet. Catches made with Uncommon or Rare Fishing on are kept here, to show what "
			.. "their extra rewards really are: the game doesn't say. /onecast report shares them.", x, y, width, 12, INK_SOFT)
	end

	frame.pages[1].title:SetText("Fishing at camp")
	frame.pages[2].title:SetText("Your camp")
	frame.pages[1].number:SetText(1)
	frame.pages[2].number:SetText(2)
	frame.pageLabel:SetText("")
	frame.prev:SetEnabled(false)
	frame.next:SetEnabled(false)
end

-- Window ---------------------------------------------------------------------------------

local function CreatePage(parent)
	local page = CreateFrame("Frame", nil, parent)
	local parchment = page:CreateTexture(nil, "BACKGROUND")
	parchment:SetAllPoints()
	ns.Theme.Register(parchment, "parchment")
	if HasAtlas("QuestBG-Parchment") then
		parchment:SetAtlas("QuestBG-Parchment")
	else
		parchment:SetTexture("Interface\\QuestFrame\\QuestBG")
		parchment:SetTexCoord(0, 0.586, 0, 0.65)
	end
	page.title = page:CreateFontString(nil, "OVERLAY")
	SizedFont(page.title, QuestTitleFont, 18)
	Ink(page.title, INK)
	page.title:SetShadowOffset(0, 0)
	page.title:SetPoint("TOP", 0, -20)
	page.number = page:CreateFontString(nil, "OVERLAY")
	SizedFont(page.number, QuestFont, 12)
	Ink(page.number, INK_SOFT)
	page.number:SetShadowOffset(0, 0)
	page.number:SetPoint("BOTTOM", 0, 14)
	page.grid = CreateFrame("Frame", nil, page)
	page.grid:SetAllPoints()
	page.cells = {}
	local gridW = COLS * CELL_W
	for i = 1, PER_PAGE do
		local cell = CreateCell(page.grid)
		local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		cell:SetPoint("TOPLEFT", page.grid, "TOP", -gridW / 2 + col * CELL_W, -52 - row * CELL_H)
		page.cells[i] = cell
	end
	page.detail = CreateFrame("Frame", nil, page)
	page.detail:SetAllPoints()
	page.zones = CreateFrame("Frame", nil, page)
	page.zones:SetAllPoints()
	page.camp = CreateFrame("Frame", nil, page)
	page.camp:SetAllPoints()
	return page
end

local function CreateWindow()
	local f = TryCreate("Frame", "OneCastBookFrame", UIParent, "ButtonFrameTemplate")
	if not f then
		f = CreateFrame("Frame", "OneCastBookFrame", UIParent, "BackdropTemplate")
		f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 } })
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
	end
	if f.SetTitle then
		f:SetTitle("Fishing Collection")
	end
	if ns.SetPortrait then
		ns.SetPortrait(f, "Interface\\Icons\\INV_Misc_Book_09")
	end
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	ns.UI.RememberPosition(f, "book")
	tinsert(UISpecialFrames, f:GetName())
	ns.UI.KeepOpenThroughOptions(f:GetName())

	local inset = f.Inset or CreateFrame("Frame", nil, f)
	inset:ClearAllPoints()
	inset:SetPoint("TOPLEFT", 4, -60)
	inset:SetPoint("BOTTOMRIGHT", -6, 30)
	ns.Theme.Frame(f, inset)

	-- Category tabs, like the stats window's.
	f.Tabs = {}
	for i, cat in ipairs(CATEGORIES) do
		local tab = TryCreate("Button", "OneCastBookFrameTab" .. i, f, "PanelTopTabButtonTemplate")
			or CreateFrame("Button", "OneCastBookFrameTab" .. i, f, "UIPanelButtonTemplate")
		ns.Theme.Register(tab, "button")
		tab:SetID(i)
		tab:SetText(cat.label)
		if not tab.Text and tab:GetWidth() < 10 then
			tab:SetSize(80, 22)
		end
		if i == 1 then
			tab:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 62, 0)
		else
			tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", 2, 0)
		end
		tab:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			state.cat, state.spread, state.fishID = cat.key, 1, nil
			Book.Refresh()
		end)
		tab.cat = cat.key
		f.Tabs[i] = tab
	end
	if PanelTemplates_SetNumTabs then
		PanelTemplates_SetNumTabs(f, #CATEGORIES)
	end

	-- Progress, top right.
	f.progressText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.progressText:SetPoint("TOPRIGHT", -24, -32)
	f.progress = CreateFrame("StatusBar", nil, f)
	f.progress:SetSize(170, 8)
	f.progress:SetPoint("TOPRIGHT", f.progressText, "BOTTOMRIGHT", 0, -4)
	f.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	f.progress:SetStatusBarColor(0.16, 0.36, 0.86)
	f.progress:SetMinMaxValues(0, 1)
	local progressBg = f.progress:CreateTexture(nil, "BACKGROUND")
	progressBg:SetAllPoints()
	progressBg:SetColorTexture(0, 0, 0, 0.6)

	-- Two parchment pages.
	f.pages = {}
	for p = 1, 2 do
		local page = CreatePage(inset)
		page:SetPoint("TOP", inset, "TOP", 0, -6)
		page:SetPoint("BOTTOM", inset, "BOTTOM", 0, 6)
		if p == 1 then
			page:SetPoint("LEFT", inset, "LEFT", 6, 0)
			page:SetPoint("RIGHT", inset, "CENTER", -3, 0)
		else
			page:SetPoint("LEFT", inset, "CENTER", 3, 0)
			page:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
		end
		f.pages[p] = page
	end
	f.leftPool = NewPool(f.pages[1].detail)
	f.rightPool = NewPool(f.pages[2].detail)
	f.zonePools = { NewPool(f.pages[1].zones), NewPool(f.pages[2].zones) }
	f.campPools = { NewPool(f.pages[1].camp), NewPool(f.pages[2].camp) }

	f.empty = f.pages[1].grid:CreateFontString(nil, "OVERLAY")
	SizedFont(f.empty, QuestFont, 15)
	Ink(f.empty, INK_SOFT)
	f.empty:SetShadowOffset(0, 0)
	f.empty:SetPoint("TOP", 0, -80)
	f.empty:SetText("Nothing here yet.")

	-- Map box on the fish page, with its caption and an Open map button.
	f.map = CreateFrame("Frame", nil, f.pages[2].detail, "BackdropTemplate")
	f.map:SetSize(MAP_W, MAP_H)
	f.map:SetClipsChildren(true)
	f.map:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f.map:SetBackdropColor(0.10, 0.08, 0.05, 0.25)
	f.map:SetBackdropBorderColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.8)
	f.map.tiles, f.map.overlays, f.map.poolDots = {}, {}, {}
	f.map.empty = f.map:CreateFontString(nil, "OVERLAY")
	SizedFont(f.map.empty, QuestFont, 13)
	Ink(f.map.empty, INK_SOFT)
	f.map.empty:SetShadowOffset(0, 0)
	f.map.empty:SetPoint("CENTER")
	f.map.empty:SetText("No map for this zone.")
	-- The little map opens the world map; its pool dots have their own tooltips over it.
	f.map:EnableMouse(true)
	f.map:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "LeftButton" then
			OpenZoneMap(frame.mapID)
		end
	end)
	f.map:SetScript("OnEnter", function(self)
		if not frame.mapID then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(state.zone or "")
		GameTooltip:AddLine("Click: open the world map", 0.6, 0.8, 1)
		if #ns.Pools.ForMap(frame.mapID) > 0 then
			GameTooltip:AddLine("Blue dots are pools you've found: hover or click one.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	f.map:SetScript("OnLeave", GameTooltip_Hide)
	f.mapCaption = f.pages[2].detail:CreateFontString(nil, "OVERLAY")
	SizedFont(f.mapCaption, QuestFont, 13)
	Ink(f.mapCaption, INK_SOFT)
	f.mapCaption:SetShadowOffset(0, 0)
	f.mapCaption:SetPoint("TOPLEFT", f.map, "BOTTOMLEFT", 0, -8)
	f.openMap = CreateFrame("Button", nil, f.pages[2].detail, "UIPanelButtonTemplate")
	ns.Theme.Register(f.openMap, "button")
	f.openMap:SetSize(96, 20)
	f.openMap:SetPoint("TOPRIGHT", f.map, "BOTTOMRIGHT", 0, -4)
	f.mapCaption:SetPoint("RIGHT", f.openMap, "LEFT", -8, 0)
	f.mapCaption:SetJustifyH("LEFT")
	f.mapCaption:SetWordWrap(false)
	f.openMap:SetText("Open map")
	f.openMap:SetScript("OnClick", function()
		OpenZoneMap(frame.mapID)
	end)

	-- Bottom bar.
	f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ns.Theme.Register(f.back, "button")
	f.back:SetSize(150, 22)
	f.back:SetPoint("BOTTOMLEFT", 10, 4)
	f.back:SetScript("OnClick", function()
		if state.fishID then
			state.fishID, state.zone = nil, nil
		else
			local i = 1
			for n, show in ipairs(SHOW) do
				if show == state.show then
					i = n % #SHOW + 1
				end
			end
			state.show, state.spread = SHOW[i], 1
		end
		Book.Refresh()
	end)
	-- On the Zones and Camp tabs, where the fish filters aren't: share your data.
	f.share = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ns.Theme.Register(f.share, "button")
	f.share:SetSize(170, 22)
	f.share:SetPoint("BOTTOMLEFT", 10, 4)
	f.share:SetScript("OnClick", function()
		ns.Report.Show()
	end)
	f.share:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Data report")
		GameTooltip:AddLine(ns.Report.TooltipLine() or "Your catches and getaways as text, to share.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.share:SetScript("OnLeave", GameTooltip_Hide)
	-- Zone filter: a menu of every zone, with this one first ("what's left here?").
	f.where = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ns.Theme.Register(f.where, "button")
	f.where:SetSize(170, 22)
	f.where:SetPoint("LEFT", f.back, "RIGHT", 4, 0)
	f.where:SetScript("OnClick", function(self)
		Book.OpenZoneMenu(self)
	end)
	f.where:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Zone")
		GameTooltip:AddLine("Show only the fish of one zone. Pick yours, then Showing: missing, to see what's left to catch here.",
			1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.where:SetScript("OnLeave", GameTooltip_Hide)

	-- Search by name.
	f.search = TryCreate("EditBox", "OneCastBookSearchBox", f, "SearchBoxTemplate")
		or CreateFrame("EditBox", "OneCastBookSearchBox", f, "InputBoxTemplate")
	f.search:SetSize(150, 20)
	f.search:SetAutoFocus(false)
	f.search:SetPoint("LEFT", f.where, "RIGHT", 12, 0)
	f.search:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or ""):lower()
		text = text ~= "" and text or nil
		if text ~= state.search then
			state.search, state.spread, state.fishID = text, 1, nil
			Book.Refresh()
		end
	end)
	f.search:HookScript("OnEnterPressed", f.search.ClearFocus)

	f.pageLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ns.Theme.Register(f.next, "button")
	f.next:SetSize(100, 22)
	f.next:SetPoint("BOTTOMRIGHT", -22, 4) -- clear of the resize grip
	f.next:SetText("Next")
	f.next:SetScript("OnClick", function()
		if state.fishID and state.index then
			state.fishID, state.zone = state.list[state.index + 1].fish.id, nil
		else
			state.spread = state.spread + 1
		end
		Book.Refresh()
	end)
	f.prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ns.Theme.Register(f.prev, "button")
	f.prev:SetSize(100, 22)
	f.prev:SetPoint("RIGHT", f.next, "LEFT", -4, 0)
	f.prev:SetText("Previous")
	f.pageLabel:SetPoint("RIGHT", f.prev, "LEFT", -12, 0)
	f.prev:SetScript("OnClick", function()
		if state.fishID and state.index then
			state.fishID, state.zone = state.list[state.index - 1].fish.id, nil
		else
			state.spread = state.spread - 1
		end
		Book.Refresh()
	end)

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		if delta < 0 and f.next:IsEnabled() then
			f.next:Click()
		elseif delta > 0 and f.prev:IsEnabled() then
			f.prev:Click()
		end
	end)

	f:Hide()
	ns.Hub.Attach("collection", f, function()
		return state.cat == "camp" and "camp" or "collection"
	end)
	return f
end

function Book.Refresh()
	if not frame then
		return
	end
	ns.Hub.UpdateTabs()
	for i, tab in ipairs(frame.Tabs) do
		if tab.cat == state.cat then
			if PanelTemplates_SetTab then
				PanelTemplates_SetTab(frame, i)
			else
				tab:LockHighlight()
			end
		elseif not PanelTemplates_SetTab then
			tab:UnlockHighlight()
		end
	end

	local caught, total = ns.Collection.Progress()
	frame.progressText:SetText(string.format("Collected |cffffffff%d|r of %d", caught, total))
	frame.progress:SetValue(total > 0 and caught / total or 0)

	if state.fishID then
		state.list = state.list or Filtered() -- the fish page's Previous and Next walk it
	end
	local showFish = state.fishID ~= nil and RenderFish()
	local showZones = not showFish and state.cat == "zones"
	local showCamp = not showFish and state.cat == "camp"
	local showGrid = not showFish and not showZones and not showCamp
	if showZones then
		RenderZones()
	elseif showCamp then
		RenderCamp()
	elseif showGrid then
		RenderGrid()
	end
	for _, page in ipairs(frame.pages) do
		page.grid:SetShown(showGrid)
		page.detail:SetShown(showFish)
		page.zones:SetShown(showZones)
		page.camp:SetShown(showCamp)
		page.title:SetShown(not showFish)
		page.number:SetShown(not showFish)
	end
	frame.back:SetShown(not showZones and not showCamp)
	frame.back:SetText(showFish and "Back to collection" or SHOW_LABEL[state.show])
	frame.where:SetShown(showGrid)
	frame.where:SetText(state.where or "All zones")
	frame.search:SetShown(showGrid)
	frame.prev:SetShown(not showCamp)
	frame.next:SetShown(not showCamp)
	frame.share:SetShown(showZones or showCamp)
	if showZones or showCamp then
		local n = ns.Report and #ns.Report.Unshared() or 0
		frame.share:SetText("Share your data" .. (n > 0 and (" |cff1eff00(" .. n .. ")|r") or ""))
	end
end

local function SetWhere(zone)
	state.where, state.spread, state.fishID = zone, 1, nil
	Book.Refresh()
end

-- From the Zones view: every fish of that zone, whatever the category was.
function Book.ShowZoneFish(zone)
	state.cat = "all"
	SetWhere(zone)
end

function Book.OpenZoneMenu(owner)
	local here = ns.Stats.CurrentZone()
	here = here ~= "" and here or nil
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		-- No menu API: switch between every zone and this one.
		SetWhere(not state.where and here or nil)
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local function Radio(text, zone)
			root:CreateRadio(text, function()
				return state.where == zone
			end, function()
				SetWhere(zone)
			end)
		end
		Radio("All zones", nil)
		if here then
			Radio("Here: " .. here, here)
		end
		root:CreateDivider()
		for _, zone in ipairs(ZoneChoices()) do
			local level = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone]
			Radio(level and string.format("%s (%d)", zone, level) or zone, zone)
		end
		if root.SetScrollMode then
			root:SetScrollMode(400)
		end
	end)
end

-- The Camp tab, from anywhere: /onecast camp.
function Book.ShowCamp()
	Book.Show()
	state.cat, state.fishID, state.spread = "camp", nil, 1
	Book.Refresh()
end

-- The collection, leaving the Camp tab if it was on it.
function Book.ShowCollection()
	if state.cat == "camp" then
		state.cat, state.fishID, state.spread = "all", nil, 1
	end
	Book.Show()
end

-- Bags or recipes changed: only the Camp tab shows those.
function Book.RefreshCampIfShown()
	if frame and frame:IsShown() and state.cat == "camp" and not state.fishID then
		Book.Refresh()
	end
end

Book.ZoneMapID = ZoneMapID

function Book.RefreshIfShown()
	if frame and frame:IsShown() then
		state.list = nil
		Book.Refresh()
	end
end

function Book.ShowFish(itemID)
	state.fishID, state.zone = itemID, nil
	Book.Refresh()
end

function Book.Show()
	frame = frame or CreateWindow()
	ns.Collection.SyncCharacter()
	state.list = nil
	frame:Show()
	Book.Refresh()
end

function Book.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Book.Show()
	end
end

-- Global for the "Fishing collection" key binding.
function OneCast_ToggleBook()
	Book.Toggle()
end

-- Item names and icons arrive from the server over time; redraw when they do.
local pending = false
local events = CreateFrame("Frame")
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function()
	if frame and frame:IsShown() and not pending then
		pending = true
		C_Timer.After(0.2, function()
			pending = false
			Book.RefreshIfShown()
		end)
	end
end)

-- A new theme: the palette, then whatever's drawn with it.
ns.Theme.OnChange(function(theme)
	ApplyPalette(theme)
	if frame then
		frame.map:SetBackdropBorderColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.8)
	end
	Book.RefreshIfShown()
end)

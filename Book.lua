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
local MAX_RECIPES, MAX_CHARS = 4, 4
local MAP_W, MAP_H = 300, 200 -- the fish page's map before it's sized to the page
-- Zones view, in pixels: the height a page has for rows, and what each kind of line takes.
local ZONES_TOP = 50
local ZONE_ROW, RUNG_ROW = 24, 30

local CATEGORIES = {
	{ key = "all", label = "全部" },
	{ key = "fish", label = "鱼类" },
	{ key = "special", label = "特殊" },
	{ key = "trophy", label = "奖杯" },
	{ key = "bloated", label = "浮肿" },
	{ key = "treasure", label = "宝藏" },
	{ key = "zones", label = "区域" },
	{ key = "camp", label = "营地" },
}
local CAT_ORDER = { fish = 1, special = 2, trophy = 3, bloated = 4, treasure = 5 }
-- FishData's `when`: fish that bite only at some hours in Classic.
local WHEN_TEXT = {
	night = "在经典中仅夜间上钩，服务器时间 18:00–06:00。",
	day = "在经典中仅白天上钩，服务器时间 06:00–18:00。",
}
local CAT_NAME = { fish = "鱼类", special = "特殊渔获", trophy = "奖杯鱼", bloated = "浮肿鱼",
	treasure = "宝藏" }
local CAT_LEAD = {
	fish = "一种鱼",
	special = "一种特殊渔获",
	trophy = "一种奖杯鱼，因其体型而收藏而非食用",
	bloated = "一种浮肿鱼，打开后可能藏有珍珠或其他宝物",
	treasure = "从水中钓上的宝藏",
}
local SHOW = { "all", "caught", "missing", "reach", "rare" }
local SHOW_LABEL = { all = "显示：全部", caught = "显示：已钓到", missing = "显示：未钓到",
	reach = "显示：可钓到", rare = "显示：稀有" }

-- Rare and Very rare, by Classic's odds.
local function IsRare(fish)
	local rarity = ns.Rarity and ns.Rarity(fish.id)
	return rarity and (rarity.key == "rare" or rarity.key == "veryrare") or false
end

-- Parchment ink, as in the What's new window.
local INK = { 0.18, 0.10, 0.02 }
local INK_SOFT = { 0.36, 0.25, 0.14 }
local LEAD = "|cff7a2a00"
local SOFT = "|cff6b5233"
local GOOD = "|cff1f6b1f"
local BAD = "|cffa01c1c"

local function Ink(fontString, color)
	fontString:SetTextColor(color[1], color[2], color[3])
end

local frame
-- cat, show, where (zone filter) and search pick the fish; spread is the grid's page pair;
-- fishID and zone are the open fish page and its selected zone.
local state = { cat = "all", show = "all", spread = 1 }

local TryCreate, HasAtlas, SizedFont = ns.UI.TryCreate, ns.UI.HasAtlas, ns.UI.SizedFont

-- Fish data ------------------------------------------------------------------------------

local function FishName(fish)
	return C_Item.GetItemNameByID(fish.id) or fish.name or ("物品 " .. fish.id)
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

-- In reach: a fish with a known zone your Fishing (lure and pole included) already covers, and
-- not one that only bites during an event.
local function InReach(fish)
	if fish.event then
		return false
	end
	local needed = EasiestSkill(fish)
	local rank, _, modifier = ns.Stats.FishingSkill()
	if not needed or not rank then
		return false
	end
	return rank + (modifier or 0) >= needed
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
			and (not state.search or (ns.Search and ns.Search.MatchesFish(fish, state.search))
				or FishName(fish):lower():find(state.search, 1, true)) then
			local info = ns.Collection.Get(fish.id)
			local caught = info.total > 0
			local shown = state.show == "all" or (state.show == "rare" and IsRare(fish))
				or (state.show == "reach" and not caught and InReach(fish))
				or ((state.show == "caught" or state.show == "missing") and (state.show == "caught") == caught)
			if shown
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
	local text = CAT_LEAD[fish.cat] or "一种渔获"
	if zones == 1 then
		text = text .. "，见于 " .. first
	elseif zones > 1 then
		text = text .. string.format("，见于 %d 个区域，最常见于 %s", zones, first)
	end
	text = text .. "."
	local rarity = ns.Rarity and ns.Rarity(fish.id)
	if rarity then
		text = text .. string.format(" %s: about %s catches at best, %s (Classic's odds).", rarity.label,
			ns.OneIn(rarity.pct), ns.RarityWhere(rarity))
	end
	local skill = EasiestSkill(fish)
	if skill then
		text = text .. string.format(" 最易钓水域需要 %d 点钓鱼，以免脱钩。", skill)
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
		text = text .. " 用于 " .. table.concat(parts, " 与 ") .. "."
	end
	if fish.when then
		text = text .. " " .. WHEN_TEXT[fish.when]
	end
	if fish.event == "extravaganza" and ns.Extravaganza then
		text = text .. " " .. ns.Extravaganza.Describe(fish.id)
	end
	if fish.discovered then
		text = text .. " 图鉴记录中尚无此鱼：是你自己发现的。"
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
	local lead = total == 1 and "你记录的唯一一次钓获" or ("全部 " .. total .. " 次记录的钓获")
	if night == 0 then
		return lead .. "发生在白天（服务器时间 06:00–18:00）。"
	elseif day == 0 then
		return lead .. "发生在夜间（服务器时间 18:00–06:00）。"
	end
	return string.format("白天钓到 %d 次、夜间 %d 次（服务器时间）。", day, day == 1 and "" or "s", night)
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

-- Pools you've found (Pools.lua), on the map as the game's own fishing-pool icon. Pools found
-- close together share one icon, with how many on it, so a stretch of coast doesn't fill with
-- overlapping marks; its tooltip lists them all.
local POOL_ICON = 16       -- the icon's size on the little map
local POOL_NEAR = 12       -- pools closer than this (in map pixels) share an icon

local function PoolIcon(box, n)
	box.poolCounts = box.poolCounts or {}
	local tex = box.poolDots[n]
	if not tex then
		tex = box:CreateTexture(nil, "OVERLAY", nil, 2)
		if not (ns.UI.HasAtlas("fishing-hole") and tex:SetAtlas("fishing-hole") ~= false) then
			-- Without the atlas: a round blue mark with a dark rim.
			tex:SetTexture("Interface\\Common\\Indicator-Gray")
			tex:SetVertexColor(0.35, 0.75, 1)
		end
		box.poolDots[n] = tex
		local count = box:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		count:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 4, -3)
		box.poolCounts[n] = count
	end
	tex:SetSize(POOL_ICON, POOL_ICON)
	tex:Show()
	return tex, box.poolCounts[n]
end

-- An invisible button over a pool icon: the pools there, when you were last at each, and a click
-- for the world map with a waypoint on it.
local function PoolHotspot(box, n, mapID, group)
	box.poolButtons = box.poolButtons or {}
	local b = box.poolButtons[n]
	if not b then
		b = CreateFrame("Button", nil, box)
		b:SetFrameLevel((box:GetFrameLevel() or 0) + 2)
		box.poolButtons[n] = b
	end
	b:SetSize(POOL_ICON + 4, POOL_ICON + 4)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if #group.pools == 1 then
			local pool = group.pools[1]
			GameTooltip:SetText(pool.name)
			GameTooltip:AddLine("你在这里发现的鱼群" .. (pool.seen and ("，上次发现于 "
				.. date("%Y年%m月%d日", pool.seen)) or "") .. ".", 1, 1, 1, true)
		else
			GameTooltip:SetText(#group.pools .. " fishing pools found here")
			-- Each kind once, with how many and when you last saw one.
			local kinds, order = {}, {}
			for _, pool in ipairs(group.pools) do
				local k = kinds[pool.name]
				if not k then
					k = { n = 0, seen = 0 }
					kinds[pool.name] = k
					order[#order + 1] = pool.name
				end
				k.n = k.n + 1
				k.seen = math.max(k.seen, pool.seen or 0)
			end
			table.sort(order)
			for _, name in ipairs(order) do
				local k = kinds[name]
				GameTooltip:AddDoubleLine(name .. (k.n > 1 and (" x" .. k.n) or ""),
					k.seen > 0 and date("暂无记录。稀有渔获、想要的鱼和图鉴新鱼会显示在这里。", k.seen) or "", 1, 1, 1, 0.6, 0.6, 0.6)
			end
		end
		GameTooltip:AddLine("鱼群会移动，现在可能已不在该处。", 0.6, 0.6, 0.6, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("点击：在地图上显示并设置路径点", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", function()
		ns.UI.ShowOnMap(mapID, group.x, group.y, #group.pools == 1 and group.pools[1].name or "鱼群")
	end)
	b:Show()
	return b
end

-- The pools, grouped where they're close on this map: { x, y (map fractions), pools }.
local function PoolGroups(mapID, width, height)
	local groups = {}
	for _, pool in ipairs(ns.Pools.ForMap(mapID)) do
		local px, py = pool.x * width, pool.y * height
		local near
		for _, g in ipairs(groups) do
			if math.abs(g.px - px) < POOL_NEAR and math.abs(g.py - py) < POOL_NEAR then
				near = g
				break
			end
		end
		if near then
			near.pools[#near.pools + 1] = pool
			-- The icon goes to the middle of its pools.
			local n = #near.pools
			near.px, near.py = near.px + (px - near.px) / n, near.py + (py - near.py) / n
		else
			groups[#groups + 1] = { px = px, py = py, pools = { pool } }
		end
	end
	for _, g in ipairs(groups) do
		g.x, g.y = g.px / width, g.py / height
	end
	return groups
end

local function DrawPools(box, mapID, width, height, offX, offY)
	for i, group in ipairs(PoolGroups(mapID, width, height)) do
		local x, y = offX + group.px, -(offY + group.py)
		local hot = PoolHotspot(box, i, mapID, group)
		hot:ClearAllPoints()
		hot:SetPoint("CENTER", box, "TOPLEFT", x, y)
		local icon, count = PoolIcon(box, i)
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", box, "TOPLEFT", x, y)
		count:SetText(#group.pools > 1 and tostring(#group.pools) or "")
		count:Show()
	end
end

-- Draw a zone's map art, scaled to fit the box. Returns the map ID, or nil if none.
local function DrawMap(box, zone)
	for _, list in ipairs({ box.tiles, box.overlays, box.poolDots, box.poolButtons or {}, box.poolCounts or {} }) do
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
	local boxW, boxH = box.w or MAP_W, box.h or MAP_H
	local scale = math.min(boxW / layer.layerWidth, boxH / layer.layerHeight)
	local offX = (boxW - layer.layerWidth * scale) / 2
	local offY = (boxH - layer.layerHeight * scale) / 2
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
		ns.Print("游戏中没有" .. (zone or "该区域") .. ".")
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
	SizedFont(fs, fontObject, size - (pool.shrink or 0)) -- smaller where a page must fit (Fit)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowOffset(0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:SetWidth(0)
	fs:ClearAllPoints()
	fs:Show()
	return fs
end

-- Fitting a page -------------------------------------------------------------------------------
-- A page's text is sized for its usual content. Where it runs past the page's foot (bigger
-- text, a long list), the page is drawn again a point smaller, then another, until it fits:
-- with "Larger text" on, a page with room keeps it, and a full one steps back as far as it
-- must, down to a point under the usual size at most.
local PAGE_FOOT = 34 -- room kept clear for the page number

local function Overflows(pool)
	local floor = pool.page.GetBottom and pool.page:GetBottom()
	if not floor then
		return false
	end
	local limit = floor + PAGE_FOOT
	for _, part in ipairs({ { pool.strings, pool.s }, { pool.textures, pool.t }, { pool.buttons, pool.b } }) do
		for i = 1, part[2] do
			local bottom = part[1][i]:GetBottom()
			if bottom and bottom < limit then
				return true
			end
		end
	end
	return false
end

-- `render` draws on `pools`; drawn again smaller until nothing runs off a page. Its result.
local function Fit(pools, render)
	local most = ns.LargerText and ns.LargerText() and 4 or 2
	local result
	for shrink = 0, most do
		for _, pool in ipairs(pools) do
			pool.shrink = shrink
		end
		result = render()
		local over = false
		for _, pool in ipairs(pools) do
			over = over or Overflows(pool)
		end
		if not over then
			break
		end
	end
	return result
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
		b.padMore = true -- with a controller, X does what a right-click does
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
	local glow = b:GetHighlightTexture()
	if glow then
		glow:SetAlpha(1)
	end
	b.right:ClearAllPoints()
	b.right:SetPoint("RIGHT", -6, 0)
	b.right:SetWidth(0)
	b.right:SetJustifyH("RIGHT")
	b.right:SetWordWrap(false)
	b.left:ClearAllPoints()
	b.left:SetPoint("LEFT", 6, 0)
	b.left:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
	for _, script in ipairs({ "OnClick", "OnEnter", "OnLeave" }) do
		b:SetScript(script, nil)
	end
	b:Show()
	return b
end

-- An invisible button over part of a page: hovering shows a tooltip `fill` writes, and a
-- Shift-click links what `link` returns in chat. Text underneath shows through.
-- `wowhead` is { "item" or "spell", id }: right-click shows its Wowhead page to copy.
local function Hover(pool, x, y, width, height, fill, link, wowhead, click)
	local b = PoolButton(pool)
	b:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x - 3, -y + 2)
	b:SetSize(width + 6, height)
	b.bg:Hide()
	local glow = b:GetHighlightTexture()
	if glow then
		glow:SetAlpha(0.35) -- over text on parchment, a soft glow
	end
	b.left:SetText("")
	b.right:SetText("")
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		fill(GameTooltip)
		if link then
			GameTooltip:AddLine("Shift+点击：链接到聊天框", 0.6, 0.8, 1)
		end
		if wowhead then
			GameTooltip:AddLine("右键：Wowhead 链接", 0.6, 0.8, 1)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" and wowhead then
			ns.UI.ShowWowhead(wowhead[1], wowhead[2])
			return
		end
		local text = link and IsModifiedClick("CHATLINK") and link()
		if text then
			ns.InsertChatLink(text)
		elseif click and mouseButton ~= "RightButton" then
			click()
		end
	end)
	return b
end

-- Who sells a recipe (ns.RECIPE_SELLERS) to you: { npc, name, side, mapID, x, y, zone, mine },
-- your faction's first, nearest first: in your zone, then on your continent.
local function RecipeSellers(spellID)
	local entry = ns.RECIPE_SELLERS and ns.RECIPE_SELLERS[spellID]
	if not entry then
		return nil
	end
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	local mySide = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
	local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pos = here and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(here, "player")
	local px, py
	if pos and pos.GetXY then
		px, py = pos:GetXY()
	end
	local function Continent(mapID)
		local info = mapID and C_Map.GetMapInfo(mapID)
		return info and info.parentMapID
	end
	local hereContinent = Continent(here)
	local list = {}
	for _, s in ipairs(entry) do
		local info = C_Map.GetMapInfo(s[4])
		local mine = s[3] == "B" or s[3] == mySide or mySide == nil
		local rank
		if s[4] == here and px then
			rank = (s[5] - px) ^ 2 + (s[6] - py) ^ 2
		elseif hereContinent and Continent(s[4]) == hereContinent then
			rank = 10
		else
			rank = 20
		end
		list[#list + 1] = { npc = s[1], name = s[2], side = s[3], mapID = s[4], x = s[5], y = s[6],
			zone = info and info.name or "?", mine = mine, rank = rank }
	end
	table.sort(list, function(a, b)
		if a.mine ~= b.mine then
			return a.mine
		end
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.name < b.name
	end)
	return list
end
Book.RecipeSellers = RecipeSellers

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
	-- The rarity gem sits on the parchment beside the icon, never over it.
	b.gem = b:CreateTexture(nil, "OVERLAY", nil, 3)
	b.gem:SetPoint("RIGHT", b.icon, "LEFT", -3, 0)
	b.gem:Hide()
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
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			ns.UI.ShowItemMenu(self.fishID)
			return
		end
		local link = IsModifiedClick("CHATLINK") and ns.ItemLink(self.fishID)
		if link then
			ns.InsertChatLink(link)
			return
		end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Book.ShowFish(self.fishID)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(self.fishID)
		local info = ns.Collection.Get(self.fishID)
		GameTooltip:AddLine(" ")
		if info.total > 0 then
			GameTooltip:AddLine(string.format("已在 %d 个角色上钓到 %d 次", info.total,
				info.total == 1 and "" or "s", #info.chars, #info.chars == 1 and "" or "s"), 0.6, 0.8, 1)
		else
			GameTooltip:AddLine("尚未钓到", 0.7, 0.7, 0.7)
		end
		local rarity = ns.Rarity and ns.Rarity(self.fishID)
		if rarity then
			GameTooltip:AddLine(string.format("%s%s|r  ·  %s catches at best", ns.RARITY_COLOR[rarity.key], rarity.label,
				ns.OneIn(rarity.pct)), 0.8, 0.8, 0.8)
		end
		GameTooltip:AddLine("点击打开详情页", 0.6, 0.8, 1)
		GameTooltip:AddLine("右键：更多（想要、咬钩地点、Wowhead）", 0.6, 0.8, 1)
		GameTooltip:AddLine("Shift+点击：在聊天中链接", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- Cut gems from the game's own art (its followers' rarity gems), at their own shape.
local GEMS = {
	rare = { atlas = "adventurers-followers-rare-gem", w = 14, h = 15, icon = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02" },
	veryrare = { atlas = "adventurers-followers-epic-gem", w = 14, h = 20, icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02" },
}

local function FillCell(cell, entry)
	local fish, info = entry.fish, entry.info
	local caught = info.total > 0
	cell.fishID = fish.id
	cell.icon:SetTexture(FishIcon(fish))
	cell.icon:SetDesaturated(not caught)
	cell.icon:SetVertexColor(caught and 1 or 0.55, caught and 1 or 0.55, caught and 1 or 0.55)
	-- Its colours show either way, so you can see what's rare before you've caught it: the icon
	-- alone is greyed until then. An uncaught border is a little dimmer.
	local color = QualityColor(FishQuality(fish))
	if color then
		local k = caught and 1 or 0.75
		cell.border:SetVertexColor(color.r * k, color.g * k, color.b * k)
	else
		cell.border:SetVertexColor(0.4, 0.35, 0.3)
	end
	cell.check:SetShown(caught and ns.db.collectionTicks ~= false)
	-- The game's own rarity gems (the mission table's), blue for Rare and purple for Very rare:
	-- coloured already, so they show bright on any icon, caught or not.
	local rarity = ns.Rarity and ns.Rarity(fish.id)
	local gem = rarity and GEMS[rarity.key]
	cell.gem:SetShown(gem and true or false)
	if gem then
		if HasAtlas(gem.atlas) then
			cell.gem:SetTexCoord(0, 1, 0, 1)
			cell.gem:SetAtlas(gem.atlas)
		else
			-- Without that art: the game's gem item icon, its square edge trimmed.
			cell.gem:SetTexture(gem.icon)
			cell.gem:SetTexCoord(0.15, 0.85, 0.15, 0.85)
		end
		cell.gem:SetSize(gem.w, gem.h)
	end
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
	local label = state.where and "鱼类" or "艾泽拉斯鱼类"
	for _, cat in ipairs(CATEGORIES) do
		if cat.key == state.cat and cat.key ~= "all" then
			label = cat.label
		end
	end
	if state.where then
		label = label .. "的" .. state.where
	end
	frame.pages[1].title:SetText(label)
	frame.pages[2].title:SetText(#list == 0 and "" or string.format("显示 %d 种", #list))
	frame.empty:SetShown(#list == 0)
	if state.show == "missing" and not state.search then
		frame.empty:SetText("此处已全部钓到！")
	elseif state.show == "rare" and not state.search then
		frame.empty:SetText("没有匹配的鱼。")
	elseif state.show == "reach" and not state.search then
		frame.empty:SetText("可钓到的已全部钓完：你技能覆盖的都已上钩。")
	elseif state.search then
		frame.empty:SetText("没有匹配的渔获。搜索框下列出的其他项可继续查找。")
	elseif state.where or state.show ~= "all" then
		frame.empty:SetText("没有匹配的鱼。")
	else
		frame.empty:SetText("这里还没有内容。")
	end
	frame.pageLabel:SetText(string.format("第 %d–%d 页，共 %d 页", state.spread * 2 - 1, state.spread * 2, spreads * 2))
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

-- "Used in": the recipes it goes into, each with its own tooltip. Returns the y below.
local function RenderRecipes(pool, fish, x, y, width)
	local page = pool.page
	y = y + Heading(pool, "用途", x, y, 32)
	local recipes = fish.recipes or {}
	for i, recipe in ipairs(recipes) do
		if i > MAX_RECIPES then
			local more = PoolString(pool, QuestFont, 13, INK_SOFT)
			more:SetText(string.format("还有 %d 个", #recipes - MAX_RECIPES))
			more:SetPoint("TOPLEFT", page, "TOPLEFT", x + 18, -y)
			return y + 17
		end
		local dot = PoolTexture(pool)
		dot:SetTexture("Interface\\QuestFrame\\UI-Quest-BulletPoint")
		dot:SetSize(12, 12)
		dot:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y - 1)
		local line = PoolString(pool, QuestFont, 14, INK)
		local skill = recipe[4] and (" " .. recipe[4]) or ""
		local sellers = RecipeSellers(recipe[1])
		local yours = 0
		for _, s in ipairs(sellers or {}) do
			yours = yours + (s.mine and 1 or 0)
		end
		local sold = yours > 0 and string.format("  %s· %d seller%s|r", SOFT, yours, yours == 1 and "" or "s") or ""
		line:SetText(string.format("%s  %s%s%s|r%s", recipe[2], SOFT, recipe[3], skill, sold))
		line:SetPoint("TOPLEFT", page, "TOPLEFT", x + 18, -y)
		Hover(pool, x + 18, y, line:GetStringWidth() or width, 17, function(tip)
			tip:SetSpellByID(recipe[1])
			if recipe[4] then
				tip:AddLine(string.format("需要 %d 点%s。", recipe[4], recipe[3]), 1, 0.82, 0)
			end
			if sellers then
				tip:AddLine(" ")
				tip:AddLine("配方出售于：", 1, 0.82, 0)
				local shown = 0
				for _, s in ipairs(sellers) do
					if shown == 8 then
						tip:AddLine(string.format("还有 %d 个", #sellers - shown), 0.6, 0.6, 0.6)
						break
					end
					shown = shown + 1
					local where = string.format("%s (%.0f, %.0f)", s.zone, s.x * 100, s.y * 100)
					if s.mine then
						tip:AddDoubleLine(s.name, where, 1, 1, 1, 0.8, 0.8, 0.8)
					else
						tip:AddDoubleLine(s.name .. (s.side == "A" and " (Alliance)" or " (Horde)"), where, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
					end
				end
				if yours > 0 then
					tip:AddLine("点击：设置到最近处的路径点", 0.6, 0.8, 1)
				end
				tip:AddLine("数据来自经典版，Forever 可能不同。", 0.6, 0.6, 0.6, true)
			end
		end, SpellLink(recipe[1]), { "spell", recipe[1] }, yours > 0 and function()
			local best = sellers[1]
			if best and best.mine and ns.UI and ns.UI.ShowOnMap then
				ns.UI.ShowOnMap(best.mapID, best.x, best.y, best.name .. "，地点：" .. best.zone)
			end
		end or nil)
		y = y + 17
	end
	if #recipes == 0 then
		local none = PoolString(pool, QuestFont, 14, INK_SOFT)
		none:SetText("未用于任何配方。")
		none:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
		y = y + 17
	end
	return y
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
	local rarity = ns.Rarity and ns.Rarity(fish.id)
	kind:SetText((CAT_NAME[fish.cat] or "Catch") .. (skill and ("  ·  " .. skill .. " 钓鱼") or "")
		.. (rarity and ("  ·  " .. ns.RARITY_INK[rarity.key] .. rarity.label .. " 脱钩|r") or ""))
	kind:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	Hover(pool, x, 30, width, 56, function(tip)
		tip:SetItemByID(fish.id)
	end, ItemLink(fish.id), { "item", fish.id })

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

	y = y + Heading(pool, "你的钓获", x, y, 32)
	if info.total > 0 then
		Paragraph(string.format("已在 %d 个角色上钓到 %s%d|r 次。", LEAD, info.total,
			info.total == 1 and "" or "s", #info.chars, #info.chars == 1 and "" or "s"), INK, 6)
		if #info.chars <= MAX_CHARS then
			for _, who in ipairs(info.chars) do
				Paragraph(string.format("%s  %s%d|r", who.name, LEAD, who.count), INK, 4)
			end
		else
			-- Two columns, so a long list of characters still fits the page.
			local colW = (width - 12) / 2
			for i, who in ipairs(info.chars) do
				local fs = PoolString(pool, QuestFont, 14, INK)
				fs:SetWidth(colW)
				fs:SetWordWrap(false)
				fs:SetText(string.format("%s  %s%d|r", who.name, LEAD, who.count))
				fs:SetPoint("TOPLEFT", page, "TOPLEFT", x + ((i - 1) % 2) * (colW + 12), -(y + math.floor((i - 1) / 2) * 18))
			end
			y = y + math.ceil(#info.chars / 2) * 18 + 4
		end
		-- This character's own rate: how many of its catches were this one.
		local mine = OneCastCharDB and OneCastCharDB.lifetime
		local count = mine and mine.items and mine.items[fish.id] and mine.items[fish.id].count or 0
		if count > 0 and (mine.catches or 0) >= count then
			Paragraph(string.format("%sOn this character, %s of your catches.|r", SOFT,
				ns.OneIn(count / mine.catches * 100)), INK, 4)
		end
		y = y + 6
		if info.first then
			Paragraph(string.format("%s首次由 %s 于 %s%s钓到。|r", SOFT, date("%d %B %Y", info.first.time),
				info.first.char or "?", info.first.zone and ("，地点：" .. info.first.zone) or ""), INK, 4)
		end
		local when = TimeOfDay(info)
		if when then
			Paragraph(SOFT .. when .. " 脱钩|r", INK)
		end
	else
		local tip = (fish.zones and fish.zones[1]) or (fish.more and fish.more[1] and fish.more[1][1])
		Paragraph("尚未钓到。" .. (tip and (" 可尝试 " .. tip .. ".") or ""), INK)
	end

	y = y + 8
	RenderRecipes(pool, fish, x, y, width)
end

-- The right page: every zone it's found in, in two columns, then a map of the chosen one as big
-- as the page allows. A fish found almost everywhere shows a "+N more" that opens the full list
-- in the map's place; picking a zone brings the map back.
local ZONE_ROW, ZONE_GAP = 19, 12
local ZONE_GRID_MAX = 16 -- zones shown with the map, before "+N more"
local MAP_ASPECT = 2 / 3 -- zone maps are 3:2
local MAP_MIN_H = 120

local TAG_TEXT = {
	classic = "来自经典数据：Forever 中尚未见到。",
	reported = "Forever 玩家报告。",
	["found by you"] = "你自己钓到过的地点。",
}

local function ZoneCell(pool, fish, row, info, x, y, width)
	local b = PoolButton(pool)
	b:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	b:SetWidth(width)
	b.bg:SetShown(row.zone == state.zone)
	b.left:SetText(row.zone .. (row.tag and (SOFT .. " *|r") or ""))
	b.left:SetTextColor(INK[1], INK[2], INK[3])
	local needs = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[row.zone]
	local mine = info.zones[row.zone]
	b.right:SetText((mine and (LEAD .. "x" .. mine .. "|r  ") or "") .. ((needs and needs > 1) and tostring(needs) or ""))
	b.right:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
	SizedFont(b.left, QuestFont, 13)
	local room = width - 12 - 8 - (b.right:GetStringWidth() or 0)
	if (b.left:GetStringWidth() or 0) > room then
		SizedFont(b.left, QuestFont, 12)
	end
	b:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			OpenZoneByName(row.zone)
			return
		end
		state.zone, state.zonesExpanded = row.zone, false
		Book.Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(row.zone)
		if needs and needs > 1 then
			GameTooltip:AddDoubleLine("所需钓鱼技能", tostring(needs), 1, 0.82, 0, 1, 1, 1)
		end
		if mine then
			GameTooltip:AddDoubleLine("你已钓到", tostring(mine), 1, 0.82, 0, 1, 1, 1)
		end
		local here = ns.ODDS and ns.ODDS[fish.id] and ns.ODDS[fish.id].water and ns.ODDS[fish.id].water[row.zone]
		if here then
			GameTooltip:AddDoubleLine("此处几率", ns.OneIn(here) .. " catches", 1, 0.82, 0, 1, 1, 1)
		end
		if row.tag then
			GameTooltip:AddLine(TAG_TEXT[row.tag] or row.tag, 0.8, 0.8, 0.8, true)
		end
		GameTooltip:AddLine(ns.Stats.ZoneVerdict(row.zone), 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("点击：在地图上显示", 0.6, 0.8, 1)
		GameTooltip:AddLine("右键：打开世界地图", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
end

-- "+N more" or "Show fewer": a cell that opens or closes the full list.
local function MoreCell(pool, text, x, y, width)
	local b = PoolButton(pool)
	b:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	b:SetWidth(width)
	b.bg:Hide()
	b.left:SetText(LEAD .. text .. " 脱钩|r")
	b.right:SetText("")
	b:SetScript("OnClick", function()
		state.zonesExpanded = not state.zonesExpanded
		Book.Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(state.zonesExpanded and "返回地图" or "所有出没区域")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
end

local function RenderRight(fish, info)
	local pool = frame.rightPool
	local page = pool.page
	ResetPool(pool)
	local x, width = 32, math.max(page:GetWidth(), 400) - 64
	local y = 30

	y = y + Heading(pool, "出没地点", x, y, 32)
	local rows = ZoneRows(fish, info)
	if not state.zone then
		state.zone = rows[1] and rows[1].zone
	end
	local colW = (width - ZONE_GAP) / 2
	local function Cell(i)
		local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
		return x + col * (colW + ZONE_GAP), y + line * ZONE_ROW
	end
	local expanded = state.zonesExpanded and #rows > ZONE_GRID_MAX
	local shown = #rows
	if not expanded and #rows > ZONE_GRID_MAX then
		shown = ZONE_GRID_MAX - 1 -- the last cell is "+N more"
	end
	for i = 1, shown do
		local cx, cy = Cell(i)
		ZoneCell(pool, fish, rows[i], info, cx, cy, colW)
	end
	local cells = shown
	if #rows > ZONE_GRID_MAX then
		cells = cells + 1
		local cx, cy = Cell(cells)
		MoreCell(pool, expanded and "收起" or string.format("+%d 更多", #rows - shown), cx, cy, colW)
	end
	y = y + math.ceil(cells / 2) * ZONE_ROW
	if #rows == 0 then
		local none = PoolString(pool, QuestFont, 14, INK_SOFT)
		none:SetText("尚无已知水域。钓到一条后，插件会记住地点。")
		none:SetWidth(width)
		none:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
		y = y + none:GetStringHeight() + 6
	end
	local tagged = false
	for _, row in ipairs(rows) do
		tagged = tagged or row.tag ~= nil
	end
	if tagged then
		local key = PoolString(pool, QuestFont, 11, INK_SOFT)
		key:SetText("* not from Wowhead's Forever data: hover for where it's from")
		key:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(y + 2))
		y = y + 16
	end

	-- The map: as big as the rest of the page allows, in its own 3:2 shape. Hidden while the full
	-- list is open.
	local map = frame.map
	if expanded then
		map:Hide()
		frame.mapCaption:SetText("")
		frame.openMap:Hide()
		return
	end
	y = y + 10
	local room = page:GetHeight() - y - 44 -- the caption and Open map button go under it
	local h = math.max(MAP_MIN_H, math.min(math.floor(width * MAP_ASPECT), room))
	local w = math.floor(h / MAP_ASPECT)
	map:SetSize(w, h)
	map.w, map.h = w, h
	map:ClearAllPoints()
	map:SetPoint("TOP", page, "TOP", 0, -y)
	map:Show()
	frame.openMap:Show()
	frame.mapID = DrawMap(map, state.zone)
	local pools = frame.mapID and #ns.Pools.ForMap(frame.mapID) or 0
	frame.mapCaption:SetText((state.zone or "") .. (pools > 0
		and string.format("  ·  %d pool%s found", pools, pools == 1 and "" or "s") or ""))
	frame.openMap:SetEnabled(frame.mapID ~= nil)
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

-- One zone's fish: how many are known there and how many you've caught, for the world map.
function Book.ZoneFishCount(zone)
	local count = { caught = 0, total = 0 }
	for _, fish in ipairs(AllFish()) do
		local info = ns.Collection.Get(fish.id)
		if FoundIn(fish, info, zone) then
			count.total = count.total + 1
			count.caught = count.caught + (info.total > 0 and 1 or 0)
		end
	end
	return count
end

-- A row's status, in ink dark enough for parchment.
local function ZoneStatusText(status)
	if status.kind == "ok" then
		return GOOD .. "达标|r"
	elseif status.kind == "short" then
		return BAD .. status.short .. " short|r"
	elseif status.kind == "getaways" then
		return BAD .. "会脱钩|r"
	elseif status.kind == "outgrown" then
		return SOFT .. "曾于 " .. status.escapeSkill .. " 脱钩|r"
	elseif status.kind == " 种鱼|r" then
		return GOOD .. "无脱钩|r"
	elseif status.kind == "note" then
		return GOOD .. "无最低要求|r"
	end
end

-- Zones: a ladder of Fishing levels -------------------------------------------------------
-- The left page is a ladder: each Fishing level a rung (how many zones, how many of their fish
-- you've caught, and whether your skill clears it), with your own Fishing marked between the
-- rungs where it falls. The right page is the chosen rung: what your skill means there, then
-- its zones, each with a bar of the fish you've caught there and anything that's happened there
-- that the level doesn't explain. Previous and Next step from rung to rung.

local BAR_WIDTH = 60

local function FishBar(pool, anchor, caught, total)
	local back = PoolTexture(pool)
	back:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.25)
	back:SetSize(BAR_WIDTH, 6)
	back:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
	if total > 0 and caught > 0 then
		local fill = PoolTexture(pool)
		fill:SetColorTexture(0.15, 0.45, 0.1, 0.9)
		fill:SetSize(math.max(1, BAR_WIDTH * caught / total), 6)
		fill:SetPoint("LEFT", back, "LEFT")
	end
end

-- What a rung means for you: cleared, or how far short.
local function RungStatus(level, effective)
	if not level then
		return SOFT .. "等级未知|r", "unknown"
	elseif not effective then
		return "", "level"
	elseif effective >= level then
		return GOOD .. "无脱钩|r", "ok"
	end
	return BAD .. (level - effective) .. " short|r", "short"
end

-- A zone row's columns from the right: the count, as wide as the page's widest so the bars line up
-- (RenderZones sets it, whatever the text size), then the bar; the name (and anything the level
-- doesn't explain) has the rest, cut short with "..." if it's long, never under the bar.

local function RenderZoneRow(pool, zone, count, here, x, y, width, tierKind)
	local b = PoolButton(pool)
	b:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	b:SetWidth(width)
	b:SetHeight(ZONE_ROW - 2)
	b.bg:SetShown(zone == here)
	-- Only what the level doesn't already say: getaways seen here, a reported quirk.
	local status = ns.Stats.ZoneStatus(zone)
	local extra
	if status.kind == "getaways" or status.kind == "outgrown" or status.kind == "note"
		or (tierKind == "unknown" and status.kind == " 种鱼|r") then
		extra = ZoneStatusText(status)
	end
	b.left:SetText(zone .. (zone == here and (" " .. SOFT .. "(you're here)|r") or "")
		.. (extra and ("  " .. extra) or ""))
	b.left:SetTextColor(INK[1], INK[2], INK[3])
	b.right:SetText(count.total > 0 and (count.caught .. "/" .. count.total) or (SOFT .. "-|r"))
	b.right:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
	b.left:SetPoint("RIGHT", b.right, "LEFT", -(8 + BAR_WIDTH + 10), 0)
	if count.total > 0 then
		FishBar(pool, b.right, count.caught, count.total)
	end
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
			GameTooltip:AddLine(string.format("你已钓到此处已知 %d 种鱼中的 %d 种。", count.caught, count.total),
				1, 1, 1, true)
		else
			GameTooltip:AddLine("此处尚无已知鱼类。", 0.7, 0.7, 0.7, true)
		end
		GameTooltip:AddLine("点击：查看该区域的鱼", 0.6, 0.8, 1)
		GameTooltip:AddLine("右键：打开世界地图", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- Where your Fishing falls on the ladder: a gold rule either side of it, written between.
local function SkillMarker(pool, x, y, width, text)
	local label = PoolString(pool, QuestTitleFont, 14, INK)
	label:SetText(text)
	label:SetPoint("CENTER", pool.page, "TOPLEFT", x + width / 2, -(y + 10))
	for _, side in ipairs({ "left", "right" }) do
		local rule = PoolTexture(pool)
		rule:SetColorTexture(0.62, 0.42, 0.1, 0.8)
		rule:SetHeight(2)
		if side == "left" then
			rule:SetPoint("LEFT", pool.page, "TOPLEFT", x, -(y + 10))
			rule:SetPoint("RIGHT", label, "LEFT", -8, 0)
		else
			rule:SetPoint("LEFT", label, "RIGHT", 8, 0)
			rule:SetPoint("RIGHT", pool.page, "TOPLEFT", x + width, -(y + 10))
		end
	end
	return 24
end

local function RenderZones()
	local groups = ZoneGroups()
	local counts = ZoneCounts(groups)
	local rank, _, modifier = ns.Stats.FishingSkill()
	local effective = rank and rank + (modifier or 0)
	local here = ns.Stats.CurrentZone()

	-- The rung first shown: the one with the zone you're in, else the highest you clear.
	if not state.zonesPicked then
		local pick = 1
		for i, group in ipairs(groups) do
			if group.level and effective and effective >= group.level then
				pick = i
			end
		end
		for i, group in ipairs(groups) do
			for _, zone in ipairs(group.zones) do
				if zone == here then
					pick = i
				end
			end
		end
		state.spread, state.zonesPicked = pick, true
	end
	state.spread = math.max(1, math.min(state.spread, #groups))
	local chosen = groups[state.spread]

	local left, right = frame.zonePools[1], frame.zonePools[2]
	ResetPool(left)
	ResetPool(right)
	local x = 32
	local width = math.max(left.page:GetWidth(), 400) - 64

	-- The ladder.
	local y = ZONES_TOP
	local intro = PoolString(left, QuestFont, 13, INK_SOFT)
	intro:SetWidth(width)
	intro:SetText("各区域需要一定钓鱼技能才能让鱼稳定上钩。选一个等级。")
	intro:SetPoint("TOPLEFT", left.page, "TOPLEFT", x, -y)
	y = y + intro:GetStringHeight() + 12
	local marked = not effective
	local function Mark()
		if not marked then
			marked = true
			y = y + SkillMarker(left, x, y, width, string.format("你的钓鱼：%d%s", rank,
				(modifier or 0) > 0 and (" +" .. modifier) or ""))
		end
	end
	-- Rungs as tall as the page allows (the marker and the note under them have their room).
	local room = (HEIGHT - 102) - y - 24 - 60
	local rungRow = math.max(RUNG_ROW, math.min(46, math.floor(room / math.max(#groups, 1))))
	for i, group in ipairs(groups) do
		if group.level and effective and effective < group.level then
			Mark()
		elseif not group.level then
			Mark()
		end
		local caught, total = 0, 0
		for _, zone in ipairs(group.zones) do
			caught, total = caught + counts[zone].caught, total + counts[zone].total
		end
		local b = PoolButton(left)
		b:SetPoint("TOPLEFT", left.page, "TOPLEFT", x, -y)
		b:SetWidth(width)
		b:SetHeight(rungRow - 4)
		b.bg:SetShown(i == state.spread)
		b.left:SetText((group.level and (group.level .. " 钓鱼") or "等级未知") .. "  " .. SOFT
			.. #group.zones .. (#group.zones == 1 and " zone" or " zones") .. " 脱钩|r")
		b.left:SetTextColor(INK[1], INK[2], INK[3])
		b.right:SetText((RungStatus(group.level, effective)))
		-- With the room: the name on top, and under it the fish you've caught at this level.
		if rungRow >= 40 and total > 0 then
			b.left:ClearAllPoints()
			b.left:SetPoint("TOPLEFT", 6, -5)
			b.left:SetPoint("RIGHT", b.right, "LEFT", -8, 0)
			local sub = PoolString(left, QuestFont, 12, INK_SOFT)
			sub:SetText(string.format("已钓 %d / %d 种鱼", caught, total))
			sub:SetPoint("TOPLEFT", b.left, "BOTTOMLEFT", 0, -2)
		end
		b:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			state.spread = i
			Book.Refresh()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(group.level and (group.level .. " 钓鱼") or "等级未知")
			GameTooltip:AddLine(table.concat(group.zones, ", "), 1, 1, 1, true)
			if total > 0 then
				GameTooltip:AddLine(string.format("你已钓到这些区域已知 %d 种鱼中的 %d 种。", caught, total),
					0.8, 0.8, 0.8, true)
			end
			GameTooltip:AddLine("点击：查看这些区域", 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		y = y + rungRow
	end
	Mark()
	local foot = PoolString(left, QuestFont, 12, INK_SOFT)
	foot:SetWidth(width)
	foot:SetText("诱饵与鱼竿计入技能。等级来自经典版；Forever 可能不同，"
		.. "你看到的脱钩会记录并在数据报告中分享。")
	foot:SetPoint("TOPLEFT", left.page, "TOPLEFT", x, -(y + 10))

	-- The chosen rung.
	y = ZONES_TOP
	local _, kind = RungStatus(chosen.level, effective)
	local say
	if kind == "unknown" then
		say = "Forever 新增或尚未测定。「哇，大鱼」根据你的经历判断："
			.. "你的渔获与脱钩会显示在各区域旁。"
	elseif kind == "level" then
		say = "学习钓鱼技能后可查看你的水平。"
	elseif kind == "ok" then
		say = string.format("你的钓鱼（%d）足够：此处上钩的鱼不应脱钩。", effective)
	else
		say = string.format("你还差 %d：此处仍会时不时脱钩，差距越大越明显，"
			.. "技能越低越明显。每次渔获仍计入技能。", chosen.level - effective)
	end
	local sayString = PoolString(right, QuestFont, 13, INK)
	sayString:SetWidth(width)
	sayString:SetText(say)
	sayString:SetPoint("TOPLEFT", right.page, "TOPLEFT", x, -y)
	y = y + sayString:GetStringHeight() + 10
	y = y + Heading(right, "区域", x, y, 32)
	local rows, countWidth = {}, 0
	for _, zone in ipairs(chosen.zones) do
		local row = RenderZoneRow(right, zone, counts[zone], here, x, y, width, kind)
		rows[#rows + 1] = row
		countWidth = math.max(countWidth, row.right:GetStringWidth() or 0)
		y = y + ZONE_ROW
	end
	for _, row in ipairs(rows) do
		row.right:SetWidth(math.ceil(countWidth) + 2) -- every count the same width: the bars line up
	end

	-- What's left to catch in these waters: each fish's icon, its page a click away.
	local missing = {}
	for _, fish in ipairs(AllFish()) do
		local info = ns.Collection.Get(fish.id)
		if info.total == 0 then
			local where = {}
			for _, zone in ipairs(chosen.zones) do
				if FoundIn(fish, info, zone) then
					where[#where + 1] = zone
				end
			end
			if #where > 0 then
				missing[#missing + 1] = { fish = fish, where = where }
			end
		end
	end
	y = y + 8
	y = y + Heading(right, "此处仍待钓到", x, y, 32)
	if #missing == 0 then
		local done = PoolString(right, QuestFont, 13, INK_SOFT)
		done:SetWidth(width)
		done:SetText(counts and #chosen.zones > 0 and "这片水域已知鱼类你已全部钓到。" or "")
		done:SetPoint("TOPLEFT", right.page, "TOPLEFT", x, -y)
	else
		local ICON, STEP = 30, 36
		local perRow = math.max(1, math.floor((width + STEP - ICON) / STEP))
		local rows = math.max(1, math.floor((HEIGHT - 102 - 44 - y) / STEP))
		local room = perRow * rows
		local shown = #missing > room and room - 1 or #missing
		for i = 1, shown do
			local m = missing[i]
			local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
			local b = PoolButton(right)
			b:SetSize(ICON, ICON)
			b:SetPoint("TOPLEFT", right.page, "TOPLEFT", x + col * STEP, -(y + row * STEP))
			b.bg:Hide()
			b.left:SetText("")
			b.right:SetText("")
			local icon = PoolTexture(right)
			icon:SetTexture(C_Item.GetItemIconByID(m.fish.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
			icon:SetAllPoints(b)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			icon:SetDrawLayer("ARTWORK", 1)
			b:SetScript("OnClick", function()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Book.ShowFish(m.fish.id)
			end)
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetItemByID(m.fish.id)
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("出没地点：" .. table.concat(m.where, ", ") .. ".", 1, 1, 1, true)
				GameTooltip:AddLine("点击：查看它的页面", 0.6, 0.8, 1)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", GameTooltip_Hide)
		end
		if shown < #missing then
			local more = PoolString(right, QuestFont, 13, INK_SOFT)
			more:SetText("+" .. (#missing - shown))
			local col, row = shown % perRow, math.floor(shown / perRow)
			more:SetPoint("CENTER", right.page, "TOPLEFT", x + col * STEP + ICON / 2, -(y + row * STEP + ICON / 2))
		end
	end

	frame.pages[1].title:SetText("去哪钓鱼")
	frame.pages[2].title:SetText(chosen.level and (chosen.level .. " 钓鱼") or "等级未知")
	frame.pages[1].number:SetText(1)
	frame.pages[2].number:SetText(2)
	frame.pageLabel:SetText(string.format("第 %d / %d 级", state.spread, #groups))
	frame.prev:SetEnabled(state.spread > 1)
	frame.next:SetEnabled(state.spread < #groups)
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
	end, ItemLink(itemID), { "item", itemID })
end

-- A thin rule across the page, between cards.
local function CampRule(pool, x, y, width)
	local rule = PoolTexture(pool)
	rule:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.3)
	rule:SetSize(width, 1)
	rule:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
end

-- An item's icon, small, with a count beside it; its tooltip on hover. Returns its width.
local function ItemChip(pool, itemID, text, x, y, size)
	local icon = PoolTexture(pool)
	icon:SetTexture(C_Item.GetItemIconByID(itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetSize(size, size)
	icon:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	local label = PoolString(pool, QuestFont, 12, INK)
	label:SetText(text)
	label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
	local w = size + 3 + (label:GetStringWidth() or 0)
	ItemHover(pool, itemID, nil, x, y, w, size)
	return w
end

-- A line with a bullet in front, wrapped. Returns where the next goes.
local function Bullet(pool, text, x, y, width)
	local dot = PoolTexture(pool)
	dot:SetTexture("Interface\\QuestFrame\\UI-Quest-BulletPoint")
	dot:SetSize(12, 12)
	dot:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y - 1)
	return CampText(pool, text, x + 16, y, width - 16, 12)
end

-- A camp feature as a card: icon and name with where you stand (learned, or what's missing),
-- what it does in a line, what it's made from as icons with have/need, and, until it's learned,
-- where its Blueprint comes from. The whole story is in the tooltips.
local function RenderCraft(pool, craft, x, y, width)
	local Camp = ns.Camp
	local tight = pool.shrink or 0 -- drawn smaller to fit (Fit): closer together too
	local top = y
	local icon = PoolTexture(pool)
	icon:SetTexture(C_Item.GetItemIconByID(craft.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
	icon:SetSize(40, 40)
	icon:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x, -y)
	local name = PoolString(pool, QuestTitleFont, 17, INK)
	name:SetText(craft.name)
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)

	local rank = ns.Stats.FishingSkill()
	local known = Camp.Known(craft)
	local status
	if known then
		status = GOOD .. "已学会|r"
	elseif craft.blueprint and Camp.Count(craft.blueprint) > 0 then
		status = GOOD .. "背包中有蓝图|r"
	elseif rank and rank < craft.skill then
		status = BAD .. "需要 " .. craft.skill .. " 点钓鱼|r"
	elseif known == false then
		status = SOFT .. "尚未学会|r"
	end
	local made = Camp.Count(craft.item)
	if made > 0 then
		status = (status and (status .. "  ·  ") or "") .. SOFT .. made .. " in your bags|r"
	end
	if status then
		local st = PoolString(pool, QuestFont, 12, INK_SOFT)
		st:SetText(status)
		st:SetPoint("TOPRIGHT", pool.page, "TOPLEFT", x + width, -y - 3)
		st:SetJustifyH("RIGHT")
	end
	local effect = PoolString(pool, QuestFont, 12, INK_SOFT)
	effect:SetWidth(width - 46)
	effect:SetText(craft.effect or craft.does)
	effect:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	ItemHover(pool, craft.item, function(tip)
		tip:AddLine(" ")
		tip:AddLine(craft.does, 1, 1, 1, true)
		if known then
			tip:AddLine("你已学会制作它。", 0.12, 1, 0)
		elseif known == false then
			tip:AddLine("你还没有学会制作它。", 1, 0.3, 0.3)
		end
		if made > 0 then
			tip:AddLine(string.format("你有 %d 个。", made), 1, 1, 1)
		end
	end, x, top, width, math.max(44, 24 + (effect:GetStringHeight() or 14)))
	y = y + math.max(44, 24 + (effect:GetStringHeight() or 14)) + 8 - tight * 2

	-- Made from: each ingredient on its own line, its icon and name, and have/need at the right.
	for _, r in ipairs(craft.reagents) do
		local have = Camp.Count(r[1])
		local icon = PoolTexture(pool)
		icon:SetTexture(C_Item.GetItemIconByID(r[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		icon:SetSize(20, 20)
		icon:SetPoint("TOPLEFT", pool.page, "TOPLEFT", x + 46, -y)
		local name = PoolString(pool, QuestFont, 13, INK)
		name:SetText(Camp.ItemName(r[1], r[3]))
		name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
		local need = PoolString(pool, QuestFont, 13, INK)
		need:SetText((have >= r[2] and GOOD or BAD) .. math.min(have, r[2]) .. "/" .. r[2] .. " 脱钩|r")
		need:SetPoint("RIGHT", pool.page, "TOPLEFT", x + width, -y - 10)
		need:SetJustifyH("RIGHT")
		ItemHover(pool, r[1], function(tip)
			tip:AddLine(string.format("你有 %d 个，需要 %d 个。", have, r[2]), 1, 1, 1)
		end, x + 46, y, width - 46, 22 - tight * 2)
		y = y + 24 - tight * 2
	end
	y = y + 4 - tight

	-- Where the Blueprint comes from, until it's learned or in the bags.
	if craft.blueprintFrom and known ~= true and Camp.Count(craft.blueprint) == 0 then
		local line = y
		y = CampText(pool, LEAD .. "蓝图：|r" .. (craft.blueprintShort or craft.blueprintFrom), x + 46, y, width - 46, 12)
		-- Its tooltip, and a click for a waypoint at the dungeon's entrance.
		local where = craft.blueprintWhere
		Hover(pool, x + 46, line, width - 46, y - line, function(tip)
			tip:SetItemByID(craft.blueprint)
			tip:AddLine(" ")
			tip:AddLine("It " .. craft.blueprintFrom, 1, 1, 1, true)
			if where then
				tip:AddLine("点击：在 " .. where.zone, 0.6, 0.8, 1)
			end
		end, ItemLink(craft.blueprint), { "item", craft.blueprint }, where and function()
			local mapID = ZoneMapID(where.zone)
			if mapID then
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				OpenZoneMap(mapID, where.x, where.y, where.label)
			else
				ns.Print("游戏没有该区域的地图：" .. where.zone .. ".")
			end
		end or nil)
	end
	return y + 8 - tight * 2
end

local function RenderCamp()
	local Camp = ns.Camp
	for p in ipairs(frame.pages) do
		ResetPool(frame.campPools[p])
	end
	local left, right = frame.campPools[1], frame.campPools[2]
	local x = 32
	local width = math.max(left.page:GetWidth(), 400) - 64

	-- The features, a card each.
	local y = CAMP_TOP
	for i, craft in ipairs(Camp.CRAFTS) do
		if i > 1 then
			CampRule(left, x, y, width)
			y = y + 14 - (left.shrink or 0) * 2
		end
		y = RenderCraft(left, craft, x, y, width)
	end

	-- Your camp: what's on now first.
	y = CAMP_TOP
	y = y + Heading(right, "营地玩法", x, y, 32)
	local craft, timeLeft = Camp.ActiveBuff()
	local buffIcon = PoolTexture(right)
	buffIcon:SetSize(36, 36)
	buffIcon:SetPoint("TOPLEFT", right.page, "TOPLEFT", x, -y)
	local headline = PoolString(right, QuestTitleFont, 15, INK)
	headline:SetPoint("TOPLEFT", buffIcon, "TOPRIGHT", 10, -1)
	local sub = PoolString(right, QuestFont, 12, INK_SOFT)
	sub:SetWidth(width - 46)
	sub:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -3)
	if craft then
		buffIcon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(craft.buff))
			or C_Item.GetItemIconByID(craft.item))
		headline:SetText(GOOD .. craft.buffName .. " 脱钩|r")
		sub:SetText((timeLeft and string.format("%d more minutes, ", math.ceil(timeLeft / 60)) or "")
			.. "from a " .. craft.name .. ".")
		Hover(right, x, y, width, 38, function(tip)
			tip:SetSpellByID(craft.buff)
		end, SpellLink(craft.buff))
	else
		buffIcon:SetTexture(C_Item.GetItemIconByID(Camp.CRAFTS[#Camp.CRAFTS].item))
		buffIcon:SetDesaturated(true)
		headline:SetText("当前没有营地增益")
		sub:SetText("带着钓鱼架或钓鱼小屋坐在营火旁即可获得增益。")
	end
	y = y + math.max(40, 22 + (sub:GetStringHeight() or 14)) + 10

	-- How camps work, in short.
	y = y + Heading(right, "营地玩法", x, y, 32)
	y = Bullet(right, "用烹饪制作营火，并在旁边放置营地设施。", x, y, width)
	y = Bullet(right, string.format("在附近坐 %d 秒：每个设施效果持续 1 小时。", Camp.SIT_SECONDS), x, y, width)
	y = Bullet(right, string.format("设施存在 %d 分钟，共享 %d 分钟冷却。", Camp.FEATURE_MINUTES,
		Camp.COOLDOWN_MINUTES), x, y, width)
	y = y + 8

	-- The campfires: each Cooking recipe, and how many features it holds.
	y = y + Heading(right, "Campfires", x, y, 32)
	for _, fire in ipairs(Camp.CAMPFIRES) do
		local icon = PoolTexture(right)
		icon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(fire.recipe))
			or "Interface\\Icons\\Spell_Fire_Fire")
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		icon:SetSize(24, 24)
		icon:SetPoint("TOPLEFT", right.page, "TOPLEFT", x, -y)
		local name = PoolString(right, QuestFont, 13, INK)
		name:SetText(fire.name)
		name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
		local holds = PoolString(right, QuestFont, 13, INK_SOFT)
		holds:SetText(string.format("holds %d features", fire.holds))
		holds:SetPoint("RIGHT", right.page, "TOPLEFT", x + width, -y - 12)
		Hover(right, x, y, width, 26, function(tip)
			tip:SetSpellByID(fire.recipe)
			tip:AddLine(string.format("烹饪配方。最多可放置 %d 个营地设施。", fire.holds), 1, 1, 1, true)
			tip:AddLine(fire.from, 1, 0.82, 0, true)
		end, SpellLink(fire.recipe), { "spell", fire.recipe })
		y = y + 28
	end
	y = y + 10

	-- What the buffs have brought in: each buff's catches and what they were.
	y = y + Heading(right, "增益期间的钓获", x, y, 32)
	local any = false
	for _, c in ipairs(Camp.CRAFTS) do
		local r = c.buff and Camp.Record(c.key)
		if r and r.catches > 0 then
			any = true
			local line = PoolString(right, QuestFont, 13, INK)
			line:SetText(string.format("%s%s|r  %s%d catch%s|r", LEAD, c.buffName, SOFT, r.catches, r.catches == 1 and "" or "es"))
			line:SetPoint("TOPLEFT", right.page, "TOPLEFT", x, -y)
			y = y + 20
			local items = {}
			for id, n in pairs(r.items) do
				items[#items + 1] = { id = id, n = n }
			end
			table.sort(items, function(a, b)
				return a.n > b.n
			end)
			local cx = x
			for _, item in ipairs(items) do
				local w = 22 + 3 + 28
				if cx + w > x + width then
					cx, y = x, y + 26
				end
				ItemChip(right, item.id, "x" .. item.n, cx, y, 22)
				cx = cx + w + 6
			end
			y = y + 30
		end
	end
	if not any then
		CampText(right, "暂无。带着优良或稀有钓鱼增益钓到的渔获会记录在这里，以揭示"
			.. "额外奖励究竟是什么：游戏并未说明。输入 /onecast report 可分享。", x, y, width, 12, INK_SOFT)
	end

	frame.pages[1].title:SetText("营地钓鱼")
	frame.pages[2].title:SetText("你的营地")
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
		f:SetTitle("钓鱼图鉴")
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

	local inset = f.Inset or CreateFrame("Frame", nil, f)
	inset:ClearAllPoints()
	inset:SetPoint("TOPLEFT", 4, -60)
	inset:SetPoint("BOTTOMRIGHT", -6, 30)

	-- Category tabs, like the stats window's.
	f.Tabs = {}
	for i, cat in ipairs(CATEGORIES) do
		local tab = TryCreate("Button", "OneCastBookFrameTab" .. i, f, "PanelTopTabButtonTemplate")
			or CreateFrame("Button", "OneCastBookFrameTab" .. i, f, "UIPanelButtonTemplate")
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
			state.zonesPicked = nil
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
	f.progress:SetSize(140, 8) -- narrow enough to clear the eight category tabs
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
	f.empty:SetText("这里还没有内容。")

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
	f.map.empty:SetText("此区域无地图。")
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
		GameTooltip:AddLine("点击：打开世界地图", 0.6, 0.8, 1)
		if #ns.Pools.ForMap(frame.mapID) > 0 then
			GameTooltip:AddLine("蓝色圆点是你发现的鱼群：悬停或点击查看。", 1, 1, 1, true)
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
	f.openMap:SetSize(96, 20)
	f.openMap:SetPoint("TOPRIGHT", f.map, "BOTTOMRIGHT", 0, -4)
	f.mapCaption:SetPoint("RIGHT", f.openMap, "LEFT", -8, 0)
	f.mapCaption:SetJustifyH("LEFT")
	f.mapCaption:SetWordWrap(false)
	f.openMap:SetText("打开地图")
	f.openMap:SetScript("OnClick", function()
		OpenZoneMap(frame.mapID)
	end)

	-- Bottom bar.
	f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.back:SetSize(150, 22)
	f.back:SetPoint("BOTTOMLEFT", 10, 4)
	f.back:SetScript("OnEnter", function(self)
		if state.fishID then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("显示哪些渔获")
		GameTooltip:AddLine("点击切换：全部、已钓到、未钓到、可钓到（未钓到但所在区域技能达标的鱼）。"
			.. "Fishing already covers, lure included) and rare.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.back:SetScript("OnLeave", GameTooltip_Hide)
	f.wowhead = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.wowhead:SetSize(110, 22)
	f.wowhead:SetPoint("LEFT", f.back, "RIGHT", 6, 0)
	f.wowhead:SetText("Wowhead")
	f.wowhead:SetScript("OnClick", function()
		if state.fishID then
			ns.UI.ShowWowhead("item", state.fishID)
		end
	end)
	f.wowhead:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Wowhead")
		GameTooltip:AddLine("该物品的 Wowhead Forever 页面，可复制到浏览器。", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.wowhead:SetScript("OnLeave", GameTooltip_Hide)
	f.wowhead:Hide()
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
	-- Zone filter: a menu of every zone, with this one first ("what's left here?").
	f.where = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.where:SetSize(170, 22)
	f.where:SetPoint("LEFT", f.back, "RIGHT", 4, 0)
	f.where:SetScript("OnClick", function(self)
		Book.OpenZoneMenu(self)
	end)
	f.where:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("区域")
		GameTooltip:AddLine("只显示某一区域的鱼。选中你的区域，再设为「显示：未钓到」，即可查看此处还缺什么。",
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
	local typed = 0
	f.search:HookScript("搜索", function(self, userInput)
		local text = strtrim(self:GetText() or ""):lower()
		text = text ~= "" and text or nil
		if text ~= state.search then
			state.search, state.spread, state.fishID = text, 1, nil
			Book.Refresh()
		end
		-- Everything else that matches, under the box, once typing pauses.
		typed = typed + 1
		local this = typed
		C_Timer.After(0.4, function()
			if this == typed and ns.Search and self:IsVisible() then
				ns.Search.ShowResults(text or "", self)
			end
		end)
	end)
	f.search:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Search")
		GameTooltip:AddLine("按名称、区域、鱼群或配方搜索渔获。其他匹配项（区域、装备、技能等级、设置）会列在搜索框下方：点一项即可跳转。", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.search:HookScript("OnLeave", GameTooltip_Hide)
	-- The results list goes when the book does (closed with B, or by opening another page).
	f.search:HookScript("OnHide", function()
		typed = typed + 1 -- a pending list shouldn't open after
		local menu = _G.OneCastItemMenu
		if menu and menu.searchResults then
			menu:Hide()
		end
	end)
	f.search:HookScript("OnEnterPressed", f.search.ClearFocus)

	f.pageLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.next:SetSize(100, 22)
	f.next:SetPoint("BOTTOMRIGHT", -22, 4) -- clear of the resize grip
	f.next:SetText("下一页")
	f.next:SetScript("OnClick", function()
		if state.fishID and state.index then
			state.fishID, state.zone = state.list[state.index + 1].fish.id, nil
			state.zonesExpanded = false
		else
			state.spread = state.spread + 1
		end
		Book.Refresh()
	end)
	f.prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.prev:SetSize(100, 22)
	f.prev:SetPoint("RIGHT", f.next, "LEFT", -4, 0)
	f.prev:SetText("上一页")
	f.pageLabel:SetPoint("RIGHT", f.prev, "LEFT", -12, 0)
	f.padScrollLabel = "翻页" -- with a controller, what the right stick does here
	-- ...while the selection is on a catch in the grid.
	f.padScrollOwns = function(button)
		for _, page in ipairs(f.pages or {}) do
			for _, cell in ipairs(page.cells or {}) do
				if cell == button then
					return cell:IsVisible()
				end
			end
		end
		return false
	end
	f.prev:SetScript("OnClick", function()
		if state.fishID and state.index then
			state.fishID, state.zone = state.list[state.index - 1].fish.id, nil
			state.zonesExpanded = false
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
	frame.progressText:SetText(string.format("已收集 |cffffffff%d|r / %d", caught, total))
	frame.progress:SetValue(total > 0 and caught / total or 0)

	if state.fishID then
		state.list = state.list or Filtered() -- the fish page's Previous and Next walk it
	end
	local showFish = state.fishID ~= nil and Fit({ frame.leftPool, frame.rightPool }, RenderFish)
	local showZones = not showFish and state.cat == "zones"
	local showCamp = not showFish and state.cat == "camp"
	local showGrid = not showFish and not showZones and not showCamp
	if showZones then
		RenderZones()
	elseif showCamp then
		Fit(frame.campPools, RenderCamp)
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
	frame.back:SetText(showFish and "返回图鉴" or SHOW_LABEL[state.show])
	frame.wowhead:SetShown(showFish and true or false)
	frame.where:SetShown(showGrid)
	frame.where:SetText(state.where or "全部区域")
	frame.search:SetShown(showGrid)
	frame.prev:SetShown(not showCamp)
	frame.next:SetShown(not showCamp)
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
		Radio("全部区域", nil)
		if here then
			Radio("此处：" .. here, here)
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

-- Search from outside the book (/onecast search): the collection, with the words in its box.
function Book.Search(text)
	Book.ShowCollection()
	if frame and frame.search then
		frame.search:SetText(text or "")
	end
end

function Book.ShowFish(itemID)
	state.zonesExpanded = false
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


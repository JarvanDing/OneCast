-- OneCast search: one search across everything OneCast knows. Catches by name, and by the zones
-- and pools they come from and the recipes that use them; zones; fishing gear; ranks;
-- and settings. Each result opens where it lives. The collection's search box shows
-- the results under it as you type, and its grid narrows to the catches that match.

local _, ns = ...

local Search = {}
ns.Search = Search

local GREY = "|cff9d9d9d"
local MAX_RESULTS = 12
local ORDER = { catch = 1, zone = 2, pool = 3, recipe = 4, gear = 5, rank = 6, setting = 7 }

local function Has(text, query)
	return type(text) == "string" and text:lower():find(query, 1, true) ~= nil
end

local function ItemName(id, fallback)
	return C_Item.GetItemNameByID(id) or fallback or ("item " .. id)
end

local function Icon(id)
	local icon = id and C_Item.GetItemIconByID(id)
	return icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
end

-- Does a catch match: its name, a zone or pool it comes from, or a recipe that uses it?
function Search.MatchesFish(fish, query)
	if not query or query == "" then
		return true
	end
	if Has(ItemName(fish.id, fish.name), query) then
		return true
	end
	for _, zone in ipairs(fish.zones or {}) do
		if Has(zone, query) then
			return true
		end
	end
	for _, extra in ipairs(fish.more or {}) do
		if Has(extra[1], query) then
			return true
		end
	end
	for _, recipe in ipairs(fish.recipes or {}) do
		if Has(recipe[2], query) then
			return true
		end
	end
	local odds = ns.ODDS and ns.ODDS[fish.id]
	return odds and odds.pool and Has(odds.pool[1], query) or false
end

-- Opening a result.
local function OpenFish(id)
	return function()
		if ns.Book then
			ns.Book.ShowCollection()
			ns.Book.ShowFish(id)
		end
	end
end

local function OpenZone(zone)
	return function()
		if ns.Book then
			ns.Book.ShowCollection()
			ns.Book.ShowZoneFish(zone)
		end
	end
end

local function OpenJourney(view)
	return function()
		if ns.Journey and ns.Journey.ShowView then
			ns.Journey.ShowView(view)
		end
	end
end

local function OpenSetting(category)
	return function()
		if ns.Hub and ns.Hub.ShowOptions then
			ns.Hub.ShowOptions(category)
		end
	end
end

-- The Options category each setting is on.
local function SettingCategories()
	local where = {}
	for _, section in ipairs(ns.OPTION_MAIN or {}) do
		for i = 2, #section do
			where[section[i]] = "General"
		end
	end
	for _, page in ipairs(ns.OPTION_PAGES or {}) do
		for _, section in ipairs(page) do
			for i = 2, #section do
				where[section[i]] = page.name
			end
		end
	end
	return where
end

-- Everything matching `query`: { text, open, kind }, the best matches first, at most MAX_RESULTS.
function Search.Find(query)
	query = query and strtrim(query):lower() or ""
	local results = {}
	if #query < 2 then
		return results
	end
	local seen = {}
	local function Add(kind, key, name, label, open)
		if seen[kind .. key] then
			return
		end
		seen[kind .. key] = true
		local starts = name:lower():sub(1, #query) == query
		results[#results + 1] = { kind = kind, text = label, open = open, starts = starts, name = name }
	end
	local zones = {}
	for _, fish in ipairs(ns.FISH or {}) do
		local name = ItemName(fish.id, fish.name)
		if Has(name, query) then
			Add("catch", fish.id, name, Icon(fish.id) .. name, OpenFish(fish.id))
		end
		for _, recipe in ipairs(fish.recipes or {}) do
			if Has(recipe[2], query) then
				Add("recipe", recipe[1], recipe[2], string.format("%s %s(%s %d, uses %s)|r", recipe[2], GREY, recipe[3],
					recipe[4] or 0, name), OpenFish(fish.id))
			end
		end
		local odds = ns.ODDS and ns.ODDS[fish.id]
		if odds and odds.pool and Has(odds.pool[1], query) then
			Add("pool", odds.pool[1], odds.pool[1], odds.pool[1] .. GREY .. " (pool: " .. name .. ")|r", OpenFish(fish.id))
		end
		for _, zone in ipairs(fish.zones or {}) do
			zones[zone] = true
		end
		for _, extra in ipairs(fish.more or {}) do
			zones[extra[1]] = true
		end
	end
	for zone in pairs(ns.ZONE_FISHING_SKILL or {}) do
		zones[zone] = true
	end
	for zone in pairs(zones) do
		if Has(zone, query) then
			local needed = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone]
			Add("zone", zone, zone, zone .. GREY .. (needed and (" (zone, needs " .. needed .. ")") or " (zone)") .. "|r", OpenZone(zone))
		end
	end
	for _, g in ipairs(ns.Journey and ns.Journey.GEAR or {}) do
		local name = ItemName(g.id)
		if Has(name, query) and ns.Journey.ForYourFaction(g) then
			Add("gear", g.id, name, Icon(g.id) .. name .. GREY .. " (fishing gear)|r", OpenJourney("gear"))
		end
	end
	for _, r in ipairs(ns.Journey and ns.Journey.RANKS or {}) do
		local name = r.name .. " Fishing"
		if Has(name, query) then
			Add("rank", r.name, name, name .. GREY .. " (rank)|r", OpenJourney("ranks"))
		end
	end
	local where = SettingCategories()
	for _, opt in ipairs(ns.OPTIONS or {}) do
		if Has(opt.label, query) and where[opt.key] then
			Add("setting", opt.key, opt.label, opt.label .. GREY .. " (setting, " .. where[opt.key] .. ")|r", OpenSetting(where[opt.key]))
		end
	end
	-- The cast key: a setting of the game's, chosen in OneCast's own window.
	for _, name in ipairs({ "Cast and reel key", "Key binding" }) do
		if Has(name, query) and ns.Onboarding then
			Add("setting", "castKey", name, name .. GREY .. " (setting, Fishing)|r", ns.Onboarding.Show)
		end
	end
	for key, spec in pairs(ns.OPTION_CHOICES or {}) do
		if Has(spec.label, query) and where[key] then
			Add("setting", key, spec.label, spec.label .. GREY .. " (setting, " .. where[key] .. ")|r", OpenSetting(where[key]))
		end
	end
	table.sort(results, function(a, b)
		if a.starts ~= b.starts then
			return a.starts
		end
		if a.kind ~= b.kind then
			return ORDER[a.kind] < ORDER[b.kind]
		end
		return a.name < b.name
	end)
	for i = #results, MAX_RESULTS + 1, -1 do
		results[i] = nil
	end
	return results
end

-- The results as a menu under `anchor` (the search box), or nothing if there are none.
function Search.ShowResults(query, anchor)
	local results = Search.Find(query)
	local menu = _G.OneCastItemMenu
	if #results == 0 then
		if menu and menu.searchResults then
			menu:Hide()
		end
		return nil
	end
	local entries = {}
	for _, r in ipairs(results) do
		entries[#entries + 1] = { r.text, r.open }
	end
	menu = ns.UI and ns.UI.ShowMenu and ns.UI.ShowMenu("Search: " .. strtrim(query), entries)
	if menu then
		menu.searchResults = true
		if not menu.searchHooked then
			menu.searchHooked = true
			menu:HookScript("OnHide", function(self)
				self.searchResults = nil
			end)
		end
		if anchor then
			menu:ClearAllPoints()
			menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -4, -4)
		end
	end
	return menu
end

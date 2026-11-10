-- OneCast camp: Forever's fishing crafts for its wilderness camps, and the buffs they give.
--
-- Forever lets players build a campfire and place camp features by it. Fishing has three:
-- the Fish Bowl, the Fishing Rack and the Fishing Hut. Sitting by the fire for a minute gives
-- each feature's benefit for an hour; the Rack and the Hut give "Uncommon Fishing" and "Rare
-- Fishing", extra rewards while fishing. What those rewards are is decided by the server and
-- not published anywhere, so catches made under each buff are recorded here, to be shown in
-- the collection book's Camp tab and in /onecast report.
--
-- Everything below is from Forever's game data on wago.tools (build 1.60.1.70862): recipe and
-- item IDs, reagents, the Fishing each needs (the craft's skill-up level and the item's own
-- requirement), the 15-minute features, the hour-long buffs and the shared hour cooldown.
-- Where the Blueprints, the Fish Bowl recipe and Seasonal Fish Steaks come from isn't in it:
-- `blueprintFrom` is from player reports (10 November 2026). The Rack's Blueprint dropping from
-- Gelihast is reported by several guides, which disagree only on the drop rate; no source for
-- the Hut's had been found.

local _, ns = ...

local Camp = {}
ns.Camp = Camp

Camp.CRAFTS = {
	{ key = "bowl", name = "Fish Bowl", recipe = 1229745, item = 279967, skill = 20,
		reagents = { { 6291, 1, "Raw Brilliant Smallfish" }, { 3371, 1, "Empty Vial" } },
		does = "Placed by a campfire, it gives you and everyone sitting nearby +8% to all stats for an hour. It doesn't stack with Blessing of Kings." },
	{ key = "rack", name = "Fishing Rack", recipe = 1262990, item = 279965, skill = 140,
		blueprint = 273141, blueprintName = "Blueprint: Fishing Rack", buff = 1280341, buffName = "Uncommon Fishing",
		blueprintFrom = "drops from Gelihast in Blackfathom Deeps, not on every kill. Other players can trade it to you.",
		reagents = { { 4470, 2, "Simple Wood" }, { 8925, 1, "Crystal Vial" }, { 8365, 2, "Raw Mithril Head Trout" } },
		does = "Placed by a campfire, it gives Uncommon Fishing for an hour: extra rewards while you fish. It also provides lures and the Fish Bowl's +8% stats, and can replace a Fish Bowl." },
	{ key = "hut", name = "Fishing Hut", recipe = 1262998, item = 279966, skill = 300,
		blueprint = 273119, blueprintName = "Blueprint: Fishing Hut", buff = 1280342, buffName = "Rare Fishing",
		blueprintFrom = "where it comes from isn't known yet. Nobody has reported finding one.",
		reagents = { { 4470, 5, "Simple Wood" }, { 14048, 2, "Bolt of Runecloth" }, { 273295, 1, "Seasonal Fish Steaks" } },
		does = "Placed by a campfire, it gives Rare Fishing for an hour: greater extra rewards while you fish. It also provides lures and the Fish Bowl's +8% stats, and can replace a Fish Bowl." },
}

-- Cooking recipes: a campfire holds this many features.
Camp.CAMPFIRES = {
	{ name = "Basic Campfire", recipe = 1229737, holds = 3 },
	{ name = "Journeyman Campfire", recipe = 1283400, holds = 5 },
	{ name = "Expert Campfire", recipe = 1291341, holds = 10 },
}
Camp.FEATURE_MINUTES = 15  -- a placed feature stands this long
Camp.SIT_SECONDS = 60      -- time by the fire before its benefits arrive
Camp.COOLDOWN_MINUTES = 60 -- shared by every camp feature

local byBuff = {}
for _, craft in ipairs(Camp.CRAFTS) do
	if craft.buff then
		byBuff[craft.buff] = craft
	end
end

Camp.Count = ns.ItemCount

function Camp.ItemName(itemID, fallback)
	return C_Item.GetItemNameByID(itemID) or fallback
end

-- True if the recipe is learned, false if not, nil if the game can't say.
function Camp.Known(craft)
	if IsPlayerSpell then
		return IsPlayerSpell(craft.recipe) and true or false
	end
end

-- The camp fishing buff on you now, if any: the craft that gives it and seconds left. The
-- Hut's is the stronger, so it wins if both are somehow on.
function Camp.ActiveBuff()
	if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
		return nil
	end
	local found, left
	for _, craft in ipairs(Camp.CRAFTS) do
		if craft.buff then
			local aura = C_UnitAuras.GetPlayerAuraBySpellID(craft.buff)
			local expires = aura and aura.expirationTime
			if expires and not (issecretvalue and issecretvalue(expires)) then
				found, left = craft, expires > 0 and math.max(0, expires - GetTime()) or nil
			end
		end
	end
	return found, left
end

-- Catches made under each buff: { [buff key] = { catches, items = { [id] = count }, zones } }.
local function Records()
	local charDB = OneCastCharDB
	if not charDB then
		return nil
	end
	charDB.camp = charDB.camp or {}
	return charDB.camp
end

function Camp.Record(key)
	local records = Records()
	return records and records[key]
end

-- From the stats window's catch handling, with the zone and what came out of the water.
function Camp.OnCatch(zone, loot)
	local craft = Camp.ActiveBuff()
	local records = craft and Records()
	if not records then
		return
	end
	local r = records[craft.key]
	if not r then
		r = { catches = 0, items = {}, zones = {} }
		records[craft.key] = r
	end
	r.catches = r.catches + 1
	r.zones[zone] = (r.zones[zone] or 0) + 1
	for _, l in ipairs(loot) do
		r.items[l.id] = (r.items[l.id] or 0) + l.quantity
	end
end

-- "Rare Fishing  ·  42m", for the stats window and minimap tooltip, or nil with no buff on.
function Camp.StatusText()
	local craft, left = Camp.ActiveBuff()
	if not craft then
		return nil
	end
	if left then
		return string.format("%s  ·  %dm", craft.buffName, math.ceil(left / 60))
	end
	return craft.buffName
end

local function RefreshViews()
	if ns.Stats and ns.Stats.RefreshIfShown then
		ns.Stats.RefreshIfShown()
	end
	if ns.Book and ns.Book.RefreshCampIfShown then
		ns.Book.RefreshCampIfShown()
	end
end

-- Auras change all the time, in combat above all: only a buff starting or ending matters.
-- When one runs out, say so once: the next hour needs another sit by the fire.
local had -- the buff's craft key, false for none, nil before login
local function CheckBuff()
	local craft = Camp.ActiveBuff()
	local now = craft and craft.key or false
	if now == had then
		return
	end
	if had and not now and ns.db and ns.db.campReminder then
		for _, gone in ipairs(Camp.CRAFTS) do
			if gone.key == had then
				local buff = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(gone.buff) or gone.buffName
				local item = ns.ItemLink(gone.item, gone.name)
				ns.Print(buff .. " has worn off. Sit by a campfire with a " .. item .. " to get it again.")
			end
		end
	end
	had = now
	RefreshViews()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterEvent("BAG_UPDATE_DELAYED")
-- A recipe learned: Forever calls it LEARNED_SPELL_IN_SKILL_LINE, older clients LEARNED_SPELL_IN_TAB.
ns.RegisterAnyEvent(events, { "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB" })
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		local craft = Camp.ActiveBuff()
		had = craft and craft.key or false
	elseif event == "UNIT_AURA" then
		if had ~= nil then
			CheckBuff()
		end
	elseif ns.Book and ns.Book.RefreshCampIfShown then
		-- Reagents or a recipe changed: only the Camp tab shows those.
		ns.Book.RefreshCampIfShown()
	end
end)

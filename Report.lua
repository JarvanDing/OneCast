-- OneCast report: this character's fishing data as plain text, to copy and share.
--
-- Nobody has published Forever's real zone fishing levels or all of its fish, and the
-- game doesn't tell addons either. OneCast already sees every catch and getaway, and the skill
-- each happened at, so players can pass that on: OneCast's numbers can then become Forever's
-- own. The text holds fishing numbers only: no character name, realm or guild.

local _, ns = ...

local Report = {}
ns.Report = Report

local MAX_FISH = 15 -- items listed per camp buff, most caught first

-- The area ID for a zone name as the game gives it, in any client language.
local function AreaID(zone)
	local id = ns.ZONE_AREA_IDS and ns.ZONE_AREA_IDS[zone]
	if id then
		return id
	end
	for _, areaID in pairs(ns.ZONE_AREA_IDS or {}) do
		if C_Map.GetAreaInfo(areaID) == zone then
			return areaID
		end
	end
end

local function ByCount(items)
	local list = {}
	for id, item in pairs(items) do
		local count = type(item) == "table" and item.count or item
		local name = type(item) == "table" and item.name or C_Item.GetItemNameByID(id)
		list[#list + 1] = { id = id, count = count, name = name or ("item " .. id) }
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.id < b.id
	end)
	return list
end

local function ItemLine(items)
	local parts = {}
	local list = ByCount(items)
	for i = 1, math.min(#list, MAX_FISH) do
		parts[i] = string.format("%s (%d) x%d", list[i].name, list[i].id, list[i].count)
	end
	if #list > MAX_FISH then
		parts[#parts + 1] = string.format("and %d more", #list - MAX_FISH)
	end
	return table.concat(parts, ", ")
end

-- "  skill 200-224: 40 caught, 3 got away" for each step with anything in it.
local function SkillLines(z, add)
	local steps, seen = {}, {}
	for _, key in ipairs({ "skillCatches", "skillGetaways" }) do
		for bucket in pairs(z[key] or {}) do
			if not seen[bucket] then
				seen[bucket] = true
				steps[#steps + 1] = bucket
			end
		end
	end
	table.sort(steps)
	local step = ns.Stats.SKILL_STEP
	for _, bucket in ipairs(steps) do
		local caught = z.skillCatches and z.skillCatches[bucket] or 0
		local away = z.skillGetaways and z.skillGetaways[bucket] or 0
		add(string.format("  skill %d-%d: %d caught%s", bucket, bucket + step - 1, caught,
			away > 0 and string.format(", %d got away", away) or ""))
	end
	return #steps > 0
end

-- Findings: what this character has seen that OneCast doesn't know ----------------------
-- Worth sharing: a badge on the Data report tab until the report is copied.

local MIN_UNKNOWN_LEVEL = 10 -- catches in a zone with no known level
local MIN_BELOW_LEVEL = 20   -- catches without a getaway below a zone's listed level
local MIN_EXPECTED = 3       -- getaways those catches should have had, had the level been right
local MIN_CAMP = 5           -- catches under a camp buff

-- A collection fish the book can't say where to find: no zones at all, from any source. Only
-- these are worth a report when caught: a known fish in one more zone helps nobody find it.
local function Unplaced(fish)
	return not (fish.zones and fish.zones[1]) and not (fish.more and fish.more[1])
end

local function ItemName(id, item)
	return (type(item) == "table" and item.name) or C_Item.GetItemNameByID(id) or ("item " .. id)
end

-- What Classic's fishing gives that the collection leaves out on purpose: junk, potions, herbs
-- and reagents (checked against CMaNGOS's fishing and pool loot, 13 November 2026), and the
-- Electropeller, a quest drop. Anything else fished up that the collection lacks is news.
local NOT_COLLECTED = {
	[6456] = true, [6297] = true, [6301] = true, [6455] = true, [6457] = true, -- junk
	[118] = true, [858] = true, [929] = true, [1710] = true, [3928] = true, [13446] = true, -- healing potions
	[2455] = true, [3385] = true, [3827] = true, [6149] = true, [13443] = true, -- mana potions
	[3820] = true, [2447] = true, [3857] = true, [7070] = true, [7079] = true, [7080] = true, -- herbs, reagents
	[6718] = true, -- Electropeller
}

-- Weapons and armour: a mob's drop looted right after a cast can be logged as a catch (a Flanged
-- Mace "fished up" in Elwynn Forest), and all the fishable gear known is in the collection already.
local function IsGear(id)
	local classID = select(6, C_Item.GetItemInfoInstant(id))
	return classID == 2 or classID == 4
end

-- A collection item OneCast only knows from Classic: no Forever zones, only `more` ones marked
-- "classic". The first Forever catch of one confirms it's still there.
local function ClassicOnly(fish)
	if fish.zones and fish.zones[1] then
		return false
	end
	for _, extra in ipairs(fish.more or {}) do
		if extra[2] ~= "classic" then
			return false
		end
	end
	return fish.more and fish.more[1] ~= nil
end

-- Every finding, as { key, text, zone }: the key stays the same while the finding does. The
-- tab's badge, stats window, book and this window can all ask in one redraw, so the list is
-- worked out once a frame. Callers may sort it, so each gets its own copy.
local cached, cachedAt
local Findings

function Report.Findings()
	local now = GetTime()
	if not cached or cachedAt ~= now then
		cached, cachedAt = Findings(), now
	end
	local copy = {}
	for i, f in ipairs(cached) do
		copy[i] = f
	end
	return copy
end

-- Nothing cached survives a catch, a getaway or sharing.
function Report.Forget()
	cached = nil
end

Findings = function()
	local found = {}
	-- text: the line in the report. title and detail: the window's, for the player: what was
	-- found, and why it's worth sending.
	local function add(key, text, zone, title, detail)
		found[#found + 1] = { key = key, text = text, zone = zone, title = title, detail = detail }
	end
	local step = ns.Stats.SKILL_STEP
	local zoneNames = {}
	for zone in pairs(OneCastCharDB and OneCastCharDB.zoneStats or {}) do
		zoneNames[#zoneNames + 1] = zone
	end
	table.sort(zoneNames)
	for _, zone in ipairs(zoneNames) do
		local z = OneCastCharDB.zoneStats[zone]
		local listed = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone]
		if not listed then
			if (z.catches or 0) >= MIN_UNKNOWN_LEVEL then
				add("level:" .. zone, string.format("%d catches in %s, which has no known fishing level", z.catches, zone), zone,
					zone, string.format("%d catches here. OneCast doesn't know the skill this zone needs: yours will tell.", z.catches))
			end
		else
			-- A getaway at or above the listed level says the real one is higher.
			local highestAway
			for bucket, n in pairs(z.skillGetaways or {}) do
				if n > 0 and (not highestAway or bucket > highestAway) then
					highestAway = bucket
				end
			end
			if highestAway and highestAway >= listed then
				add("above:" .. zone, string.format("A fish got away in %s at skill %d-%d, though OneCast lists %d",
					zone, highestAway, highestAway + step - 1, listed), zone,
					zone, string.format("A fish got away at skill %d, where OneCast says %d is plenty. It may need more.",
						highestAway, listed))
			end
			-- Plenty of catches below the listed level, none getting away there, says it's lower: but
			-- only where getaways were to be expected. Fish get away about (level - skill)% of the
			-- time below a zone's level, so catches just under it say little. Each step counts at its
			-- top skill, the least getaways it could expect; it takes MIN_EXPECTED in all.
			local below, lowest, expected = 0, nil, 0
			for bucket, n in pairs(z.skillCatches or {}) do
				if bucket + step <= listed and not (highestAway and bucket <= highestAway) then
					below = below + n
					lowest = math.min(lowest or bucket, bucket)
					expected = expected + n * (listed - (bucket + step - 1)) / 100
				end
			end
			if below >= MIN_BELOW_LEVEL and expected >= MIN_EXPECTED then
				add("below:" .. zone, string.format("%d catches in %s from skill %d with no getaways, though OneCast lists %d",
					below, zone, lowest, listed), zone,
					zone, string.format("%d catches from skill %d with none getting away, though OneCast says %d. It may need less.",
						below, lowest, listed))
			end
		end
	end
	for _, entry in ipairs(ns.Collection and ns.Collection.Discovered() or {}) do
		-- Where this character caught it, so the finding says everything on its own.
		local where = {}
		for _, zone in ipairs(zoneNames) do
			local item = OneCastCharDB.zoneStats[zone].items and OneCastCharDB.zoneStats[zone].items[entry.id]
			if item and (item.count or 0) > 0 then
				where[#where + 1] = string.format("%s x%d", zone, item.count)
			end
		end
		add("fish:" .. entry.id, string.format("%s (%d), which isn't in OneCast's collection%s", entry.name or ("item " .. entry.id),
			entry.id, #where > 0 and (" (caught in " .. table.concat(where, ", ") .. ")") or ""), nil,
			entry.name or ("Item " .. entry.id), "A fish OneCast's collection doesn't have yet"
				.. (#where > 0 and (", caught in " .. table.concat(where, ", ")) or "") .. ".")
	end
	-- Anything else fished up that the collection lacks (treasure, gear, junk new to Forever), and
	-- the first Forever catch of anything OneCast only knows from Classic.
	local other, confirmed = {}, {}
	for _, zone in ipairs(zoneNames) do
		for id, item in pairs(OneCastCharDB.zoneStats[zone].items or {}) do
			if (item.count or 0) > 0 then
				local fish = ns.FISH_BY_ID and ns.FISH_BY_ID[id]
				local list
				if not fish and not NOT_COLLECTED[id] and not (ns.Collection and ns.Collection.IsFish(id)) and not IsGear(id) then
					list = other
				elseif fish and ClassicOnly(fish) then
					list = confirmed
				end
				if list then
					list[id] = list[id] or { name = ItemName(id, item), where = {}, places = {} }
					table.insert(list[id].where, string.format("%s x%d", zone, item.count))
					table.insert(list[id].places, item.count > 1 and string.format("%s (%d)", zone, item.count) or zone)
				end
			end
		end
	end
	for _, list in ipairs({ other, confirmed }) do
		local ids = {}
		for id in pairs(list) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local e = list[id]
			if list == other then
				add("item:" .. id, string.format("%s (%d) fished up in %s, which isn't in OneCast's collection",
					e.name, id, table.concat(e.where, ", ")), nil,
					e.name, "Fished up in " .. table.concat(e.places, ", ") .. ". It isn't in OneCast's collection yet.")
			else
				add("confirm:" .. id, string.format("%s (%d) caught in %s: OneCast only had Classic's data for it",
					e.name, id, table.concat(e.where, ", ")), nil,
					e.name, "Caught in " .. table.concat(e.places, ", ") .. ". Proof it's in Forever: OneCast only knew it from Classic.")
			end
		end
	end
	-- For the Fisherman's journey: where ranks and fishing spells are learned, and fishing gear
	-- it doesn't list.
	for _, f in ipairs(ns.Journey and ns.Journey.Findings and ns.Journey.Findings() or {}) do
		add(f.key, f.text, nil, f.title, f.detail)
	end
	-- Where a Blueprint or Seasonal Fish Steaks dropped, unless it's the source already confirmed.
	local drops = OneCastCharDB.campDrops or {}
	local dropIDs = {}
	for id in pairs(drops) do
		dropIDs[#dropIDs + 1] = id
	end
	table.sort(dropIDs)
	for _, id in ipairs(dropIDs) do
		local known
		for _, craft in ipairs(ns.Camp and ns.Camp.CRAFTS or {}) do
			if craft.blueprint == id then
				known = craft.blueprintKnown
			end
		end
		local keys = {}
		for key in pairs(drops[id]) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local d = drops[id][key]
			local isKnown = known and ((d.npc and d.npc == known.npc) or (d.name and d.name == known.name))
			if not isKnown then
				local from = d.name and (d.npc and string.format("%s [%d]", d.name, d.npc) or d.name)
					or (d.npc and string.format("creature %d", d.npc)) or (d.object and "a chest or object") or "somewhere"
				local name = ns.Camp.TRACKED_DROPS[id] or ItemName(id)
				add("drop:" .. id .. ":" .. key, string.format("%s (%d) dropped from %s in %s%s", name, id, from, d.zone,
					d.count > 1 and string.format(" (x%d)", d.count) or ""), nil,
					name, string.format("Dropped from %s in %s%s. OneCast doesn't know this source yet.",
						d.name or (d.object and "a chest or object") or "something", d.zone,
						d.count > 1 and string.format(", %d times", d.count) or ""))
			end
		end
	end
	for _, craft in ipairs(ns.Camp and ns.Camp.CRAFTS or {}) do
		local r = craft.buff and ns.Camp.Record(craft.key)
		if r and r.catches >= MIN_CAMP then
			add("camp:" .. craft.key, string.format("%d catches with %s on", r.catches, craft.buffName), nil,
				craft.buffName, string.format("%d catches with it on: enough to show what the buff really does.", r.catches))
		end
	end
	for _, zone in ipairs(zoneNames) do
		for id, item in pairs(OneCastCharDB.zoneStats[zone].items or {}) do
			local fish = ns.FISH_BY_ID and ns.FISH_BY_ID[id]
			if fish and Unplaced(fish) and (item.count or 0) > 0 then
				add("place:" .. id .. ":" .. zone, string.format("%s caught in %s: OneCast doesn't know where it's found yet",
					ItemName(id, item), zone), zone,
					ItemName(id, item), "Caught in " .. zone .. ". OneCast doesn't know where it's found yet.")
			end
		end
	end
	return found
end

local function Seen()
	local charDB = OneCastCharDB
	charDB.reportFindings = charDB.reportFindings or { shared = {} }
	charDB.reportFindings.said = nil -- the chat hints' record, before 1.0
	return charDB.reportFindings
end

-- Findings not yet shared (copied from the report).
function Report.Unshared()
	if not OneCastCharDB then
		return {}
	end
	local shared = Seen().shared
	local list = {}
	for _, f in ipairs(Report.Findings()) do
		if not shared[f.key] then
			list[#list + 1] = f
		end
	end
	return list
end

-- After a catch or getaway: what's new shows quietly, as the Data report tab's badge.
function Report.Check()
	Report.Forget()
	if ns.Hub and ns.Hub.UpdateBadges then
		ns.Hub.UpdateBadges()
	end
	if Report.RefreshIfShown then
		Report.RefreshIfShown()
	end
end

-- Copying the report shares what's in it.
function Report.MarkShared()
	Report.Forget()
	if not OneCastCharDB then
		return
	end
	local seen = Seen()
	for _, f in ipairs(Report.Findings()) do
		seen.shared[f.key] = true
	end
	if ns.Hub and ns.Hub.UpdateBadges then
		ns.Hub.UpdateBadges()
	end
end

-- The report text ---------------------------------------------------------------------------
-- Only what OneCast can learn from: what's new, the evidence for zone levels, what camp buffs
-- bring in, and any fishing messages OneCast didn't recognise. Zones whose catches only agree
-- with the level OneCast already lists say nothing new, so they're left out.

-- Whether a zone's catches and getaways say anything about its fishing level.
local function Telling(zone, z)
	if (z.casts or 0) == 0 then
		return false
	end
	local listed = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone]
	if not listed then
		return (z.catches or 0) > 0 or (z.escapes or 0) > 0
	end
	for _, n in pairs(z.skillGetaways or {}) do
		if n > 0 then
			return true -- getaways bound the level, above or below the listed one
		end
	end
	local step = ns.Stats.SKILL_STEP
	for bucket, n in pairs(z.skillCatches or {}) do
		if n > 0 and bucket + step <= listed then
			return true -- caught below the listed level
		end
	end
	return (z.escapeSkill or 0) > 0 -- a getaway from before 0.7.0
end

function Report.Text()
	local out = {}
	local function add(line)
		out[#out + 1] = line
	end
	local charDB = OneCastCharDB or {}
	local version, build = GetBuildInfo()
	add(string.format("OneCast %s data report", ns.VERSION or "?"))
	add(string.format("Game %s (build %s), %s, %s", version or "?", build or "?", GetLocale(), date("%Y-%m-%d")))
	local rank, maxRank, modifier = ns.Stats.FishingSkill()
	add(rank and string.format("Fishing %d/%d%s", rank, maxRank,
		modifier > 0 and string.format(" (+%d from lure or pole right now)", modifier) or "") or "Fishing skill not found")

	local findings = Report.Findings()
	add("")
	if #findings > 0 then
		add(string.format("New to OneCast (%d):", #findings))
		for _, f in ipairs(findings) do
			add("- " .. f.text)
		end
	else
		add("New to OneCast: nothing yet.")
	end

	local zones = {}
	for zone, z in pairs(charDB.zoneStats or {}) do
		if Telling(zone, z) then
			zones[#zones + 1] = { zone = zone, z = z }
		end
	end
	table.sort(zones, function(a, b)
		return a.zone < b.zone
	end)
	if #zones > 0 then
		add("")
		add("Zone levels: catches and getaways at each effective skill (lure and pole included).")
		for _, entry in ipairs(zones) do
			local zone, z = entry.zone, entry.z
			local id = AreaID(zone)
			local listed = ns.ZONE_FISHING_SKILL and ns.ZONE_FISHING_SKILL[zone]
			add(string.format("%s%s, %s", zone, id and (" [" .. id .. "]") or "",
				listed and ("OneCast lists " .. listed) or "no level known"))
			if not SkillLines(z, add) then
				-- Catches from before 0.7.0 weren't recorded by skill: their totals still say something.
				add(string.format("  %d caught, %d got away (skill not recorded: before 0.7.0)",
					z.catches or 0, z.escapes or 0))
				if z.escapeSkill then
					add(string.format("  a fish got away at %d", z.escapeSkill))
				end
			end
		end
	end

	local camp = {}
	for _, craft in ipairs(ns.Camp and ns.Camp.CRAFTS or {}) do
		local r = craft.buff and ns.Camp.Record(craft.key)
		if r and r.catches > 0 then
			camp[#camp + 1] = { craft = craft, r = r }
		end
	end
	if #camp > 0 then
		add("")
		add("Camp buffs: what was caught while each was on.")
		for _, entry in ipairs(camp) do
			local zonesHere = {}
			for zone, n in pairs(entry.r.zones) do
				zonesHere[#zonesHere + 1] = string.format("%s %d", zone, n)
			end
			table.sort(zonesHere)
			add(string.format("%s (%s): %d caught, in %s", entry.craft.buffName, entry.craft.name, entry.r.catches,
				table.concat(zonesHere, ", ")))
			add("  " .. ItemLine(entry.r.items))
		end
	end

	-- What fished-up trunks, crates, clams and bloated fish held when they were opened.
	local opened = {}
	for id, record in pairs(charDB.containerLoot or {}) do
		opened[#opened + 1] = { id = id, record = record }
	end
	table.sort(opened, function(a, b) return a.id < b.id end)
	if #opened > 0 then
		add("")
		add("What fished-up containers held:")
		for _, entry in ipairs(opened) do
			add(string.format("%s (%d), opened %d: %s", ItemName(entry.id), entry.id, entry.record.opened,
				ItemLine(entry.record.items)))
		end
	end

	-- Fishing messages OneCast didn't recognise: what to match if one is ever being missed.
	local messages = charDB.messagesWhileFishing
	if messages and #messages > 0 then
		add("")
		add("Unrecognised fishing messages:")
		for _, m in ipairs(messages) do
			add(string.format("- %q x%d (%s%s)", m.text, m.count, m.event, m.id and (", " .. m.id) or ""))
		end
	end
	return table.concat(out, "\n")
end

-- The window ------------------------------------------------------------------------------
-- Two columns. On the left, what you've found, each with what it means in full. On the right,
-- how to share it (the steps, with the button and links in them, on parchment like the book's
-- pages), and the report text itself under them.

local WINDOW_WIDTH = 820
local EDGE, GAP, HEADER_HEIGHT, HEADER_GAP = 10, 8, 24, 4
local FOUND_WIDTH = 430 -- the left column
local SIDE_LEFT = EDGE + FOUND_WIDTH + 2 * GAP -- where the right column starts
local SIDE_WIDTH = WINDOW_WIDTH - 10 - SIDE_LEFT - EDGE
local NEW_ROWS, NEW_ROW_HEIGHT = 9, 48
local SHARE_PAD = 12
local LINK_HEIGHT, LINK_GAP = 20, 4
-- Where reports go. The GitHub link opens the repo's Data report issue form.
Report.WHERE = {
	{ label = "CurseForge", url = "https://www.curseforge.com/wow/addons/onecast/comments" },
	{ label = "GitHub", url = "https://github.com/rynmon/OneCast/issues/new?template=data-report.yml" },
}
local HINT = "Ctrl+C copies the report once it's selected."
local HINT_NOTHING = "Keep fishing: anything new shows up here, ready to share."
local SELECTED = "|cffffd100Selected! Now press Ctrl+C to copy.|r"
local COPIED = "|cff20ff20Report copied!|r Now copy a link, open it in your browser and paste."
local LINK_COPIED = "|cff20ff20Link copied!|r Paste it in your browser's address bar."

-- A box holding a web address, read-only, all selected when clicked: WoW can't open links,
-- so copying is the way out.
local function LinkBox(parent, url, onCopy)
	local box = ns.UI.TryCreate("EditBox", nil, parent, "InputBoxTemplate") or CreateFrame("EditBox", nil, parent)
	box:SetAutoFocus(false)
	box:SetFontObject(OneCastFontHighlightSmall)
	box:SetHeight(LINK_HEIGHT)
	box:SetText(url)
	box:SetCursorPosition(0)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(url)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		self:SetCursorPosition(0)
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() then
			onCopy()
		end
	end)
	return box
end

-- Parchment text in its ink.
local function Ink(fs, size, font)
	ns.UI.SizedFont(fs, font or QuestFont, size)
	fs:SetShadowOffset(0, 0)
	fs:SetJustifyH("LEFT")
	return fs
end

-- Share it: three numbered steps, each with what it needs right there, and what a report holds.
local function SharePanel(f, parent)
	local panel = CreateFrame("Frame", nil, parent)
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if ns.UI.HasAtlas("QuestBG-Parchment") then
		bg:SetAtlas("QuestBG-Parchment")
	else
		bg:SetTexture("Interface\\QuestFrame\\QuestBG")
		bg:SetTexCoord(0, 0.586, 0, 0.65)
	end
	local edge = panel:CreateTexture(nil, "BORDER")
	edge:SetColorTexture(0.55, 0.40, 0.15, 0.8)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(3)

	local width = SIDE_WIDTH - 2 * SHARE_PAD
	panel.texts = {}
	local function Text(size, font)
		local fs = Ink(panel:CreateFontString(nil, "OVERLAY"), size, font)
		fs:SetWidth(width)
		panel.texts[#panel.texts + 1] = fs
		return fs
	end

	-- 1. Select it, and copy.
	panel.step1 = Text(12)
	panel.step1:SetPoint("TOPLEFT", SHARE_PAD, -SHARE_PAD)
	local select = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	select:SetSize(130, 22)
	select:SetPoint("TOPLEFT", panel.step1, "BOTTOMLEFT", 16, -4)
	select:SetText("Select report")
	select:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Select report")
		GameTooltip:AddLine("Selects all of it. Then press Ctrl+C to copy: the game doesn't let addons copy for you.",
			1, 1, 1, true)
		GameTooltip:Show()
	end)
	select:SetScript("OnLeave", GameTooltip_Hide)
	f.select = select

	-- 2. Where to post it.
	panel.step2 = Text(12)
	panel.step2:SetPoint("TOPLEFT", select, "BOTTOMLEFT", -16, -10)
	panel.links = {}
	local previous = panel.step2
	for i, where in ipairs(Report.WHERE) do
		local label = Text(12)
		label:SetSize(74, LINK_HEIGHT)
		label:SetText(where.label)
		label:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", i == 1 and 16 or 0, i == 1 and -4 or -LINK_GAP)
		local box = LinkBox(panel, where.url, function()
			f.hint:SetText(LINK_COPIED)
		end)
		box:SetPoint("LEFT", label, "RIGHT", 6, 0)
		box:SetPoint("RIGHT", panel, "RIGHT", -SHARE_PAD - 4, 0)
		panel.links[i] = { label = label, box = box }
		previous = label
	end

	-- 3. Post it.
	panel.step3 = Text(12)
	panel.step3:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -16, -10)

	-- What's in a report, and what isn't: said plainly, at the foot.
	panel.privacy = Text(11)
	panel.privacy:SetPoint("TOPLEFT", panel.step3, "BOTTOMLEFT", 0, -8)
	panel.privacy:SetText("A report holds fishing numbers only: no character name, realm, guild, account or anything "
		.. "else that could identify you, and nothing is sent unless you paste it yourself.")
	return panel
end

local STEP1 = "%s1.|r  Select your report, then press %sCtrl+C|r to copy it."
local STEP2 = "%s2.|r  Click a link, press %sCtrl+C|r, and open it in your browser."
local STEP3 = "%s3.|r  Paste it into a new comment or issue, and post it. Thank you!"

-- The panel's in the book's ink, and it's sized to its text.
local function InkShare(panel)
	local theme = ns.Theme.Current()
	for _, fs in ipairs(panel.texts) do
		fs:SetTextColor(theme.ink[1], theme.ink[2], theme.ink[3])
	end
	panel.privacy:SetTextColor(theme.inkSoft[1], theme.inkSoft[2], theme.inkSoft[3])
	panel.step1:SetText(string.format(STEP1, theme.lead, theme.lead))
	panel.step2:SetText(string.format(STEP2, theme.lead, theme.lead))
	panel.step3:SetText(string.format(STEP3, theme.lead))
	local height = SHARE_PAD + panel.step1:GetStringHeight() + 4 + 22 + 10 + panel.step2:GetStringHeight() + 4
		+ #panel.links * (LINK_HEIGHT + LINK_GAP) - LINK_GAP + 10 + panel.step3:GetStringHeight()
		+ 8 + panel.privacy:GetStringHeight() + SHARE_PAD
	panel:SetHeight(height)
end

-- With nothing found: an emblem, a headline, what's been counted so far, and what OneCast is
-- looking for on parchment, so the page says what to do instead of standing empty.
local LOOKING_FOR = {
	{ icon = "Interface\\Icons\\INV_Misc_Map_01", title = "A zone with no known level",
		text = "Ten catches somewhere OneCast has no fishing level for." },
	{ icon = "Interface\\Icons\\Trade_Fishing", title = "A fish getting away where it shouldn't",
		text = "Above a zone's listed level, or never below it." },
	{ icon = "Interface\\Icons\\INV_Box_02", title = "A catch OneCast doesn't have",
		text = "A new fish or treasure, or one it can't place yet." },
	{ item = 279965, icon = "Interface\\Icons\\Spell_Fire_Fire", title = "Fishing with a camp buff",
		text = "Five catches with Uncommon or Rare Fishing on." },
	{ item = 273119, icon = "Interface\\Icons\\INV_Scroll_03", title = "Where a Blueprint drops",
		text = "Loot one, and OneCast notes who dropped it." },
	{ item = 16083, icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Fishing ranks and gear",
		text = "Where ranks are taught, and new fishing gear." },
}
local LOOK_ROW = 38

local function EmptyState(parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(560, 10)

	-- The emblem: the fishing icon in a round frame.
	local emblem = panel:CreateTexture(nil, "ARTWORK")
	emblem:SetSize(52, 52)
	emblem:SetPoint("TOP", 0, -4)
	emblem:SetTexture("Interface\\Icons\\Trade_Fishing")
	if panel.CreateMaskTexture then
		local mask = panel:CreateMaskTexture()
		mask:SetAllPoints(emblem)
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		emblem:AddMaskTexture(mask)
	end
	-- A gold ring round it: a slightly bigger gold disc behind, cut round the same way.
	local ring = panel:CreateTexture(nil, "BORDER")
	ring:SetSize(60, 60)
	ring:SetPoint("CENTER", emblem, "CENTER")
	ring:SetColorTexture(0.85, 0.65, 0.25, 0.9)
	if panel.CreateMaskTexture then
		local mask = panel:CreateMaskTexture()
		mask:SetAllPoints(ring)
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		ring:AddMaskTexture(mask)
	else
		ring:Hide()
	end

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("TOP", emblem, "BOTTOM", 0, -12)
	panel.title:SetText("Nothing new to share yet")
	panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.sub:SetPoint("TOP", panel.title, "BOTTOM", 0, -6)
	panel.sub:SetText("Everything you've fished matches what OneCast knows.")
	panel.count = panel:CreateFontString(nil, "OVERLAY", "OneCastFontDisableSmall")
	panel.count:SetPoint("TOP", panel.sub, "BOTTOM", 0, -6)

	-- What to look out for, on parchment like the share steps.
	local paper = CreateFrame("Frame", nil, panel)
	paper:SetPoint("TOP", panel.count, "BOTTOM", 0, -16)
	paper:SetPoint("LEFT", panel, "LEFT")
	paper:SetPoint("RIGHT", panel, "RIGHT")
	paper:SetHeight(SHARE_PAD + 20 + #LOOKING_FOR * LOOK_ROW + SHARE_PAD - 6)
	local bg = paper:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if ns.UI.HasAtlas("QuestBG-Parchment") then
		bg:SetAtlas("QuestBG-Parchment")
	else
		bg:SetTexture("Interface\\QuestFrame\\QuestBG")
		bg:SetTexCoord(0, 0.586, 0, 0.65)
	end
	local edge = paper:CreateTexture(nil, "BORDER")
	edge:SetColorTexture(0.55, 0.40, 0.15, 0.8)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(3)
	panel.texts, panel.softs = {}, {}
	paper.heading = Ink(paper:CreateFontString(nil, "OVERLAY"), 14)
	paper.heading:SetPoint("TOPLEFT", SHARE_PAD, -SHARE_PAD)
	paper.heading:SetText("OneCast is looking for")
	panel.texts[#panel.texts + 1] = paper.heading
	for i, look in ipairs(LOOKING_FOR) do
		local top = -(SHARE_PAD + 24 + (i - 1) * LOOK_ROW)
		local icon = paper:CreateTexture(nil, "ARTWORK")
		icon:SetSize(26, 26)
		icon:SetPoint("TOPLEFT", SHARE_PAD + 2, top)
		icon:SetTexture(look.item and C_Item.GetItemIconByID(look.item) or look.icon)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local title = Ink(paper:CreateFontString(nil, "OVERLAY"), 12)
		title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
		title:SetPoint("RIGHT", paper, "RIGHT", -SHARE_PAD, 0)
		title:SetWordWrap(false)
		title:SetText(look.title)
		local text = Ink(paper:CreateFontString(nil, "OVERLAY"), 11)
		text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
		text:SetPoint("RIGHT", paper, "RIGHT", -SHARE_PAD, 0)
		text:SetWordWrap(false)
		text:SetText(look.text)
		panel.texts[#panel.texts + 1] = title
		panel.softs[#panel.softs + 1] = text
	end
	panel.paper = paper
	panel:SetHeight(4 + 52 + 12 + 18 + 6 + 14 + 6 + 12 + 16 + paper:GetHeight())
	return panel
end

local function InkEmpty(panel)
	local theme = ns.Theme.Current()
	for _, fs in ipairs(panel.texts) do
		fs:SetTextColor(theme.ink[1], theme.ink[2], theme.ink[3])
	end
	for _, fs in ipairs(panel.softs) do
		fs:SetTextColor(theme.inkSoft[1], theme.inkSoft[2], theme.inkSoft[3])
	end
end

-- "Keeping count: 1,204 catches and 37 getaways in 12 zones on this character."
local function CountLine()
	local catches, escapes, zones = 0, 0, 0
	for _, z in pairs(OneCastCharDB and OneCastCharDB.zoneStats or {}) do
		if (z.catches or 0) > 0 or (z.escapes or 0) > 0 then
			zones = zones + 1
		end
		catches = catches + (z.catches or 0)
		escapes = escapes + (z.escapes or 0)
	end
	if catches == 0 and escapes == 0 then
		return "Go fishing: OneCast keeps count as you do."
	end
	local function n(v, one, many)
		return (BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v)) .. " " .. (v == 1 and one or many)
	end
	return string.format("Keeping count: %s and %s in %s on this character.",
		n(catches, "catch", "catches"), n(escapes, "getaway", "getaways"), n(zones, "zone", "zones"))
end

-- What a finding is about, for its row's icon: the fish's own, the craft's, or a map.
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local function FindingIcon(key)
	local kind, a = key:match("^(%a+):([^:]+)")
	if kind == "place" or kind == "fish" or kind == "item" or kind == "confirm" or kind == "drop" then
		return C_Item.GetItemIconByID(tonumber(a)) or MAP_ICON
	elseif kind == "journey" then
		-- Gear by its own icon; ranks and spells by the Fisherman's journey's book.
		local id = a == "gear" and tonumber(key:match("^journey:gear:(%d+)") or "")
		return C_Item.GetItemIconByID(id or 16083) or MAP_ICON
	elseif kind == "camp" then
		for _, craft in ipairs(ns.Camp and ns.Camp.CRAFTS or {}) do
			if craft.key == a then
				return C_Item.GetItemIconByID(craft.item) or MAP_ICON
			end
		end
	end
	return MAP_ICON
end

local KIND_LABEL = {
	level = "Zone level",
	above = "Zone level",
	below = "Zone level",
	place = "Where it's found",
	item = "New catch",
	confirm = "Seen in Forever",
	drop = "Where it drops",
	journey = "Journey",
	fish = "New fish",
	camp = "Camp buff",
}

-- A finding's name in its item's quality colour, where it's an item.
local function FindingTitle(finding)
	local title = finding.title or finding.text
	local kind, a = finding.key:match("^(%a+):([^:]+)")
	local id = tonumber(a or "")
	if kind == "journey" then
		id = tonumber(finding.key:match("^journey:gear:(%d+)") or "")
	elseif kind ~= "place" and kind ~= "fish" and kind ~= "item" and kind ~= "confirm" and kind ~= "drop" then
		id = nil
	end
	local quality = id and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return (color and color.hex or "|cffffffff") .. title .. "|r"
end

local function FindingRow(parent, index, y)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", EDGE, y)
	row:SetSize(FOUND_WIDTH, NEW_ROW_HEIGHT - 2)
	ns.UI.RowBackground(row, index)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(34, 34)
	row.icon:SetPoint("TOPLEFT", 6, -6)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- Top line: what it is; right of it, the kind of finding and whether it's been shared. Under
	-- it, what it means, over two lines where it needs them.
	row.tag = row:CreateFontString(nil, "OVERLAY", "OneCastFontNormalSmall")
	row.tag:SetPoint("TOPRIGHT", -8, -6)
	row.kind = row:CreateFontString(nil, "OVERLAY", "OneCastFontNormalSmall")
	row.kind:SetPoint("RIGHT", row.tag, "LEFT", -8, 0)
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 1)
	row.title:SetPoint("RIGHT", row.kind, "LEFT", -6, 0)
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)
	row.text = row:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
	row.text:SetPoint("RIGHT", -8, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetJustifyV("TOP")
	row.text:SetWordWrap(true)
	if row.text.SetMaxLines then
		row.text:SetMaxLines(2)
	end
	row.text:SetSpacing(1)
	row.text:SetTextColor(0.82, 0.82, 0.82)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if not self.finding then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local kind = self.finding.key:match("^(%a+)")
		GameTooltip:SetText(FindingTitle(self.finding))
		GameTooltip:AddLine(KIND_LABEL[kind] or "New to OneCast", 1, 0.82, 0)
		GameTooltip:AddLine(self.finding.detail or self.finding.text, 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("In the report: " .. self.finding.text, 0.6, 0.6, 0.6, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(self.shared and "Already in a report you copied." or "Not shared yet: copy your report to send it.",
			0.6, 0.8, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function FillFindingRow(row, finding, shared)
	row.finding, row.shared = finding, shared
	row.icon:SetTexture(FindingIcon(finding.key))
	row.icon:Show()
	local kind = finding.key:match("^(%a+)")
	row.kind:SetText(KIND_LABEL[kind] or "")
	row.title:SetText(FindingTitle(finding))
	row.text:SetText(finding.detail or finding.text)
	row.tag:SetText(shared and "|cff9d9d9dShared|r" or "|cff20ff20New|r")
	row:Show()
end

local frame
local FillFindings -- below; copying the report redraws the list with it

local function CreateWindow()
	local UI = ns.UI
	local f, inset = UI.CreateShell("OneCastReportFrame", "OneCast data report", "Interface\\Icons\\INV_Misc_Note_01")
	f:SetSize(WINDOW_WIDTH, ns.UI.PAGE_HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	ns.UI.RememberPosition(f, "report")

	-- Right of the portrait, above the inset: what this window is for.
	f.status = f:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 62, 6)
	f.status:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
	f.status:SetJustifyH("LEFT")
	f.status:SetWordWrap(false)

	-- 1. What you've found: the left column.
	local y = -GAP
	f.newHeader = UI.SectionHeader(inset, y)
	f.newHeader:ClearAllPoints()
	f.newHeader:SetPoint("TOPLEFT", EDGE, y)
	f.newHeader:SetWidth(FOUND_WIDTH)
	y = y - HEADER_HEIGHT - HEADER_GAP
	f.rows = {}
	for i = 1, NEW_ROWS do
		f.rows[i] = FindingRow(inset, i, y - (i - 1) * NEW_ROW_HEIGHT)
	end
	f.empty = EmptyState(inset)
	-- Centred in the room under the header.
	f.empty:SetPoint("CENTER", inset, "CENTER", 0, y / 2)
	InkEmpty(f.empty)
	f.empty:Hide()
	f.listTop = y
	-- Between the columns, the window's gold rule.
	f.divider = inset:CreateTexture(nil, "BORDER")
	f.divider:SetColorTexture(0.62, 0.48, 0.24, 0.5)
	f.divider:SetPoint("TOPLEFT", EDGE + FOUND_WIDTH + GAP, -GAP)
	f.divider:SetPoint("BOTTOMLEFT", EDGE + FOUND_WIDTH + GAP, EDGE)
	f.divider:SetWidth(1)

	-- 2. Share it: placed under however much the list above shows (PlaceShare).
	f.shareHeader = UI.SectionHeader(inset, y)
	f.shareHeader.text:SetText("Share it")
	f.share = SharePanel(f, inset)
	InkShare(f.share)

	-- 3. The report text, under the panel, in its own sunken box.
	local textHeader = UI.SectionHeader(inset, 0)
	textHeader:ClearAllPoints()
	textHeader:SetPoint("TOPLEFT", f.share, "BOTTOMLEFT", 0, -GAP)
	textHeader:SetPoint("TOPRIGHT", f.share, "BOTTOMRIGHT", 0, -GAP)
	textHeader.text:SetText("Report text")
	f.textHeader = textHeader
	local box = UI.TryCreate("Frame", nil, inset, "InsetFrameTemplate") or CreateFrame("Frame", nil, inset)
	box:SetPoint("TOPLEFT", textHeader, "BOTTOMLEFT", 0, -HEADER_GAP)
	box:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	f.textBox = box
	-- The game's slim modern scroll bar, or the classic one where that template is missing.
	local scroll = UI.TryCreate("ScrollFrame", "OneCastReportScroll", box, "ScrollFrameTemplate")
		or UI.TryCreate("ScrollFrame", "OneCastReportScroll", box, "UIPanelScrollFrameTemplate")
		or CreateFrame("ScrollFrame", "OneCastReportScroll", box)
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -22, 6)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(OneCastFontHighlightSmall)
	edit:SetWidth(SIDE_WIDTH - 30)
	edit:SetMaxLetters(0)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	-- Read-only, and all of it selected whenever it's clicked, ready to copy.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(f.text or "")
			self:HighlightText()
		end
	end)
	edit:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	edit:SetScript("OnKeyDown", function(_, key)
		if key == "C" and IsControlKeyDown() then
			f.hint:SetText(COPIED)
			Report.MarkShared()
			FillFindings(f)
			if ns.Stats and ns.Stats.RefreshIfShown then
				ns.Stats.RefreshIfShown()
			end
			if ns.Book and ns.Book.RefreshIfShown then
				ns.Book.RefreshIfShown()
			end
		end
	end)
	scroll:SetScrollChild(edit)
	-- A click anywhere in the box, not just on the text, focuses it.
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)
	f.box = edit

	f.select:SetScript("OnClick", function()
		edit:SetFocus()
		edit:HighlightText()
		f.hint:SetText(SELECTED)
	end)

	-- Along the bottom: what to do next, as you go.
	f.hint = f:CreateFontString(nil, "OVERLAY", "OneCastFontDisableSmall")
	f.hint:SetPoint("BOTTOMLEFT", 14, 9)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -22, 0) -- clear of the resize grip
	f.hint:SetJustifyH("LEFT")
	f.hint:SetWordWrap(false)
	f:Hide()
	ns.Hub.Attach("report", f)
	return f
end

-- The share steps at the top of the right column; the report text below gets the rest of it.
local function PlaceShare(f)
	local y = -GAP
	f.shareHeader:ClearAllPoints()
	f.shareHeader:SetPoint("TOPLEFT", SIDE_LEFT, y)
	f.shareHeader:SetPoint("TOPRIGHT", -EDGE, y)
	y = y - HEADER_HEIGHT - HEADER_GAP
	f.share:ClearAllPoints()
	f.share:SetPoint("TOPLEFT", SIDE_LEFT, y)
	f.share:SetPoint("TOPRIGHT", -EDGE, y)
end

FillFindings = function(f)
	local findings = Report.Findings()
	local shared = OneCastCharDB and OneCastCharDB.reportFindings and OneCastCharDB.reportFindings.shared or {}
	-- Not yet shared first, as that's what's worth sending; otherwise in the report's order.
	local order = {}
	for i, finding in ipairs(findings) do
		order[finding] = i
	end
	table.sort(findings, function(a, b)
		local sa, sb = shared[a.key] and 1 or 0, shared[b.key] and 1 or 0
		if sa ~= sb then
			return sa < sb
		end
		return order[a] < order[b]
	end)
	local fresh = 0
	for _, finding in ipairs(findings) do
		if not shared[finding.key] then
			fresh = fresh + 1
		end
	end
	f.newHeader.text:SetText(fresh > 0 and string.format("What you've found  |cff20ff20(%d to share)|r", fresh)
		or "What you've found")
	f.status:SetText(fresh > 0 and string.format("You've found %d thing%s OneCast doesn't know yet.", fresh, fresh == 1 and "" or "s")
		or "Help fill in Forever's real fishing numbers.")
	local shown = math.min(#findings, NEW_ROWS)
	if #findings > NEW_ROWS then
		shown = NEW_ROWS - 1
	end
	for i, row in ipairs(f.rows) do
		local finding = findings[i]
		if i <= shown and finding then
			FillFindingRow(row, finding, shared[finding.key])
		elseif i == shown + 1 and #findings > shown then
			row.icon:Hide()
			row.title:SetText(string.format("|cff9d9d9dAnd %d more|r", #findings - shown))
			row.text:SetText("|cff9d9d9dThey're all in the report text below.|r")
			row.kind:SetText("")
			row.tag:SetText("")
			row.finding = nil
			row:Show()
		else
			row:Hide()
		end
	end
	-- Nothing found means nothing worth sending: no share steps and no report text until there is.
	local nothing = #findings == 0
	f.nothing = nothing
	f.empty:SetShown(nothing)
	if nothing then
		f.empty.count:SetText(CountLine())
	end
	f.shareHeader:SetShown(not nothing)
	f.share:SetShown(not nothing)
	f.textHeader:SetShown(not nothing)
	f.textBox:SetShown(not nothing)
	-- With nothing to share, one column: the header across the window over what to look for.
	f.divider:SetShown(not nothing)
	f.newHeader:ClearAllPoints()
	f.newHeader:SetPoint("TOPLEFT", EDGE, -GAP)
	if nothing then
		f.newHeader:SetPoint("TOPRIGHT", -EDGE, -GAP)
	else
		f.newHeader:SetWidth(FOUND_WIDTH)
	end
	PlaceShare(f)
end

local function Fill(f)
	FillFindings(f)
	f.text = Report.Text()
	f.box:SetText(f.text)
	f.box:SetCursorPosition(0)
	f.hint:SetText(f.nothing and HINT_NOTHING or HINT)
	InkShare(f.share)
end


-- After a catch or getaway, an open window keeps up.
function Report.RefreshIfShown()
	-- Not while the text is selected for copying: redrawing would lose the selection.
	if frame and frame:IsShown() and not (frame.box.HasFocus and frame.box:HasFocus()) then
		Fill(frame)
	end
end

function Report.Show()
	frame = frame or CreateWindow()
	Fill(frame)
	frame:Show()
end

function Report.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Report.Show()
	end
end

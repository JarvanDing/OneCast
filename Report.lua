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
-- Worth sharing, so worth saying: once in chat when each is first found, and as a count on
-- the minimap button until the report is copied.

local MIN_UNKNOWN_LEVEL = 10 -- catches in a zone with no known level
local MIN_BELOW_LEVEL = 20   -- catches without a getaway below a zone's listed level
local MIN_CAMP = 5           -- catches under a camp buff

-- A collection fish the book can't say where to find: no zones at all, from any source. Only
-- these are worth a report when caught: a known fish in one more zone helps nobody find it.
local function Unplaced(fish)
	return not (fish.zones and fish.zones[1]) and not (fish.more and fish.more[1])
end

local function ItemName(id, item)
	return (type(item) == "table" and item.name) or C_Item.GetItemNameByID(id) or ("item " .. id)
end

-- Every finding, as { key, text, zone }: the key stays the same while the finding does. The
-- minimap button, stats window, book and this window can all ask in one redraw, so the list is
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
	local function add(key, text, zone)
		found[#found + 1] = { key = key, text = text, zone = zone }
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
				add("level:" .. zone, string.format("%d catches in %s, which has no known fishing level", z.catches, zone), zone)
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
					zone, highestAway, highestAway + step - 1, listed), zone)
			end
			-- Plenty of catches below the listed level, none getting away there, says it's lower.
			local below, lowest = 0, nil
			for bucket, n in pairs(z.skillCatches or {}) do
				if bucket + step <= listed and not (highestAway and bucket <= highestAway) then
					below = below + n
					lowest = math.min(lowest or bucket, bucket)
				end
			end
			if below >= MIN_BELOW_LEVEL then
				add("below:" .. zone, string.format("%d catches in %s from skill %d with no getaways, though OneCast lists %d",
					below, zone, lowest, listed), zone)
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
		add("fish:" .. entry.id, string.format("%s, which isn't in OneCast's collection%s", entry.name or ("item " .. entry.id),
			#where > 0 and (" (caught in " .. table.concat(where, ", ") .. ")") or ""))
	end
	for _, craft in ipairs(ns.Camp and ns.Camp.CRAFTS or {}) do
		local r = craft.buff and ns.Camp.Record(craft.key)
		if r and r.catches >= MIN_CAMP then
			add("camp:" .. craft.key, string.format("%d catches with %s on", r.catches, craft.buffName))
		end
	end
	for _, zone in ipairs(zoneNames) do
		for id, item in pairs(OneCastCharDB.zoneStats[zone].items or {}) do
			local fish = ns.FISH_BY_ID and ns.FISH_BY_ID[id]
			if fish and Unplaced(fish) and (item.count or 0) > 0 then
				add("place:" .. id .. ":" .. zone, string.format("%s caught in %s: OneCast doesn't know where it's found yet",
					ItemName(id, item), zone), zone)
			end
		end
	end
	return found
end

local function Seen()
	local charDB = OneCastCharDB
	charDB.reportFindings = charDB.reportFindings or { said = {}, shared = {} }
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

-- Unshared findings by zone: { [zone] = { finding, ... } }, for the book's Zones tab.
function Report.UnsharedByZone()
	local byZone = {}
	for _, f in ipairs(Report.Unshared()) do
		if f.zone then
			byZone[f.zone] = byZone[f.zone] or {}
			table.insert(byZone[f.zone], f)
		end
	end
	return byZone
end

-- What a window's tooltip says about sharing: a line, or nil with nothing new.
function Report.TooltipLine()
	local n = #Report.Unshared()
	if n == 0 then
		return nil
	end
	return string.format("You have %d thing%s OneCast doesn't know yet. Sharing your report helps fill in Forever's numbers.",
		n, n == 1 and "" or "s")
end

-- After a catch or getaway: say anything newly found, once each.
function Report.Check()
	Report.Forget()
	if ns.Hub and ns.Hub.UpdateBadges then
		ns.Hub.UpdateBadges()
	end
	if Report.RefreshIfShown then
		Report.RefreshIfShown()
	end
	if not (OneCastCharDB and ns.db and ns.db.reportHint) then
		return
	end
	local said = Seen().said
	local fresh = {}
	for _, f in ipairs(Report.Unshared()) do
		if not said[f.key] then
			said[f.key] = true
			fresh[#fresh + 1] = f
		end
	end
	if #fresh == 1 then
		ns.Print("you've found something OneCast doesn't know yet: " .. fresh[1].text .. ". /onecast report to share it.")
	elseif #fresh > 1 then
		ns.Print(string.format("you've found %d things OneCast doesn't know yet, like: %s. /onecast report to share them.",
			#fresh, fresh[1].text))
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
		seen.said[f.key] = true
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
-- Three parts, top to bottom: what you've found, how to share it (the steps, with the button and
-- links in them, on parchment like the book's pages), and the report text itself.

local WINDOW_WIDTH = 440
local EDGE, GAP, HEADER_HEIGHT, HEADER_GAP = 10, 8, 24, 4
local NEW_ROWS, NEW_ROW_HEIGHT = 6, 20
local SHARE_PAD = 12
local LINK_HEIGHT, LINK_GAP = 20, 4
-- Where reports go. The GitHub link opens the repo's Data report issue form.
Report.WHERE = {
	{ label = "CurseForge", url = "https://www.curseforge.com/wow/addons/onecast/comments" },
	{ label = "GitHub", url = "https://github.com/rynmon/OneCast/issues/new?template=data-report.yml" },
}
local HINT = "Ctrl+C copies the report once it's selected."
local SELECTED = "|cffffd100Selected! Now press Ctrl+C to copy.|r"
local COPIED = "|cff1eff00Report copied!|r Now copy a link, open it in your browser and paste."
local LINK_COPIED = "|cff1eff00Link copied!|r Paste it in your browser's address bar."

-- A box holding a web address, read-only, all selected when clicked: WoW can't open links,
-- so copying is the way out.
local function LinkBox(parent, url, onCopy)
	local box = ns.UI.TryCreate("EditBox", nil, parent, "InputBoxTemplate") or CreateFrame("EditBox", nil, parent)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
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

-- Parchment text in the theme's ink.
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
	ns.Theme.Register(bg, "parchment")
	local edge = panel:CreateTexture(nil, "BORDER")
	edge:SetColorTexture(0.55, 0.40, 0.15, 0.8)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(3)

	local width = WINDOW_WIDTH - 10 - 2 * EDGE - 2 * SHARE_PAD
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
	ns.Theme.Register(select, "button")
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

-- The panel's ink follows the theme, as the book's does, and it's sized to its text.
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

-- What a finding is about, for its row's icon: the fish's own, the craft's, or a map.
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local function FindingIcon(key)
	local kind, a = key:match("^(%a+):([^:]+)")
	if kind == "place" or kind == "fish" then
		return C_Item.GetItemIconByID(tonumber(a)) or MAP_ICON
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
	level = "No known level here",
	above = "Level may be higher",
	below = "Level may be lower",
	place = "Where a fish is found",
	fish = "A fish OneCast doesn't have",
	camp = "What a camp buff gives",
}

local function FindingRow(parent, index, y)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", EDGE, y)
	row:SetPoint("TOPRIGHT", -EDGE, y)
	row:SetHeight(NEW_ROW_HEIGHT)
	ns.UI.RowBackground(row, index)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(NEW_ROW_HEIGHT - 4, NEW_ROW_HEIGHT - 4)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.tag:SetPoint("RIGHT", -6, 0)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if not self.finding then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local kind = self.finding.key:match("^(%a+)")
		GameTooltip:SetText(KIND_LABEL[kind] or "New to OneCast")
		GameTooltip:AddLine(self.finding.text, 1, 1, 1, true)
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
	row.text:SetText(finding.text)
	row.tag:SetText(shared and "|cff9d9d9dshared|r" or "|cff1eff00new|r")
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
	tinsert(UISpecialFrames, f:GetName())
	UI.KeepOpenThroughOptions(f:GetName())

	-- Right of the portrait, above the inset: what this window is for.
	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 62, 6)
	f.status:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
	f.status:SetJustifyH("LEFT")
	f.status:SetWordWrap(false)

	-- 1. What you've found.
	local y = -GAP
	f.newHeader = UI.SectionHeader(inset, y)
	y = y - HEADER_HEIGHT - HEADER_GAP
	f.rows = {}
	for i = 1, NEW_ROWS do
		f.rows[i] = FindingRow(inset, i, y - (i - 1) * NEW_ROW_HEIGHT)
	end
	f.empty = inset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.empty:SetPoint("TOPLEFT", EDGE + 12, y - 16)
	f.empty:SetPoint("RIGHT", -(EDGE + 12), 0)
	f.empty:SetJustifyH("CENTER")
	f.empty:SetWordWrap(true)
	f.empty:SetSpacing(3)
	f.empty:SetText("Nothing new yet: everything you've fished matches what OneCast knows.\n"
		.. "|cff9d9d9dA zone with no known level, a fish getting away above a listed level, a fish the collection "
		.. "doesn't have or can't place, or catches with a camp buff will show here.|r")
	y = y - NEW_ROWS * NEW_ROW_HEIGHT - GAP

	-- 2. Share it.
	UI.SectionHeader(inset, y).text:SetText("Share it")
	y = y - HEADER_HEIGHT - HEADER_GAP
	f.share = SharePanel(f, inset)
	f.share:SetPoint("TOPLEFT", EDGE, y)
	f.share:SetPoint("TOPRIGHT", -EDGE, y)
	InkShare(f.share)

	-- 3. The report text, under the panel, in its own sunken box.
	local textHeader = UI.SectionHeader(inset, 0)
	textHeader:ClearAllPoints()
	textHeader:SetPoint("TOPLEFT", f.share, "BOTTOMLEFT", 0, -GAP)
	textHeader:SetPoint("TOPRIGHT", f.share, "BOTTOMRIGHT", 0, -GAP)
	textHeader.text:SetText("Report text")
	local box = UI.TryCreate("Frame", nil, inset, "InsetFrameTemplate") or CreateFrame("Frame", nil, inset)
	box:SetPoint("TOPLEFT", textHeader, "BOTTOMLEFT", 0, -HEADER_GAP)
	box:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	ns.Theme.Panel(box)
	-- The game's slim modern scroll bar, or the classic one where that template is missing.
	local scroll = UI.TryCreate("ScrollFrame", "OneCastReportScroll", box, "ScrollFrameTemplate")
		or UI.TryCreate("ScrollFrame", "OneCastReportScroll", box, "UIPanelScrollFrameTemplate")
		or CreateFrame("ScrollFrame", "OneCastReportScroll", box)
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -22, 6)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlightSmall)
	edit:SetWidth(WINDOW_WIDTH - 10 - 2 * EDGE - 30)
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
	f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.hint:SetPoint("BOTTOMLEFT", 14, 9)
	f.hint:SetPoint("RIGHT", f, "RIGHT", -22, 0) -- clear of the resize grip
	f.hint:SetJustifyH("LEFT")
	f.hint:SetWordWrap(false)
	f:Hide()
	ns.Hub.Attach("report", f)
	return f
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
	f.newHeader.text:SetText(fresh > 0 and string.format("What you've found  |cff1eff00(%d to share)|r", fresh)
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
			row.text:SetText(string.format("|cff9d9d9dand %d more, all in the report text below|r", #findings - shown))
			row.tag:SetText("")
			row.finding = nil
			row:Show()
		else
			row:Hide()
		end
	end
	f.empty:SetShown(#findings == 0)
end

local function Fill(f)
	FillFindings(f)
	f.text = Report.Text()
	f.box:SetText(f.text)
	f.box:SetCursorPosition(0)
	f.hint:SetText(HINT)
	InkShare(f.share)
end

ns.Theme.OnChange(function()
	if frame then
		InkShare(frame.share)
	end
end)

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

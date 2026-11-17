-- OneCast mini mode: a slim bar in place of the stats window while you fish. Your skill and
-- how the zone suits it, the session's catches and rate, your lure, and your wanted list.
-- Opens when you cast if "Mini bar instead of the stats window" is on, and closes when your
-- weapons go back on, as the window does. Click it for the full stats; right-click or its X closes it until the pole comes off.

local _, ns = ...

local Mini = {}
ns.Mini = Mini

local WIDTH = 300
local LATEST_HEIGHT = 28 -- the latest catch's card
local PAD = 8
local MOOD = { good = "|cff20ff20", warn = "|cffffd100", bad = "|cffff2020", unknown = "|cff9d9d9d" }

local frame
local autoOpened = false

local function Line(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "OneCastFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	return fs
end

-- A compact frame of its own: the game's window art is built for full-size windows, and its
-- heavy top and bottom swamp a bar this short. The dialog border, the windows' gilded section
-- band as its title, holding your skill, and a dark panel.
local BORDER = 9         -- inside the dialog border
local BAND_HEIGHT = 22   -- the title band
local TITLE_HEIGHT = BORDER + BAND_HEIGHT + 1 -- from the top to the panel
local BOTTOM = BORDER

local function Create()
	local UI = ns.UI
	local f = CreateFrame("Frame", "OneCastMiniFrame", UIParent, "BackdropTemplate")
	-- The border the game's own popups use; the old dialog border where that template is missing.
	local border = UI and UI.TryCreate and UI.TryCreate("Frame", nil, f, "DialogBorderTemplate")
	if border then
		border:SetAllPoints()
		border:SetFrameLevel(f:GetFrameLevel() + 3)
		-- Only the edge: the panel and band below are the body.
		if border.Bg then
			border.Bg:Hide()
		end
	elseif f.SetBackdrop then
		f:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16,
			insets = { left = BORDER, right = BORDER, top = BORDER, bottom = BORDER } })
	end
	f.border = border
	-- A dark backing for the whole frame, under the border: around the band and behind the X
	-- would otherwise show the world through.
	local backing = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	backing:SetPoint("TOPLEFT", 4, -4)
	backing:SetPoint("BOTTOMRIGHT", -4, 4)
	backing:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
	backing:SetHorizTile(true)
	backing:SetVertTile(true)
	-- The close button inside the top right; the band runs up to it, so both its ends show.
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -BORDER + 1, -BORDER + 1)
	close:SetFrameLevel(f:GetFrameLevel() + 5)
	f.CloseButton = close
	if UI and UI.CloseOwn then
		UI.CloseOwn(f) -- its X works in combat too
	end
	-- Done fishing: weapons and gear back on.
	local done = UI and UI.IconButton and UI.IconButton(f, "Weapons", "完成钓鱼：武器与装备已换回，会话统计会保留直到你重置。", function()
		OneCast_DoneFishing()
	end)
	if done then
		done:SetSize(20, 20)
		done.icon:SetSize(14, 14)
		done:SetPoint("RIGHT", close, "LEFT", -1, 0)
		done:SetFrameLevel(f:GetFrameLevel() + 5)
		f.done = done
	end
	local band = f:CreateTexture(nil, "ARTWORK")
	band:SetPoint("TOPLEFT", BORDER, -BORDER)
	band:SetPoint("RIGHT", done or close, "LEFT", 0, 0)
	band:SetHeight(BAND_HEIGHT)
	if UI and UI.HasAtlas and UI.HasAtlas("UI-Character-Info-Title") then
		band:SetAtlas("UI-Character-Info-Title")
	else
		band:SetColorTexture(0.25, 0.18, 0.10, 0.95)
	end
	f.band = band
	f.titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.titleText:SetPoint("CENTER", band, "CENTER", 0, 1)

	local inset = CreateFrame("Frame", nil, f)
	inset:SetPoint("TOPLEFT", BORDER, -TITLE_HEIGHT)
	inset:SetPoint("BOTTOMRIGHT", -BORDER, BOTTOM)
	local bg = inset:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)
	f.inset = inset
	f:SetSize(WIDTH, 80)
	f:SetPoint("TOP", UIParent, "TOP", 0, -140)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if UI and UI.RememberPosition then
		UI.RememberPosition(f, "mini")
	end
	-- Closed with its X: it stays closed for this stretch of fishing.
	if f.CloseButton then
		f.CloseButton:HookScript("OnClick", function()
			Mini.dismissed = true
			autoOpened = false
		end)
	end

	-- Clicks on the body: the full stats, or close. It drags the window too.
	local body = CreateFrame("Button", nil, inset)
	body:SetAllPoints()
	body:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	body:RegisterForDrag("LeftButton")
	body:SetScript("OnDragStart", function() f:StartMoving() end)
	-- Through the window's own handler, which saves where it was left.
	body:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
	body:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			Mini.dismissed = true
			Mini.Hide()
		elseif ns.Stats and ns.Stats.Show then
			ns.Stats.Show()
		end
	end)
	body:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("哇，大鱼 · 迷你条")
		GameTooltip:AddLine("左键：打开完整统计。右键：关闭。拖动可移动。", 1, 1, 1, true)
		GameTooltip:AddLine("可在「哇，大鱼」选项的「统计窗口」中关闭迷你条。", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	body:SetScript("OnLeave", GameTooltip_Hide)

	-- The zone in words: what it needs, and what that means for you here.
	f.zone = Line(inset)
	f.zone:SetPoint("TOPLEFT", PAD, -PAD + 2)
	f.zone:SetPoint("RIGHT", -PAD, 0)
	f.session = Line(inset)
	f.session:SetPoint("TOPLEFT", f.zone, "BOTTOMLEFT", 0, -3)
	f.session:SetPoint("RIGHT", -PAD, 0)
	-- The latest catch, as a small card under the session.
	f.latest = CreateFrame("Frame", nil, inset)
	f.latest:SetHeight(LATEST_HEIGHT)
	f.latest:SetPoint("TOPLEFT", f.session, "BOTTOMLEFT", 0, -4)
	f.latest:SetPoint("RIGHT", -PAD, 0)
	f.latest.icon = f.latest:CreateTexture(nil, "ARTWORK")
	f.latest.icon:SetSize(LATEST_HEIGHT - 2, LATEST_HEIGHT - 2)
	f.latest.icon:SetPoint("LEFT", 0, 0)
	f.latest.border = f.latest:CreateTexture(nil, "OVERLAY")
	f.latest.border:SetAllPoints(f.latest.icon)
	f.latest.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	f.latest.name = Line(f.latest, "GameFontHighlight")
	f.latest.name:SetPoint("TOPLEFT", f.latest.icon, "TOPRIGHT", 6, -1)
	f.latest.name:SetPoint("RIGHT", 0, 0)
	f.latest.sub = Line(f.latest, "OneCastFontHighlightSmall")
	f.latest.sub:SetTextColor(0.78, 0.78, 0.78)
	f.latest.sub:SetPoint("BOTTOMLEFT", f.latest.icon, "BOTTOMRIGHT", 6, 1)
	f.latest.sub:SetPoint("RIGHT", 0, 0)
	f.latest:Hide()
	f.lure = Line(inset)
	f.lure:SetPoint("RIGHT", -PAD, 0)
	-- The Fishing Extravaganza: while it runs, or in the hours before.
	f.contest = Line(inset)
	f.contest:SetPoint("RIGHT", -PAD, 0)
	f.goals = {}

	-- Lure time and rates tick over: redraw once a second while shown.
	local since = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since >= 1 then
			since = 0
			Mini.Refresh()
		end
	end)
	f:Hide()
	return f
end

local function GoalLine(i)
	local fs = frame.goals[i]
	if not fs then
		fs = Line(frame.inset)
		fs:SetPoint("RIGHT", -PAD, 0)
		frame.goals[i] = fs
	end
	return fs
end

-- "Tanaris needs 300: no fish get away", "Riverglades needs 225: 44 short, fish get away".
local function ZoneLine(zone, badge)
	local status = ns.Stats.ZoneStatus(zone)
	local place = badge.place or zone
	local said
	if status.kind == "ok" then
		said = string.format("%s 需 %d：鱼不应脱钩", place, status.needed)
	elseif status.kind == "short" then
		said = string.format("%s 需 %d：还差 %d，鱼会脱钩", place, status.needed, status.short)
	elseif status.kind == "getaways" then
		said = place .. "：此处曾脱钩，技能偏低"
	elseif status.kind == "clear" then
		said = place .. "：等级未知，尚无脱钩"
	elseif status.kind == "note" then
		said = place .. "：无最低技能要求"
	elseif status.kind == "outgrown" then
		said = place .. "：等级未知，已超过上次脱钩时的水平"
	else
		said = place .. "：钓鱼等级未知"
	end
	return (MOOD[badge.mood] or "") .. said .. "|r"
end

function Mini.Refresh()
	if not (frame and frame:IsShown()) or not ns.Stats then
		return
	end
	local Stats = ns.Stats
	local rank, maxRank, modifier = Stats.FishingSkill()
	frame.titleText:SetText(rank and string.format("%s %d/%d%s", ns.GetFishingName and ns.GetFishingName() or "Fishing",
		rank, maxRank, (modifier or 0) > 0 and string.format(" |cff20ff20+%d|r", modifier) or "") or (ns.GetFishingName and ns.GetFishingName() or "钓鱼"))
	local zone = Stats.CurrentZone()
	local badge = zone and Stats.ZoneBadge(zone)
	frame.zone:SetText(badge and ZoneLine(zone, badge) or "")
	frame.session:SetText(Stats.Summary() or "|cff9d9d9d本会话尚未抛竿。|r")
	-- The latest catch: its icon, its name, and when.
	local last = Stats.LatestCatch and Stats.LatestCatch()
	local card = frame.latest
	card:SetShown(last and true or false)
	if last then
		card.icon:SetTexture(last.icon)
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[last.quality or 1]
		card.name:SetText(last.name or "?")
		card.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
		card.border:SetVertexColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
		card.sub:SetText("最近渔获  ·  " .. Stats.Since(last.time) .. ((last.quantity or 1) > 1 and ("  ·  x" .. last.quantity) or ""))
	end
	local lure, problem
	if ns.Lure then
		lure, problem = ns.Lure.StatusLine()
	end
	frame.lure:SetText(lure and ((problem and "|cffff2020" or "|cffd0d0d0") .. "诱饵：" .. lure .. "|r") or "")

	-- The wanted list: what's still wanted first.
	local list = {}
	for id, w in pairs(Stats.Wanted and Stats.Wanted() or {}) do
		list[#list + 1] = { id = id, g = w }
	end
	table.sort(list, function(a, b)
		local da, db = a.g.target and a.g.got >= a.g.target or false, b.g.target and b.g.got >= b.g.target or false
		if da ~= db then
			return not da
		end
		return (a.g.name or "") < (b.g.name or "")
	end)
	local below = last and frame.latest or frame.session
	frame.lure:ClearAllPoints()
	frame.lure:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, last and -4 or -3)
	frame.lure:SetPoint("RIGHT", -PAD, 0)
	local previous = lure and frame.lure or below
	local lines = (lure and 3 or 2)
	-- The Extravaganza, when there's something to say about it.
	local contest = ns.Extravaganza and ns.Extravaganza.StatusLine and ns.Extravaganza.StatusLine(zone)
	frame.contest:ClearAllPoints()
	frame.contest:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
	frame.contest:SetPoint("RIGHT", -PAD, 0)
	frame.contest:SetText(contest and ("|cffffd100钓鱼大赛：|r " .. contest) or "")
	frame.contest:SetShown(contest ~= nil)
	if contest then
		previous = frame.contest
		lines = lines + 1
	end
	for i, entry in ipairs(list) do
		local fs = GoalLine(i)
		local g = entry.g
		local icon = C_Item.GetItemIconByID(entry.id)
		local done = g.target and g.got >= g.target
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
		fs:SetPoint("RIGHT", -PAD, 0)
		local count = g.target and string.format("%s%d/%d|r", done and "|cff20ff20" or "|cff71d5ff", math.min(g.got, g.target), g.target)
			or ((g.got or 0) > 0 and string.format("|cffffd100x%d|r", g.got) or "|cffffd100想要|r")
		fs:SetText(string.format("%s%s  %s", icon and ("|T" .. icon .. ":12:12:0:0:64:64:5:59:5:59|t ") or "",
			g.name or C_Item.GetItemNameByID(entry.id) or ("item " .. entry.id), count))
		fs:Show()
		previous = fs
		lines = lines + 1
	end
	for i = #list + 1, #frame.goals do
		frame.goals[i]:Hide()
	end
	-- With a controller: what the buttons do, in a legend under the bar, as under the windows.
	if ns.Controller and ns.Controller.UpdateMiniLegend then
		ns.Controller.UpdateMiniLegend(frame)
	end
	frame.lure:SetShown(lure ~= nil)
	-- The title, the lines (12 high, 3 apart) with a little room above and below, the border.
	frame:SetHeight(TITLE_HEIGHT + BOTTOM + 6 + lines * 12 + (lines - 1) * 3 + 7 + (last and (LATEST_HEIGHT + 4) or 0))
end

function Mini.Show(auto)
	frame = frame or Create()
	autoOpened = auto and true or false
	frame:Show()
	Mini.Refresh()
end

-- Done fishing, kept open: no longer closing itself when the weapons go back on.
function Mini.KeepOpen()
	autoOpened = false
end

function Mini.Hide()
	autoOpened = false
	if frame then
		frame:Hide()
	end
end

function Mini.Frame()
	return frame
end

function Mini.IsShown()
	return frame and frame:IsShown() or false
end

-- From the stats' cast handling: open in place of the window when mini mode is on.
function Mini.OnCast()
	if Mini.dismissed then
		return
	end
	if not Mini.IsShown() then
		Mini.Show(true)
	else
		Mini.Refresh()
	end
end

-- Weapons back on after fishing: a bar that opened itself closes itself.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:SetScript("OnEvent", function()
	C_Timer.After(0.2, function()
		if not (ns.HasFishingPole and not ns.HasFishingPole()) then
			return
		end
		-- The pole's off: closing it by hand only lasted this stretch of fishing.
		Mini.dismissed = false
		if autoOpened and Mini.IsShown() and ns.db and ns.db.closeOnDone then
			Mini.Hide()
		end
	end)
end)

-- Skill-ups ----------------------------------------------------------------------------------
-- "+1 Fishing" rising and fading on screen when your skill goes up: over the mini bar when it's
-- open, else high in the middle of the screen. Off with "Skill-up pop-up" (skillToast).
local toast

local function CreateToast()
	local t = CreateFrame("Frame", "OneCastSkillToast", UIParent)
	t:SetSize(260, 44)
	t:SetFrameStrata("HIGH")
	t:EnableMouse(false)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetSize(30, 30)
	t.icon:SetPoint("LEFT", 0, 0)
	t.icon:SetTexture("Interface\\Icons\\Trade_Fishing")
	t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	t.title = t:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	t.title:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 8, 2)
	t.sub = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t.sub:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -1)
	t:SetAlpha(0)
	t:Hide()
	local anim = t:CreateAnimationGroup()
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.25)
	fadeIn:SetOrder(1)
	local rise = anim:CreateAnimation("Translation")
	rise:SetOffset(0, 26)
	rise:SetDuration(2.4)
	rise:SetSmoothing("OUT")
	rise:SetOrder(1)
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetStartDelay(1.8)
	fadeOut:SetDuration(0.6)
	fadeOut:SetOrder(1)
	anim:SetScript("OnPlay", function()
		t:SetAlpha(1)
	end)
	anim:SetScript("OnFinished", function()
		t:SetAlpha(0)
		t:Hide()
	end)
	t.anim = anim
	return t
end

function Mini.SkillToast(gained, rank, maxRank)
	if ns.db and ns.db.skillToast == false then
		return
	end
	toast = toast or CreateToast()
	local name = ns.GetFishingName and ns.GetFishingName() or "钓鱼"
	toast.title:SetText(string.format("+%d %s", gained, name))
	toast.sub:SetText(maxRank and string.format("%d / %d", rank, maxRank) or tostring(rank))
	toast:ClearAllPoints()
	if Mini.IsShown() then
		toast:SetPoint("BOTTOM", frame, "TOP", 0, 6)
	else
		toast:SetPoint("CENTER", UIParent, "CENTER", 0, 210)
	end
	toast.anim:Stop()
	toast:Show()
	toast.anim:Play()
end

-- OneCast hub: every OneCast window as one, with side tabs to move between them.
--
-- The stats window, tackle box, collection book, data report and What's new stay their own
-- frames, so everything inside them works as before. The hub makes them act as one window:
-- only one is open at a time, each opens where the last one was (dragging any of them moves
-- "the window"), and a rail of side tabs on the open one's right edge switches between them.
-- Every page is the same height, so switching only changes the width. The Options tab has every
-- setting, built from the same description as the game's options panel.

local _, ns = ...

local Hub = {}
ns.Hub = Hub

local TAB_SIZE, TAB_GAP = 32, 14
local RAIL_TOP = 48 -- below the window's title bar
local RAIL_TOP_LEFT = 72 -- below the portrait, on the left

-- The tabs, top to bottom. `open` shows that panel; the panel registers itself with Attach.
local TABS = {
	{ key = "session", label = "统计", icon = "Interface\\Icons\\INV_Misc_Fish_68",
		open = function() ns.Stats.Show() end },
	{ key = "tackle", label = "工具箱", icon = 466035,
		open = function() ns.TackleBox.ShowWindow() end },
	{ key = "collection", label = "钓鱼图鉴", icon = "Interface\\Icons\\INV_Misc_Book_09",
		open = function() ns.Book.ShowCollection() end },
	{ key = "camp", label = "营地", item = 279966, icon = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth",
		open = function() ns.Book.ShowCamp() end },
	{ key = "report", label = "数据报告", icon = "Interface\\Icons\\INV_Letter_15",
		open = function() ns.Report.Show() end },
	{ key = "news", label = "更新内容", icon = "Interface\\Icons\\INV_Misc_Note_01",
		open = function() ns.WhatsNew.Show() end },
	{ key = "options", label = "选项", icon = "Interface\\Icons\\INV_Misc_Gear_01",
		open = function() Hub.ShowOptions() end },
}

local panels = {}    -- frame -> function returning its tab key
local tabsByKey = {} -- key -> TABS entry
local active         -- the panel open now
local rail

-- Where the window's top-left corner is, in UIParent's units, shared by every panel.
local function SavedPoint()
	return ns.db and ns.db.windowPoints and ns.db.windowPoints.hub
end

local function SavePoint(frame)
	local left, top, scale = frame:GetLeft(), frame:GetTop(), frame:GetScale()
	if not (left and top and scale and ns.db) then
		return
	end
	ns.db.windowPoints = ns.db.windowPoints or {}
	ns.db.windowPoints.hub = { left * scale, top * scale }
end

local function PlaceAtPoint(frame)
	local point = SavedPoint()
	local scale = frame:GetScale() or 1
	if not point then
		SavePoint(frame) -- the first panel opened sets where the window is
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", point[1] / scale, point[2] / scale)
end

-- The rail ----------------------------------------------------------------------------------

for _, def in ipairs(TABS) do
	tabsByKey[def.key] = def
end

-- The page open now, by its tab's key.
local function CurrentKey()
	return active and panels[active] and panels[active]()
end

-- A green dot on a tab with something waiting: findings to share, a version not yet read.
local BADGES = {
	report = function()
		return ns.Report and #ns.Report.Unshared() > 0
	end,
	news = function()
		return ns.db and ns.db.seenVersion ~= ns.VERSION
	end,
}

function Hub.UpdateBadges()
	if not (rail and rail:IsShown()) then
		return
	end
	for _, tab in ipairs(rail.tabs) do
		local badge = BADGES[tab.key]
		tab.badge:SetShown(badge and badge() and true or false)
	end
end

local function UpdateTabs()
	if not (rail and active) then
		return
	end
	local current = CurrentKey()
	for _, tab in ipairs(rail.tabs) do
		tab:SetChecked(tab.key == current)
	end
	if current and ns.db then
		ns.db.lastPage = current -- for the key binding that reopens the window
	end
	Hub.UpdateBadges()
end
Hub.UpdateTabs = UpdateTabs

local function CreateRail()
	local r = CreateFrame("Frame", "OneCastHubTabs", UIParent)
	r:SetSize(TAB_SIZE, #TABS * (TAB_SIZE + TAB_GAP))
	r:Hide()
	r.tabs = {}
	for i, def in ipairs(TABS) do
		-- After the spellbook's side tabs: an icon on a tab-shaped backing, lit when chosen.
		local tab = CreateFrame("CheckButton", nil, r)
		tab:SetSize(TAB_SIZE, TAB_SIZE)
		tab:SetPoint("TOPLEFT", 0, -(i - 1) * (TAB_SIZE + TAB_GAP))
		local back = tab:CreateTexture(nil, "BACKGROUND")
		back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
		back:SetSize(64, 64)
		back:SetPoint("TOPLEFT", -3, 11)
		tab.back = back
		local icon = tab:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexture((def.item and C_Item.GetItemIconByID(def.item)) or def.icon)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		tab.icon = icon
		-- Built as textures with their blend mode set on them: the client ignores the blend mode
		-- argument to SetCheckedTexture, and the glow's black centre then hides the icon.
		local hover = tab:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
		hover:SetBlendMode("ADD")
		local chosen = tab:CreateTexture(nil, "OVERLAY")
		chosen:SetAllPoints()
		chosen:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		chosen:SetBlendMode("ADD")
		tab:SetCheckedTexture(chosen)
		local checked = tab.GetCheckedTexture and tab:GetCheckedTexture()
		if checked then
			checked:SetBlendMode("ADD")
		end
		tab.badge = tab:CreateTexture(nil, "OVERLAY", nil, 7)
		tab.badge:SetSize(10, 10)
		tab.badge:SetPoint("CENTER", tab, "TOPRIGHT", -3, -3)
		tab.badge:SetTexture("Interface\\COMMON\\Indicator-Green")
		tab.badge:Hide()
		tab.key, tab.label = def.key, def.label
		tab:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			Hub.TourSeen()
			def.open()
			UpdateTabs()
		end)
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(def.label)
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", GameTooltip_Hide)
		r.tabs[i] = tab
	end
	return r
end

-- Panels ------------------------------------------------------------------------------------

-- A resize grip in a page's bottom-right corner: dragging it scales the whole window.
local function AddGrip(frame)
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", -4, 6)
	grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		if ns.db and ns.db.lockWindow then
			return
		end
		local startX = GetCursorPosition() / UIParent:GetEffectiveScale()
		local startWidth = frame:GetWidth() * frame:GetScale()
		grip:SetScript("OnUpdate", function()
			local x = GetCursorPosition() / UIParent:GetEffectiveScale()
			ns.Stats.SetScale((startWidth + x - startX) / frame:GetWidth() * 100, true)
		end)
	end)
	grip:SetScript("OnMouseUp", function()
		if not grip:GetScript("OnUpdate") then
			return
		end
		grip:SetScript("OnUpdate", nil)
		ns.Stats.SetScale(frame:GetScale() * 100)
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("拖动调整大小")
		GameTooltip:AddLine("调整窗口所有页面的大小。在统计页面上也可按住 Ctrl 并滚动鼠标滚轮。", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)
	frame.grip = grip
end

-- A panel becomes part of the window. `currentKey` says which tab it is now (the book is both
-- Collection and Camp); without one, it's always `key`.
function Hub.Attach(key, frame, currentKey)
	panels[frame] = currentKey or function()
		return key
	end
	frame:SetClampedToScreen(true)
	AddGrip(frame)
	-- A locked window doesn't move.
	local startDrag = frame:GetScript("OnDragStart")
	frame:SetScript("OnDragStart", function(self, ...)
		if ns.db and ns.db.lockWindow then
			return
		end
		if startDrag then
			startDrag(self, ...)
		end
	end)
	frame:HookScript("OnShow", function(self)
		Hub.Activate(self)
	end)
	frame:HookScript("OnHide", function(self)
		if active == self then
			active = nil
			if rail then
				rail:Hide()
			end
		end
	end)
	-- Dragging any panel moves the whole window.
	frame:HookScript("OnDragStop", function(self)
		SavePoint(self)
	end)
	if frame:IsShown() then
		Hub.Activate(frame)
	end
end

-- A panel opened: it takes the window's place, and the one it replaces closes.
function Hub.Activate(frame)
	local previous = active
	active = frame
	frame:SetScale(Hub.Scale())
	PlaceAtPoint(frame)
	if previous and previous ~= frame and previous:IsShown() then
		previous:Hide()
	end
	rail = rail or CreateRail()
	Hub.UpdateSide()
	rail:SetScale(frame:GetScale() or 1)
	rail:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
	rail:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
	rail:SetAlpha(1)
	rail:Show()
	Hub.UpdateLock()
	UpdateTabs()
	if ns.db and not ns.db.hubTourSeen then
		Hub.ShowTour()
	end
end

-- The lock: no grip on a locked window.
function Hub.UpdateLock()
	local locked = ns.db and ns.db.lockWindow
	for frame in pairs(panels) do
		if frame.grip then
			frame.grip:SetShown(not locked)
		end
	end
end

-- For the stats page fading while fishing: the tabs fade with it, and hovering them counts.
function Hub.SetTabsAlpha(frame, alpha)
	if rail and active == frame then
		rail:SetAlpha(alpha)
	end
end

function Hub.IsMouseOverTabs()
	return rail and rail:IsShown() and rail:IsMouseOver() or false
end

-- Open a page by its tab's key.
function Hub.Open(key)
	local def = tabsByKey[key] or tabsByKey.session
	def.open()
end

-- The key binding: close the window, or open it on the page last used.
function Hub.Toggle()
	if Hub.IsOpen() then
		active:Hide()
	else
		Hub.Open(ns.db and ns.db.lastPage or "session")
	end
end

function OneCast_ToggleWindow()
	Hub.Toggle()
end

-- The first time the window opens: a note by the tabs saying what they are.
local tour
function Hub.ShowTour()
	if not rail then
		return
	end
	if not tour then
		tour = CreateFrame("Frame", "OneCastHubTour", rail, "BackdropTemplate")
		tour:SetSize(220, 96)
		tour:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		tour:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
		tour:SetBackdropBorderColor(1, 0.82, 0)
		tour.title = tour:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		tour.title:SetPoint("TOPLEFT", 12, -10)
		tour.title:SetText("合而为一的窗口")
		tour.text = tour:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tour.text:SetPoint("TOPLEFT", tour.title, "BOTTOMLEFT", 0, -4)
		tour.text:SetWidth(196)
		tour.text:SetJustifyH("LEFT")
		tour.text:SetText("这些标签用于切换页面：统计、工具箱、钓鱼图鉴、营地、数据报告、更新内容和选项。悬停可查看各是哪一页。")
		local ok = CreateFrame("Button", nil, tour, "UIPanelButtonTemplate")
		ok:SetSize(70, 20)
		ok:SetPoint("BOTTOMRIGHT", -8, 8)
		ok:SetText("知道了")
		ok:SetScript("OnClick", function()
			Hub.TourSeen()
		end)
		tour.ok = ok
	end
	tour:ClearAllPoints()
	if Hub.Side() == "left" then
		tour:SetPoint("TOPRIGHT", rail, "TOPLEFT", -8, 0)
	else
		tour:SetPoint("TOPLEFT", rail, "TOPRIGHT", 8, 0)
	end
	tour:Show()
end

function Hub.TourSeen()
	if ns.db then
		ns.db.hubTourSeen = true
	end
	if tour then
		tour:Hide()
	end
end

-- Through a /reload, the page that was open opens again.
local hubEvents = CreateFrame("Frame")
hubEvents:RegisterEvent("PLAYER_LOGOUT")
hubEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
hubEvents:SetScript("OnEvent", function(_, event, isLogin, isReload)
	if not ns.db then
		return
	end
	if event == "PLAYER_LOGOUT" then
		ns.db.reopenPage = Hub.IsOpen() and CurrentKey() or nil
	elseif event == "PLAYER_ENTERING_WORLD" then
		local page = ns.db.reopenPage
		ns.db.reopenPage = nil
		if isReload and page then
			C_Timer.After(0.5, function()
				Hub.Open(page)
			end)
		end
	end
end)

-- The window's scale, for every page: the "Window scale" setting (statsScale, from when only the
-- stats window had one).
function Hub.Scale()
	return (ns.db and ns.db.statsScale or 100) / 100
end

-- The scale changed: the open page and its tabs follow, its top-left corner staying put.
function Hub.SetScale(scale)
	if not active then
		return
	end
	active:SetScale(scale)
	PlaceAtPoint(active)
	if rail then
		rail:SetScale(scale)
	end
end

-- "left" or "right": the side of the window the tabs are on.
function Hub.Side()
	return ns.db and ns.db.tabSide == "left" and "left" or "right"
end

-- Put the tabs on the chosen side of the open panel, the tab art facing the window.
function Hub.UpdateSide()
	if not (rail and active) then
		return
	end
	local left = Hub.Side() == "left"
	-- The window stops at the screen's edge with its tabs still on screen.
	active:SetClampRectInsets(left and -TAB_SIZE or 0, left and 0 or TAB_SIZE, 0, 0)
	rail:ClearAllPoints()
	if left then
		-- Lower on the left, clear of the window's round portrait.
		rail:SetPoint("TOPRIGHT", active, "TOPLEFT", 0, -RAIL_TOP_LEFT)
	else
		rail:SetPoint("TOPLEFT", active, "TOPRIGHT", 0, -RAIL_TOP)
	end
	for _, tab in ipairs(rail.tabs) do
		tab.back:ClearAllPoints()
		if left then
			tab.back:SetPoint("TOPRIGHT", 3, 11)
			tab.back:SetTexCoord(1, 0, 0, 1)
		else
			tab.back:SetPoint("TOPLEFT", -3, 11)
			tab.back:SetTexCoord(0, 1, 0, 1)
		end
	end
end

-- True while any panel of the window is open.
function Hub.IsOpen()
	return active ~= nil and active:IsShown()
end

-- Options ---------------------------------------------------------------------------------
-- Every OneCast setting, in the window: built from the same description as the game's options
-- panel (ns.OPTIONS, OPTION_CHOICES, OPTION_MAIN, OPTION_PAGES), and each row is that panel's own
-- setting, so the two always agree and a new option shows in both. As wide as the collection,
-- in two columns, in the panel's order. Only the cast key stays in the game's options: key
-- bindings are set there.

local OPTIONS_WIDTH, ROW, HEADER, GAP = 840, 22, 28, 8 -- the stats window's spacing
local EDGE, COLUMN_GAP = 10, 20
local COLUMN_WIDTH = math.floor((OPTIONS_WIDTH - 10 - 2 * EDGE - COLUMN_GAP) / 2)
local INDENT = 16 -- settings that belong to the one above
-- Every label starts where a checkbox's does, and every value sits in the same place with its
-- arrows, so the rows line up down each column.
local LABEL_LEFT = 2 + ROW + 4 -- after a checkbox: its inset, its size, a gap
local VALUE_WIDTH = 130 -- leaves the longest label, indented, its full width
-- The arrows' whole width, so a slider starts where a row's first arrow does.
local CONTROL_WIDTH = 2 + 24 + 4 + VALUE_WIDTH + 4 + 24
local SLIDER_VALUE_WIDTH = 44
-- Settings that change the window itself apply when the slider is let go, not while dragging:
-- the window scale would otherwise resize the page under the mouse.
local APPLY_ON_RELEASE = { statsScale = true }

local optionsFrame

local function Setting(key)
	return ns.optionSettings and ns.optionSettings[key]
end

local function OptionValue(key, char)
	local setting = Setting(key)
	if setting then
		return setting:GetValue()
	end
	local store = char and OneCastCharDB or ns.db
	return store and store[key]
end

local function SetOption(key, value)
	local setting = Setting(key)
	if setting then
		setting:SetValue(value)
	elseif ns.db then
		ns.db[key] = value
	end
end

local function Tooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title)
	GameTooltip:AddLine(text, 1, 1, 1, true)
	GameTooltip:Show()
end

local function CreateOptions()
	local UI = ns.UI
	local f, inset = UI.CreateShell("OneCastOptionsWindow", "选项", "Interface\\Icons\\INV_Misc_Gear_01")
	f:SetSize(OPTIONS_WIDTH, ns.UI.PAGE_HEIGHT)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER")
	tinsert(UISpecialFrames, f:GetName())
	UI.KeepOpenThroughOptions(f:GetName())

	-- Right of the portrait, above the inset, as on the data report.
	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 62, 6)
	f.status:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
	f.status:SetJustifyH("LEFT")
	f.status:SetText("「哇，大鱼」的全部设置。更改立即生效：悬停可查看各项的作用。")

	local content = inset
	f.content = content

	local byKey = {}
	for _, opt in ipairs(ns.OPTIONS or {}) do
		byKey[opt.key] = opt
	end
	local choices = ns.OPTION_CHOICES or {}
	local parents = ns.OPTION_PARENT or {}

	-- Two columns, each with its own place to add the next row.
	local columns = { { x = EDGE, y = -GAP }, { x = EDGE + COLUMN_WIDTH + COLUMN_GAP, y = -GAP } }
	local column = columns[1]
	local index = 0
	f.rows, f.checks, f.choiceRows = {}, {}, {}

	local function Line(key)
		index = index + 1
		local indent = parents[key] and INDENT or 0
		local line = CreateFrame("Frame", nil, content)
		line:SetHeight(ROW)
		line:SetPoint("TOPLEFT", column.x + indent, column.y)
		line:SetWidth(COLUMN_WIDTH - indent)
		UI.RowBackground(line, index)
		line.key, line.parent = key, parents[key]
		f.rows[#f.rows + 1] = line
		column.y = column.y - ROW
		return line
	end

	local function CheckRow(opt)
		local line = Line(opt.key)
		local check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
		check:SetSize(ROW, ROW)
		check:SetPoint("LEFT", 2, 0)
		check.label = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		check.label:SetPoint("LEFT", LABEL_LEFT, 0)
		check.label:SetPoint("RIGHT", -6, 0)
		check.label:SetJustifyH("LEFT")
		check.label:SetWordWrap(false)
		check.label:SetText(opt.label)
		check.opt = opt
		check:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			SetOption(opt.key, self:GetChecked() and true or false)
			f:Refresh() -- settings that belong to this one follow it
		end)
		check:SetScript("OnEnter", function(self)
			Tooltip(self, opt.label, opt.tooltip)
		end)
		check:SetScript("OnLeave", GameTooltip_Hide)
		line.Update = function()
			check:SetChecked(OptionValue(opt.key, opt.char) and true or false)
		end
		line.SetActive = function(_, on)
			check:SetEnabled(on)
			check.label:SetAlpha(on and 1 or 0.5)
		end
		f.checks[#f.checks + 1] = check
		return line
	end

	-- A setting with a value: ‹ value ›, stepping through its list or its range.
	local function ChoiceRow(key, spec)
		local line = Line(key)
		line:EnableMouse(true)
		local text = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("LEFT", LABEL_LEFT, 0)
		text:SetText(spec.label)
		local nextButton = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
		nextButton:SetSize(24, 20)
		nextButton:SetPoint("RIGHT", -2, 0)
		nextButton:SetText(">")
		local value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("RIGHT", nextButton, "LEFT", -4, 0)
		value:SetJustifyH("CENTER")
		value:SetWordWrap(false)
		local prevButton = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
		prevButton:SetSize(24, 20)
		prevButton:SetText("<")
		prevButton:SetPoint("RIGHT", value, "LEFT", -4, 0)
		value:SetWidth(VALUE_WIDTH) -- the same for every row, so the arrows line up
		text:SetPoint("RIGHT", prevButton, "LEFT", -6, 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		line.value = value

		local function Current()
			return OptionValue(key, spec.char)
		end
		local function Show(v)
			if spec.list then
				for _, choice in ipairs(spec.list()) do
					if choice[1] == v then
						return choice[2]
					end
				end
				return tostring(v)
			end
			return spec.format and spec.format(v) or tostring(v)
		end
		local function Step(delta)
			local v = Current()
			if spec.list then
				local list = spec.list()
				local at = 1
				for i, choice in ipairs(list) do
					if choice[1] == v then
						at = i
					end
				end
				v = list[(at - 1 + delta) % #list + 1][1]
			else
				v = math.max(spec.min, math.min(spec.max, (tonumber(v) or spec.min) + delta * spec.step))
			end
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			SetOption(key, v)
			line.Update()
		end
		prevButton:SetScript("OnClick", function()
			Step(-1)
		end)
		nextButton:SetScript("OnClick", function()
			Step(1)
		end)
		for _, b in ipairs({ prevButton, nextButton }) do
			ns.Theme.Register(b, "button")
		end
		line:SetScript("OnEnter", function(self)
			Tooltip(self, spec.label, spec.tooltip)
			-- The whole value, in case the row had to cut it short.
			GameTooltip:AddLine(" ")
			GameTooltip:AddDoubleLine("当前", Show(Current()), 1, 0.82, 0, 1, 1, 1)
			GameTooltip:Show()
		end)
		line:SetScript("OnLeave", GameTooltip_Hide)
		line.Update = function()
			value:SetText(Show(Current()))
		end
		line.SetActive = function(_, on)
			prevButton:SetEnabled(on)
			nextButton:SetEnabled(on)
			text:SetAlpha(on and 1 or 0.5)
			value:SetAlpha(on and 1 or 0.5)
		end
		f.choiceRows[#f.choiceRows + 1] = line
		return line
	end

	-- A setting with a range, as a slider like the game's options use, its value after it.
	local function SliderRow(key, spec)
		local line = Line(key)
		line:EnableMouse(true)
		local text = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("LEFT", LABEL_LEFT, 0)
		text:SetText(spec.label)
		local value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("RIGHT", -2, 0)
		value:SetWidth(SLIDER_VALUE_WIDTH)
		value:SetJustifyH("RIGHT")
		value:SetWordWrap(false)
		local slider = UI.TryCreate("Slider", nil, line, "MinimalSliderTemplate")
			or UI.TryCreate("Slider", nil, line, "UISliderTemplate")
			or CreateFrame("Slider", nil, line)
		slider:SetOrientation("HORIZONTAL")
		slider:SetPoint("LEFT", line, "RIGHT", -CONTROL_WIDTH, 0)
		slider:SetPoint("RIGHT", value, "LEFT", -6, 0)
		slider:SetHeight(18)
		slider:SetMinMaxValues(spec.min, spec.max)
		slider:SetValueStep(spec.step)
		slider:SetObeyStepOnDrag(true)
		text:SetPoint("RIGHT", slider, "LEFT", -6, 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		line.value, line.slider = value, slider

		local function Show(v)
			return spec.format and spec.format(v) or tostring(v)
		end
		local function Snap(v)
			return math.floor((v - spec.min) / spec.step + 0.5) * spec.step + spec.min
		end
		local updating = false
		slider:SetScript("OnValueChanged", function(_, v, userInput)
			if updating then
				return
			end
			v = Snap(v)
			value:SetText(Show(v))
			if userInput ~= false and not APPLY_ON_RELEASE[key] then
				SetOption(key, v)
			end
		end)
		slider:HookScript("OnMouseUp", function(self)
			if APPLY_ON_RELEASE[key] then
				SetOption(key, Snap(self:GetValue()))
			end
		end)
		line:SetScript("OnEnter", function(self)
			Tooltip(self, spec.label, spec.tooltip)
		end)
		line:SetScript("OnLeave", GameTooltip_Hide)
		line.Update = function()
			local v = tonumber(OptionValue(key, spec.char)) or spec.min
			updating = true
			slider:SetValue(v)
			updating = false
			value:SetText(Show(v))
		end
		line.SetActive = function(_, on)
			slider:SetEnabled(on)
			slider:SetAlpha(on and 1 or 0.5)
			text:SetAlpha(on and 1 or 0.5)
			value:SetAlpha(on and 1 or 0.5)
		end
		f.choiceRows[#f.choiceRows + 1] = line
		return line
	end

	local function Section(section)
		local header = UI.SectionHeader(content, column.y)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", column.x, column.y)
		header:SetWidth(COLUMN_WIDTH)
		header.text:SetText(section[1])
		column.y = column.y - HEADER
		index = 0
		for i = 2, #section do
			local key = section[i]
			local row
			if choices[key] then
				row = choices[key].list and ChoiceRow(key, choices[key]) or SliderRow(key, choices[key])
			elseif byKey[key] then
				row = CheckRow(byKey[key])
			end
			if key == "theme" then
				f.themeRow, f.themeValue = row, row.value
			elseif key == "tabSide" then
				f.sideRow = row
			end
		end
		column.y = column.y - GAP
	end
	local sections = {}
	for _, section in ipairs(ns.OPTION_MAIN or {}) do
		sections[#sections + 1] = section
	end
	-- Each page of the options panel is a section here, its own sections run together.
	for _, page in ipairs(ns.OPTION_PAGES or {}) do
		local keys = { page.name }
		for _, section in ipairs(page) do
			for i = 2, #section do
				keys[#keys + 1] = section[i]
			end
		end
		sections[#sections + 1] = keys
	end
	-- In order, down the left column until about half, then the right: a section goes left while
	-- its middle would still be in the left's half.
	local heights, total = {}, 0
	for i, section in ipairs(sections) do
		heights[i] = HEADER + (#section - 1) * ROW + GAP
		total = total + heights[i]
	end
	local left = 0
	for i, section in ipairs(sections) do
		if column == columns[1] and left + heights[i] / 2 > total / 2 then
			column = columns[2]
		end
		if column == columns[1] then
			left = left + heights[i]
		end
		Section(section)
	end
	f.columnHeights = { -columns[1].y, -columns[2].y }

	-- The one thing that stays in the game's options: your cast key.
	local keys = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	ns.Theme.Register(keys, "button")
	keys:SetSize(140, 22)
	keys:SetPoint("BOTTOMLEFT", 10, 4)
	keys:SetText("按键绑定")
	keys:SetScript("OnClick", function()
		if ns.OpenSettings then
			ns.OpenSettings()
		end
	end)
	keys:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("按键绑定")
		GameTooltip:AddLine("设置你的施法键。它在游戏选项里，按键绑定都在那边设置。", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	keys:SetScript("OnLeave", GameTooltip_Hide)
	f.all = keys

	-- Every row shows its setting's value, and those that belong to another follow it.
	function f:Refresh()
		for _, line in ipairs(self.rows) do
			line.Update()
			if line.parent then
				line:SetActive(OptionValue(line.parent) and true or false)
			end
		end
	end
	f:SetScript("OnShow", function(self)
		self:Refresh()
	end)
	f:Hide()
	Hub.Attach("options", f)
	return f
end

function Hub.ShowOptions()
	optionsFrame = optionsFrame or CreateOptions()
	optionsFrame:Show()
end

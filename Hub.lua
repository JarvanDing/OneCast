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

-- Escape ----------------------------------------------------------------------------------------
-- OneCast's windows stay open through Escape unless "Escape closes OneCast windows" is on: it's
-- for the game (closing its own windows, then its menu), and OneCast is open while you fish. Its
-- short-lived frames (right-click menus, the welcome), and with that setting its windows too,
-- close with Escape, one at a time, newest first, but only when none of the game's windows is open:
-- the game closes every window on its list (UISpecialFrames) at once, so those frames aren't on
-- it, and a keyboard watcher of OneCast's sees Escape (or whatever's bound to the game menu) first
-- while one is open. The watcher can't hold a key back in combat, so in combat they go on the
-- game's list after all, and come off again after.
local escapable = {} -- frame -> when it was last shown
local mainWindow = {} -- frame -> true: a OneCast window, escapable only with the setting on

local function Escapable(frame)
	return not mainWindow[frame] or (ns.db and ns.db.escapeCloses) or false
end
local watcher = CreateFrame("Frame", "OneCastEscapeWatcher", UIParent)
watcher:Hide()
watcher:SetFrameStrata("BACKGROUND") -- after anything typing or capturing a key
watcher:EnableKeyboard(true)
if not InCombatLockdown() then
	watcher:SetPropagateKeyboardInput(true)
end

local function Shown(frame)
	return frame and frame.IsShown and frame:IsShown() or false
end

-- One of the game's own windows is open: Escape is for that.
local function GameWindowOpen()
	for _, name in ipairs(UISpecialFrames or {}) do
		local frame = _G[name]
		if Shown(frame) and not (escapable[frame] and Escapable(frame)) then
			return true
		end
	end
	if GetUIPanel then
		for _, side in ipairs({ "left", "center", "right", "doublewide", "fullscreen" }) do
			local ok, panel = pcall(GetUIPanel, side)
			if ok and panel then
				return true
			end
		end
	end
	for _, name in ipairs({ "WorldMapFrame", "GameMenuFrame", "SettingsPanel", "ContainerFrameCombinedBags", "StaticPopup1" }) do
		if Shown(_G[name]) then
			return true
		end
	end
	for i = 1, 13 do
		if Shown(_G["ContainerFrame" .. i]) then
			return true
		end
	end
	return false
end

-- The OneCast window shown last, if any is.
local function Latest()
	local latest, at
	for frame, shownAt in pairs(escapable) do
		if Shown(frame) and Escapable(frame) and (not at or shownAt > at) then
			latest, at = frame, shownAt
		end
	end
	return latest
end

local function UpdateWatcher()
	if InCombatLockdown() then
		return
	end
	watcher:SetShown(Latest() ~= nil)
end

local function IsEscape(key)
	return key == "ESCAPE" or GetBindingAction(key) == "TOGGLEGAMEMENU"
end

watcher:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() or not IsEscape(key) then
		return -- through to the game, as every other key goes
	end
	local frame = not GameWindowOpen() and Latest()
	if not frame then
		return
	end
	-- This one's OneCast's: held back from the game, and the window closed.
	self:SetPropagateKeyboardInput(false)
	frame:Hide()
	C_Timer.After(0, function()
		if not InCombatLockdown() then
			self:SetPropagateKeyboardInput(true)
		end
		UpdateWatcher()
	end)
end)

-- Combat: OneCast's windows on the game's list, which closes them with the rest; after, off again.
local combatEvents = CreateFrame("Frame")
combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
combatEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		watcher:Hide()
		for frame in pairs(escapable) do
			if frame:GetName() and Escapable(frame) then
				tinsert(UISpecialFrames, frame:GetName())
			end
		end
	else
		for i = #UISpecialFrames, 1, -1 do
			local frame = _G[UISpecialFrames[i]]
			if frame and escapable[frame] then
				table.remove(UISpecialFrames, i)
			end
		end
		watcher:SetPropagateKeyboardInput(true)
		UpdateWatcher()
	end
end)

-- `frame` closes with Escape, as the game's own windows do, but on its own. `main`: one of
-- OneCast's windows, which closes so only with "Escape closes OneCast windows" on.
function ns.UI.EscapeCloses(frame, main)
	mainWindow[frame] = main or nil
	if escapable[frame] then
		UpdateWatcher()
		return
	end
	escapable[frame] = 0
	frame:HookScript("OnShow", function(self)
		escapable[self] = GetTime()
		UpdateWatcher()
	end)
	frame:HookScript("OnHide", function()
		UpdateWatcher()
	end)
	if frame:IsShown() then
		escapable[frame] = GetTime()
		UpdateWatcher()
	end
end

-- The setting changed: the watcher on or off to match.
ns.UI.UpdateEscape = UpdateWatcher

local TAB_SIZE, TAB_GAP = 32, 14
local RAIL_TOP = 48 -- below the window's title bar
local RAIL_TOP_LEFT = 72 -- below the portrait, on the left

-- The tabs, top to bottom. `open` shows that panel; the panel registers itself with Attach.
local TABS = {
	{ key = "session", hint = "/onecast stats", label = "Session stats", icon = "Interface\\Icons\\INV_Misc_Fish_68",
		open = function() ns.Stats.Show() end },
	{ key = "tackle", hint = "/onecast tackle", label = "Tackle box", icon = 466035,
		open = function() ns.TackleBox.ShowWindow() end },
	{ key = "wardrobe", hint = "/onecast wardrobe", label = "Fishing wardrobe", item = 19972, icon = "Interface\\Icons\\INV_Helmet_31",
		open = function() ns.Wardrobe.Show() end },
	{ key = "collection", hint = "/onecast book", label = "Fishing collection", icon = "Interface\\Icons\\INV_Misc_Book_09",
		open = function() ns.Book.ShowCollection() end },
	{ key = "journey", hint = "/onecast journey", label = "Fisherman's journey", item = 16083, icon = "Interface\\Icons\\Trade_Fishing",
		open = function() ns.Journey.Show() end },
	{ key = "camp", hint = "/onecast camp", label = "Camp", item = 279966, icon = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth",
		open = function() ns.Book.ShowCamp() end },
	{ key = "report", hint = "/onecast report", label = "Data report", icon = "Interface\\Icons\\INV_Letter_15",
		open = function() ns.Report.Show() end },
	{ key = "news", hint = "/onecast new", label = "What's new", icon = "Interface\\Icons\\INV_Misc_Note_01",
		open = function() ns.WhatsNew.Show() end },
	{ key = "options", hint = "/onecast", label = "Options", icon = "Interface\\Icons\\INV_Misc_Gear_01",
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
	local on = not (ns.db and ns.db.tabBadges == false)
	for _, tab in ipairs(rail.tabs) do
		local badge = BADGES[tab.key]
		tab.badge:SetShown(on and badge and badge() and true or false)
	end
end

local function UpdateTabs()
	if not (rail and active) then
		return
	end
	local current = CurrentKey()
	Hub.LayoutTabs()
	for _, tab in ipairs(rail.tabs) do
		tab:SetChecked(tab.key == current)
	end
	if current and ns.db then
		ns.db.lastPage = current -- for the key binding that reopens the window
	end
	Hub.UpdateBadges()
end
Hub.UpdateTabs = UpdateTabs

-- Side tabs you've hidden (right-click one): ns.db.hiddenTabs[key] = true. Options can't be
-- hidden, so every tab's menu can always bring the rest back.
local function TabHidden(key)
	return key ~= "options" and ns.db and ns.db.hiddenTabs and ns.db.hiddenTabs[key] or false
end

-- The tabs down the rail, closing up around the hidden ones. Hiding goes at once, even the open
-- page's tab: the page itself stays open, and its command and key binding still open it.
function Hub.LayoutTabs()
	if not rail then
		return
	end
	local y = 0
	for _, tab in ipairs(rail.tabs) do
		local shown = not TabHidden(tab.key)
		tab:SetShown(shown)
		if shown then
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", 0, -y)
			y = y + TAB_SIZE + TAB_GAP
		end
	end
	rail:SetHeight(math.max(TAB_SIZE, y))
end

-- The side tabs on show, top to bottom, and the open page's place among them: for paging with
-- a controller's triggers.
function Hub.SideTabs()
	local list, current = {}, nil
	if not rail then
		return list, nil
	end
	local key = CurrentKey()
	for _, tab in ipairs(rail.tabs) do
		if tab:IsShown() then
			list[#list + 1] = tab
			if tab.key == key then
				current = #list
			end
		end
	end
	return list, current
end

function Hub.Rail()
	return rail
end

local function HiddenCount()
	local n = 0
	for key in pairs(ns.db and ns.db.hiddenTabs or {}) do
		if key ~= "options" then
			n = n + 1
		end
	end
	return n
end

local function TabMenu(tab)
	local entries = {}
	if tab.key ~= "options" then
		entries[#entries + 1] = { "Hide this tab", function()
			ns.db.hiddenTabs = ns.db.hiddenTabs or {}
			ns.db.hiddenTabs[tab.key] = true
			ns.Print(tab.label .. " tab hidden. Right-click any tab to bring it back.")
			Hub.LayoutTabs()
		end }
	end
	local hidden = HiddenCount()
	if hidden > 0 then
		entries[#entries + 1] = { string.format("Show hidden tabs (%d)", hidden), function()
			ns.db.hiddenTabs = nil
			Hub.LayoutTabs()
		end }
	end
	if #entries > 0 and ns.UI and ns.UI.ShowMenu then
		ns.UI.ShowMenu(tab.label, entries)
	end
end

local function CreateRail()
	local r = CreateFrame("Frame", "OneCastHubTabs", UIParent)
	r:SetSize(TAB_SIZE, #TABS * (TAB_SIZE + TAB_GAP))
	r:Hide()
	r.tabs = {}
	for i, def in ipairs(TABS) do
		-- After the spellbook's side tabs: an icon on a tab-shaped backing, lit when chosen.
		local tab = CreateFrame("CheckButton", nil, r)
		tab:SetSize(TAB_SIZE, TAB_SIZE)
		tab.padMore = "Hide tab" -- with a controller, X opens its menu
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
		tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		tab:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				self:SetChecked(not self:GetChecked()) -- a right-click doesn't choose the tab
				TabMenu(self)
				UpdateTabs()
				return
			end
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			Hub.TourSeen()
			def.open()
			UpdateTabs()
		end)
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(def.label)
			if def.hint then
				GameTooltip:AddLine("Also " .. def.hint, 0.6, 0.8, 1)
			end
			local key = GetBindingKey and GetBindingKey("ONECAST_WINDOW")
			if key then
				GameTooltip:AddLine(key .. " opens the page you last used", 0.6, 0.8, 1)
			end
			GameTooltip:AddLine(def.key == "options" and "Right-click: show hidden tabs"
				or "Right-click: hide this tab", 0.6, 0.6, 0.6)
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
	grip.gamepadSkip = true
	if ns.Controller then
		ns.Controller.NoStop(grip)
	end
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
		GameTooltip:SetText("Drag to resize")
		GameTooltip:AddLine("Resizes every page of the window. Also Ctrl + mouse wheel over the stats page.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)
	-- Closed mid-drag (Escape, a tab): the drag ends at the size reached, rather than running on.
	frame:HookScript("OnHide", function()
		if grip:GetScript("OnUpdate") then
			grip:SetScript("OnUpdate", nil)
			ns.Stats.SetScale(frame:GetScale() * 100)
		end
	end)
	frame.grip = grip
end

-- A panel becomes part of the window. `currentKey` says which tab it is now (the book is both
-- Collection and Camp); without one, it's always `key`.
function Hub.Attach(key, frame, currentKey)
	panels[frame] = currentKey or function()
		return key
	end
	ns.UI.CloseOwn(frame) -- its X works in combat too
	ns.UI.EscapeCloses(frame, true)
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
	if ns.Controller then
		ns.Controller.Navigate(frame)
	end
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
	local inPage = ns.Controller and ns.Controller.Native() and not InCombatLockdown()
	rail:SetParent(inPage and frame or UIParent)
	rail.inPage = inPage and frame or nil
	Hub.UpdateSide()
	rail:SetScale(inPage and 1 or (frame:GetScale() or 1))
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
		tour.title:SetText("One window for OneCast")
		tour.text = tour:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
		tour.text:SetPoint("TOPLEFT", tour.title, "BOTTOMLEFT", 0, -4)
		tour.text:SetWidth(196)
		tour.text:SetJustifyH("LEFT")
		tour.text:SetText("These tabs switch pages: stats, tackle box, collection, Camp, data report, What's new and options. Hover one to see which.")
		local ok = CreateFrame("Button", nil, tour, "UIPanelButtonTemplate")
		ok:SetSize(70, 20)
		ok:SetPoint("BOTTOMRIGHT", -8, 8)
		ok:SetText("Got it")
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
		rail:SetScale(rail.inPage and 1 or scale) -- inside the page, it scales with it
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
-- setting, so the two always agree and a new option shows in both. As wide as the collection, a
-- category at a time. The cast key is set here too, with the game's own binding (Onboarding.lua).

local OPTIONS_WIDTH, ROW, HEADER, GAP = 840, 24, 26, 8
local EDGE = 10
local INDENT = 16 -- settings that belong to the one above
-- Every label starts where a checkbox's does, and every value sits in the same place with its
-- arrows, so the rows line up down the page.
local LABEL_LEFT = 2 + ROW + 4 -- after a checkbox: its inset, its size, a gap
local VALUE_WIDTH = 120 -- leaves the longest label, indented, its full width
-- The arrows' whole width, so a slider starts where a row's first arrow does.
local CONTROL_WIDTH = 2 + 22 + 2 + VALUE_WIDTH + 2 + 22
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

-- The page in three parts: categories down the left, the chosen one's settings in the middle
-- (one compact row each, white labels, gold section headers), and on the right, on parchment,
-- whatever setting the mouse is over: its full description, its value and its chat command.
local NAV_WIDTH, DETAIL_WIDTH, PANE_GAP = 168, 250, 12
local LIST_WIDTH = OPTIONS_WIDTH - 10 - 2 * EDGE - NAV_WIDTH - DETAIL_WIDTH - 2 * PANE_GAP
local NAV_ROW = 34
local CATEGORY = {
	General = { icon = "Interface\\Icons\\INV_Misc_Gear_01", blurb = "How OneCast looks, and what it shows where." },
	Fishing = { icon = "Interface\\Icons\\Trade_Fishing", blurb = "How you cast and reel, your pole and fishing gear, and what happens to what you catch." },
	Lures = { item = 6533, icon = "Interface\\Icons\\INV_Misc_Orb_03", blurb = "Which lure OneCast uses on this character, and the tackle box button." },
	["While fishing"] = { icon = "Interface\\Icons\\INV_Misc_Horn_01", blurb = "What you see and hear with your line out: your bobber marked, and the splash over everything else." },
	Controller = { icon = "Interface\\Icons\\INV_Misc_EngGizmos_17", blurb = "Fish with a controller: the button that casts and reels, the one that opens OneCast, prompts and rumble." },
	Accessibility = { icon = "Interface\\Icons\\INV_Misc_Spyglass_03", blurb = "Bigger text and controller buttons, ticks on what you have, and calmer windows with less moving." },
	["Stats and alerts"] = { icon = "Interface\\Icons\\INV_Misc_Book_09", blurb = "The stats window and mini bar, catch alerts, reminders and the collection." },
}

local function ArrowButton(parent, which)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. which .. "Page-"
	b:SetNormalTexture(base .. "Up")
	b:SetPushedTexture(base .. "Down")
	b:SetDisabledTexture(base .. "Disabled")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	return b
end

-- A row's name as a button: a stop for a controller in line with the checkboxes (the D-pad only
-- moves to controls in the direction pressed, and a row's arrows are far over on the right). A
-- (or a click) moves to the next choice or step, X (or a right-click) to the one before.
local function NameButton(line, controls, step, enter, leave, rowClick)
	local b = CreateFrame("Button", nil, line)
	b:SetSize(ROW, ROW)
	b:SetPoint("LEFT", 2, 0)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(_, button)
		step(button == "RightButton" and -1 or 1)
	end)
	b:SetScript("OnEnter", enter)
	b:SetScript("OnLeave", leave)
	b.padAdjust = true -- with a controller: left and right change it
	-- The mouse: on a row of choices, a click anywhere on the name does the same.
	if rowClick then
		line:SetScript("OnMouseUp", function(_, button)
			if b:IsEnabled() and (button == "LeftButton" or button == "RightButton") then
				step(button == "RightButton" and -1 or 1)
			end
		end)
	end
	local C = ns.Controller
	if C then
		-- With a controller: up and down move between rows, left and right change this one.
		C.Adjust(b, function() step(-1) end, function() step(1) end)
		-- Only the small stop is one: not the row, its arrows or its slider.
		C.NoStop(line)
		for _, control in ipairs(controls) do
			C.NoStop(control)
		end
	end
	return b
end

-- With a controller, how to change a row from its name.
local function PadHint(tooltip)
	local C = ns.Controller
	if not (C and C.Native and C.Native()) then
		return tooltip
	end
	return (tooltip or "") .. "\n\n" .. C.Glyph("PADDLEFT") .. " " .. C.Glyph("PADDRIGHT") .. "  change it"
end

local function CreateOptions()
	local UI = ns.UI
	local f, inset = UI.CreateShell("OneCastOptionsWindow", "Options", "Interface\\Icons\\INV_Misc_Gear_01")
	f:SetSize(OPTIONS_WIDTH, ns.UI.PAGE_HEIGHT)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER")

	-- Right of the portrait, above the inset, as on the data report.
	f.status = f:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 62, 6)
	f.status:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
	f.status:SetJustifyH("LEFT")
	f.status:SetText("Every OneCast setting. Changes apply straight away.")

	local content = inset
	f.content = content

	local byKey = {}
	for _, opt in ipairs(ns.OPTIONS or {}) do
		byKey[opt.key] = opt
	end
	local choices = ns.OPTION_CHOICES or {}
	local parents = ns.OPTION_PARENT or {}

	-- The details on the right: parchment, in its ink.
	local detail = CreateFrame("Frame", nil, content)
	detail:SetPoint("TOPRIGHT", -EDGE, -GAP)
	detail:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	detail:SetWidth(DETAIL_WIDTH)
	local paper = detail:CreateTexture(nil, "BACKGROUND")
	paper:SetAllPoints()
	if UI.HasAtlas("QuestBG-Parchment") then
		paper:SetAtlas("QuestBG-Parchment")
	else
		paper:SetTexture("Interface\\QuestFrame\\QuestBG")
		paper:SetTexCoord(0, 0.586, 0, 0.65)
	end
	local edge = detail:CreateTexture(nil, "BORDER")
	edge:SetColorTexture(0.55, 0.40, 0.15, 0.8)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(3)
	local function Ink(size, font)
		local fs = detail:CreateFontString(nil, "OVERLAY")
		UI.SizedFont(fs, font or QuestFont, size)
		fs:SetShadowOffset(0, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWidth(DETAIL_WIDTH - 32)
		return fs
	end
	detail.title = Ink(17, QuestTitleFont or QuestFont)
	detail.title:SetPoint("TOPLEFT", 18, -18)
	detail.text = Ink(13)
	detail.text:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -10)
	detail.text:SetSpacing(3)
	detail.now = Ink(12)
	detail.now:SetPoint("TOPLEFT", detail.text, "BOTTOMLEFT", 0, -14)
	detail.cmd = Ink(11)
	detail.cmd:SetPoint("TOPLEFT", detail.now, "BOTTOMLEFT", 0, -6)
	f.detail = detail

	local function InkDetail()
		local theme = ns.Theme.Current()
		for _, fs in ipairs({ detail.title, detail.text, detail.now }) do
			fs:SetTextColor(theme.ink[1], theme.ink[2], theme.ink[3])
		end
		detail.cmd:SetTextColor(theme.inkSoft[1], theme.inkSoft[2], theme.inkSoft[3])
	end
	InkDetail()

	-- What the details show: a setting (title, text, its value now, its command), or a category.
	local function ShowDetail(title, text, now, cmd)
		local lead = ns.Theme.Current().lead or ""
		detail.title:SetText(title or "")
		detail.text:SetText(text or "")
		detail.now:SetText(now and (lead .. "Now:|r " .. now) or "")
		detail.cmd:SetText(cmd and ("Chat command: /onecast " .. cmd) or "")
	end
	f.ShowDetail = ShowDetail

	-- The categories down the left.
	local nav = CreateFrame("Frame", nil, content)
	nav:SetPoint("TOPLEFT", EDGE, -GAP)
	nav:SetPoint("BOTTOMLEFT", EDGE, EDGE)
	nav:SetWidth(NAV_WIDTH)
	local navBg = nav:CreateTexture(nil, "BACKGROUND")
	navBg:SetAllPoints()
	navBg:SetColorTexture(0, 0, 0, 0.25)
	local divider = content:CreateTexture(nil, "BORDER")
	divider:SetColorTexture(0.62, 0.48, 0.24, 0.5)
	divider:SetPoint("TOPLEFT", nav, "TOPRIGHT", PANE_GAP / 2, 0)
	divider:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", PANE_GAP / 2, 0)
	divider:SetWidth(1)

	local pages = {}
	f.rows, f.checks, f.choiceRows, f.pages, f.navButtons, f.pageHeights = {}, {}, {}, {}, {}, {}
	local page, y, index -- the page being built, where its next row goes, and the row's index

	local function Line(key)
		index = index + 1
		local indent = parents[key] and INDENT or 0
		local line = CreateFrame("Frame", nil, page)
		line:SetHeight(ROW)
		line:SetPoint("TOPLEFT", indent, y)
		line:SetWidth(LIST_WIDTH - indent)
		UI.RowBackground(line, index)
		local hover = line:CreateTexture(nil, "BACKGROUND", nil, 2)
		hover:SetAllPoints()
		if UI.HasAtlas("options_list_hover") then
			hover:SetAtlas("options_list_hover")
		else
			hover:SetColorTexture(1, 0.82, 0.3, 0.08)
		end
		hover:Hide()
		line.hover = hover
		line.key, line.parent = key, parents[key]
		f.rows[#f.rows + 1] = line
		y = y - ROW
		return line
	end

	local function Hover(line, title, text, now, cmd)
		line.hover:Show()
		ShowDetail(title, text, now, cmd)
	end
	local function Unhover(line)
		if line and line.hover then
			line.hover:Hide()
		end
	end

	local function CheckRow(opt)
		local line = Line(opt.key)
		line:EnableMouse(true)
		local check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
		check:SetSize(ROW, ROW)
		check:SetPoint("LEFT", 2, 0)
		check.label = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		check.label:SetPoint("LEFT", LABEL_LEFT, 0)
		check.label:SetPoint("RIGHT", -6, 0)
		check.label:SetJustifyH("LEFT")
		check.label:SetWordWrap(false)
		check.label:SetText(opt.label)
		check.opt = opt
		local function Now()
			return OptionValue(opt.key, opt.char) and "on" or "off"
		end
		check:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			SetOption(opt.key, self:GetChecked() and true or false)
			f:Refresh() -- settings that belong to this one follow it
			ShowDetail(opt.label, opt.tooltip, Now(), opt.cmd)
		end)
		local function Enter()
			Hover(line, opt.label, opt.tooltip, Now(), opt.cmd)
		end
		check:SetScript("OnEnter", Enter)
		check:SetScript("OnLeave", function() Unhover(line) end)
		line:SetScript("OnEnter", Enter)
		line:SetScript("OnLeave", Unhover)
		-- The label ticks the box too. With a controller, the box alone is the stop.
		if ns.Controller then
			ns.Controller.NoStop(line)
		end
		line:SetScript("OnMouseUp", function(_, button)
			if button == "LeftButton" and check:IsEnabled() then
				check:SetChecked(not check:GetChecked())
				check:GetScript("OnClick")(check)
			end
		end)
		line.Update = function()
			check:SetChecked(OptionValue(opt.key, opt.char) and true or false)
		end
		line.SetActive = function(_, on)
			check:SetEnabled(on)
			check.label:SetAlpha(on and 1 or 0.45)
		end
		f.checks[#f.checks + 1] = check
		return line
	end

	-- The cast key, set right here: click its button, then press the key. It's the game's own
	-- binding, the one under Key Bindings > OneCast.
	local KEY_TIP = "The key that does all of OneCast's fishing: press it to cast, and again when "
		.. "the bobber splashes to reel in.\n\nClick the button, then press the key you want. "
		.. "Shift, Ctrl and Alt combinations and side mouse buttons work too; Escape cancels. "
		.. "It's the same key as Key Bindings > OneCast > Cast / reel."
	local function KeyRow()
		local line = Line("castKey")
		line:EnableMouse(true)
		local text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", LABEL_LEFT, 0)
		text:SetPoint("RIGHT", -(CONTROL_WIDTH + 8), 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		text:SetText("Cast and reel key")
		local O = ns.Onboarding
		local button = O.CaptureButton(line, CONTROL_WIDTH, ROW - 2, function()
			f:Refresh()
		end)
		button:SetPoint("RIGHT", -2, 0)
		local function Now()
			return O.KeyText() or "not bound"
		end
		local function Enter()
			Hover(line, "Cast and reel key", KEY_TIP, Now(), "setup")
		end
		line:SetScript("OnEnter", Enter)
		line:SetScript("OnLeave", Unhover)
		button:HookScript("OnEnter", Enter)
		button:HookScript("OnLeave", function() Unhover(line) end)
		button:HookScript("OnClick", Enter)
		if ns.Controller then
			ns.Controller.NoStop(line) -- the button's the stop
		end
		line.Update = function()
			button:Refresh()
		end
		line.SetActive = function() end
		return line
	end

	-- A setting with a value: the game's page arrows either side of it.
	local function ChoiceRow(key, spec)
		local line = Line(key)
		line:EnableMouse(true)
		local text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", LABEL_LEFT, 0)
		text:SetText(spec.label)
		local nextButton = ArrowButton(line, "Next")
		nextButton:SetPoint("RIGHT", -2, 0)
		local value = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		value:SetPoint("RIGHT", nextButton, "LEFT", -2, 0)
		value:SetJustifyH("CENTER")
		value:SetWordWrap(false)
		value:SetWidth(VALUE_WIDTH)
		local prevButton = ArrowButton(line, "Prev")
		prevButton:SetPoint("RIGHT", value, "LEFT", -2, 0)
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
		local function Enter()
			Hover(line, spec.label, PadHint(spec.tooltip), Show(Current()))
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
			Enter()
		end
		prevButton:SetScript("OnClick", function()
			Step(-1)
		end)
		nextButton:SetScript("OnClick", function()
			Step(1)
		end)
		local name = NameButton(line, { prevButton, nextButton }, Step, Enter, function() Unhover(line) end, true)
		line.name = name
		for _, b in ipairs({ prevButton, nextButton }) do
			b:SetScript("OnEnter", Enter)
			b:SetScript("OnLeave", function() Unhover(line) end)
		end
		line:SetScript("OnEnter", Enter)
		line:SetScript("OnLeave", Unhover)
		line.Update = function()
			value:SetText(Show(Current()))
		end
		line.SetActive = function(_, on)
			prevButton:SetEnabled(on)
			nextButton:SetEnabled(on)
			name:SetEnabled(on)
			text:SetAlpha(on and 1 or 0.45)
			value:SetAlpha(on and 1 or 0.45)
		end
		f.choiceRows[#f.choiceRows + 1] = line
		return line
	end

	-- A setting with a range, as a slider like the game's options use, its value after it.
	local function SliderRow(key, spec)
		local line = Line(key)
		line:EnableMouse(true)
		local text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("LEFT", LABEL_LEFT, 0)
		text:SetText(spec.label)
		local value = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		value:SetPoint("RIGHT", -2, 0)
		value:SetWidth(SLIDER_VALUE_WIDTH)
		value:SetJustifyH("RIGHT")
		value:SetWordWrap(false)
		local slider = UI.TryCreate("Slider", nil, line, "MinimalSliderTemplate")
			or UI.TryCreate("Slider", nil, line, "UISliderTemplate")
			or CreateFrame("Slider", nil, line)
		slider:SetOrientation("HORIZONTAL")
		local down = ArrowButton(line, "Prev")
		down:SetSize(18, 18)
		down:SetPoint("LEFT", line, "RIGHT", -CONTROL_WIDTH, 0)
		local up = ArrowButton(line, "Next")
		up:SetSize(18, 18)
		up:SetPoint("RIGHT", value, "LEFT", -4, 0)
		slider:SetPoint("LEFT", down, "RIGHT", 4, 0)
		slider:SetPoint("RIGHT", up, "LEFT", -4, 0)
		line.down, line.up = down, up
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
		local function Enter()
			Hover(line, spec.label, PadHint(spec.tooltip), Show(tonumber(OptionValue(key, spec.char)) or spec.min))
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
		local function Step(by)
			local v = Snap((tonumber(OptionValue(key, spec.char)) or spec.min) + by * spec.step)
			v = math.max(spec.min, math.min(spec.max, v))
			PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			SetOption(key, v)
			line.Update()
			Enter()
		end
		down:SetScript("OnClick", function()
			Step(-1)
		end)
		up:SetScript("OnClick", function()
			Step(1)
		end)
		for _, b in ipairs({ down, up }) do
			b:SetScript("OnEnter", Enter)
			b:SetScript("OnLeave", function() Unhover(line) end)
		end
		local name = NameButton(line, { down, up, slider }, Step, Enter, function() Unhover(line) end)
		line.name = name
		line:SetScript("OnEnter", Enter)
		line:SetScript("OnLeave", Unhover)
		line.Update = function()
			local v = tonumber(OptionValue(key, spec.char)) or spec.min
			updating = true
			slider:SetValue(v)
			updating = false
			value:SetText(Show(v))
		end
		line.SetActive = function(_, on)
			slider:SetEnabled(on)
			down:SetEnabled(on)
			up:SetEnabled(on)
			name:SetEnabled(on)
			slider:SetAlpha(on and 1 or 0.45)
			text:SetAlpha(on and 1 or 0.45)
			value:SetAlpha(on and 1 or 0.45)
		end
		f.choiceRows[#f.choiceRows + 1] = line
		return line
	end

	local function Section(section)
		local header = UI.SectionHeader(page, y)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", 0, y)
		header:SetWidth(LIST_WIDTH)
		header.text:SetText(section[1])
		y = y - HEADER - 2
		index = 0
		for i = 2, #section do
			local key = section[i]
			local row
			if key == "castKey" then
				row = KeyRow()
			elseif choices[key] then
				row = choices[key].list and ChoiceRow(key, choices[key]) or SliderRow(key, choices[key])
			elseif byKey[key] then
				row = CheckRow(byKey[key])
			end
			if key == "tabSide" then
				f.sideRow = row
			end
		end
		y = y - GAP - 4
	end

	-- The categories: General (the main page's sections), then each page of the options panel.
	local categories = { { name = "General", sections = ns.OPTION_MAIN or {} } }
	for _, p in ipairs(ns.OPTION_PAGES or {}) do
		local sections = {}
		for _, section in ipairs(p) do
			sections[#sections + 1] = section
		end
		categories[#categories + 1] = { name = p.name, sections = sections }
	end

	local function Select(name)
		for _, cat in ipairs(categories) do
			local on = cat.name == name
			pages[cat.name]:SetShown(on)
			f.navButtons[cat.name].selected:SetShown(on)
			f.navButtons[cat.name].label:SetFontObject(on and "GameFontHighlight" or "GameFontNormal")
		end
		if ns.db then
			ns.db.optionsPage = name
		end
		local info = CATEGORY[name] or {}
		ShowDetail(name, info.blurb or "", nil, nil)
	end
	f.Select = Select

	for i, cat in ipairs(categories) do
		page = CreateFrame("Frame", nil, content)
		page:SetPoint("TOPLEFT", nav, "TOPRIGHT", PANE_GAP, 0)
		page:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", PANE_GAP, 0)
		page:SetWidth(LIST_WIDTH)
		page:Hide()
		pages[cat.name] = page
		f.pages[#f.pages + 1] = page
		y = 0
		for _, section in ipairs(cat.sections) do
			Section(section)
		end
		f.pageHeights[cat.name] = -y

		local info = CATEGORY[cat.name] or {}
		local b = CreateFrame("Button", nil, nav)
		b:SetHeight(NAV_ROW)
		b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * (NAV_ROW + 2))
		b:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * (NAV_ROW + 2))
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b.selected = b:CreateTexture(nil, "BACKGROUND")
		b.selected:SetAllPoints()
		if ns.UI.HasAtlas("options_list_active") then
			b.selected:SetAtlas("options_list_active") -- as the game's own options list
		else
			b.selected:SetColorTexture(1, 0.82, 0.3, 0.16)
		end
		b.selected:Hide()
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(24, 24)
		b.icon:SetPoint("LEFT", 6, 0)
		b.icon:SetTexture(info.item and C_Item.GetItemIconByID(info.item) or info.icon)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
		b.label:SetPoint("RIGHT", -4, 0)
		b.label:SetJustifyH("LEFT")
		b.label:SetText(cat.name)
		b:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Select(cat.name)
		end)
		f.navButtons[cat.name] = b
		f.navList = f.navList or {}
		f.navList[i] = b
		b.category = cat.name
	end
	-- For a controller's bumpers: the categories, and the one on show.
	f.gamepadTabs = function()
		local current = ns.db and ns.db.optionsPage or "General"
		for i, b in ipairs(f.navList) do
			if b.category == current then
				return f.navList, i
			end
		end
		return f.navList, 1
	end
	f.gamepadTabsVertical = true
	f.gamepadTabsLabel = "Category"

	-- The one thing that stays in the game's options: your cast key.
	local keys = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	keys:SetSize(140, 22)
	keys:SetPoint("BOTTOMLEFT", 10, 4)
	keys:SetText("Key bindings")
	keys:SetScript("OnClick", function()
		if ns.OpenSettings then
			ns.OpenSettings()
		end
	end)
	keys:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Key bindings")
		GameTooltip:AddLine("Set your cast key. It's in the game's options, where key bindings are set.", 1, 1, 1, true)
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
	local first = ns.db and ns.db.optionsPage
	Select(pages[first or ""] and first or categories[1].name)
	f:Hide()
	Hub.Attach("options", f)
	return f
end

-- `category`, if given, is the one to show ("Fishing", "Controller").
function Hub.ShowOptions(category)
	optionsFrame = optionsFrame or CreateOptions()
	optionsFrame:Show()
	if category and optionsFrame.Select then
		optionsFrame.Select(category)
	end
end

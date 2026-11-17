-- OneCast with a controller. Three things, all on the game's own gamepad support:
--
-- 1. A fishing button. While your fishing pole is on (and you're out of combat), one controller
--    button casts and reels in place of whatever it normally does, A / Cross by default, and a
--    second opens the OneCast window. With both triggers held (or one, your choice) the fishing
--    button works with no pole on too, so the first press can put the pole on. Everything goes
--    back the moment the pole comes off or combat starts.
-- 2. Window navigation. In Forever's gamepad interface, OneCast's windows join the game's own
--    navigation (the D-pad moves between buttons, A presses, B closes), with the side tabs part
--    of whichever page is open.
-- 3. Prompts and rumble. The mini bar says which button casts, drawn with the game's icon for
--    it, and the controller rumbles with OneCast's on-screen alerts (a rare catch, a goal).
--
-- A controller works in two setups: Forever's gamepad interface (InputUtil.IsGamepadUIEnabled),
-- or the standard interface with a gamepad turned on (C_GamePad.IsEnabled; ConsolePort and the
-- like). The fishing button, prompts and rumble work in both. Window navigation is the gamepad
-- interface's own; in the standard interface the cursor addon or the game's pad cursor does it.

local _, ns = ...

local Controller = {}
ns.Controller = Controller

local BUTTON_NAME = "OneCastButton"

-- The buttons a fishing or window button can be: { key, name }. The menu buttons are the game's.
Controller.BUTTONS = {
	{ "PAD1", "A / Cross" },
	{ "PAD2", "B / Circle" },
	{ "PAD3", "X / Square" },
	{ "PAD4", "Y / Triangle" },
	{ "PADLSHOULDER", "LB / L1" },
	{ "PADRSHOULDER", "RB / R1" },
	{ "PADLSTICK", "Left stick click" },
	{ "PADRSTICK", "Right stick click" },
	{ "PADDUP", "D-pad up" },
	{ "PADDDOWN", "D-pad down" },
	{ "PADDLEFT", "D-pad left" },
	{ "PADDRIGHT", "D-pad right" },
}
-- With the triggers held: the game reads LT as Shift and RT as Ctrl on a controller.
Controller.STARTS = {
	{ "both", "LT + RT + 按键", "CTRL-SHIFT-" },
	{ "left", "LT + 按键", "SHIFT-" },
	{ "right", "RT + 按键", "CTRL-" },
	{ "off", "关闭" },
}

local told = {}          -- OneCast's windows the gamepad interface has been told about
local startHeld = false  -- the triggers are held, and the fishing button puts the pole on
-- One of OneCast's windows: told to the game, or named as OneCast's own.
local function IsOurs(frame)
	if not frame then
		return false
	end
	if told[frame] then
		return true
	end
	local ok, name = pcall(frame.GetName, frame)
	return ok and type(name) == "string" and name:find("^OneCast") ~= nil
end

local owner = CreateFrame("Frame", "OneCastControllerBindings", UIParent)
local held = false       -- our buttons are taken right now
local noticed = false    -- said so in chat this session

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- Forever's gamepad interface is on.
function Controller.Native()
	if not (InputUtil and InputUtil.IsGamepadUIEnabled) then
		return false
	end
	local ok, on = pcall(InputUtil.IsGamepadUIEnabled)
	return ok and on == true and not Secret(on)
end

-- A controller is in use, in either setup.
function Controller.Active()
	if Controller.Native() then
		return true
	end
	if C_GamePad and C_GamePad.IsEnabled then
		local ok, on = pcall(C_GamePad.IsEnabled)
		return ok and on == true and not Secret(on)
	end
	return false
end

-- The gamepad interface has a window focused: its own navigation owns the buttons. Its own
-- flag isn't enough: when another addon's error interrupts the game closing a window, the flag
-- stays set with nothing on screen. So the focused window has to be there too.
local function WindowFocused()
	local manager = GamepadMode and GamepadMode.FrameControlsManager
	if not (Controller.Native() and manager and manager.isUIFocused == true) then
		return false
	end
	local focused = manager.focusedFrame
	local ok, visible = pcall(function()
		return focused and focused.IsVisible and focused:IsVisible()
	end)
	return ok and visible == true
end

local function Valid(key, list)
	for _, entry in ipairs(list) do
		if entry[1] == key then
			return entry
		end
	end
end

-- The fishing button's key, or nil when it's off.
function Controller.FishingKey()
	local db = ns.db
	if not (db and db.padFishing ~= false) then
		return nil
	end
	local entry = Valid(db.padButton or "PAD1", Controller.BUTTONS)
	return entry and entry[1] or "PAD1"
end

-- The window button's key, or nil: never the fishing button's.
function Controller.WindowKey()
	local db = ns.db
	local key = db and db.padFishing ~= false and db.padWindow or "off"
	local entry = Valid(key, Controller.BUTTONS)
	if entry and entry[1] ~= Controller.FishingKey() then
		return entry[1]
	end
end

-- "CTRL-SHIFT-" and the like, or nil: the fishing button with it held works with no pole on.
function Controller.StartPrefix()
	local entry = Valid(ns.db and ns.db.padStart or "both", Controller.STARTS)
	return entry and entry[3] or nil
end

-- The atlas the game draws a button with for the controller in use, or nil.
function Controller.Atlas(key)
	local util = InputIconTextureSetUtility
	if key and util and util.GetNormalActiveInputIconButtonTexture then
		local ok, atlas = pcall(util.GetNormalActiveInputIconButtonTexture, key)
		if ok and type(atlas) == "string" and atlas ~= "" and not Secret(atlas) then
			return atlas
		end
	end
end

-- The game's own picture of a button, for the controller you're using: letters on Xbox,
-- shapes on PlayStation, Switch's layout on Switch. Its name where the game has no picture.
-- The game's button icons have room round the button in them, so in a line of text they need
-- to be bigger than the text to read as big as it. Every size is scaled by the "Controller
-- button size" option.
local GLYPH_SCALE = { normal = 1, large = 1.25, largest = 1.5 }

function Controller.GlyphPixels(base)
	local scale = GLYPH_SCALE[ns.db and ns.db.glyphSize or "normal"] or 1
	return math.floor(base * scale + 0.5)
end

function Controller.Glyph(key, size)
	local util = InputIconTextureSetUtility
	if key and util and util.GetNormalActiveInputIconButtonTexture then
		local ok, atlas = pcall(util.GetNormalActiveInputIconButtonTexture, key)
		if ok and type(atlas) == "string" and atlas ~= "" and not Secret(atlas) then
			size = Controller.GlyphPixels(size or 24)
			return "|A:" .. atlas .. ":" .. size .. ":" .. size .. "|a"
		end
	end
	local entry = key and Valid(key, Controller.BUTTONS)
	return entry and entry[2] or key or "?"
end

-- "LT + RT + [A]" for the start, or nil.
-- A combination as it's pressed, with the game's icons where it has them: "LT + RT + A".
function Controller.StartLabel(id)
	local entry = Valid(id or "both", Controller.STARTS)
	local key = Controller.FishingKey() or "PAD1"
	if not (entry and entry[3]) then
		return "关闭"
	end
	local function Icon(k, short)
		local glyph = Controller.Glyph(k, 24)
		return glyph:find("|A:") and glyph or short
	end
	local lt, rt = Icon("PADLTRIGGER", "LT"), Icon("PADRTRIGGER", "RT")
	local with = entry[1] == "both" and (lt .. " + " .. rt .. " + ") or entry[1] == "left" and (lt .. " + ") or (rt .. " + ")
	return with .. Icon(key, (Valid(key, Controller.BUTTONS) or { nil, key })[2]:match("^(%S+)"))
end

function Controller.StartText()
	local entry = Valid(ns.db and ns.db.padStart or "both", Controller.STARTS)
	if not (Controller.FishingKey() and entry and entry[3]) then
		return nil
	end
	return Controller.StartLabel(entry[1])
end

-- The keys that reel while a line is out: OneCast.lua binds them with its own.
function Controller.ReelKeys()
	local keys = {}
	local key = Controller.Active() and Controller.FishingKey()
	if key then
		keys[1] = key
	end
	return keys
end

local windowButton = CreateFrame("Button", "OneCastControllerWindowButton", UIParent)
windowButton:Hide()
windowButton:RegisterForClicks("AnyDown") -- on the press, not the release
windowButton:SetScript("OnClick", function()
	if OneCast_ToggleWindow then
		OneCast_ToggleWindow()
	end
end)

-- Take or give back the buttons, as things stand now. Never in combat: bindings are locked
-- then, and combat's start gives them back first.
function Controller.Update()
	if InCombatLockdown() then
		return
	end
	for frame in pairs(told) do
		if not frame:IsShown() then
			Controller.WindowHidden(frame)
		end
	end
	ClearOverrideBindings(owner)
	held = false
	local key = Controller.Active() and Controller.FishingKey()
	-- While a line is out, the reel bindings (OneCast.lua) have the keys.
	if not key or (ns.IsFishing and ns.IsFishing()) or WindowFocused() then
		return
	end
	if ns.HasFishingPole and ns.HasFishingPole() then
		SetOverrideBindingClick(owner, true, key, BUTTON_NAME, "LeftButton")
		local window = Controller.WindowKey()
		if window then
			SetOverrideBindingClick(owner, true, window, windowButton:GetName(), "LeftButton")
		end
		held = true
		if not noticed and ns.db and not ns.db.padNoticeSeen then
			noticed = true
			ns.db.padNoticeSeen = true
			ns.Print(string.format("手柄：装备鱼竿时 %s 可施放与收杆%s。可在「哇，大鱼」选项的「手柄」中修改。",
				Controller.Glyph(key, 20), window and ("，" .. Controller.Glyph(window, 20) .. " 打开窗口") or ""))
		end
	end
	if ns.Mini and ns.Mini.Refresh then
		ns.Mini.Refresh()
	end
end

-- The buttons are OneCast's right now (for the tests).
function Controller.Held()
	return held
end

-- A short rumble with OneCast's on-screen alerts.
local rumbleTimer
function Controller.Rumble(strength, seconds)
	if not (ns.db and ns.db.padRumble ~= false and Controller.Active()) then
		return
	end
	if not (C_GamePad and C_GamePad.SetVibration and C_GamePad.StopVibration) then
		return
	end
	if not pcall(C_GamePad.SetVibration, "High", strength or 0.6) then
		return
	end
	if rumbleTimer then
		rumbleTimer:Cancel()
	end
	rumbleTimer = C_Timer.NewTimer(seconds or 0.35, function()
		rumbleTimer = nil
		pcall(C_GamePad.StopVibration)
	end)
end

-- Window navigation --------------------------------------------------------------------------
-- The gamepad interface navigates a window it's been told about: every button in it, and
-- anything that takes a click, found by the game itself. Telling it is allowed out of combat.

local function Manager()
	local manager = GamepadMode and GamepadMode.FrameControlsManager
	if manager and manager.FrameShown and manager.FrameHidden then
		return manager
	end
end

function Controller.WindowShown(frame, popup)
	local manager = Manager()
	if not manager or told[frame] or not Controller.Native() or InCombatLockdown() then
		return
	end
	told[frame] = true
	Controller.ApplyNoStops()
	Controller.UpdateGlyphs(not popup and frame or nil)
	pcall(manager.FrameShown, manager, frame, popup and true or false)
	-- After the page has laid itself out.
	C_Timer.After(0, function()
		if frame:IsShown() then
			Controller.SelectFirst(frame)
		end
	end)
	Controller.Update()
end

function Controller.WindowHidden(frame)
	local manager = Manager()
	if not (manager and told[frame]) then
		return
	end
	told[frame] = nil
	if not InCombatLockdown() then
		pcall(manager.FrameHidden, manager, frame)
	end
	C_Timer.After(0, Controller.Update)
end

-- A window joins the navigation whenever it's shown.
function Controller.Navigate(frame, popup)
	if not frame or frame.oneCastNavigated then
		return
	end
	frame.oneCastNavigated = true
	frame:HookScript("OnShow", function(self)
		Controller.WindowShown(self, popup)
	end)
	frame:HookScript("OnHide", function(self)
		Controller.WindowHidden(self)
	end)
	if frame:IsShown() then
		Controller.WindowShown(frame, popup)
	end
end

-- Not a stop ---------------------------------------------------------------------------------
-- The game's navigation stops on anything that takes a click. Some of OneCast's frames do that
-- for the mouse alone (a row whose label ticks its box, the model you turn): those aren't stops,
-- their own controls are. The game's helper arrives with its gamepad interface, so frames wait
-- here until it has.
local noStops = {}

function Controller.ApplyNoStops()
	if not (SmartNavigation_MarkFrameIgnored and Controller.Native()) or InCombatLockdown() then
		return
	end
	for frame in pairs(noStops) do
		pcall(SmartNavigation_MarkFrameIgnored, frame, true) -- the frame alone, not its children
		noStops[frame] = nil
	end
end

function Controller.NoStop(frame)
	if frame then
		noStops[frame] = true
		Controller.ApplyNoStops()
	end
end

-- Left and right that change a value ----------------------------------------------------------
-- On a setting's row, up and down move between rows and left and right change the setting, as
-- in the game's own options. While such a control is selected, OneCast binds those directions
-- of the D-pad to its own hidden buttons (UpdateAdjust, below), the way it binds X and the
-- triggers. Not the game's navigation overrides: an override that's an addon's function hands
-- the game's navigation a tainted answer, every value it then writes is tainted, and the next
-- window the game opens itself (the map) is blocked from a protected call and blames OneCast.
local adjusters = {} -- button -> { left = step, right = step } or { up = step, down = step }

function Controller.Adjust(button, left, right)
	if button then
		adjusters[button] = { left = left, right = right }
	end
end

-- Up and down on `button` run `up` and `down` (a page of text scrolled), and the selection stays.
function Controller.AdjustVertical(button, up, down)
	if button then
		adjusters[button] = { up = up, down = down }
	end
end

-- Up and down reach further sideways ----------------------------------------------------------
-- The game moves only to a control within 45 degrees of the way pressed, centre to centre. In
-- OneCast's windows a full-width row (a lure, a catch) sits above a checkbox at the far left,
-- and down from the row would skip the checkbox. Up and down from OneCast's controls look
-- wider; the nearest within that still wins, and a control beside is never up or down.
local VERTICAL_REACH = 72 -- degrees

function Controller.WidenReach(window)
	local directions = SMART_NAV_INPUT_DIRECTION
	if not (SmartNavigation_SetDirectionBufferThreshold and directions and Controller.Native()) or InCombatLockdown() then
		return
	end
	local function Visit(region, depth)
		if depth > 12 then
			return
		end
		for _, child in ipairs({ region:GetChildren() }) do
			if child:IsObjectType("Button") then
				Controller.WidenOne(child)
			end
			Visit(child, depth + 1)
		end
	end
	Visit(window, 0)
end

function Controller.WidenOne(button)
	local directions = SMART_NAV_INPUT_DIRECTION
	if button.padReach or not (SmartNavigation_SetDirectionBufferThreshold and directions) or InCombatLockdown() then
		return
	end
	button.padReach = true
	pcall(SmartNavigation_SetDirectionBufferThreshold, button, directions.UP, VERTICAL_REACH)
	pcall(SmartNavigation_SetDirectionBufferThreshold, button, directions.DOWN, VERTICAL_REACH)
end

-- Where the cursor starts --------------------------------------------------------------------
-- The game starts on the button it finds top-left first, and that's often the close button. A
-- window's first button is its top-most, left-most control instead: never the close button,
-- the tabs (the bumpers and triggers page through those) or the resize grip.
local function Skip(frame, button)
	if button == frame.CloseButton or button.gamepadSkip or button.gamepadTab then
		return true
	end
	local rail = ns.Hub and ns.Hub.Rail and ns.Hub.Rail()
	local parent = button
	while parent and parent ~= frame do
		if parent == rail then
			return true
		end
		parent = parent:GetParent()
	end
	return false
end

function Controller.FirstButton(frame)
	local best, bestTop, bestLeft
	local function Visit(region, depth)
		if depth > 12 then
			return
		end
		for _, child in ipairs({ region:GetChildren() }) do
			if child:IsVisible() then
				if child:IsObjectType("Button") and child:IsEnabled() and not Skip(frame, child) then
					local top, left = child:GetTop(), child:GetLeft()
					if top and left then
						top = math.floor(top / 6 + 0.5) -- one row: within a few pixels
						if not best or top > bestTop or (top == bestTop and left < bestLeft) then
							best, bestTop, bestLeft = child, top, left
						end
					end
				end
				Visit(child, depth + 1)
			end
		end
	end
	Visit(frame, 0)
	return best
end

local function Navigation()
	return SmartNavigation and SmartNavigation.SetTargetButtonForFrame and SmartNavigation or nil
end

-- Start the cursor on the window's first button.
function Controller.SelectFirst(frame, contentChanged)
	Controller.WidenReach(frame)
	Controller.SetupScrolling(frame)
	local nav = Navigation()
	local first = nav and Controller.FirstButton(frame)
	if first and not InCombatLockdown() then
		if contentChanged and nav.RefreshButtonGroups then
			pcall(nav.RefreshButtonGroups, nav, frame)
		end
		pcall(nav.SetTargetButtonForFrame, nav, frame, first)
	end
end

-- Paging: triggers through the side tabs, bumpers through a page's own ----------------------
-- Tabs leave the D-pad's way, as they do in the game's own windows.
local function MarkTab(tab)
	if tab and not tab.gamepadTab then
		tab.gamepadTab = true
		if SmartNavigation_MarkFrameIgnored and not InCombatLockdown() then
			pcall(SmartNavigation_MarkFrameIgnored, tab)
		end
	end
end

-- A page's own tabs on show, and the selected one's place.
local function TopTabs(frame)
	if frame.gamepadTabs then
		return frame.gamepadTabs()
	end
	local list, current = {}, nil
	for i, tab in ipairs(frame.Tabs or {}) do
		if tab:IsShown() then
			list[#list + 1] = tab
			if frame.selectedTab == i then
				current = #list
			end
		end
	end
	return list, current
end

local function Page(list, current, by)
	local n = #list
	if n < 2 then
		return false
	end
	local index = (((current or 1) - 1 + by) % n) + 1
	list[index]:Click()
	return true
end

-- The OneCast window that has the gamepad interface's focus, if one has.
local function FocusedWindow()
	local manager = GamepadMode and GamepadMode.FrameControlsManager
	local frame = manager and manager.focusedFrame
	return frame and (told[frame] or IsOurs(frame)) and frame or nil
end

local SETTLE = 0.2       -- seconds after a trigger press before the page it points at opens
local pendingSide        -- the side tab a run of trigger presses is heading for
local sideTimer
local lastSideOpen = 0

function Controller.PageSide(by)
	if not (ns.Hub and ns.Hub.SideTabs) then
		return
	end
	local list, current = ns.Hub.SideTabs()
	local n = #list
	if n < 2 then
		return
	end
	local from = current or 1
	if pendingSide then
		for i, tab in ipairs(list) do
			if tab == pendingSide then
				from = i
			end
		end
	end
	local target = list[((from - 1 + by) % n) + 1]
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
	-- A single press opens its page at once; presses in quick succession only move the
	-- highlight, and the page opens once they stop.
	if not pendingSide and GetTime() - lastSideOpen > SETTLE then
		lastSideOpen = GetTime()
		target:Click()
		return
	end
	pendingSide = target
	for _, tab in ipairs(list) do
		tab:SetChecked(tab == target)
	end
	if sideTimer then
		sideTimer:Cancel()
	end
	sideTimer = C_Timer.NewTimer(SETTLE, function()
		sideTimer = nil
		local tab = pendingSide
		pendingSide = nil
		lastSideOpen = GetTime()
		if tab and tab:IsShown() then
			tab:Click()
		end
	end)
end

function Controller.PageTop(by)
	local frame = FocusedWindow()
	if not frame then
		return
	end
	local list, current = TopTabs(frame)
	if Page(list, current, by) then
		-- The page changed under the cursor: start it again on the new page's first button.
		C_Timer.After(0, function()
			if frame:IsShown() then
				Controller.SelectFirst(frame, true)
			end
		end)
	end
end

-- Acting as the button goes down, not as it comes back up: a page turns as the trigger is
-- pressed, as the game's own do (a button's clicks are on release unless told otherwise).
local function PagingButton(name, fn)
	local b = CreateFrame("Button", name, UIParent)
	b:Hide()
	b:RegisterForClicks("AnyDown")
	b:SetScript("OnClick", fn)
	return b
end
-- The right stick scrolls ---------------------------------------------------------------------
-- Every scrolling part of OneCast scrolls with the mouse wheel: the stats list, the collection's
-- pages, What's new's notes, the wardrobe's zoom. The right stick turns that same wheel, on the
-- focused window's largest scrolling part (the notes on What's new, not the version list), or
-- the window itself. Held, it keeps going. A scroll frame with no wheel of its own (the data
-- report's text) is scrolled directly.

local function Wheel(frame)
	local ok, fn = pcall(frame.GetScript, frame, "OnMouseWheel")
	return ok and fn or nil
end

-- What the right stick scrolls in `window`: { frame, wheel } or nil.
function Controller.ScrollTarget(window)
	local best, bestArea
	local function Visit(region, depth)
		if depth > 10 then
			return
		end
		for _, child in ipairs({ region:GetChildren() }) do
			if child:IsVisible() and not child.padProxy then
				local scrollFrame = child:IsObjectType("ScrollFrame")
				if Wheel(child) or scrollFrame then
					local w, h = child:GetWidth() or 0, child:GetHeight() or 0
					if not best or w * h > bestArea then
						best, bestArea = child, w * h
					end
				end
				Visit(child, depth + 1)
			end
		end
	end
	Visit(window, 0)
	return best or (Wheel(window) and window) or nil
end

-- The game's navigation scrolls a window's scroll frame with the right stick itself, smoothly,
-- once told which it is. A part that scrolls by the wheel instead gets a stand-in scroll frame
-- over it: the game then reads the stick for it (and keeps it off the camera), and its speed is
-- turned into wheel steps here.
local WHEEL_PIXELS = 70 -- how far the game's scrolling goes for one turn of the wheel

local function Navigator()
	return SmartNavigation and SmartNavigation.SetScrollFrameForFrame and SmartNavigation or nil
end

-- The button the game's navigation has selected, if any.
local function Selected()
	if not (SmartNavigation and SmartNavigation.GetCurrentButton) then
		return nil
	end
	local ok, button = pcall(SmartNavigation.GetCurrentButton, SmartNavigation)
	return ok and type(button) == "table" and button or nil
end

-- Find the window's scrolling part (when it opens, changes page or gains the focus).
function Controller.SetupScrolling(window)
	window.padTarget = Controller.ScrollTarget(window)
	window.padScrollCurrent = false -- not yet told: the next look tells the game either way
	Controller.UpdateScrollFocus(window)
end

-- Is `button` inside `part`?
local function Inside(button, part)
	local region, depth = button, 0
	while region and depth < 20 do
		if region == part then
			return true
		end
		region = region:GetParent()
		depth = depth + 1
	end
	return false
end

-- The right stick scrolls only while the selection is in the scrolling part (a list's rows, the
-- report's text, What's new's notes and their scroll bar); anywhere else it's the camera's.
-- A window whose wheel is its own (the stats list, the collection's pages) says which of its
-- controls are the scrolling part (window.padScrollOwns).
function Controller.ScrollActive(window)
	local target, selected = window and window.padTarget, Selected()
	if not (target and selected and target:IsVisible()) then
		return false
	end
	if target ~= window and Inside(selected, target) then
		return true
	end
	return window.padScrollOwns and window.padScrollOwns(selected) and true or false
end

function Controller.UpdateScrollFocus(window)
	local nav = Navigator()
	if not (nav and window) or InCombatLockdown() then
		return
	end
	local target = window.padTarget
	local scrollFrame
	window.padWheel = nil
	if Controller.ScrollActive(window) then
		if target:IsObjectType("ScrollFrame") and (target.GetScrollChild and target:GetScrollChild() or not Wheel(target)) then
			scrollFrame = target -- a real scroll frame: the game scrolls it itself
		else
			-- The stand-in: an empty scroll frame over the part, for the game to read the stick into.
			if not window.padProxy then
				window.padProxy = CreateFrame("ScrollFrame", nil, window)
				window.padProxy.padProxy = true
			end
			local proxy = window.padProxy
			proxy:ClearAllPoints()
			proxy:SetAllPoints(target)
			proxy:Show()
			scrollFrame, window.padWheel = proxy, target
		end
	end
	if window.padScrollCurrent ~= scrollFrame then
		window.padScrollCurrent = scrollFrame
		pcall(nav.SetScrollFrameForFrame, nav, window, scrollFrame)
	end
end

-- Each frame: the game's stick speed for a stand-in, as wheel steps.
local wheelOwed = 0
local sinceScrollLook = 0
function Controller.WheelTick(elapsed)
	local window = FocusedWindow()
	sinceScrollLook = sinceScrollLook + elapsed
	if window and sinceScrollLook >= 0.1 then
		sinceScrollLook = 0
		Controller.UpdateScrollFocus(window)
	end
	local speed = SmartNavigation and SmartNavigation.scrollSpeed
	if not (window and window.padWheel and type(speed) == "number" and speed ~= 0) or Secret(speed) then
		wheelOwed = 0
		return
	end
	wheelOwed = wheelOwed + speed * elapsed
	while math.abs(wheelOwed) >= WHEEL_PIXELS do
		local step = wheelOwed > 0 and 1 or -1 -- stick up: the game's speed is positive, the wheel's up is 1
		wheelOwed = wheelOwed - step * WHEEL_PIXELS
		local wheel = Wheel(window.padWheel)
		if wheel and window.padWheel:IsVisible() then
			wheel(window.padWheel, step)
		end
	end
end

local pageButtons = {
	PADLTRIGGER = PagingButton("OneCastControllerSidePrev", function() Controller.PageSide(-1) end),
	PADRTRIGGER = PagingButton("OneCastControllerSideNext", function() Controller.PageSide(1) end),
	PADLSHOULDER = PagingButton("OneCastControllerTopPrev", function() Controller.PageTop(-1) end),
	PADRSHOULDER = PagingButton("OneCastControllerTopNext", function() Controller.PageTop(1) end),
}

-- In the gamepad interface, tabs leave the D-pad's way (the triggers and bumpers page
-- through them, as in the game's own windows). Which buttons do what is in the legend below.
function Controller.UpdateGlyphs(frame)
	if not Controller.Native() then
		return
	end
	for _, tab in ipairs(ns.Hub and ns.Hub.SideTabs and (ns.Hub.SideTabs()) or {}) do
		MarkTab(tab)
	end
	if frame then
		for _, tab in ipairs((TopTabs(frame))) do
			MarkTab(tab)
		end
	end
end

-- "More options" -----------------------------------------------------------------------------
-- The game's navigation presses a button with A and has nothing for a right-click, which is
-- how OneCast's catch menu and its side tabs' menu open. While one of OneCast's windows has
-- the focus, X / Square right-clicks the selected button.
local CONTEXT_KEY = "PAD3"
local navOwner = CreateFrame("Frame", "OneCastControllerNavBindings", UIParent)
local navBound = false

-- Inside one of OneCast's windows.
local function Ours(region)
	local depth = 0
	while region and depth < 20 do
		if IsOurs(region) then
			return true
		end
		region = region.GetParent and region:GetParent()
		depth = depth + 1
	end
	return false
end

local contextButton = CreateFrame("Button", "OneCastControllerContextButton", UIParent)
contextButton:Hide()
contextButton:RegisterForClicks("AnyDown") -- on the press, not the release
contextButton:SetScript("OnClick", function()
	local button = Selected()
	if not (button and Ours(button)) then
		return
	end
	if button.IsObjectType and button:IsObjectType("Button") and button:GetScript("OnClick") then
		button:Click("RightButton")
	else
		local up = button:GetScript("OnMouseUp")
		if up then
			up(button, "RightButton")
		end
	end
end)

-- Where a pop-up menu goes with a controller: by the selected button, not the mouse.
function Controller.MenuAnchor()
	if not WindowFocused() then
		return nil
	end
	local button = Selected()
	return button and Ours(button) and button or nil
end

-- One of OneCast's windows has the gamepad interface's focus.
local function OursFocused()
	local manager = Manager()
	if not (WindowFocused() and manager) then
		return false
	end
	local frame = manager.focusedFrame
	if IsOurs(frame) then
		told[frame] = true -- the game has it: from now on it's counted
		return true
	end
	return false
end

-- The game's gamepad interface binds the triggers itself (to move between open windows) and
-- sets its bindings again whenever its own state changes, and the latest binding wins. So a
-- binding of OneCast's is checked, and claimed back if the game has taken it.
local function Claim(bindOwner, key, buttonName)
	local want = "CLICK " .. buttonName .. ":LeftButton"
	local ok, action = pcall(GetBindingAction, key, true)
	if not ok or action ~= want then
		SetOverrideBindingClick(bindOwner, true, key, buttonName, "LeftButton")
	end
end

-- The D-pad on a control that changes a value: its directions bound to OneCast's own buttons
-- while it's selected. A press steps once; held, it repeats, as the game's D-pad does.
local ADJUST_KEYS = { left = "PADDLEFT", right = "PADDRIGHT", up = "PADDUP", down = "PADDDOWN" }
local REPEAT_START, REPEAT_EVERY = 0.4, 0.08
local adjustOwner = CreateFrame("Frame", "OneCastControllerAdjustBindings", UIParent)
local adjustOn       -- the control whose steps have the D-pad now
local adjustButtons = {}
local padHeld, padHeldFor = nil, 0 -- the D-pad direction held down, and for how long

local function Step(dir)
	local steps = adjustOn and adjusters[adjustOn]
	local step = steps and steps[dir]
	if step and adjustOn:IsVisible() then
		step()
		return true
	end
end

local repeater = CreateFrame("Frame", nil, UIParent)
repeater:Hide()
repeater:SetScript("OnUpdate", function(self, elapsed)
	padHeldFor = padHeldFor + elapsed
	if not padHeld then
		self:Hide()
	elseif padHeldFor >= REPEAT_START then
		padHeldFor = REPEAT_START - REPEAT_EVERY
		if not Step(padHeld) then
			padHeld = nil
		end
	end
end)

for dir, key in pairs(ADJUST_KEYS) do
	local b = CreateFrame("Button", "OneCastControllerAdjust" .. dir, UIParent)
	b:Hide()
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetScript("OnClick", function(_, _, down)
		if down then
			if Step(dir) then
				padHeld, padHeldFor = dir, 0
				repeater:Show()
			end
		elseif padHeld == dir then
			padHeld = nil
		end
	end)
	adjustButtons[dir] = b
end

local function UpdateAdjust()
	if InCombatLockdown() then
		return
	end
	local selected = navBound and Selected()
	local want = selected and adjusters[selected] and selected:IsVisible() and selected or nil
	if want ~= adjustOn then
		ClearOverrideBindings(adjustOwner)
		adjustOn, padHeld = want, nil
		if want then
			for dir in pairs(adjusters[want]) do
				SetOverrideBindingClick(adjustOwner, true, ADJUST_KEYS[dir], adjustButtons[dir]:GetName(), "LeftButton")
			end
		end
	elseif want then
		for dir in pairs(adjusters[want]) do
			Claim(adjustOwner, ADJUST_KEYS[dir], adjustButtons[dir]:GetName())
		end
	end
end
Controller.UpdateAdjust = UpdateAdjust

local function UpdateContext()
	if InCombatLockdown() then
		return
	end
	local want = OursFocused()
	if want == navBound then
		if want then
			Claim(navOwner, CONTEXT_KEY, contextButton:GetName())
			for key, b in pairs(pageButtons) do
				Claim(navOwner, key, b:GetName())
			end
		end
		return
	end
	ClearOverrideBindings(navOwner)
	navBound = want
	if want then
		-- The window has the focus now, so the game knows it: tell it what scrolls.
		local window = FocusedWindow()
		if window then
			Controller.SetupScrolling(window)
		end
		SetOverrideBindingClick(navOwner, true, CONTEXT_KEY, contextButton:GetName(), "LeftButton")
		for key, b in pairs(pageButtons) do
			SetOverrideBindingClick(navOwner, true, key, b:GetName(), "LeftButton")
		end
	end
end
Controller.UpdateContext = UpdateContext

-- The legend ------------------------------------------------------------------------------
-- With a controller, under the focused OneCast window: what each button does there, right now,
-- with the game's own pictures of them, as the game's gamepad windows and consoles show it.
-- Only what works: the bumpers when the page has tabs, the right stick when something scrolls,
-- the D-pad's left and right on a setting, X on what has more (a catch, a zone, a side tab).
local LEGEND_GAP = 18
-- The legend's button icons: 28 at the normal size.
local function LegendIcon()
	return Controller.GlyphPixels(28)
end
local legend

local function LegendEntry(parent)
	local e = CreateFrame("Frame", nil, parent)
	e:SetHeight(LegendIcon())
	e.icons = {}
	for i = 1, 3 do
		local t = e:CreateTexture(nil, "OVERLAY")
		t:SetSize(LegendIcon(), LegendIcon())
		e.icons[i] = t
	end
	e.icons[1]:SetPoint("LEFT", 0, 0)
	e.icons[2]:SetPoint("LEFT", e.icons[1], "RIGHT", 1, 0)
	e.icons[3]:SetPoint("LEFT", e.icons[2], "RIGHT", 1, 0)
	e.text = e:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if ns.UI and ns.UI.SizedFont and GameFontHighlight then
		ns.UI.SizedFont(e.text, GameFontHighlight, 15)
	end
	return e
end

local function CreateLegend(name)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetHeight(LegendIcon() + 14)
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = true, tileSize = 32,
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f:SetBackdropColor(0, 0, 0, 0.92)
		f:SetBackdropBorderColor(0.85, 0.68, 0.32, 1)
	end
	f:EnableMouse(false)
	f:SetClampedToScreen(true) -- a window low on the screen keeps its legend in sight
	f.entries = {}
	f:Hide()
	return f
end

-- What the legend says for the selected control and the focused window: { { keys }, label }.
local function LegendItems(window)
	local items = {}
	local selected = Selected()
	local adjust = selected and selected.padAdjust
	local scrollStop = selected and selected.padScrollStop
	if adjust then
		items[#items + 1] = { { "PADDLEFT", "PADDRIGHT" }, "调整" }
	end
	if scrollStop then
		-- A page of text: the D-pad (and the right stick) scroll it, and A has nothing to do.
		items[#items + 1] = { { "PADDUP", "PADDDOWN" }, "滚动" }
	else
		items[#items + 1] = { { "PAD1" }, adjust and "下一项" or "确认" }
	end
	items[#items + 1] = { { "PAD2" }, "关闭" }
	if selected and selected.padMore and Ours(selected) then
		items[#items + 1] = { { CONTEXT_KEY }, selected.padMore == true and "更多" or selected.padMore }
	end
	if #(TopTabs(window)) > 1 then
		items[#items + 1] = { { "PADLSHOULDER", "PADRSHOULDER" }, window.gamepadTabsLabel or "标签" }
	end
	local side = ns.Hub and ns.Hub.SideTabs and (ns.Hub.SideTabs()) or {}
	if #side > 1 then
		items[#items + 1] = { { "PADLTRIGGER", "PADRTRIGGER" }, "页面" }
	end
	if Controller.ScrollActive(window) and not scrollStop then
		items[#items + 1] = { { "PADRSTICK" }, window.padScrollLabel or "滚动", stick = true }
	end
	return items
end

-- What a legend says, as one string: unchanged, it isn't drawn again.
local function LegendKey(items, extra)
	local parts = { extra or "", ns.db and ns.db.glyphSize or "" } -- a new size redraws it
	for _, item in ipairs(items) do
		parts[#parts + 1] = table.concat(item[1], "+") .. "=" .. item[2]
	end
	return table.concat(parts, "|")
end

-- Fill a legend's entries; their widths, and the widest.
local function FillLegend(lg, items)
	local widths, widest = {}, 0
	for i, item in ipairs(items) do
		local e = lg.entries[i] or LegendEntry(lg)
		lg.entries[i] = e
		local count = 0
		for n, t in ipairs(e.icons) do
			local key = item[1][n]
			local atlas = key and (item.stick and (Controller.Atlas(GAMEPAD_STICK_RIGHT_VERTICAL or "<right-stick-vertical>")
				or Controller.Atlas("PADRSTICKAXIS")) or Controller.Atlas(key))
			if atlas then
				t:SetAtlas(atlas)
				t:SetSize(LegendIcon(), LegendIcon())
				t:Show()
				count = count + 1
			else
				t:Hide()
			end
		end
		e.text:ClearAllPoints()
		e.text:SetPoint("LEFT", e.icons[math.max(1, count)], count > 0 and "RIGHT" or "LEFT", count > 0 and 5 or 0, 0)
		e.text:SetText(item[2])
		e:SetHeight(LegendIcon())
		widths[i] = count * (LegendIcon() + 1) + 5 + (e.text:GetStringWidth() or 0)
		e:SetWidth(widths[i])
		e:Show()
		widest = math.max(widest, widths[i])
	end
	for i = #items + 1, #lg.entries do
		lg.entries[i]:Hide()
	end
	return widths, widest
end

-- In a row: the width it takes.
local function RowLegend(lg, widths)
	local x = 12
	for i, w in ipairs(widths) do
		local e = lg.entries[i]
		e:ClearAllPoints()
		e:SetPoint("LEFT", lg, "LEFT", x, 0)
		x = x + w + LEGEND_GAP
	end
	lg:SetSize(x - LEGEND_GAP + 12, LegendIcon() + 14)
end

-- In a column, each entry under the last.
local function ColumnLegend(lg, widths, widest)
	for i = 1, #widths do
		local e = lg.entries[i]
		e:ClearAllPoints()
		e:SetPoint("TOPLEFT", lg, "TOPLEFT", 12, -8 - (i - 1) * (LegendIcon() + 6))
	end
	lg:SetSize(widest + 24, 16 + #widths * (LegendIcon() + 6) - 6)
end

function Controller.UpdateLegend(window)
	local show = window and Controller.Native() and ns.db and ns.db.padHints ~= false and window:IsVisible()
	if not show then
		if legend then
			legend:Hide()
		end
		return
	end
	legend = legend or CreateLegend("OneCastControllerLegend")
	local items = LegendItems(window)
	local key = LegendKey(items, tostring(window) .. (window:GetWidth() or 0) .. (ns.Hub and ns.Hub.Side and ns.Hub.Side() or ""))
	if legend.key == key and legend:IsShown() and legend:GetParent() == window then
		return
	end
	legend.key = key
	legend:SetParent(window)
	legend:SetFrameStrata(window:GetFrameStrata() or "DIALOG")
	legend:SetFrameLevel((window:GetFrameLevel() or 0) + 40)
	legend:ClearAllPoints()
	local widths, widest = FillLegend(legend, items)
	RowLegend(legend, widths)
	if legend:GetWidth() <= (window:GetWidth() or 0) then
		-- It fits: under the window.
		legend:SetPoint("TOP", window, "BOTTOM", 0, 2)
		legend.vertical = false
	else
		-- Too wide: a column on the window's side, away from the side tabs, level with its foot.
		ColumnLegend(legend, widths, widest)
		local tabsLeft = ns.Hub and ns.Hub.Side and ns.Hub.Side() == "left"
		if tabsLeft then
			legend:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", 2, 0)
		else
			legend:SetPoint("BOTTOMRIGHT", window, "BOTTOMLEFT", -2, 0)
		end
		legend.vertical = true
	end
	legend:Show()
end

-- The mini bar's legend, under it: what the fishing button does now, and the window button.
local miniLegend

function Controller.MiniItems()
	-- Only in the gamepad interface, as the windows' legends: with it off, a connected pad
	-- still fishes, but the screen stays as it is for the keyboard.
	if not (ns.db and ns.db.padHints ~= false) or not Controller.Native() then
		return {}
	end
	local key = Controller.FishingKey()
	if not key then
		return {}
	end
	local fishing = ns.IsFishing and ns.IsFishing()
	if not (held or fishing) then
		local entry = Controller.StartPrefix() and Valid(ns.db.padStart or "both", Controller.STARTS)
		if not entry then
			return {}
		end
		local keys = entry[1] == "both" and { "PADLTRIGGER", "PADRTRIGGER", key }
			or entry[1] == "left" and { "PADLTRIGGER", key } or { "PADRTRIGGER", key }
		return { { keys, "装上鱼竿" } }
	end
	local items = { { { key }, fishing and "收杆" or "施放" } }
	local window = Controller.WindowKey()
	if window and not fishing then
		items[#items + 1] = { { window }, "打开窗口" }
	end
	return items
end

function Controller.UpdateMiniLegend(mini)
	local items = mini and mini:IsShown() and Controller.MiniItems() or {}
	if #items == 0 then
		if miniLegend then
			miniLegend:Hide()
		end
		return
	end
	miniLegend = miniLegend or CreateLegend("OneCastControllerMiniLegend")
	local key = LegendKey(items, tostring(mini))
	if miniLegend.key == key and miniLegend:IsShown() then
		return
	end
	miniLegend.key = key
	miniLegend:SetParent(mini)
	miniLegend:SetFrameStrata(mini:GetFrameStrata() or "MEDIUM")
	miniLegend:SetFrameLevel((mini:GetFrameLevel() or 0) + 10)
	local widths = FillLegend(miniLegend, items)
	RowLegend(miniLegend, widths)
	miniLegend:ClearAllPoints()
	miniLegend:SetPoint("TOP", mini, "BOTTOM", 0, 2)
	if miniLegend.SetIgnoreParentAlpha then
		miniLegend:SetIgnoreParentAlpha(false)
	end
	miniLegend:Show()
end

-- /onecast pad: what OneCast sees, for when a controller doesn't do what it should.
function Controller.Status()
	local function YesNo(v)
		return v and "是" or "否"
	end
	local manager = Manager()
	local key, window = Controller.FishingKey(), Controller.WindowKey()
	ns.Print("手柄在用：" .. YesNo(Controller.Active()) .. " | 手柄界面：" .. YesNo(Controller.Native())
		.. " | 鱼竿已装备：" .. YesNo(ns.HasFishingPole and ns.HasFishingPole()) .. " | 线已抛出：" .. YesNo(ns.IsFishing and ns.IsFishing()))
	ns.Print("钓鱼键：" .. (key and (Controller.Glyph(key, 20) .. "（" .. key .. "）") or "关") .. " | 无鱼竿时："
		.. (Controller.StartText() or "关") .. " | 窗口键：" .. (window and (Controller.Glyph(window, 20) .. "（" .. window .. "）") or "关"))
	ns.Print("当前占用按键：" .. YesNo(held) .. " | 窗口获焦点：" .. YesNo(WindowFocused())
		.. " | 为哇，大鱼窗口：" .. YesNo(OursFocused()) .. " | X 打开更多：" .. YesNo(navBound)
		.. " | 游戏导航可用：" .. YesNo(manager ~= nil))
	local names = {}
	local function Name(frame)
		local ok, name = pcall(function()
			return frame and (frame:GetName() or (frame:GetParent() and ((frame:GetParent():GetName() or "?") .. "'s child"))) or "none"
		end)
		return ok and tostring(name) or "?"
	end
	for frame in pairs(told) do
		names[#names + 1] = Name(frame)
	end
	ns.Print("已纳入导航的窗口：" .. (#names > 0 and table.concat(names, ", ") or "无")
		.. " | 战斗中：" .. YesNo(InCombatLockdown()))
	ns.Print("焦点窗口：" .. Name(manager and manager.focusedFrame) .. " | 当前选中：" .. Name(Selected()))
	local heldNow = Controller.HeldButtons()
	ns.Print("可读按键：" .. YesNo(heldNow ~= nil) .. " | 扳机就绪（可装竿）：" .. YesNo(startHeld)
		.. " | 输入 /onecast pad watch 查看按键")
end

-- Putting the pole on ---------------------------------------------------------------------------
-- With no pole on, the fishing button is the game's (A is Jump). Holding the chosen trigger or
-- triggers lends it to OneCast for the press that puts the pole on. The game's gamepad interface
-- doesn't treat the triggers as Shift and Ctrl for addons' bindings, so OneCast watches the
-- controller's buttons itself and takes the fishing button only while the triggers are held.
local startOwner = CreateFrame("Frame", "OneCastControllerStartBindings", UIParent)
local buttonIndex -- binding name -> place in the mapped state's buttons

-- The controller's buttons held now, by binding name ("PADLTRIGGER"), or nil if unreadable.
function Controller.HeldButtons()
	if not (C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.ButtonIndexToBinding) then
		return nil
	end
	local id = C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID()
	local ok, state = pcall(C_GamePad.GetDeviceMappedState, id)
	if not ok or type(state) ~= "table" or type(state.buttons) ~= "table" then
		return nil
	end
	if not buttonIndex then
		-- The game numbers buttons from 0; the table they come in counts from 1.
		buttonIndex = {}
		for i = 0, (state.buttonCount or #state.buttons) - 1 do
			local name = C_GamePad.ButtonIndexToBinding(i)
			if type(name) == "string" then
				buttonIndex[name] = i + 1
			end
		end
	end
	local held = {}
	for name, at in pairs(buttonIndex) do
		if state.buttons[at] == true then
			held[name] = true
		end
	end
	return held
end

local function TriggersHeld()
	local start = ns.db and ns.db.padStart or "both"
	local held = Controller.HeldButtons()
	if not held then
		return false
	end
	if start == "both" then
		return held.PADLTRIGGER and held.PADRTRIGGER or false
	elseif start == "left" then
		return held.PADLTRIGGER or false
	elseif start == "right" then
		return held.PADRTRIGGER or false
	end
	return false
end

local function SetStart(on)
	if on == startHeld or InCombatLockdown() then
		return
	end
	startHeld = on
	ClearOverrideBindings(startOwner)
	if on then
		SetOverrideBindingClick(startOwner, true, Controller.FishingKey(), BUTTON_NAME, "LeftButton")
	end
end

local sinceStart = 0
function Controller.WatchStart(elapsed)
	sinceStart = sinceStart + elapsed
	if sinceStart < 0.05 then
		return
	end
	sinceStart = 0
	local want = Controller.Active() and Controller.FishingKey() and Controller.StartPrefix()
		and not InCombatLockdown() and not (ns.HasFishingPole and ns.HasFishingPole())
		and not (ns.IsFishing and ns.IsFishing()) and not WindowFocused()
	SetStart(want and TriggersHeld() and true or false)
end

-- /onecast pad watch: for ten seconds, each controller button as it's pressed, as the game
-- reports it. To see what a controller's triggers are called, and whether they're read at all.
local watchUntil
function Controller.Watch()
	if not Controller.HeldButtons() then
		ns.Print("手柄监视：游戏未上报手柄按键。")
		return
	end
	watchUntil = GetTime() + 10
	ns.Print("手柄监视：接下来 10 秒内请按手柄按键（含扳机）。")
end

local watchedLast = {}
local function WatchTick()
	if not watchUntil then
		return
	end
	if GetTime() > watchUntil then
		watchUntil = nil
		ns.Print("手柄监视：结束。")
		return
	end
	local held = Controller.HeldButtons() or {}
	for name in pairs(held) do
		if not watchedLast[name] then
			ns.Print(string.format("按下 %s（%s）| Shift：%s，Ctrl：%s", name, Controller.Glyph(name, 20),
				IsShiftKeyDown() and "按下" or "松开", IsControlKeyDown() and "按下" or "松开"))
		end
	end
	watchedLast = held
end

-- Events -------------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UPDATE_BINDINGS")
-- Each only if this client has it: an unknown event's name is an error.
for _, name in ipairs({ "GAME_PAD_CONNECTED", "GAME_PAD_DISCONNECTED", "GAME_PAD_ACTIVE_CHANGED",
	"GAME_PAD_CONFIGS_CHANGED", "INPUT_DEVICE_INTERFACE_TRANSITION" }) do
	if ns.RegisterAnyEvent then
		ns.RegisterAnyEvent(events, { name })
	end
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- The last moment bindings can change: every button back to its own job.
		ClearOverrideBindings(owner)
		ClearOverrideBindings(navOwner)
		ClearOverrideBindings(startOwner)
		ClearOverrideBindings(adjustOwner)
		held, navBound, startHeld = false, false, false
		adjustOn, padHeld = nil, nil
	else
		-- After OneCast's own handlers, and the pole's swap, have settled.
		C_Timer.After(0, Controller.Update)
	end
end)

-- A window gaining or losing the gamepad interface's focus changes who owns the buttons, and
-- nothing announces it: looked at a few times a second, only while a controller is in use.
local since = 0
function Controller.Tick(elapsed)
	since = since + elapsed
	if since < 0.25 then
		return
	end
	since = 0
	if not Controller.Native() or InCombatLockdown() then
		Controller.UpdateLegend(nil) -- no legend outside the gamepad interface
		return
	end
	UpdateContext()
	Controller.UpdateLegend(navBound and FocusedWindow() or nil)
	-- A control made since the page opened (a fish's page in the collection): its up and down
	-- reach wide too, from the moment it's selected.
	local selected = navBound and Selected()
	if selected and not selected.padReach and Ours(selected) then
		Controller.WidenOne(selected)
	end
	local want = Controller.FishingKey() and ns.HasFishingPole and ns.HasFishingPole()
		and not (ns.IsFishing and ns.IsFishing()) and not WindowFocused()
	if (want and true or false) ~= held then
		Controller.Update()
	elseif held then
		Claim(owner, Controller.FishingKey(), BUTTON_NAME)
	end
end
local activeLook, activeNow = 0, nil
events:SetScript("OnUpdate", function(_, elapsed)
	WatchTick()
	activeLook = activeLook + elapsed
	if activeNow == nil or activeLook >= 0.5 then
		activeLook = 0
		local now = Controller.Active()
		if now ~= activeNow then
			activeNow = now
			if not now then
				-- Put down: legends away, and every button back to the game.
				Controller.UpdateLegend(nil)
				Controller.UpdateMiniLegend(nil)
				if adjustOn and not InCombatLockdown() then
					ClearOverrideBindings(adjustOwner) -- the D-pad back to the game
					adjustOn, padHeld = nil, nil
				end
				SetStart(false)
				Controller.Update()
			end
		end
	end
	if not activeNow then
		return -- no controller: nothing to do, every frame
	end
	Controller.WheelTick(elapsed)
	UpdateAdjust() -- every frame: the D-pad is ready the moment a setting is selected
	Controller.Tick(elapsed)
	Controller.WatchStart(elapsed)
end)

-- OneCast's welcome: the cast key chosen in OneCast itself, not found in the game's Key
-- Bindings. A new player sees a small window at login while no key casts: one button, click it
-- and press the key you want. The same button is the "Cast and reel key" row at the top of
-- Options > Fishing, and /onecast setup opens the window any time.
--
-- The key is bound with the game's own SetBinding and saved to the binding set in use, the way
-- the Key Bindings page does it, so the two always agree. Out of combat only (the game doesn't
-- allow it in combat). The game's Settings panel is never touched.

local _, ns = ...

local Onboarding = {}
ns.Onboarding = Onboarding

local MAX_SHOWN = 3 -- times the window comes up by itself at login before it leaves you be
local RED, GREY, WHITE = "|cffff2020", "|cff9d9d9d", "|cffffffff"

-- Keys that are only part of a combination, never one on their own.
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	LMETA = true, RMETA = true }
-- Keys that can't be the cast key.
local REFUSED = { UNKNOWN = true, PRINTSCREEN = true }
-- Mouse buttons that can be: not the left and right, which every click uses.
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function Command()
	return ns.BINDING_COMMAND or "CLICK OneCastButton:LeftButton"
end

-- The keys that cast, as the game shows them ("Shift-F"), or nil.
function Onboarding.KeyText()
	local keys = { GetBindingKey(Command()) }
	if #keys == 0 then
		return nil
	end
	for i, key in ipairs(keys) do
		keys[i] = GetBindingText and GetBindingText(key) or key
	end
	return table.concat(keys, ", ")
end

function Onboarding.Bound()
	return GetBindingKey(Command()) ~= nil
end

-- `key` with whatever modifiers are held, as the game writes them: ALT-CTRL-SHIFT-F.
local function Chord(key)
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

-- What a binding does, as the Key Bindings page names it.
local function ActionName(action)
	return _G["BINDING_NAME_" .. action] or action
end

-- Make `key` the cast key, in place of any it had. Returns true and what the key did before (if
-- anything else), or false and why not.
function Onboarding.Bind(key)
	if InCombatLockdown() then
		return false, "not in combat"
	end
	local command = Command()
	local before = GetBindingAction(key)
	for _, old in ipairs({ GetBindingKey(command) }) do
		if old ~= key then
			SetBinding(old)
		end
	end
	if not SetBinding(key, command) then
		return false, "the game wouldn't take that key"
	end
	SaveBindings(GetCurrentBindingSet())
	if before and before ~= "" and before ~= command then
		return true, ActionName(before)
	end
	return true
end

-- The capture button --------------------------------------------------------------------------
-- Click it, then press a key (or a combination, or a side mouse button). Escape, a click
-- elsewhere on it, combat or the window closing call it off. `labels.unbound` is its text with
-- no key yet; `labels.bound(keyText)` with one. `onChange(keyText, replaced)` after a key's set.
local capturing -- the button waiting for a key, if one is

local function StopCapture(button)
	if capturing ~= button then
		return
	end
	capturing = nil
	button:EnableKeyboard(false)
	button:SetScript("OnKeyDown", nil)
	button:SetScript("OnMouseDown", nil)
	button:Refresh()
end

local function Finish(button, key)
	StopCapture(button)
	local ok, detail = Onboarding.Bind(key)
	local text = GetBindingText and GetBindingText(key) or key
	if not ok then
		ns.Print("无法设置施放键：" .. detail .. "。")
		return
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	if detail then
		ns.Print(string.format("施放键已设为 %s（原先为 %s）。", WHITE .. text .. "|r", detail))
	else
		ns.Print(string.format("施放键已设为 %s。", WHITE .. text .. "|r"))
	end
	button:Refresh()
	if button.onChange then
		button.onChange(text, detail)
	end
end

local function StartCapture(button)
	if InCombatLockdown() then
		ns.Print("战斗中无法更改施放键。")
		return
	end
	if capturing and capturing ~= button then
		StopCapture(capturing)
	end
	capturing = button
	button:SetText("|cffffd100请按键…|r  " .. GREY .. "（Esc 取消）|r")
	button:EnableKeyboard(true)
	button:SetPropagateKeyboardInput(false)
	button:SetScript("OnKeyDown", function(self, key)
		if MODIFIERS[key] then
			return -- waiting for the rest of the combination
		elseif key == "ESCAPE" then
			StopCapture(self)
		elseif key:match("^PAD") then
			-- A controller's button: those are chosen in Options > Controller.
			StopCapture(self)
			ns.Print("手柄按钮请在「选项 > 手柄」中设置；施放键须为键盘键或鼠标侧键。")
		elseif not REFUSED[key] then
			Finish(self, Chord(key))
		end
	end)
	button:SetScript("OnMouseDown", function(self, mouse)
		if MOUSE[mouse] then
			Finish(self, Chord(MOUSE[mouse]))
		end
	end)
end

function Onboarding.CaptureButton(parent, width, height, onChange, labels)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, height)
	b:RegisterForClicks("LeftButtonUp")
	b.onChange = onChange
	labels = labels or {}
	function b:Refresh()
		if capturing == self then
			return
		end
		local text = Onboarding.KeyText()
		if text then
			self:SetText(labels.bound and labels.bound(text) or text)
		else
			self:SetText(labels.unbound or (RED .. "未绑定|r"))
		end
	end
	b:SetScript("OnClick", function(self)
		if capturing == self then
			StopCapture(self) -- a second click calls it off
		else
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			StartCapture(self)
		end
	end)
	b:SetScript("OnHide", StopCapture)
	b:Refresh()
	return b
end

-- The welcome window ----------------------------------------------------------------------------
-- The key's what it's about: a line on what it does, the big button to choose it, and under a
-- rule, the other ways to fish, a row each: the mouse's double right-click, and a controller's
-- button with the combination that puts the pole on. The window is as tall as what it says.
local WIDTH, EDGE = 500, 18
local PICTURE = 48 -- the room for a way's picture, left of its text
local welcome

-- One of the other ways: its picture, its name in gold and what to do, in a panel of its own.
local function WayPanel(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetWidth(WIDTH - 2 * EDGE - 8)
	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.3)
	p.picture = p:CreateTexture(nil, "ARTWORK")
	p.picture:SetPoint("TOPLEFT", 12, -10)
	p.glyph = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	p.glyph:SetPoint("TOPLEFT", 8, -8)
	p.name = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.name:SetPoint("TOPLEFT", 12 + PICTURE, -10)
	p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	p.text:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -5)
	p.text:SetWidth(WIDTH - 2 * EDGE - 8 - 12 - PICTURE - 12)
	p.text:SetJustifyH("LEFT")
	p.text:SetSpacing(4)
	return p
end

-- A way's text set, its panel as tall as it needs.
local function SetWay(p, name, text)
	p.name:SetText(name)
	p.text:SetText(text)
	local height = 10 + (p.name:GetStringHeight() or 14) + 5 + (p.text:GetStringHeight() or 14) + 12
	p:SetHeight(math.max(64, height))
	return p:GetHeight()
end

-- The ways that are on, one under another, and the window sized round them.
local function PaintWays(f)
	local ways, height = {}, 0
	f.mouseWay:Hide()
	f.padWay:Hide()
	if ns.db and ns.db.doubleClick then
		local p = f.mouseWay
		if ns.UI and ns.UI.HasAtlas("newplayertutorial-icon-mouse-rightbutton") then
			p.picture:SetAtlas("newplayertutorial-icon-mouse-rightbutton")
			p.picture:SetSize(33, 44)
		else
			p.picture:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
			p.picture:SetSize(36, 36)
		end
		p.glyph:SetText("")
		height = height + SetWay(p, "鼠标", "装备鱼竿时，对水面双击右键施放；"
			.. "再次双击右键收杆。")
		ways[#ways + 1] = p
	end
	local C = ns.Controller
	if C and C.Glyph and ns.db and ns.db.padFishing then
		local p = f.padWay
		local button = ns.db.padButton or "PAD1"
		p.picture:SetTexture(nil)
		p.glyph:SetText(C.Glyph(button, 40))
		local start = C.StartLabel and C.StartLabel(ns.db.padStart)
		local lines = { "装备鱼竿时，" .. C.Glyph(button, 28) .. " 可施放与收杆，无需键盘键。" }
		if start and start ~= "Off" and start ~= "关闭" then
			lines[#lines + 1] = "没拿鱼竿？" .. start .. " 可先装上。"
		end
		lines[#lines + 1] = "|cffffd100在「选项 > 手柄」中可修改。|r"
		height = height + SetWay(p, "手柄", table.concat(lines, "\n"))
		ways[#ways + 1] = p
	end
	f.waysHeader:SetShown(#ways > 0)
	f.rule:SetShown(#ways > 0)
	local previous = f.waysHeader
	for _, p in ipairs(ways) do
		p:ClearAllPoints()
		p:SetPoint("TOP", previous, "BOTTOM", 0, previous == f.waysHeader and -8 or -6)
		p:Show()
		previous = p
	end
	-- Everything above the rule, the rule and header, the ways, and the frame round the inset.
	local top = EDGE + f.heading:GetStringHeight() + 10 + f.intro:GetStringHeight() + 16 + 44 + 10
		+ f.result:GetStringHeight()
	local below = #ways > 0 and (16 + 1 + 8 + f.waysHeader:GetStringHeight() + 8 + height + 6 * (#ways - 1)) or 0
	f:SetHeight(math.floor(60 + top + below + EDGE + 30))
end

local function CreateWelcome()
	local UI = ns.UI
	local f, inset = UI.CreateShell("OneCastWelcome", "欢迎使用哇，大鱼", "Interface\\Icons\\Trade_Fishing")
	f:SetSize(WIDTH, 480)
	f:SetPoint("CENTER", 0, 80)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	ns.UI.EscapeCloses(f)

	local heading = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.heading = heading
	heading:SetPoint("TOP", 0, -EDGE)
	heading:SetText("一键钓鱼")

	local intro = inset:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.intro = intro
	intro:SetPoint("TOP", heading, "BOTTOM", 0, -10)
	intro:SetWidth(WIDTH - 4 * EDGE)
	intro:SetJustifyH("CENTER")
	intro:SetSpacing(3)
	intro:SetText("按下施放；浮漂起水花时再按一次收杆。"
		.. "就这么简单。")

	f.result = inset:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.capture = Onboarding.CaptureButton(inset, 320, 44, function(text, replaced)
		f.result:SetText("|cff20ff20完成！|r 装备鱼竿后按 " .. WHITE .. text .. "|r 即可钓鱼。"
			.. (replaced and ("\n" .. GREY .. "原先绑定为 " .. replaced .. "。|r") or ""))
		f.done:SetText("完成")
		PaintWays(f)
	end, {
		unbound = "点击后按键",
		bound = function(text) return "当前按键：" .. WHITE .. text .. "|r  " .. GREY .. "（更改）|r" end,
	})
	f.capture:SetPoint("TOP", intro, "BOTTOM", 0, -16)
	f.capture:SetNormalFontObject("GameFontNormalLarge")
	f.capture:SetHighlightFontObject("GameFontHighlightLarge")

	f.result:SetPoint("TOP", f.capture, "BOTTOM", 0, -10)
	f.result:SetWidth(WIDTH - 4 * EDGE)
	f.result:SetJustifyH("CENTER")
	f.result:SetSpacing(3)
	f.result:SetText(GREY .. "也可使用 Shift、Ctrl 或 Alt 组合键，以及鼠标侧键。\n"
		.. "可随时在「选项 > 钓鱼」中修改。|r")

	-- The other ways, under a rule.
	f.rule = inset:CreateTexture(nil, "ARTWORK")
	f.rule:SetColorTexture(0.62, 0.48, 0.24, 0.5)
	f.rule:SetHeight(1)
	f.rule:SetPoint("TOP", f.result, "BOTTOM", 0, -16)
	f.rule:SetWidth(WIDTH - 2 * EDGE)
	f.waysHeader = inset:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.waysHeader:SetPoint("TOP", f.rule, "BOTTOM", 0, -8)
	f.waysHeader:SetText("其它钓鱼方式")
	f.mouseWay = WayPanel(inset)
	f.padWay = WayPanel(inset)

	local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	later:SetSize(110, 24)
	later:SetText("稍后")
	later:SetPoint("BOTTOMLEFT", 8, 3)
	later:SetScript("OnClick", function()
		f:Hide()
	end)

	f.done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.done:SetSize(110, 24)
	f.done:SetPoint("BOTTOMRIGHT", -8, 3)
	f.done:SetScript("OnClick", function()
		if ns.db then
			ns.db.welcomeDone = true
		end
		f:Hide()
	end)

	f:SetScript("OnShow", function(self)
		self.capture:Refresh()
		PaintWays(self)
		self.done:SetText(Onboarding.Bound() and "完成" or "跳过")
	end)
	f:SetScript("OnHide", function(self)
		StopCapture(self.capture)
	end)
	f:Hide()
	if ns.Controller then
		ns.Controller.Navigate(f, true)
	end
	return f
end

function Onboarding.Show()
	if InCombatLockdown() then
		ns.Print("欢迎窗口需在非战斗时打开，请输入 /onecast setup。")
		return
	end
	welcome = welcome or CreateWelcome()
	welcome:Show()
end

-- At login: the window, for a player with no way to cast yet who hasn't seen it too often;
-- otherwise a line in chat.
local function ControllerReady()
	local C = ns.Controller
	return C and C.Active and C.Active() and ns.db and ns.db.padFishing
end

function Onboarding.OnLogin()
	C_Timer.After(2, function()
		if Onboarding.Bound() or (welcome and welcome:IsShown()) then
			return
		end
		local db = ns.db or {}
		local shown = db.welcomeShown or 0
		if not db.welcomeDone and shown < MAX_SHOWN and not ControllerReady() and not InCombatLockdown() then
			db.welcomeShown = shown + 1
			Onboarding.Show()
		else
			ns.Print("尚未绑定施放键：输入 /onecast setup 设置，或装备鱼竿后双击右键。")
		end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
	if capturing then
		StopCapture(capturing) -- no binding in combat
	end
end)

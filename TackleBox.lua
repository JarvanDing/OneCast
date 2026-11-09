-- OneCast tackle box: one small button, shown while a pole is in the main hand, with the lure's
-- icon, count and time left. Left-click applies the chosen lure, right-click opens a separate
-- settings window, Shift-drag moves it.
--
-- Only the button is secure, and it can't be shown, hidden or moved in combat, so it goes away
-- just before combat starts and comes back after. The window only picks settings, so it's an
-- ordinary frame.

local _, ns = ...

local TackleBox = {}
ns.TackleBox = TackleBox

local Lure = ns.Lure

local TACKLE_ICON = 466035 -- file ID of the tackle box icon
local SIZE = 40
local DEFAULT_POINT = { "CENTER", "CENTER", 0, -220 }
local TICK = 0.5           -- seconds between redraws while shown
local WARN_LEFT = 30       -- seconds left when the button starts to pulse
-- Window layout, matching the stats window's.
local WINDOW_WIDTH, ROW_HEIGHT, STAT_HEIGHT = 340, 22, 17
local HEADER_HEIGHT, SECTION_GAP = 26, 6
local INSET_TOP, INSET_BOTTOM = 60, 28 -- the frame around the inset (see CreateShell)
local COUNT_WIDTH, MINUTES_WIDTH, BONUS_WIDTH = 30, 26, 32

local button, window
local inCombat = false

local function CharDB()
	return OneCastCharDB
end

-- The button --------------------------------------------------------------------------------

local function PlaceButton()
	local p = CharDB().tacklePoint or DEFAULT_POINT
	button:ClearAllPoints()
	button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("工具箱")
	local left = Lure.Left()
	local casting = Lure.IsCasting()
	if casting then
		GameTooltip:AddLine("正在使用 " .. Lure.Name(casting) .. "…", 1, 1, 1)
	elseif left > 0 then
		local shown = Lure.Shown()
		GameTooltip:AddLine(string.format("%s 已装上，剩余 %s。", shown and Lure.Name(shown) or "诱饵",
			Lure.Clock(left)), 1, 1, 1)
	else
		local lure, reason, about = Lure.Selected()
		if lure then
			GameTooltip:AddLine(string.format("%s 就绪：+%d 钓鱼，持续 %d 分钟。", Lure.Name(lure), lure.bonus,
				lure.minutes), 1, 1, 1)
		else
			GameTooltip:AddLine(Lure.ReasonText(reason, about), 1, 0.3, 0.3)
		end
	end
	GameTooltip:AddLine(" ")
	if Lure.Choice() == Lure.NONE then
		GameTooltip:AddLine("左键：选择诱饵", 0.6, 0.8, 1)
	elseif left > 0 then
		GameTooltip:AddLine("Ctrl-点击：替换诱饵", 0.6, 0.8, 1)
	else
		GameTooltip:AddLine("左键：上饵", 0.6, 0.8, 1)
	end
	GameTooltip:AddLine("右键：工具箱设置", 0.6, 0.8, 1)
	GameTooltip:AddLine("Shift-拖动：移动", 0.6, 0.8, 1)
	GameTooltip:Show()
end

local function Redraw()
	if not button or not button:IsShown() then
		return
	end
	local left = Lure.Left()
	local shown = Lure.Shown()
	local ready = Lure.Selected() ~= nil
	button.icon:SetTexture(shown and Lure.Icon(shown) or TACKLE_ICON)
	button.icon:SetDesaturated(left <= 0 and not ready)
	button.count:SetText(shown and Lure.Count(shown) or "")
	if Lure.IsCasting() then
		button.time:SetText("...")
	else
		button.time:SetText(left > 0 and Lure.Clock(left) or "")
	end
	button.glow:SetShown(left <= 0 and ready)
	-- Running out: pulse, once a tick, so it catches the eye without a sound.
	local pulse = left > 0 and left <= WARN_LEFT and math.floor(GetTime() / TICK) % 2 == 0
	button.icon:SetAlpha(pulse and 0.45 or 1)
end

local function CreateButton()
	local b = CreateFrame("Button", "OneCastTackleButton", UIParent, "SecureActionButtonTemplate")
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetClampedToScreen(true)
	b:SetMovable(true)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	b.border:SetAllPoints()
	b.border:SetVertexColor(0.65, 0.55, 0.35)
	b.glow = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	b.glow:SetBlendMode("ADD")
	b.glow:SetAllPoints()
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	b.time:SetPoint("TOP", b, "BOTTOM", 0, -2)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")

	-- A Shift-press is the start of a move, not a use of the lure.
	Lure.WireButton(b, function()
		return not IsShiftKeyDown() and Lure.Choice() ~= Lure.NONE
	end, true)
	b:HookScript("PostClick", function(_, mouseButton, down)
		if down then
			return
		end
		if mouseButton == "RightButton"
			or (mouseButton == "LeftButton" and Lure.Choice() == Lure.NONE and not IsShiftKeyDown()) then
			TackleBox.ToggleWindow()
		end
	end)

	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() and not InCombatLockdown() then
			self:StartMoving()
			self.moving = true
		end
	end)
	b:SetScript("OnDragStop", function(self)
		if self.moving then
			self:StopMovingOrSizing()
			self.moving = false
			local point, _, relPoint, x, y = self:GetPoint()
			CharDB().tacklePoint = { point, relPoint, x, y }
		end
	end)
	b:SetScript("OnEnter", ShowTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	local elapsed = 0
	b:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= TICK then
			elapsed = 0
			Redraw()
		end
	end)
	b:Hide()
	return b
end

-- Show it if it should be, unless combat has the button locked.
local function UpdateVisibility()
	if not button or InCombatLockdown() then
		return
	end
	button:SetShown(ns.db.tackleBox and Lure.MainHandPole() and not inCombat)
	Redraw()
end

-- The window --------------------------------------------------------------------------------
-- Built from the stats window's own parts (ns.UI): the same bronze portrait frame, inset,
-- section headers, alternating rows and gold stat lines.

local function RowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.lure then
		GameTooltip:SetItemByID(self.lure.id)
		if not Lure.SkillOK(self.lure) then
			GameTooltip:AddLine(string.format("需要钓鱼 %d。", self.lure.req), 1, 0.3, 0.3)
		end
	else
		GameTooltip:SetText(self.title)
		GameTooltip:AddLine(self.tip, 1, 1, 1, true)
	end
	GameTooltip:Show()
end

local function CreateRow(parent, index, y)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 10, y)
	row:SetPoint("TOPRIGHT", -10, y)
	ns.UI.RowBackground(row, index)
	row.selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(1, 0.82, 0, 0.16)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.border = row:CreateTexture(nil, "OVERLAY")
	row.border:SetAllPoints(row.icon)
	row.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	row.border:SetVertexColor(0.65, 0.55, 0.35)
	-- The same tick the collection book puts on what you've caught.
	row.check = row:CreateTexture(nil, "OVERLAY", nil, 2)
	row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	row.check:SetSize(14, 14)
	row.check:SetPoint("CENTER", row.icon, "TOPRIGHT", -2, -2)

	row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.count:SetPoint("RIGHT", -6, 0)
	row.count:SetWidth(COUNT_WIDTH)
	row.count:SetJustifyH("RIGHT")
	row.minutes = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.minutes:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
	row.minutes:SetWidth(MINUTES_WIDTH)
	row.minutes:SetJustifyH("RIGHT")
	row.bonus = row:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
	row.bonus:SetPoint("RIGHT", row.minutes, "LEFT", -4, 0)
	row.bonus:SetWidth(BONUS_WIDTH)
	row.bonus:SetJustifyH("RIGHT")
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.bonus, "LEFT", -4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function CreateCheck(parent, index, y, label, tooltip, key)
	local line = CreateFrame("Frame", nil, parent)
	line:SetHeight(ROW_HEIGHT)
	line:SetPoint("TOPLEFT", 10, y)
	line:SetPoint("TOPRIGHT", -10, y)
	ns.UI.RowBackground(line, index)
	local check = CreateFrame("CheckButton", nil, line, "UICheckButtonTemplate")
	check:SetSize(ROW_HEIGHT, ROW_HEIGHT)
	check:SetPoint("LEFT", 2, 0)
	check.label = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- gold, like the stat lines
	check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	check.label:SetText(label)
	check:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Lure.SetOption(key, self:GetChecked() and true or false)
	end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(label)
		GameTooltip:AddLine(tooltip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	return check
end

-- One line under the title: what's on the pole, or what would go on.
local function StatusText()
	local casting = Lure.IsCasting()
	if casting then
		return "|cffffd100正在使用 " .. Lure.Name(casting) .. "…|r"
	end
	local left = Lure.Left()
	if left > 0 then
		local shown = Lure.Shown()
		return string.format("|cff1eff00%s 已装上|r  |cffffffff剩余 %s|r", shown and Lure.Name(shown) or "诱饵",
			Lure.Clock(left))
	end
	local lure, reason, about = Lure.Selected()
	if lure then
		return "|cffffd100" .. Lure.Name(lure) .. " 可上饵|r"
	elseif reason == "none" then
		return "|cff9d9d9d鱼竿上没有诱饵。|r"
	end
	return "|cffff4040" .. Lure.ReasonText(reason, about) .. "|r"
end

local function RedrawWindow()
	if not window or not window:IsShown() then
		return
	end
	window.status:SetText(StatusText())
	local choice = Lure.Choice()
	for _, row in ipairs(window.rows) do
		local chosen = row.value == choice
		row.selected:SetShown(chosen)
		row.check:SetShown(chosen)
		if row.lure then
			local count = Lure.Count(row.lure)
			local usable = count > 0 and Lure.SkillOK(row.lure)
			row.icon:SetDesaturated(not usable)
			row.icon:SetAlpha(usable and 1 or 0.6)
			row.name:SetText(Lure.Name(row.lure))
			if usable then
				row.name:SetTextColor(1, 1, 1)
				row.count:SetTextColor(1, 1, 1)
			else
				row.name:SetTextColor(0.55, 0.55, 0.55)
				row.count:SetTextColor(0.55, 0.55, 0.55)
			end
			row.bonus:SetText("+" .. row.lure.bonus)
			row.minutes:SetText(row.lure.minutes .. "分钟")
			row.count:SetText("×" .. count)
		end
	end
	window.autoLure:SetChecked(CharDB().autoLure)
	window.tackleBox:SetChecked(ns.db.tackleBox)

	local rates = ns.Stats and ns.Stats.LureRates and ns.Stats.LureRates() or {}
	window.rateWith.value:SetText(rates.with and string.format("%.0f", rates.with) or "-")
	window.rateWithout.value:SetText(rates.without and string.format("%.0f", rates.without) or "-")
end

local function CreateWindow()
	local UI = ns.UI
	local f, inset = UI.CreateShell("OneCastTackleWindow", "工具箱", TACKLE_ICON)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		CharDB().tackleWindowPoint = { point, relPoint, x, y }
	end)
	tinsert(UISpecialFrames, f:GetName())
	UI.KeepOpenThroughOptions(f:GetName())

	-- Where the stats window has its tabs: right of the portrait, above the inset.
	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 62, 6)
	f.status:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
	f.status:SetJustifyH("LEFT")
	f.status:SetWordWrap(false)

	local y = -6
	UI.SectionHeader(inset, y).text:SetText("使用的诱饵")
	y = y - HEADER_HEIGHT

	local entries = {
		{ value = Lure.NONE, title = "不使用诱饵", icon = TACKLE_ICON,
			tip = "不消耗任何诱饵，仅用自身技能钓鱼。" },
		{ value = Lure.BEST, title = "能用的最好诱饵", icon = "Interface\\Icons\\INV_Misc_Fish_68",
			tip = "从背包中选取技能允许的最高加成诱饵。可能会消耗你最稀有的诱饵。" },
	}
	for _, lure in ipairs(Lure.LIST) do
		entries[#entries + 1] = { value = lure.id, lure = lure }
	end
	f.rows = {}
	for i, entry in ipairs(entries) do
		local row = CreateRow(inset, i, y)
		row.value, row.lure, row.title, row.tip = entry.value, entry.lure, entry.title, entry.tip
		if entry.lure then
			row.icon:SetTexture(Lure.Icon(entry.lure))
		else
			row.icon:SetTexture(entry.icon)
			row.name:SetText(entry.title)
		end
		row:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Lure.SetOption("lureChoice", self.value)
		end)
		f.rows[i] = row
		y = y - ROW_HEIGHT
	end

	y = y - SECTION_GAP
	UI.SectionHeader(inset, y).text:SetText("选项")
	y = y - HEADER_HEIGHT
	f.autoLure = CreateCheck(inset, 1, y, "用施法键上饵",
		"鱼竿上没有诱饵时，施法键先使用你选定的诱饵，再按一次才抛竿。会消耗诱饵，因此默认关闭。",
		"autoLure")
	y = y - ROW_HEIGHT
	f.tackleBox = CreateCheck(inset, 2, y, "显示工具箱按钮",
		"主手装备鱼竿时显示该按钮。隐藏后可用 /onecast tackle 打开本窗口。",
		"tackleBox")
	y = y - ROW_HEIGHT

	y = y - SECTION_GAP
	UI.SectionHeader(inset, y).text:SetText("每小时鱼数")
	y = y - HEADER_HEIGHT
	f.rateWith = UI.StatRow(inset, 1, y)
	f.rateWith.label:SetText("有诱饵")
	y = y - STAT_HEIGHT
	f.rateWithout = UI.StatRow(inset, 2, y)
	f.rateWithout.label:SetText("无诱饵")
	y = y - STAT_HEIGHT

	-- The bottom bar's Options button, as on the stats window.
	local options = UI.IconButton(f, "Options", "选项", function()
		if ns.OpenSettings then
			ns.OpenSettings()
		end
	end)
	options:SetPoint("BOTTOMRIGHT", -22, 3)
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", f, "BOTTOMLEFT", 12, 15)
	hint:SetPoint("RIGHT", options, "LEFT", -6, 0)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)
	hint:SetText("选定的诱饵不会自动换成别的。")

	f:SetSize(WINDOW_WIDTH, INSET_TOP - y + 8 + INSET_BOTTOM)
	local p = CharDB().tackleWindowPoint
	if p then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("CENTER", 0, 40)
	end
	f:SetScript("OnShow", function(self)
		self:SetScale((ns.db.statsScale or 100) / 100) -- same size as the stats window
		RedrawWindow()
	end)
	local elapsed = 0
	f:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta
		if elapsed >= TICK then
			elapsed = 0
			self.status:SetText(StatusText())
		end
	end)
	f:Hide()
	return f
end

function TackleBox.ToggleWindow()
	window = window or CreateWindow()
	window:SetShown(not window:IsShown())
end

-- False if it can't be done now: the button can't move during a fight.
function TackleBox.ResetPosition()
	if InCombatLockdown() then
		return false
	end
	CharDB().tacklePoint = nil
	if button then
		PlaceButton()
	end
	return true
end

-- Global for the "Tackle box" key binding.
function OneCast_ToggleTackle()
	TackleBox.ToggleWindow()
end

Lure.OnChange(function()
	UpdateVisibility()
	RedrawWindow()
end)

-- Made once, out of combat: a reload during a fight waits for it to end.
local function BuildButton()
	if not button and not InCombatLockdown() then
		button = CreateButton()
		PlaceButton()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		inCombat = InCombatLockdown()
		BuildButton()
		UpdateVisibility()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- The last moment before lockdown.
		inCombat = true
		if button then
			button:Hide()
		end
	else
		inCombat = false
		BuildButton()
		UpdateVisibility()
	end
end)

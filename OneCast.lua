-- OneCast: one-button fishing for WoW Forever (interface 16001, modern addon API).
--
-- How it works, without secure snippets (loadstring_untainted is missing on Forever,
-- so SecureHandler templates are out):
--   * OneCastButton is a plain SecureActionButton that casts Fishing. Bind a key to it
--     in Options > Keybindings > AddOns > OneCast, or double right-click with a pole.
--   * When the Fishing channel starts, that same key is overridden to INTERACTTARGET
--     and soft-interact is switched on, so the next press reels in the bobber.
--   * When the channel ends the override is dropped and the key casts again.
-- Every cast and every reel is still one hardware press by the player.

local ADDON, ns = ...

-- From the TOC's ## Version line, so there's one place to bump it.
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
-- Player-facing name (folder / SavedVariables stay OneCast for upstream merges).
ns.DISPLAY_NAME = "哇，大鱼"

local FISHING_SPELL_IDS = { 7620, 131474 } -- Classic rank 1, modern profession spell
local DOUBLE_CLICK_WINDOW = 0.4
local BUTTON_NAME = "OneCastButton"
local BINDING_COMMAND = "CLICK " .. BUTTON_NAME .. ":LeftButton"

local defaults = {
	doubleClick = true,
	softInteract = true,
	soundBoost = true,
	quietOthers = false,
	quietLevel = 0, -- percent of the player's own music, ambience and dialog volume
	minimapButton = true,
	minimapAngle = 225,
	alert = true,
	alertQuality = 2, -- Uncommon
	openOnCast = true,
	loginMessage = true,
	statsScale = 100, -- percent
	autoEquip = true,
	restoreOnCombat = true,
	restoreDelay = 60, -- seconds without casting before weapons go back on; 0 = never
	sessionSummary = true,
	autoLootHint = true,
	extravaganza = true,
	bagWarning = true,
	tackleBox = true,
	lureVendorHint = true,
	rememberPools = true,
	bobberMarker = false,
}
-- Per character: skill and bags differ, and lures get used up.
local charDefaults = {
	autoLure = false,
	lureChoice = 0, -- Lure.NONE
}

-- Options shown in the settings panel and toggled by /onecast <cmd>, in display order.
local OPTIONS = {
	{ section = "施放", cmd = "doubleclick", key = "doubleClick", label = "双击右键施放钓鱼",
		tooltip = "装备鱼竿时，双击右键世界即可施放；右键浮漂收杆。" },
	{ cmd = "softinteract", key = "softInteract", label = "钓鱼时启用软交互",
		tooltip = "鱼线抛出后，将浮漂设为软交互目标，以便施法键直接收杆。" },
	{ cmd = "bobbermarker", key = "bobberMarker", label = "标记自己的浮漂",
		tooltip = "鱼线抛出后，在自己的浮漂上显示游戏的装备图标，方便区分别人的水花。鱼咬钩时无法显示：游戏不会把咬钩告诉插件。" },
	{ cmd = "bagwarning", key = "bagWarning", label = "背包满时警告",
		tooltip = "背包没有空位时抛竿会警告一次，以免渔获装不下。" },
	{ section = "声音", cmd = "sound", key = "soundBoost", label = "钓鱼时放大水花音效",
		tooltip = "鱼线抛出后，将音效调至最大，方便听清水花声。" },
	{ cmd = "quiet", key = "quietOthers", label = "钓鱼时压低其他声音",
		tooltip = "装备鱼竿时，降低（或关闭）音乐、环境音和对白，突出水花声。换回武器后，或你手动改音量后，会恢复为你自己的音量。" },
	{ section = "鱼竿与武器", cmd = "autoequip", key = "autoEquip", label = "自动装备鱼竿",
		tooltip = "未装备鱼竿时，施法键先从背包装备最好的鱼竿（再按一次才施放）。原武器会记住，之后自动换回。" },
	{ cmd = "combatgear", key = "restoreOnCombat", label = "进入战斗时换回武器",
		tooltip = "一进入战斗就尝试换回武器。战斗中被游戏拦住的换装，会在脱战后补完。" },
	{ section = "工具箱", cmd = "tacklebox", key = "tackleBox", label = "显示工具箱按钮",
		tooltip = "主手装备鱼竿时显示小按钮，含诱饵、数量与剩余时间。左键上饵，右键打开设置，Shift-拖动可移动。" },
	{ cmd = "autolure", key = "autoLure", char = true, label = "用施法键上饵",
		tooltip = "鱼竿上没有诱饵时，施法键先使用你选定的诱饵，再按一次才抛竿。会消耗诱饵，因此默认关闭。按角色单独设置。" },
	{ cmd = "lurevendor", key = "lureVendorHint", label = "商人处提示诱饵不足",
		tooltip = "在售卖你选定诱饵的商人处，若持有少于 5 个会在聊天提示。买不买由你决定。" },
	{ section = "统计窗口", cmd = "autoopen", key = "openOnCast", label = "施放时打开统计窗口",
		tooltip = "开始钓鱼时打开统计窗口。若用关闭按钮或小地图按钮关掉，会保持关闭，直到你暂停钓鱼约 2 分钟。" },
	{ cmd = "summary", key = "sessionSummary", label = "聊天中显示会话摘要",
		tooltip = "暂停钓鱼约 2 分钟后，在聊天汇总本次：渔获、每小时鱼数、商人售价、技能提升和图鉴新鱼。" },
	{ cmd = "autoloot", key = "autoLootHint", label = "提示开启自动拾取",
		tooltip = "钓到东西时若未开启自动拾取，每次登录最多提示一次，方便渔获直接进包。" },
	{ section = "图鉴与提醒", cmd = "alert", key = "alert", label = "稀有渔获提醒",
		tooltip = "钓到达到提醒品质或以上的物品，或你标记为想要的物品时，播放音效并闪现团队警告（在统计窗口右键可标记想要）。" },
	{ cmd = "pools", key = "rememberPools", label = "记住钓鱼鱼群点",
		tooltip = "装备鱼竿时将鼠标悬停在鱼群上并抛竿，会把钓点标在图鉴的区域地图上。鱼群会移动，标记表示曾经出现过的位置。目前仅识别英文鱼群名。/onecast forgetpools 可清除。" },
	{ cmd = "extravaganza", key = "extravaganza", label = "荆棘谷钓鱼大赛提醒",
		tooltip = "荆棘谷钓鱼大赛即将开始及开始时在聊天提示（经典日程：服务器时间周日 14:00–16:00）。" },
	{ section = "界面", cmd = "loginmessage", key = "loginMessage", label = "登录时在聊天显示版本",
		tooltip = "登录时在聊天显示插件版本，并附带「更新内容」链接。" },
	{ cmd = "minimap", key = "minimapButton", label = "显示小地图按钮",
		tooltip = "在小地图上显示「哇，大鱼」按钮。可拖动调整位置。" },
}

-- CVars changed only for the length of a cast, and restored afterwards only if
-- nothing else changed them in the meantime.
local SOFT_INTERACT_CVARS = {
	SoftTargetInteract = "3",      -- always soft-target interactables
	SoftTargetInteractArc = "2",   -- 360 degrees
	SoftTargetInteractRange = "30",
}
-- The game's gear icon over the soft-interact target: your bobber, and nobody else's.
local BOBBER_MARKER_CVARS = {
	SoftTargetIconGameObject = "1",
	SoftTargetIconInteract = "1",
}
-- Sound effects raised for the cast. Music, ambience and dialog are only touched by the
-- separate "quiet" option (QUIET_CVARS), which follows the pole rather than the cast.
local SOUND_CVARS = {
	Sound_EnableSFX = "1",
	Sound_SFXVolume = "1",
}

_G.BINDING_HEADER_ONECAST = "哇，大鱼"
_G["BINDING_NAME_" .. BINDING_COMMAND] = "施放 / 收杆（一键钓鱼）"
_G.BINDING_NAME_ONECAST_RESTORE = "换回武器"
_G.BINDING_NAME_ONECAST_BOOK = "钓鱼图鉴"

local db
local fishingName
local fishing = false
local lastRightClick = 0
-- Borrowed CVars by group, each cvar -> { original = value, ours = value }: "cast" for the
-- length of one cast, "quiet" for as long as the pole is equipped. No CVar is in both.
local leases = { cast = {}, quiet = {} }
-- Turned down while the pole is on, to quietLevel percent of the player's own volume.
local QUIET_CVARS = { "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume" }

-- Separate owners so dropping the double-click override never drops the reel one.
local reelOwner = CreateFrame("Frame")
local clickOwner = CreateFrame("Frame")

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33bbff哇，大鱼|r: " .. msg)
end
ns.Print = Print
ns.GetFishingName = function()
	return fishingName
end
ns.IsFishing = function()
	return fishing
end

local function SpellName(spellID)
	if C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellID)
	end
	local info = C_Spell.GetSpellInfo(spellID)
	return info and info.name
end

local function ResolveFishingName()
	for _, id in ipairs(FISHING_SPELL_IDS) do
		local name = SpellName(id)
		if name then
			return name
		end
	end
end

local function IsFishingPole(slot)
	return ns.Gear.IsPole(GetInventoryItemID("player", slot))
end

local function HasFishingPole()
	-- Main hand on Classic-style characters; the profession tool slot (28) on modern ones.
	return IsFishingPole(INVSLOT_MAINHAND or 16) or IsFishingPole(28)
end
ns.HasFishingPole = HasFishingPole

local function LeaseCVars(group, cvars)
	local leased = leases[group]
	for name, value in pairs(cvars) do
		local current = C_CVar.GetCVar(name)
		if current ~= nil and not leased[name] then
			C_CVar.SetCVar(name, value)
			-- Read back: the game may store the number formatted its own way.
			leased[name] = { original = current, ours = C_CVar.GetCVar(name) }
		end
	end
end

-- Give the group's CVars back, each only if it still holds OneCast's value.
local function ReleaseCVars(group)
	local leased = leases[group]
	for name, lease in pairs(leased) do
		if C_CVar.GetCVar(name) == lease.ours then
			C_CVar.SetCVar(name, lease.original)
		end
		leased[name] = nil
	end
end

-- Quiet music, ambience and dialog while a pole is equipped, if the option is on.
local function UpdateQuiet(reapply)
	local want = db and db.quietOthers and HasFishingPole()
	local active = next(leases.quiet) ~= nil
	if active and (reapply or not want) then
		ReleaseCVars("quiet")
		active = false
	end
	if want and not active then
		local level = math.max(0, math.min(100, db.quietLevel or 0)) / 100
		local cvars = {}
		for _, name in ipairs(QUIET_CVARS) do
			local current = tonumber(C_CVar.GetCVar(name))
			if current then
				cvars[name] = tostring(math.floor(current * level * 100 + 0.5) / 100)
			end
		end
		LeaseCVars("quiet", cvars)
	end
end

-- Warn once each time the bags fill up, when a line goes out.
local bagsFullWarned = false

local function CheckBagSpace()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local slots, family = C_Container.GetContainerNumFreeSlots(bag)
		if (family or 0) == 0 then
			free = free + (slots or 0)
		end
	end
	if free > 0 then
		bagsFullWarned = false
	elseif db.bagWarning and not bagsFullWarned then
		bagsFullWarned = true
		Print("背包已满，渔获可能装不下。")
		if UIErrorsFrame then
			UIErrorsFrame:AddMessage("背包已满", 1, 0.3, 0.1)
		end
	end
end

local function StartReelMode()
	if InCombatLockdown() then
		return
	end
	if db.softInteract or db.bobberMarker then -- the icon goes on the soft-interact target
		LeaseCVars("cast", SOFT_INTERACT_CVARS)
	end
	if db.bobberMarker then
		LeaseCVars("cast", BOBBER_MARKER_CVARS)
	end
	if db.soundBoost then
		LeaseCVars("cast", SOUND_CVARS)
	end
	for _, key in ipairs({ GetBindingKey(BINDING_COMMAND) }) do
		SetOverrideBinding(reelOwner, true, key, "INTERACTTARGET")
	end
end

local function StopReelMode()
	if not InCombatLockdown() then
		ClearOverrideBindings(reelOwner)
	end
	ReleaseCVars("cast")
end

local equippingPress = false -- the key went down and equipped a pole, and hasn't come up yet
local reelEndedAt = 0        -- when the line last came in
local doubleClickArmed = false -- a double right-click's mouse-up is about to cast
local REEL_RELEASE_WINDOW = 1 -- seconds a key-up still counts as releasing that reel-in

-- The secure cast button. Attributes are set once, out of combat, at login.
local button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetAttribute("type", "spell")
button:HookScript("PreClick", function(self, _, down)
	if InCombatLockdown() then
		return
	end
	-- The line can come in before the key does: the release of a reel-in press isn't a cast.
	local reelRelease = not down and not doubleClickArmed and GetTime() - reelEndedAt < REEL_RELEASE_WINDOW
	reelEndedAt = 0
	if reelRelease then
		self:SetAttribute("type", nil)
		return
	end
	-- The pole can land before the key comes up: the press that equipped it stays spent.
	local equippedOnDown = equippingPress
	equippingPress = false
	if equippedOnDown and not down then
		self:SetAttribute("type", nil)
		return
	end
	-- No pole equipped: this press equips one from the bags (Gear.lua) instead of casting.
	if ns.Gear.PreClick() then
		self:SetAttribute("type", nil)
		equippingPress = down
		return
	end
	-- A lure wanted, or one going on: this press applies it or waits, instead of casting.
	local lure = ns.Lure.CastPress(down)
	if lure == "wait" then
		self:SetAttribute("type", nil)
	elseif lure then
		self:SetAttribute("type", "macro")
		self:SetAttribute("macrotext", lure)
	end
end)
button:HookScript("PostClick", function(self)
	if not InCombatLockdown() then
		self:SetAttribute("type", "spell")
		self:SetAttribute("macrotext", nil)
		-- The double-click override is one-shot: hand right-click back to the camera.
		ClearOverrideBindings(clickOwner)
		doubleClickArmed = false
	end
end)

-- Double right-click on the world casts. The second press's mouse-down rebinds
-- BUTTON2 to the cast button, so its mouse-up fires the cast.
WorldFrame:HookScript("OnMouseDown", function(_, mouseButton)
	if mouseButton ~= "RightButton" or not db or not db.doubleClick then
		return
	end
	if fishing or InCombatLockdown() or not HasFishingPole() then
		return
	end
	local now = GetTime()
	if now - lastRightClick <= DOUBLE_CLICK_WINDOW then
		lastRightClick = 0
		SetOverrideBindingClick(clickOwner, true, "BUTTON2", BUTTON_NAME)
		doubleClickArmed = true
	else
		lastRightClick = now
	end
end)

local function BoundKeysText()
	local keys = { GetBindingKey(BINDING_COMMAND) }
	return #keys > 0 and table.concat(keys, ", ") or "未绑定"
end

-- Minimap button: a plain round button orbiting the minimap, dragged to any angle.
local minimapButton

-- Round unless a minimap addon says otherwise through GetMinimapShape, the convention
-- minimap buttons share (Forever's minimap can be round or square).
local function MinimapIsRound()
	return not GetMinimapShape or GetMinimapShape() == "ROUND"
end

local function UpdateMinimapPosition()
	local angle = math.rad(db.minimapAngle)
	local x, y = math.cos(angle), math.sin(angle)
	local halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	if MinimapIsRound() then
		x, y = x * (halfW + 5), y * (halfH + 5)
	else
		-- Slide along the square's edge instead of a circle.
		local edge = math.max(math.abs(x), math.abs(y))
		x, y = x / edge * (halfW + 10), y / edge * (halfH + 10)
	end
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateMinimapVisibility()
	if minimapButton then
		minimapButton:SetShown(db.minimapButton)
	end
end

-- Settings panel (Options > AddOns > OneCast).
local settingsCategory

local function OpenSettings()
	if InCombatLockdown() then
		Print("战斗中无法打开选项。")
		return
	end
	Settings.OpenToCategory(settingsCategory:GetID())
end
ns.OpenSettings = OpenSettings

local function SetupSettings()
	local category, layout = Settings.RegisterVerticalLayoutCategory(ns.DISPLAY_NAME)
	if CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(ns.DISPLAY_NAME .. " v" .. ns.VERSION))
	end
	-- Kept out of the settings search (the last argument here, SetSearchIgnoredInLayout on the
	-- key below): Blizzard does the same for its own buttons that open something, and addon
	-- entries in the search results were reported to raise ADDON_ACTION_FORBIDDEN.
	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("钓鱼图鉴", "打开图鉴", function()
			ns.Book.Show()
		end, "全部鱼类、你已钓到的，以及其余鱼的出没地点。", false))
		layout:AddInitializer(CreateSettingsButtonInitializer("更新内容", "更新内容", function()
			ns.WhatsNew.Show()
		end, "查看「哇，大鱼」各版本的改动。", false))
	end

	-- The cast/reel key, editable right here (same binding as Keybindings > AddOns).
	if CreateKeybindingEntryInitializer then
		for i = 1, GetNumBindings() do
			if GetBinding(i) == BINDING_COMMAND then
				if CreateSettingsListSectionHeaderInitializer then
					layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("按键"))
				end
				local keyEntry = CreateKeybindingEntryInitializer(i, true)
				if keyEntry.SetSearchIgnoredInLayout then
					keyEntry:SetSearchIgnoredInLayout(layout)
				end
				layout:AddInitializer(keyEntry)
				break
			end
		end
	end
	ns.optionSettings = {}
	for _, opt in ipairs(OPTIONS) do
		if opt.section and CreateSettingsListSectionHeaderInitializer then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(opt.section))
		end
		local default = defaults[opt.key]
		if opt.char then
			default = charDefaults[opt.key]
		end
		local setting = Settings.RegisterAddOnSetting(category, "OneCast_" .. opt.key, opt.key,
			opt.char and OneCastCharDB or db, "boolean", opt.label, default)
		if opt.key == "minimapButton" then
			setting:SetValueChangedCallback(UpdateMinimapVisibility)
		elseif opt.key == "quietOthers" then
			setting:SetValueChangedCallback(function()
				UpdateQuiet()
			end)
		elseif opt.key == "tackleBox" or opt.key == "autoLure" then
			setting:SetValueChangedCallback(function()
				ns.Lure.OnSettingChanged()
			end)
		end
		Settings.CreateCheckbox(category, setting, opt.tooltip)
		opt.setting = setting
		ns.optionSettings[opt.key] = setting

		if opt.key == "tackleBox" and Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local choice = Settings.RegisterAddOnSetting(category, "OneCast_lureChoice", "lureChoice",
				OneCastCharDB, "number", "使用的诱饵", charDefaults.lureChoice)
			choice:SetValueChangedCallback(function()
				ns.Lure.OnSettingChanged()
			end)
			ns.optionSettings.lureChoice = choice
			Settings.CreateDropdown(category, choice, function()
				local container = Settings.CreateControlTextContainer()
				container:Add(ns.Lure.NONE, "不使用诱饵")
				container:Add(ns.Lure.BEST, "能用的最好诱饵")
				for _, lure in ipairs(ns.Lure.LIST) do
					container:Add(lure.id, string.format("%s（+%d）", ns.Lure.Name(lure), lure.bonus))
				end
				return container:GetData()
			end, "工具箱、「上饵」按键与施法键使用的诱饵。选定后不会自动换成别的：用完后会不带诱饵继续钓。「能用的最好诱饵」可能消耗你最稀有的诱饵。按角色单独设置。")
		end

		if opt.key == "autoEquip" and Settings.CreateSlider and Settings.CreateSliderOptions then
			local delay = Settings.RegisterAddOnSetting(category, "OneCast_restoreDelay", "restoreDelay",
				db, "number", "之后换回武器", defaults.restoreDelay)
			local options = Settings.CreateSliderOptions(0, 300, 15)
			if MinimalSliderWithSteppersMixin then
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
					return value == 0 and "从不" or (value .. " 秒")
				end)
			end
			Settings.CreateSlider(category, delay, options,
				"多少秒未施放后换回武器。0 表示一直拿着鱼竿，直到你手动换装。")
		end

		if opt.key == "quietOthers" and Settings.CreateSlider and Settings.CreateSliderOptions then
			local level = Settings.RegisterAddOnSetting(category, "OneCast_quietLevel", "quietLevel",
				db, "number", "钓鱼时其他声音", defaults.quietLevel)
			level:SetValueChangedCallback(function()
				UpdateQuiet(true)
			end)
			local options = Settings.CreateSliderOptions(0, 100, 5)
			if MinimalSliderWithSteppersMixin then
				options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
					return value == 0 and "静音" or (value .. "%")
				end)
			end
			Settings.CreateSlider(category, level, options,
				"装备鱼竿时，音乐、环境音和对白保留为你原音量的百分之几。0 为静音。")
		end

		if opt.key == "openOnCast" then
			local scale = Settings.RegisterAddOnSetting(category, "OneCast_statsScale", "statsScale",
				db, "number", "统计窗口缩放", defaults.statsScale)
			scale:SetValueChangedCallback(function(_, value)
				ns.Stats.SetScale(value)
			end)
			ns.scaleSetting = scale
			if Settings.CreateSlider and Settings.CreateSliderOptions then
				local options = Settings.CreateSliderOptions(50, 200, 5)
				if MinimalSliderWithSteppersMixin then
					options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
						return value .. "%"
					end)
				end
				Settings.CreateSlider(category, scale, options,
					"统计窗口大小。也可拖动右下角，或在窗口上按 Ctrl + 鼠标滚轮。")
			end
		end

		if opt.key == "alert" and Settings.CreateDropdown and Settings.CreateControlTextContainer then
			local quality = Settings.RegisterAddOnSetting(category, "OneCast_alertQuality", "alertQuality",
				db, "number", "提醒品质", defaults.alertQuality)
			Settings.CreateDropdown(category, quality, function()
				local container = Settings.CreateControlTextContainer()
				for q = 2, 5 do
					local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
					local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
					container:Add(q, (color and color.hex or "") .. label .. (color and "|r" or "") .. " 及以上")
				end
				return container:GetData()
			end, "触发稀有渔获提醒的最低物品品质。")
		end
	end

	Settings.RegisterAddOnCategory(category)
	settingsCategory = category
end

local function SetupMinimapButton()
	local b = CreateFrame("Button", "OneCastMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("AnyUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = b:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("CENTER")

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_68")
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("CENTER")

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.Stats.Toggle()
		elseif IsShiftKeyDown() then
			ns.Book.Toggle()
		else
			OpenSettings()
		end
	end)

	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
			UpdateMinimapPosition()
		end)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddDoubleLine(ns.DISPLAY_NAME, "v" .. ns.VERSION, nil, nil, nil, 0.6, 0.6, 0.6)
		GameTooltip:AddLine("施放 / 收杆：" .. BoundKeysText(), 1, 1, 1)
		GameTooltip:AddLine(ns.Stats.Summary(), 1, 1, 1)
		local lure = ns.Lure.StatusLine()
		if lure then
			GameTooltip:AddLine(lure, 1, 1, 1)
		end
		local contest = ns.Extravaganza and ns.Extravaganza.StatusLine(GetRealZoneText())
		if contest then
			GameTooltip:AddLine("钓鱼大赛：" .. contest, 1, 1, 1)
		end
		GameTooltip:AddLine("左键：选项", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("右键：会话统计", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Shift+点击：钓鱼图鉴", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("拖动：移动", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)

	minimapButton = b
	UpdateMinimapPosition()
	UpdateMinimapVisibility()
end

-- Addon compartment (the addons dropdown by the minimap), declared in the TOC.
function OneCast_OnAddonCompartmentClick()
	OpenSettings()
end

-- A secure button's attributes can't change in combat, so this waits until it's over.
local function ApplyFishingSpell()
	if fishingName and not InCombatLockdown() and button:GetAttribute("spell") ~= fishingName then
		button:SetAttribute("spell", fishingName)
	end
end

local function IsFishingSpell(spellID)
	if not spellID or (issecretvalue and issecretvalue(spellID)) then
		return false
	end
	return SpellName(spellID) == fishingName
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			OneCastDB = OneCastDB or {}
			for k, v in pairs(defaults) do
				if OneCastDB[k] == nil then
					OneCastDB[k] = v
				end
			end
			db = OneCastDB
			db.wanted = db.wanted or {}
			ns.db = db
			OneCastCharDB = OneCastCharDB or {}
			for k, v in pairs(charDefaults) do
				if OneCastCharDB[k] == nil then
					OneCastCharDB[k] = v
				end
			end
			SetupSettings()
			SetupMinimapButton()
		end
	elseif event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" then
		local name = ResolveFishingName()
		if name then
			fishingName = name
		end
		ApplyFishingSpell()
		if event == "PLAYER_LOGIN" then
			UpdateQuiet() -- logged in with the pole on
		end
		if event == "PLAYER_LOGIN" and not GetBindingKey(BINDING_COMMAND) then
			Print("请在 选项 > 按键设置 > 插件 > 哇，大鱼 绑定按键，或装备鱼竿后双击右键。输入 /onecast 打开选项。")
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local _, _, spellID = ...
		if IsFishingSpell(spellID) then
			fishing = true
			StartReelMode()
			CheckBagSpace()
			ns.Pools.OnCast()
			ns.Stats.OnCast()
			ns.Gear.OnCast()
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if fishing then
			fishing = false
			reelEndedAt = GetTime()
			StopReelMode()
			ns.Gear.OnFishingStopped()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.Gear.OnCombatStart()
		-- Last chance before lockdown: give every key back to its normal binding.
		fishing = false
		ClearOverrideBindings(reelOwner)
		ClearOverrideBindings(clickOwner)
		ReleaseCVars("cast") -- the quiet ones follow the pole, which combat puts away
	elseif event == "PLAYER_REGEN_ENABLED" then
		ApplyFishingSpell()
		-- A line still out: combat took the reel key away, and pressing it now would recast.
		local _, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
		if IsFishingSpell(spellID) then
			fishing = true
			StartReelMode()
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		UpdateQuiet()
	elseif event == "PLAYER_LOGOUT" then
		-- CVars are saved on logout; never save ours.
		ReleaseCVars("cast")
		ReleaseCVars("quiet")
	end
end)

SLASH_ONECAST1 = "/onecast"
SlashCmdList.ONECAST = function(msg)
	local cmd = strlower(strtrim(msg or ""))
	if cmd == "" then
		OpenSettings()
		return
	elseif cmd == "stats" then
		ns.Stats.Toggle()
		return
	elseif cmd == "session" or cmd == "zone" or cmd == "lifetime" or cmd == "log" then
		ns.Stats.Toggle(cmd)
		return
	elseif cmd == "reset" then
		ns.Stats.Reset()
		Print("会话统计已重置。")
		return
	elseif cmd == "gear" then
		OneCast_RestoreWeapons()
		return
	elseif cmd == "scan" then
		ns.Prices.Scan()
		return
	elseif cmd == "book" or cmd == "collection" then
		ns.Book.Toggle()
		return
	elseif cmd == "new" or cmd == "whatsnew" then
		ns.WhatsNew.Toggle()
		return
	elseif cmd == "tackle" then
		ns.TackleBox.ToggleWindow()
		return
	elseif cmd == "tackle reset" then
		Print(ns.TackleBox.ResetPosition() and "工具箱按钮已移回初始位置。"
			or "战斗中无法移动工具箱按钮。")
		return
	elseif cmd == "forgetpools" then
		ns.Pools.Forget()
		ns.Book.RefreshIfShown()
		Print("已清除记住的鱼群点。")
		return
	elseif cmd:match("^scale") then
		local percent = tonumber(cmd:match("^scale%s+(%d+)"))
		if percent then
			ns.Stats.SetScale(percent)
			Print("统计窗口缩放：" .. db.statsScale .. "%")
		else
			Print("用法：/onecast scale 50-200")
		end
		return
	end
	for _, opt in ipairs(OPTIONS) do
		if opt.cmd == cmd then
			-- Through the setting, so the panel and its callbacks stay in sync.
			local store = opt.char and OneCastCharDB or db
			opt.setting:SetValue(not store[opt.key])
			Print(opt.label .. "：" .. (store[opt.key] and "开" or "关"))
			return
		end
	end
	Print("v" .. ns.VERSION .. " | 按键：" .. BoundKeysText() .. " | 法术：" .. tostring(fishingName))
	Print("/onecast - 打开选项")
	Print("/onecast new - 各版本更新内容")
	Print("/onecast book - 钓鱼图鉴")
	Print("/onecast tackle - 工具箱（/onecast tackle reset 可把按钮移回原位）")
	Print("/onecast stats - 统计窗口（或 /onecast session|zone|lifetime|log 打开对应标签）")
	Print("/onecast reset - 开始新会话")
	Print("/onecast gear - 换回武器")
	Print("/onecast scan - 用 Auctionator 估价渔获（需打开拍卖行）")
	Print("/onecast forgetpools - 清除记住的鱼群点")
	Print("/onecast scale 50-200 - 统计窗口缩放百分比")
	for _, opt in ipairs(OPTIONS) do
		local store = opt.char and OneCastCharDB or db
		Print("/onecast " .. opt.cmd .. " - " .. opt.label .. "（" .. (store[opt.key] and "开" or "关") .. "）")
	end
end

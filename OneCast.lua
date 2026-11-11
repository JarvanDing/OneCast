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
	closeOnDone = true,
	fadeStats = false,
	lockWindow = false,
	tabSide = "right", -- the OneCast window's side tabs: "right" or "left"
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
	theme = "forever",
	campReminder = true,
	reportHint = true,
}
-- Per character: skill and bags differ, and lures get used up.
local charDefaults = {
	autoLure = false,
	lureChoice = 0, -- Lure.NONE
}

-- Checkboxes in the settings panel, each also toggled by /onecast <cmd>.
local OPTIONS = {
	{ cmd = "doubleclick", key = "doubleClick", label = "双击右键施放钓鱼",
		tooltip = "装备鱼竿时，双击右键世界即可施放；右键浮漂收杆。" },
	{ cmd = "softinteract", key = "softInteract", label = "钓鱼时启用软交互",
		tooltip = "鱼线抛出后，将浮漂设为软交互目标，以便施法键直接收杆。" },
	{ cmd = "bobbermarker", key = "bobberMarker", label = "标记自己的浮漂",
		tooltip = "鱼线抛出后，在自己的浮漂上显示游戏的装备图标，方便区分别人的水花。鱼咬钩时无法显示：游戏不会把咬钩告诉插件。" },
	{ cmd = "bagwarning", key = "bagWarning", label = "背包满时警告",
		tooltip = "背包没有空位时抛竿会警告一次，以免渔获装不下。" },
	{ cmd = "sound", key = "soundBoost", label = "钓鱼时放大水花音效",
		tooltip = "鱼线抛出后，将音效调至最大，方便听清水花声。" },
	{ cmd = "quiet", key = "quietOthers", label = "钓鱼时压低其他声音",
		tooltip = "装备鱼竿时，降低（或关闭）音乐、环境音和对白，突出水花声。换回武器后，或你手动改音量后，会恢复为你自己的音量。" },
	{ cmd = "autoequip", key = "autoEquip", label = "自动装备鱼竿",
		tooltip = "未装备鱼竿时，施法键先从背包装备最好的鱼竿（再按一次才施放）。原武器会记住，之后自动换回。" },
	{ cmd = "combatgear", key = "restoreOnCombat", label = "进入战斗时换回武器",
		tooltip = "一进入战斗就尝试换回武器。战斗中被游戏拦住的换装，会在脱战后补完。" },
	{ cmd = "tacklebox", key = "tackleBox", label = "显示工具箱按钮",
		tooltip = "主手装备鱼竿时显示小按钮，含诱饵与剩余时间。左键上饵，右键打开设置，Shift-拖动可移动。" },
	{ cmd = "autolure", key = "autoLure", char = true, label = "用施法键上饵",
		tooltip = "鱼竿上没有诱饵时，施法键先使用你选定的诱饵，再按一次才抛竿。会消耗诱饵，因此默认关闭。按角色单独设置。" },
	{ cmd = "lurevendor", key = "lureVendorHint", label = "商人处提示诱饵不足",
		tooltip = "在售卖你选定诱饵的商人处，若持有少于 5 个会在聊天提示。买不买由你决定。" },
	{ cmd = "autoclose", key = "closeOnDone", label = "停止钓鱼时关闭统计窗口",
		tooltip = "换回武器后，如果统计窗口是你施放时自动打开的，就把它关掉。你自己打开的窗口会保持打开。" },
	{ cmd = "fade", key = "fadeStats", label = "钓鱼时淡化统计窗口",
		tooltip = "钓鱼期间，鼠标不在统计窗口上时，窗口会淡成半透明，少遮挡一点水面。" },
	{ cmd = "lock", key = "lockWindow", label = "锁定窗口",
		tooltip = "防止「哇，大鱼」窗口被误移动或误调整大小。关闭后即可再次移动。" },
	{ cmd = "autoopen", key = "openOnCast", label = "施放时打开统计窗口",
		tooltip = "开始钓鱼时打开统计窗口。若用关闭按钮或小地图按钮关掉，会保持关闭，直到你暂停钓鱼约 2 分钟。" },
	{ cmd = "summary", key = "sessionSummary", label = "聊天中显示会话摘要",
		tooltip = "暂停钓鱼约 2 分钟后，在聊天汇总本次：渔获、每小时鱼数、商人售价、技能提升和图鉴新鱼。" },
	{ cmd = "autoloot", key = "autoLootHint", label = "提示开启自动拾取",
		tooltip = "钓到东西时若未开启自动拾取，每次登录最多提示一次，方便渔获直接进包。" },
	{ cmd = "alert", key = "alert", label = "稀有渔获提醒",
		tooltip = "钓到达到提醒品质或以上的物品，或你标记为想要的物品时，播放音效并闪现团队警告（在统计窗口右键可标记想要）。" },
	{ cmd = "pools", key = "rememberPools", label = "记住钓鱼鱼群点",
		tooltip = "装备鱼竿时将鼠标悬停在鱼群上并抛竿，会把钓点标在图鉴的区域地图上。鱼群会移动，标记表示曾经出现过的位置。目前仅识别英文鱼群名。/onecast forgetpools 可清除。" },
	{ cmd = "campreminder", key = "campReminder", label = "营地增益提醒",
		tooltip = "钓鱼架或钓鱼小屋提供的优良或稀有钓鱼增益消失时，在聊天提示。图鉴的「营地」标签页有更多营地信息。" },
	{ cmd = "reporthint", key = "reportHint", label = "提示可分享的数据",
		tooltip = "当你的钓鱼出现「哇，大鱼」还不了解的情况（例如未知等级的区域，或图鉴里没有的鱼）时，在聊天提示，方便你用 /onecast report 分享。" },
	{ cmd = "extravaganza", key = "extravaganza", label = "荆棘谷钓鱼大赛提醒",
		tooltip = "荆棘谷钓鱼大赛即将开始及开始时在聊天提示（经典日程：服务器时间周日 14:00–16:00）。" },
	{ cmd = "loginmessage", key = "loginMessage", label = "登录时在聊天显示版本",
		tooltip = "登录时在聊天显示插件版本，并附带「更新内容」链接。" },
	{ cmd = "minimap", key = "minimapButton", label = "显示小地图按钮",
		tooltip = "在小地图上显示「哇，大鱼」按钮。可拖动调整位置。" },
}

-- The sub-pages under OneCast in the options, each a list of { heading, keys... }. A key is an
-- OPTIONS entry, or one of the sliders and dropdowns built in SetupSettings.
local OPTION_PAGES = {
	{ name = "钓鱼",
		{ "施放", "doubleClick", "softInteract", "bobberMarker" },
		{ "鱼竿与武器", "autoEquip", "restoreDelay", "restoreOnCombat" },
		{ "提醒", "bagWarning", "autoLootHint" },
	},
	{ name = "诱饵",
		{ "你的诱饵", "lureChoice", "autoLure" },
		{ "工具箱", "tackleBox", "lureVendorHint" },
	},
	{ name = "声音",
		{ "钓鱼时", "soundBoost", "quietOthers", "quietLevel" },
	},
	{ name = "统计与提醒",
		{ "统计窗口", "openOnCast", "closeOnDone", "fadeStats", "sessionSummary" },
		{ "提醒", "alert", "alertQuality", "extravaganza", "campReminder", "reportHint" },
		{ "图鉴", "rememberPools" },
	},
}
-- Greyed out and indented while the option they belong to is off.
local OPTION_PARENT = {
	quietLevel = "quietOthers",
	alertQuality = "alert",
}

local UpdateQuiet -- below: quiet other sounds while fishing

-- Every setting that isn't a checkbox, described once: the options panel and the window's Options
-- page are both built from this. A `list` setting is a dropdown of { value, text } pairs; the others
-- are sliders from `min` to `max` in `step`s, shown with `format`. `char` keeps it per character.
local CHOICES = {
	theme = { label = "主题", kind = "string",
		tooltip = "「哇，大鱼」各窗口的配色。选定后立即生效。",
		list = function()
			local list = {}
			for _, id in ipairs(ns.Theme.ORDER) do
				list[#list + 1] = { id, ns.Theme.LIST[id].label }
			end
			return list
		end,
		onChange = function()
			ns.Theme.Apply()
		end },
	tabSide = { label = "侧边标签", kind = "string",
		tooltip = "「哇，大鱼」窗口的标签页位于哪一侧。",
		list = function()
			return { { "right", "右侧" }, { "left", "左侧" } }
		end,
		onChange = function()
			ns.Hub.UpdateSide()
		end },
	statsScale = { label = "窗口缩放", kind = "number", min = 50, max = 200, step = 5,
		tooltip = "「哇，大鱼」窗口的大小，所有页面通用。也可拖动任意页面的右下角，或在统计页上按 Ctrl + 鼠标滚轮。",
		format = function(value)
			return value .. "%"
		end,
		onChange = function(_, value)
			ns.Stats.SetScale(value)
		end },
	lureChoice = { label = "使用的诱饵", kind = "number", char = true,
		tooltip = "工具箱、「上饵」按键与施法键使用的诱饵。选定后不会自动换成别的：用完后会不带诱饵继续钓。「能用的最好诱饵」可能消耗你最稀有的诱饵。按角色单独设置。",
		list = function()
			local list = { { ns.Lure.NONE, "不使用诱饵" }, { ns.Lure.BEST, "能用的最好诱饵" } }
			for _, lure in ipairs(ns.Lure.LIST) do
				list[#list + 1] = { lure.id, string.format("%s（+%d）", ns.Lure.Name(lure), lure.bonus) }
			end
			return list
		end,
		onChange = function()
			ns.Lure.OnSettingChanged()
		end },
	restoreDelay = { label = "之后换回武器", kind = "number", min = 0, max = 300, step = 15,
		tooltip = "多少秒未施放后换回武器。0 表示一直拿着鱼竿，直到你手动换装。",
		format = function(value)
			return value == 0 and "从不" or (value .. " 秒")
		end },
	quietLevel = { label = "钓鱼时其他声音", kind = "number", min = 0, max = 100, step = 5,
		tooltip = "装备鱼竿时，音乐、环境音和对白保留为你原音量的百分之几。0 为静音。",
		format = function(value)
			return value == 0 and "静音" or (value .. "%")
		end,
		onChange = function()
			UpdateQuiet(true)
		end },
	alertQuality = { label = "提醒品质", kind = "number",
		tooltip = "触发稀有渔获提醒的最低物品品质。",
		list = function()
			local list = {}
			for q = 2, 5 do
				local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
				local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
				list[#list + 1] = { q, (color and color.hex or "") .. label .. (color and "|r" or "") .. " 及以上" }
			end
			return list
		end },
}

-- The options on the main page, before OPTION_PAGES, for the window's Options page.
local OPTION_MAIN = {
	{ "外观", "theme", "tabSide", "statsScale" },
	{ "常规", "lockWindow", "minimapButton", "loginMessage" },
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
_G.BINDING_NAME_ONECAST_WINDOW = "「哇，大鱼」窗口（上次使用的页面）"

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

-- Register the first of `names` the game knows, for an event whose name has changed between
-- game versions. Registering an unknown event is an error that stops the rest of the file
-- loading, so each is checked first. Returns the name registered, or nil.
function ns.RegisterAnyEvent(frame, names)
	for _, name in ipairs(names) do
		local valid
		if C_EventUtils and C_EventUtils.IsEventValid then
			valid = C_EventUtils.IsEventValid(name)
		else
			valid = pcall(frame.RegisterEvent, frame, name)
			if valid then
				return name
			end
		end
		if valid then
			frame:RegisterEvent(name)
			return name
		end
	end
end

-- How many of an item are in the bags.
function ns.ItemCount(item)
	return (C_Item.GetItemCount or GetItemCount)(item) or 0
end

-- An item as a chat link, to hover or Shift-click, or `fallback` until the game has its data.
function ns.ItemLink(itemID, fallback)
	return select(2, C_Item.GetItemInfo(itemID)) or fallback
end
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
function UpdateQuiet(reapply)
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

-- Blizzard's options panel opens the game menu whenever it closes, however it was opened. Opened
-- from OneCast (minimap button, /onecast, a window's Options button), closing it should just close
-- it. So: note that OneCast asked, and when that panel closes, hide the game menu it brings up in
-- the moment after. Opened from the game menu itself, closing still goes back there. Only hooks,
-- after Blizzard's own code, so the options panel is never tainted.
local settingsRequestedAt = -10
local settingsOpenedByUs = false
local skipGameMenuUntil = 0
local settingsHooks = {} -- owner of the options-panel callback

local function OpenSettings()
	if InCombatLockdown() then
		Print("战斗中无法打开选项。")
		return
	end
	settingsRequestedAt = GetTime()
	-- The panel opening would close OneCast's own windows, the one this came from included.
	if ns.UI and ns.UI.HoldOpenForOptions then
		ns.UI.HoldOpenForOptions()
	end
	Settings.OpenToCategory(settingsCategory:GetID())
	if SettingsPanel and SettingsPanel:IsShown() then
		settingsOpenedByUs = true
	end
end

if SettingsPanel then
	SettingsPanel:HookScript("OnShow", function()
		settingsOpenedByUs = GetTime() - settingsRequestedAt < 1
	end)
end
if EventRegistry then
	EventRegistry:RegisterCallback("SettingsPanel.OnHide", function()
		if settingsOpenedByUs then
			settingsOpenedByUs = false
			skipGameMenuUntil = GetTime() + 0.5
		end
	end, settingsHooks)
end
if GameMenuFrame then
	GameMenuFrame:HookScript("OnShow", function(self)
		if GetTime() < skipGameMenuUntil then
			skipGameMenuUntil = 0
			HideUIPanel(self)
		end
	end)
end
ns.OpenSettings = OpenSettings
ns.OPTIONS = OPTIONS
ns.OPTION_CHOICES = CHOICES
ns.OPTION_MAIN = OPTION_MAIN
ns.OPTION_PAGES = OPTION_PAGES
ns.OPTION_PARENT = OPTION_PARENT

local function SetupSettings()
	local category, layout = Settings.RegisterVerticalLayoutCategory(ns.DISPLAY_NAME)
	local optionByKey = {}
	for _, opt in ipairs(OPTIONS) do
		optionByKey[opt.key] = opt
	end
	ns.optionSettings = {}

	local function Header(pageLayout, text)
		pageLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end

	local function Register(page, key, kind, label, store, default)
		local setting = Settings.RegisterAddOnSetting(page, "OneCast_" .. key, key, store, kind, label, default)
		ns.optionSettings[key] = setting
		return setting
	end

	local function Choices(fill)
		return function()
			local container = Settings.CreateControlTextContainer()
			fill(container)
			return container:GetData()
		end
	end

	local function Slider(page, setting, low, high, step, format, tooltip)
		local options = Settings.CreateSliderOptions(low, high, step)
		if MinimalSliderWithSteppersMixin then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
		end
		return Settings.CreateSlider(page, setting, options, tooltip)
	end

	-- Everything that isn't a plain checkbox, from CHOICES.
	local function ChoiceControl(page, key)
		local spec = CHOICES[key]
		local setting = Register(page, key, spec.kind, spec.label, spec.char and OneCastCharDB or db,
			spec.char and charDefaults[key] or defaults[key])
		if spec.onChange then
			setting:SetValueChangedCallback(spec.onChange)
		end
		if key == "statsScale" then
			ns.scaleSetting = setting
		end
		if spec.list then
			return Settings.CreateDropdown(page, setting, Choices(function(container)
				for _, choice in ipairs(spec.list()) do
					container:Add(choice[1], choice[2])
				end
			end), spec.tooltip)
		end
		return Slider(page, setting, spec.min, spec.max, spec.step, spec.format, spec.tooltip)
	end
	local CONTROLS = {}
	for key in pairs(CHOICES) do
		CONTROLS[key] = function(page)
			return ChoiceControl(page, key)
		end
	end

	local ON_CHANGE = {
		minimapButton = UpdateMinimapVisibility,
		quietOthers = function()
			UpdateQuiet()
		end,
		tackleBox = function()
			ns.Lure.OnSettingChanged()
		end,
		autoLure = function()
			ns.Lure.OnSettingChanged()
		end,
		lockWindow = function()
			ns.Hub.UpdateLock()
		end,
	}

	local initializers = {}
	local function AddControl(page, key)
		local initializer
		if CONTROLS[key] then
			initializer = CONTROLS[key](page)
		else
			local opt = optionByKey[key]
			local setting = Register(page, key, "boolean", opt.label, opt.char and OneCastCharDB or db,
				opt.char and charDefaults[key] or defaults[key])
			if ON_CHANGE[key] then
				setting:SetValueChangedCallback(ON_CHANGE[key])
			end
			opt.setting = setting
			initializer = Settings.CreateCheckbox(page, setting, opt.tooltip)
		end
		initializers[key] = initializer
		local parent = OPTION_PARENT[key]
		if parent then
			initializer:SetParentInitializer(initializers[parent], function()
				return ns.optionSettings[parent]:GetValue()
			end)
		end
	end

	-- The main page: how it looks, the one key you need, and a way into every window.
	Header(layout, "外观")
	AddControl(category, "theme")
	AddControl(category, "tabSide")
	AddControl(category, "statsScale")

	-- The cast/reel key, editable right here (same binding as Keybindings > AddOns).
	if CreateKeybindingEntryInitializer then
		for i = 1, GetNumBindings() do
			if GetBinding(i) == BINDING_COMMAND then
				Header(layout, "按键")
				local keyEntry = CreateKeybindingEntryInitializer(i, true)
				-- Kept out of the settings search, as are the buttons below: Blizzard does the
				-- same for its own buttons that open something, and addon entries in the search
				-- results were reported to raise ADDON_ACTION_FORBIDDEN.
				if keyEntry.SetSearchIgnoredInLayout then
					keyEntry:SetSearchIgnoredInLayout(layout)
				end
				layout:AddInitializer(keyEntry)
				break
			end
		end
	end

	Header(layout, "打开")
	for _, entry in ipairs({
		{ "统计窗口", "打开统计", function() ns.Stats.Toggle() end, "本次会话、你的技能、鱼最爱咬钩的地点，以及你的纪录。" },
		{ "工具箱", "打开工具箱", function() ns.TackleBox.ToggleWindow() end, "选择诱饵，并对比有饵与无饵时的每小时鱼数。" },
		{ "钓鱼图鉴", "打开图鉴", function() ns.Book.Show() end, "全部鱼类、你已钓到的，以及其余鱼的出没地点。" },
		{ "数据报告", "打开报告", function() ns.Report.Show() end, "把你的渔获和脱钩整理成文本，分享出来，帮「哇，大鱼」摸清 Forever 的真实钓鱼等级。" },
		{ "更新内容", "版本 " .. ns.VERSION, function() ns.WhatsNew.Show() end, "查看「哇，大鱼」各版本的改动。" },
	}) do
		layout:AddInitializer(CreateSettingsButtonInitializer(entry[1], entry[2], entry[3], entry[4], false))
	end

	Header(layout, "常规")
	AddControl(category, "lockWindow")
	AddControl(category, "minimapButton")
	AddControl(category, "loginMessage")

	for _, pageInfo in ipairs(OPTION_PAGES) do
		local page, pageLayout = Settings.RegisterVerticalLayoutSubcategory(category, pageInfo.name)
		for _, section in ipairs(pageInfo) do
			Header(pageLayout, section[1])
			for i = 2, #section do
				AddControl(page, section[i])
			end
		end
	end

	Settings.RegisterAddOnCategory(category)
	settingsCategory = category
end

-- The tooltip for the minimap button and the addon compartment, laid out like the game's own:
-- the name and version, then gold labels with white values, then what a click does. Rows with
-- nothing to say are left out. `isMinimap` adds the clicks only the minimap button has.
local GOLD, WHITE, GREY, GREEN, RED = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.12, 1, 0 }, { 1, 0.3, 0.3 }
local HINT = { 0.6, 0.8, 1 }

function ns.FillTooltip(tip, isMinimap)
	local function Row(label, value, color)
		color = color or WHITE
		tip:AddDoubleLine(label, value, GOLD[1], GOLD[2], GOLD[3], color[1], color[2], color[3])
	end
	local function Hint(click, action)
		tip:AddDoubleLine(click, action, HINT[1], HINT[2], HINT[3], WHITE[1], WHITE[2], WHITE[3])
	end
	tip:AddDoubleLine(ns.DISPLAY_NAME, "v" .. ns.VERSION, 1, 1, 1, GREY[1], GREY[2], GREY[3])
	tip:AddLine(" ")

	local keys = { GetBindingKey(BINDING_COMMAND) }
	Row("施放 / 收杆", #keys > 0 and table.concat(keys, ", ") or "未绑定", #keys > 0 and WHITE or RED)
	local session = ns.Stats.Summary()
	Row("本次会话", session or "暂无", session and WHITE or GREY)
	local lure, problem = ns.Lure.StatusLine()
	if lure then
		Row("诱饵", lure, problem and RED or WHITE)
	end
	local camp = ns.Camp and ns.Camp.StatusText()
	if camp then
		Row("营地", camp, GREEN)
	end
	local contest = ns.Extravaganza and ns.Extravaganza.StatusLine(ns.Stats.CurrentZone())
	if contest then
		Row("钓鱼大赛", contest)
	end
	local unshared = ns.Report and #ns.Report.Unshared() or 0
	if unshared > 0 then
		Row("可分享的数据", unshared .. "  ·  /onecast report", GREEN)
	end

	tip:AddLine(" ")
	if isMinimap then
		Hint("左键", "菜单：所有窗口")
		Hint("右键", "统计窗口")
		Hint("Shift+点击", "钓鱼图鉴")
		Hint("拖动", "移动此按钮")
	else
		Hint("左键", "选项")
	end
end

-- Every OneCast window in one menu, from the minimap button's left-click. Tooltips can't hold
-- buttons, so this is how the collection and the rest are one click away. OneCast's own small
-- menu rather than the game's: the game's runs its choices inside a protected call, where
-- opening a window was failing without a word. This one's buttons are plain buttons.
local MENU = {
	{ "统计窗口", function() ns.Stats.Toggle() end },
	{ "工具箱", function() ns.TackleBox.ToggleWindow() end },
	{ "钓鱼图鉴", function() ns.Book.Toggle() end },
	{ "营地", function() ns.Book.ShowCamp() end },
	{ "数据报告", function() ns.Report.Toggle() end },
	{ "更新内容", function() ns.WhatsNew.Toggle() end },
	false, -- a divider
	{ "选项", function() ns.Hub.ShowOptions() end },
}
local MENU_WIDTH, MENU_ROW, MENU_PAD = 170, 20, 10

local menuFrame

local function CreateMenu()
	local f = (ns.UI and ns.UI.TryCreate and ns.UI.TryCreate("Frame", "OneCastMenu", UIParent, "TooltipBackdropTemplate"))
		or CreateFrame("Frame", "OneCastMenu", UIParent, "BackdropTemplate")
	if not f.NineSlice and f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	end
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	tinsert(UISpecialFrames, "OneCastMenu") -- Escape closes it

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", MENU_PAD + 2, -MENU_PAD)
	title:SetText(ns.DISPLAY_NAME)
	local y = -MENU_PAD - 18
	f.buttons = {}
	for _, entry in ipairs(MENU) do
		if entry then
			local b = CreateFrame("Button", nil, f)
			b:SetPoint("TOPLEFT", MENU_PAD - 2, y)
			b:SetPoint("TOPRIGHT", -MENU_PAD + 2, y)
			b:SetHeight(MENU_ROW)
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			b.text:SetPoint("LEFT", 4, 0)
			b.text:SetText(entry[1])
			b.label = entry[1]
			b:SetScript("OnClick", function()
				f:Hide()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				entry[2]()
			end)
			f.buttons[#f.buttons + 1] = b
			y = y - MENU_ROW
		else
			local line = f:CreateTexture(nil, "ARTWORK")
			line:SetColorTexture(1, 1, 1, 0.15)
			line:SetHeight(1)
			line:SetPoint("TOPLEFT", MENU_PAD, y - 5)
			line:SetPoint("TOPRIGHT", -MENU_PAD, y - 5)
			y = y - 11
		end
	end
	f:SetSize(MENU_WIDTH, -y + MENU_PAD)

	-- A click anywhere else closes it, as the game's menus do.
	f:SetScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	f:SetScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	f:SetScript("OnEvent", function(self)
		if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
			self:Hide()
		end
	end)
	return f
end

local function OpenMenu(owner)
	menuFrame = menuFrame or CreateMenu()
	if menuFrame:IsShown() then
		menuFrame:Hide()
		return
	end
	-- The count of data to share, on its row.
	local unshared = ns.Report and #ns.Report.Unshared() or 0
	for _, b in ipairs(menuFrame.buttons) do
		if b.label == "数据报告" then
			b.text:SetText(unshared > 0 and string.format("数据报告 |cff1eff00(%d)|r", unshared) or "数据报告")
		end
	end
	-- Open away from the screen edge the button is nearest.
	menuFrame.owner = owner
	menuFrame:ClearAllPoints()
	local x, y = owner:GetCenter()
	local right = x and x > UIParent:GetWidth() / 2
	local top = y and y > UIParent:GetHeight() / 2
	menuFrame:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), owner,
		(top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT"))
	menuFrame:Show()
end
ns.OpenMenu = OpenMenu

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
			GameTooltip:Hide()
			OpenMenu(b)
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
		ns.FillTooltip(GameTooltip, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)

	minimapButton = b
	UpdateMinimapPosition()
	UpdateMinimapVisibility()
end

-- Addon compartment (the addons dropdown by the minimap), declared in the TOC.
function OneCast_OnAddonCompartmentClick()
	ns.Hub.ShowOptions()
end

function OneCast_OnAddonCompartmentEnter(_, menuButtonFrame)
	GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
	ns.FillTooltip(GameTooltip, false)
	GameTooltip:Show()
end

function OneCast_OnAddonCompartmentLeave()
	GameTooltip:Hide()
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

-- The line comes in: the key goes back to casting, and the weapons' idle timer starts.
local function LineIn()
	fishing = false
	reelEndedAt = GetTime()
	StopReelMode()
	ns.Gear.OnFishingStopped()
end

-- While the key is borrowed for reeling, check now and then that a line really is out. The
-- game says when a cast ends, but if that's ever missed (a loading screen, a disconnect) the key
-- would stay on "interact" and never cast again. Checked out of combat only: in a fight the key
-- is already given back (PLAYER_REGEN_DISABLED), and bindings can't change.
local WATCH_EVERY = 2
local watch

local function LineIsOut()
	local _, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
	return IsFishingSpell(spellID)
end

local function StopWatch()
	if watch then
		watch:Cancel()
		watch = nil
	end
end

local function Watch()
	StopWatch()
	watch = C_Timer.NewTicker(WATCH_EVERY, function()
		if not fishing then
			StopWatch()
		elseif not InCombatLockdown() and not LineIsOut() then
			StopWatch()
			LineIn()
		end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
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
			ns.Theme.Init()
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
			Watch()
			CheckBagSpace()
			ns.Pools.OnCast()
			ns.Stats.OnCast()
			ns.Gear.OnCast()
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if fishing then
			StopWatch()
			LineIn()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Past a loading screen, a line that was out is gone.
		if fishing and not InCombatLockdown() and not LineIsOut() then
			StopWatch()
			LineIn()
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
			Watch()
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
		ns.Hub.ShowOptions()
		return
	elseif cmd == "keys" or cmd == "settings" then
		OpenSettings() -- the game's options: the cast key is set there
		return
	elseif cmd == "stats" then
		ns.Stats.Toggle()
		return
	elseif cmd == "spots" or cmd == "alltime" or cmd == "now" or cmd == "farm" or cmd == "records"
		or cmd == "session" or cmd == "zone" or cmd == "lifetime" or cmd == "log" then
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
	elseif cmd == "camp" then
		ns.Book.ShowCamp()
		return
	elseif cmd == "report" then
		ns.Report.Show()
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
	elseif cmd == "theme" or cmd:match("^theme%s") then
		local name = cmd:match("^theme%s+(%a+)")
		local label = ns.Theme.Choose(name)
		Print(label and ("主题：" .. label) or ("没有名为 " .. tostring(name) .. " 的主题。可试：" .. table.concat(ns.Theme.ORDER, ", ") .. "。"))
		return
	elseif cmd == "scale" or cmd:match("^scale%s") then
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
	Print("/onecast - 打开选项（/onecast keys 查看施法键）")
	Print("/onecast new - 各版本更新内容")
	Print("/onecast book - 钓鱼图鉴（/onecast camp 打开其中的「营地」标签页）")
	Print("/onecast report - 把你的钓鱼数据整理成文本，分享出来，帮助补全 Forever 的数据")
	Print("/onecast theme [" .. table.concat(ns.Theme.ORDER, "|") .. "] - 窗口主题（不带名称则切换到下一个）")
	Print("/onecast tackle - 工具箱（/onecast tackle reset 可把按钮移回原位）")
	Print("/onecast stats - 统计窗口（或 /onecast session|spots|alltime 打开对应标签）")
	Print("/onecast reset - 开始新会话")
	Print("/onecast gear - 换回武器")
	Print("/onecast scan - 用 Auctionator 估价渔获（需打开拍卖行）")
	Print("/onecast scale 50-200 - 窗口缩放百分比")
	for _, opt in ipairs(OPTIONS) do
		local store = opt.char and OneCastCharDB or db
		Print("/onecast " .. opt.cmd .. " - " .. opt.label .. "（" .. (store[opt.key] and "开" or "关") .. "）")
	end
end

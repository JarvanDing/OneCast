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
	{ cmd = "doubleclick", key = "doubleClick", label = "Double right-click to cast",
		tooltip = "With a fishing pole equipped, double right-click the world to cast. Right-click the bobber to reel in." },
	{ cmd = "softinteract", key = "softInteract", label = "Soft-interact while fishing",
		tooltip = "While the line is out, make the bobber the soft-interact target so the cast key reels it in." },
	{ cmd = "bobbermarker", key = "bobberMarker", label = "Mark your bobber",
		tooltip = "While the line is out, show the game's gear icon over your bobber, so you can tell it from other people's. It can't show when a fish bites: the game doesn't tell addons that." },
	{ cmd = "bagwarning", key = "bagWarning", label = "Warn when your bags are full",
		tooltip = "Warn once when you cast with no free bag space, because a catch may not fit." },
	{ cmd = "sound", key = "soundBoost", label = "Louder splash while fishing",
		tooltip = "While the line is out, turn sound effects up to full so the splash is easy to hear." },
	{ cmd = "quiet", key = "quietOthers", label = "Quiet other sounds while fishing",
		tooltip = "While your fishing pole is equipped, turn music, ambience and dialog down (or off) so the splash stands out. They go back to your own levels when your weapons go back on, or if you change them yourself." },
	{ cmd = "autoequip", key = "autoEquip", label = "Auto-equip fishing pole",
		tooltip = "If no pole is equipped, the cast key equips the best one in your bags first (press again to cast). Your weapons are saved and put back afterwards." },
	{ cmd = "combatgear", key = "restoreOnCombat", label = "Re-equip weapons when combat starts",
		tooltip = "Try to put your weapons back the moment combat starts. Anything the game blocks in combat is finished when combat ends." },
	{ cmd = "tacklebox", key = "tackleBox", label = "Show the tackle box button",
		tooltip = "Show a small button while a fishing pole is in your main hand, with your lure and its time left. Left-click applies your lure, right-click opens its settings, Shift-drag moves it." },
	{ cmd = "autolure", key = "autoLure", char = true, label = "Apply lure with the cast key",
		tooltip = "With no lure on your pole, the cast key applies your chosen lure first, then casts on the next press. It uses up the lure, so it's off until you turn it on. Set for each character." },
	{ cmd = "lurevendor", key = "lureVendorHint", label = "Low lure hint at vendors",
		tooltip = "At a vendor selling your chosen lure, say so in chat if you have fewer than 5. Buying stays up to you." },
	{ cmd = "autoopen", key = "openOnCast", label = "Open stats when you cast",
		tooltip = "Open the stats window when you start fishing. If you close it (X or minimap button), it stays closed until you take a 2-minute break from fishing." },
	{ cmd = "summary", key = "sessionSummary", label = "Session summary in chat",
		tooltip = "After a 2-minute break from fishing, sum up the session in chat: catches, fish per hour, vendor value, skill gained and new fish for your collection." },
	{ cmd = "autoloot", key = "autoLootHint", label = "Offer to turn on auto loot",
		tooltip = "If auto loot is off when you catch something, offer once per login to turn it on, so catches go straight to your bags." },
	{ cmd = "alert", key = "alert", label = "Rare catch alert",
		tooltip = "Sound and a raid-warning flash when you catch something at or above the alert quality, or an item you've marked as wanted (right-click it in the stats window)." },
	{ cmd = "pools", key = "rememberPools", label = "Remember fishing pools",
		tooltip = "Hover over a fishing pool with your pole on and cast, and the spot you fished it from is marked on the collection book's zone maps. Pools move, so a mark shows where one has been. English pool names only. /onecast forgetpools clears them." },
	{ cmd = "campreminder", key = "campReminder", label = "Camp buff reminders",
		tooltip = "Say in chat when the Uncommon or Rare Fishing buff from a Fishing Rack or Fishing Hut wears off. The collection book's Camp tab has more on camps." },
	{ cmd = "reporthint", key = "reportHint", label = "Tell me about data to share",
		tooltip = "Say in chat when your fishing shows something OneCast doesn't know yet, like a zone with no known level or a fish somewhere new, so you can share it with /onecast report." },
	{ cmd = "extravaganza", key = "extravaganza", label = "Fishing Extravaganza reminders",
		tooltip = "Say in chat shortly before the Stranglethorn Fishing Extravaganza starts, and when it does (Classic's schedule: Sundays 14:00-16:00 realm time)." },
	{ cmd = "loginmessage", key = "loginMessage", label = "Version in chat at login",
		tooltip = "Say OneCast's version in chat when you log in, with a link to What's new." },
	{ cmd = "minimap", key = "minimapButton", label = "Show minimap button",
		tooltip = "Show the OneCast button on the minimap. Drag it to move it." },
}

-- The sub-pages under OneCast in the options, each a list of { heading, keys... }. A key is an
-- OPTIONS entry, or one of the sliders and dropdowns built in SetupSettings.
local OPTION_PAGES = {
	{ name = "Fishing",
		{ "Casting", "doubleClick", "softInteract", "bobberMarker" },
		{ "Pole and weapons", "autoEquip", "restoreDelay", "restoreOnCombat" },
		{ "Reminders", "bagWarning", "autoLootHint" },
	},
	{ name = "Lures",
		{ "Your lure", "lureChoice", "autoLure" },
		{ "Tackle box", "tackleBox", "lureVendorHint" },
	},
	{ name = "Sound",
		{ "While fishing", "soundBoost", "quietOthers", "quietLevel" },
	},
	{ name = "Stats and alerts",
		{ "Stats window", "openOnCast", "statsScale", "sessionSummary" },
		{ "Alerts", "alert", "alertQuality", "extravaganza", "campReminder", "reportHint" },
		{ "Collection", "rememberPools" },
	},
}
-- Greyed out and indented while the option they belong to is off.
local OPTION_PARENT = {
	quietLevel = "quietOthers",
	alertQuality = "alert",
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

_G.BINDING_HEADER_ONECAST = "OneCast"
_G["BINDING_NAME_" .. BINDING_COMMAND] = "Cast / reel (one button fishing)"
_G.BINDING_NAME_ONECAST_RESTORE = "Re-equip weapons"
_G.BINDING_NAME_ONECAST_BOOK = "Fishing collection"

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
	DEFAULT_CHAT_FRAME:AddMessage("|cff33bbffOneCast|r: " .. msg)
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
		Print("your bags are full, so a catch may not fit.")
		if UIErrorsFrame then
			UIErrorsFrame:AddMessage("Your bags are full", 1, 0.3, 0.1)
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
	return #keys > 0 and table.concat(keys, ", ") or "not bound"
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
		Print("options can't be opened in combat.")
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

local function SetupSettings()
	local category, layout = Settings.RegisterVerticalLayoutCategory("OneCast")
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

	-- Everything that isn't a plain checkbox.
	local CONTROLS = {
		theme = function(page)
			local setting = Register(page, "theme", "string", "Theme", db, defaults.theme)
			setting:SetValueChangedCallback(function()
				ns.Theme.Apply()
			end)
			return Settings.CreateDropdown(page, setting, Choices(function(container)
				for _, id in ipairs(ns.Theme.ORDER) do
					container:Add(id, ns.Theme.LIST[id].label)
				end
			end), "The colours of OneCast's windows. Changes as soon as you pick one.")
		end,
		lureChoice = function(page)
			local setting = Register(page, "lureChoice", "number", "Lure to use", OneCastCharDB, charDefaults.lureChoice)
			setting:SetValueChangedCallback(function()
				ns.Lure.OnSettingChanged()
			end)
			return Settings.CreateDropdown(page, setting, Choices(function(container)
				container:Add(ns.Lure.NONE, "No lure")
				container:Add(ns.Lure.BEST, "Best I can use")
				for _, lure in ipairs(ns.Lure.LIST) do
					container:Add(lure.id, string.format("%s (+%d)", ns.Lure.Name(lure), lure.bonus))
				end
			end), "The lure the tackle box, the Apply lure key and the cast key use. Your choice is never swapped for another: if it runs out, OneCast fishes without one. \"Best I can use\" can spend your rarest lures. Set for each character.")
		end,
		restoreDelay = function(page)
			local setting = Register(page, "restoreDelay", "number", "Re-equip weapons after", db, defaults.restoreDelay)
			return Slider(page, setting, 0, 300, 15, function(value)
				return value == 0 and "Never" or (value .. " s")
			end, "Seconds without casting before your weapons are put back. 0 keeps the pole on until you re-equip by hand.")
		end,
		quietLevel = function(page)
			local setting = Register(page, "quietLevel", "number", "Other sounds while fishing", db, defaults.quietLevel)
			setting:SetValueChangedCallback(function()
				UpdateQuiet(true)
			end)
			return Slider(page, setting, 0, 100, 5, function(value)
				return value == 0 and "Muted" or (value .. "%")
			end, "How loud music, ambience and dialog stay while your pole is equipped, as a share of your own volume. 0 mutes them.")
		end,
		statsScale = function(page)
			local setting = Register(page, "statsScale", "number", "Stats window scale", db, defaults.statsScale)
			setting:SetValueChangedCallback(function(_, value)
				ns.Stats.SetScale(value)
			end)
			ns.scaleSetting = setting
			return Slider(page, setting, 50, 200, 5, function(value)
				return value .. "%"
			end, "Size of the stats window. You can also drag its bottom-right corner, or Ctrl + mouse wheel over it.")
		end,
		alertQuality = function(page)
			local setting = Register(page, "alertQuality", "number", "Alert quality", db, defaults.alertQuality)
			return Settings.CreateDropdown(page, setting, Choices(function(container)
				for q = 2, 5 do
					local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
					local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
					container:Add(q, (color and color.hex or "") .. label .. (color and "|r" or "") .. " or better")
				end
			end), "The lowest item quality that triggers the rare catch alert.")
		end,
	}

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
	Header(layout, "Look")
	AddControl(category, "theme")

	-- The cast/reel key, editable right here (same binding as Keybindings > AddOns).
	if CreateKeybindingEntryInitializer then
		for i = 1, GetNumBindings() do
			if GetBinding(i) == BINDING_COMMAND then
				Header(layout, "Your key")
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

	Header(layout, "Open")
	for _, entry in ipairs({
		{ "Stats window", "Open stats", function() ns.Stats.Toggle() end, "Your catches this session, in this zone and over your lifetime." },
		{ "Tackle box", "Open tackle box", function() ns.TackleBox.ToggleWindow() end, "Choose your lure and compare fish per hour with and without one." },
		{ "Fishing collection", "Open collection", function() ns.Book.Show() end, "Every fish, which you've caught, and where to find the rest." },
		{ "Data report", "Open report", function() ns.Report.Show() end, "Your catches and getaways as text, to share so OneCast can learn Forever's real fishing levels." },
		{ "What's new", "Version " .. ns.VERSION, function() ns.WhatsNew.Show() end, "See what changed in each version of OneCast." },
	}) do
		layout:AddInitializer(CreateSettingsButtonInitializer(entry[1], entry[2], entry[3], entry[4], false))
	end

	Header(layout, "General")
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
	tip:AddDoubleLine("OneCast", "v" .. ns.VERSION, 1, 1, 1, GREY[1], GREY[2], GREY[3])
	tip:AddLine(" ")

	local keys = { GetBindingKey(BINDING_COMMAND) }
	Row("Cast / reel", #keys > 0 and table.concat(keys, ", ") or "not bound", #keys > 0 and WHITE or RED)
	local session = ns.Stats.Summary()
	Row("Session", session or "nothing yet", session and WHITE or GREY)
	local lure, problem = ns.Lure.StatusLine()
	if lure then
		Row("Lure", lure, problem and RED or WHITE)
	end
	local camp = ns.Camp and ns.Camp.StatusText()
	if camp then
		Row("Camp", camp, GREEN)
	end
	local contest = ns.Extravaganza and ns.Extravaganza.StatusLine(ns.Stats.CurrentZone())
	if contest then
		Row("Extravaganza", contest)
	end
	local unshared = ns.Report and #ns.Report.Unshared() or 0
	if unshared > 0 then
		Row("Data to share", unshared .. "  ·  /onecast report", GREEN)
	end

	tip:AddLine(" ")
	if isMinimap then
		Hint("Left-click", "Menu: every window")
		Hint("Right-click", "Stats window")
		Hint("Shift-click", "Fishing collection")
		Hint("Drag", "Move this button")
	else
		Hint("Left-click", "Options")
	end
end

-- Every OneCast window in one menu, from the minimap button's left-click. Tooltips can't hold
-- buttons, so this is how the collection and the rest are one click away. OneCast's own small
-- menu rather than the game's: the game's runs its choices inside a protected call, where
-- opening a window was failing without a word. This one's buttons are plain buttons.
local MENU = {
	{ "Stats window", function() ns.Stats.Toggle() end },
	{ "Tackle box", function() ns.TackleBox.ToggleWindow() end },
	{ "Fishing collection", function() ns.Book.Toggle() end },
	{ "Camp", function() ns.Book.ShowCamp() end },
	{ "Data report", function() ns.Report.Toggle() end },
	{ "What's new", function() ns.WhatsNew.Toggle() end },
	false, -- a divider
	{ "Options", function() OpenSettings() end },
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
	title:SetText("OneCast")
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
		if b.label == "Data report" then
			b.text:SetText(unshared > 0 and string.format("Data report |cff1eff00(%d)|r", unshared) or "Data report")
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
	OpenSettings()
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
			Print("bind a key under Options > Keybindings > AddOns > OneCast, or double right-click with a pole. /onecast for options.")
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
		Print("session stats reset.")
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
		Print(ns.TackleBox.ResetPosition() and "tackle box button back to its first place."
			or "the tackle box button can't move during combat.")
		return
	elseif cmd == "forgetpools" then
		ns.Pools.Forget()
		ns.Book.RefreshIfShown()
		Print("remembered pools cleared.")
		return
	elseif cmd == "theme" or cmd:match("^theme%s") then
		local name = cmd:match("^theme%s+(%a+)")
		local label = ns.Theme.Choose(name)
		Print(label and ("theme: " .. label) or ("no theme called " .. name .. ". Try " .. table.concat(ns.Theme.ORDER, ", ") .. "."))
		return
	elseif cmd == "scale" or cmd:match("^scale%s") then
		local percent = tonumber(cmd:match("^scale%s+(%d+)"))
		if percent then
			ns.Stats.SetScale(percent)
			Print("stats window scale: " .. db.statsScale .. "%")
		else
			Print("usage: /onecast scale 50-200")
		end
		return
	end
	for _, opt in ipairs(OPTIONS) do
		if opt.cmd == cmd then
			-- Through the setting, so the panel and its callbacks stay in sync.
			local store = opt.char and OneCastCharDB or db
			opt.setting:SetValue(not store[opt.key])
			Print(opt.label .. ": " .. (store[opt.key] and "on" or "off"))
			return
		end
	end
	Print("v" .. ns.VERSION .. " | key: " .. BoundKeysText() .. " | spell: " .. tostring(fishingName))
	Print("/onecast - open options")
	Print("/onecast new - what's new in each version")
	Print("/onecast book - fishing collection (/onecast camp for its Camp tab)")
	Print("/onecast report - your fishing data as text, to share and help fill in Forever's numbers")
	Print("/onecast theme [" .. table.concat(ns.Theme.ORDER, "|") .. "] - window colours (no name: the next one)")
	Print("/onecast tackle - tackle box (/onecast tackle reset moves its button back)")
	Print("/onecast stats - stats window (or /onecast session|zone|lifetime|log for a tab)")
	Print("/onecast reset - start a new session")
	Print("/onecast gear - put your weapons back on")
	Print("/onecast scan - price your catch with Auctionator (auction house open)")
	Print("/onecast scale 50-200 - stats window size in percent")
	for _, opt in ipairs(OPTIONS) do
		local store = opt.char and OneCastCharDB or db
		Print("/onecast " .. opt.cmd .. " - " .. opt.label .. " (" .. (store[opt.key] and "on" or "off") .. ")")
	end
end

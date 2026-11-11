-- OneCast lures: which lure a character has chosen, whether one is on the pole, and the press
-- that puts it there.
--
-- Using an item on the pole is protected, so it only ever happens on the player's own press,
-- through a secure button running "/use item:<id>" then "/use 16": the cast key (when "apply
-- with the cast key" is on), the tackle box button or the Apply lure key binding.
--
-- Presses reach PreClick on both key-down and key-up, and which of them fires depends on
-- ActionButtonUseKeyDown and on the input. So a press only arms the macro, and the lure's own
-- spell events say what really happened. Lures take 5 seconds to apply: while one is going on
-- the cast key does nothing, because casting would interrupt it.

local _, ns = ...

local Lure = {}
ns.Lure = Lure

-- Item and spell IDs, required skill and the 5-second cast are from Forever's game data on
-- wago.tools (rechecked on build 1.60.1.70862), and so are the bonuses: each lure's spell puts
-- on enchant 263 (+25), 264 (+50), 265 (+75) or 266 (+100). Durations are from Method's Forever
-- fishing guide (3 November 2026). Equal bonuses keep the easier-to-get lure first, which is the
-- one "best" picks. "Secret" Bait is new in Forever and casts Shiny Bauble's own spell.
local LURES = {
	{ id = 6529, spell = 8087, name = "Shiny Bauble", bonus = 25, minutes = 10, req = 0 },
	{ id = 268880, spell = 8087, name = "\"Secret\" Bait", bonus = 25, minutes = 10, req = 0 },
	{ id = 6530, spell = 8088, name = "Nightcrawlers", bonus = 50, minutes = 10, req = 50 },
	{ id = 6811, spell = 8532, name = "Aquadynamic Fish Lens", bonus = 50, minutes = 10, req = 50 },
	{ id = 6532, spell = 8090, name = "Bright Baubles", bonus = 75, minutes = 10, req = 100 },
	{ id = 7307, spell = 9092, name = "Flesh Eating Worm", bonus = 75, minutes = 10, req = 100 },
	{ id = 6533, spell = 8089, name = "Aquadynamic Fish Attractor", bonus = 100, minutes = 5, req = 100 },
}
Lure.LIST = LURES

Lure.NONE, Lure.BEST = 0, -1 -- lureChoice values; anything else is an item ID

local MAIN = INVSLOT_MAINHAND or 16
local MIN_LEFT = 5        -- seconds: a lure this close to ending counts as gone for the cast key
local ARM_TIMEOUT = 1.5   -- seconds a press has to start the lure's spell
local SAME_PRESS = 1      -- a key held no longer than this is one press, down and up
local CAST_TIMEOUT = 7    -- seconds before a lure cast with no ending event is written off
local APPLY_GRACE = 10    -- seconds the pole's enchant may lag behind a finished lure (more on a slow server)
local MAX_FAILURES = 2    -- failed tries in a row before the cast key just casts for a while
local RETRY_AFTER = 60    -- seconds the cast key leaves lures alone after that
local LOW_COUNT = 5       -- at a vendor, fewer than this and we mention it

local byID, bySpell = {}, {} -- bySpell: the first lure with that spell
for _, lure in ipairs(LURES) do
	byID[lure.id] = lure
	bySpell[lure.spell] = bySpell[lure.spell] or lure
end

local armed, armedAt          -- the lure a press has set up, not started yet
local casting, castingAt      -- the lure being applied right now
local appliedAt = 0
local believedUntil = 0       -- when the last lure should end, if the pole can't tell us
local enchantSeen = false     -- GetWeaponEnchantInfo has reported a lure this session
local failures = 0
local lastFailureAt = -100
local holdUntil = 0           -- the cast key leaves lures alone until then
local noted = {}              -- reasons already said in chat
local notedCounts             -- the lures in the bags when they were said
local lastSay, lastSayText = 0, nil
local listeners = {}

function Lure.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Changed()
	for _, fn in ipairs(listeners) do
		fn()
	end
end
Lure.Changed = Changed

-- Say something once per press: PreClick can run twice for one.
local function Say(text)
	local now = GetTime()
	if text ~= lastSayText or now - lastSay > 0.5 then
		ns.Print(text)
	end
	lastSay, lastSayText = now, text
end

function Lure.Name(lure)
	return C_Item.GetItemNameByID(lure.id) or lure.name
end

-- The lure as a chat link, to hover or Shift-click, or its name until the game has the item.
function Lure.ChatName(lure)
	return ns.ItemLink(lure.id, Lure.Name(lure))
end

function Lure.Icon(lure)
	return C_Item.GetItemIconByID(lure.id) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function Lure.Count(lure)
	return ns.ItemCount(lure.id)
end

-- True if this character's Fishing is high enough, or can't be read (the game will say).
function Lure.SkillOK(lure)
	local rank = ns.Stats and ns.Stats.FishingSkill and ns.Stats.FishingSkill()
	return not rank or rank >= lure.req
end

function Lure.MainHandPole()
	return ns.Gear and ns.Gear.IsPole(GetInventoryItemID("player", MAIN)) or false
end

function Lure.Choice()
	return OneCastCharDB and OneCastCharDB.lureChoice or Lure.NONE
end

local function AutoApply()
	return OneCastCharDB and OneCastCharDB.autoLure or false
end

-- The lure that would go on now, or nil and why not: "none", "best", "out" or "skill"
-- (with the lure concerned). Never swaps a chosen lure for another.
function Lure.Selected()
	local choice = Lure.Choice()
	if choice == Lure.NONE then
		return nil, "none"
	elseif choice == Lure.BEST then
		local best
		for _, lure in ipairs(LURES) do
			if Lure.Count(lure) > 0 and Lure.SkillOK(lure) and (not best or lure.bonus > best.bonus) then
				best = lure
			end
		end
		if best then
			return best
		end
		return nil, "best"
	end
	local lure = byID[choice]
	if not lure then
		return nil, "none"
	elseif Lure.Count(lure) == 0 then
		return nil, "out", lure
	elseif not Lure.SkillOK(lure) then
		return nil, "skill", lure
	end
	return lure
end

function Lure.ReasonText(reason, lure)
	if reason == "none" then
		return "工具箱中未选择诱饵。"
	elseif reason == "best" then
		return "背包中没有你能用的诱饵。"
	elseif reason == "out" then
		return string.format("%s 已用完。", Lure.Name(lure))
	elseif reason == "skill" then
		return string.format("%s 需要钓鱼 %d。", Lure.Name(lure), lure.req)
	end
end

-- Seconds of lure left on the pole in the main hand, 0 if none.
function Lure.Left()
	if not Lure.MainHandPole() then
		return 0
	end
	local has, ms = GetWeaponEnchantInfo()
	if has and ms and ms > 0 then
		enchantSeen = true
		return ms / 1000
	end
	-- Don't spend a second lure because the pole hasn't caught up, or because the game doesn't
	-- report lures here at all: go by the clock until it has shown it can.
	local now = GetTime()
	if now < believedUntil and (not enchantSeen or now - appliedAt < APPLY_GRACE) then
		return believedUntil - now
	end
	return 0
end

function Lure.IsActive()
	return Lure.Left() > 0
end

-- The lure to show: the one on the pole, or with none on, the one chosen. Nil if there's a lure
-- on but we don't know which (it went on before OneCast could see it): never guess, because
-- naming the chosen lure could claim a bigger bonus than the pole really has.
function Lure.Shown()
	if Lure.IsActive() then
		return byID[OneCastCharDB and OneCastCharDB.activeLure]
	end
	local choice = Lure.Choice()
	if byID[choice] then
		return byID[choice]
	end
	return (Lure.Selected())
end

-- With the lure finished either way, the countdown to re-equip weapons starts again.
local function RestartIdleTimer()
	if ns.Gear and ns.Gear.OnFishingStopped then
		ns.Gear.OnFishingStopped()
	end
end

function Lure.IsCasting()
	if casting and GetTime() - castingAt > CAST_TIMEOUT then
		casting = nil
		RestartIdleTimer()
	end
	return casting
end

-- All the lures in the bags, to tell when "no lure left" could have changed.
local function LureCounts()
	local counts = {}
	for i, lure in ipairs(LURES) do
		counts[i] = Lure.Count(lure)
	end
	return table.concat(counts, ",")
end

local function Macro(lure)
	return string.format("/use item:%d\n/use %d", lure.id, MAIN)
end

local function StopTargeting()
	-- A /use that couldn't land leaves the item on the cursor waiting for a target.
	if SpellIsTargeting and SpellIsTargeting() and SpellStopTargeting then
		pcall(SpellStopTargeting)
	end
end

local function NoteFailure(lure)
	StopTargeting()
	lastFailureAt = GetTime()
	failures = failures + 1
	if failures >= MAX_FAILURES then
		failures = 0
		holdUntil = GetTime() + RETRY_AFTER
		ns.Print(string.format("无法装上 %s，施法键将在一分钟内只抛竿。", Lure.ChatName(lure)))
	end
	Changed()
end

-- Key-down only sets up the macro: the key may yet be held, or a click dragged off and
-- cancelled. The key-up half ends the press, so only then can it have failed to start.
local function Arm(lure, down)
	if down then
		return Macro(lure)
	end
	local now = GetTime()
	armed, armedAt = lure, now
	C_Timer.After(ARM_TIMEOUT, function()
		if armed and armedAt == now then
			armed = nil
			if now - lastFailureAt <= SAME_PRESS then
				-- The key-up half of a press whose key-down already failed: counted once.
				StopTargeting()
				Changed()
			else
				NoteFailure(lure)
			end
		end
	end)
	return Macro(lure)
end

-- A press of the cast key, out of combat, with a pole sorted out. Returns "wait" if the press
-- should do nothing, a macro if it should apply a lure, or nil to cast as usual.
function Lure.CastPress(down)
	if Lure.IsCasting() then
		return "wait"
	end
	if not AutoApply() or GetTime() < holdUntil or not Lure.MainHandPole() or Lure.Left() >= MIN_LEFT then
		return nil
	end
	if IsMounted and IsMounted() then
		return nil
	end
	local lure, reason, about = Lure.Selected()
	if not lure then
		if not noted[reason] then
			noted[reason] = true
			notedCounts = LureCounts()
			ns.Print(Lure.ReasonText(reason, about) .. " 将不带诱饵抛竿。")
		end
		return nil
	end
	return Arm(lure, down)
end

-- A press of the tackle box or the Apply lure key. Returns a macro, or nil if it has nothing to
-- do. A lure already on stays on unless `replace` says otherwise.
function Lure.ApplyPress(replace, down)
	if Lure.IsCasting() then
		return nil
	end
	if not Lure.MainHandPole() then
		Say("请先装备鱼竿。")
		return nil
	end
	if Lure.IsActive() and not replace then
		Say("鱼竿上已有诱饵。按住 Ctrl 点击工具箱可替换。")
		return nil
	end
	local lure, reason, about = Lure.Selected()
	if not lure then
		Say(Lure.ReasonText(reason, about))
		return nil
	end
	return Arm(lure, down)
end

-- A secure button that applies the chosen lure when pressed with the left button. `allow` can
-- refuse a press (the tackle box leaves Shift-drags alone), and `canReplace` lets Ctrl replace
-- a lure already on: only for a click, as a key could be bound to Ctrl-something and spend a
-- lure on every press. Nothing is set up in combat, so the button does nothing there.
function Lure.WireButton(button, allow, canReplace)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:HookScript("PreClick", function(self, mouseButton, down)
		if InCombatLockdown() or mouseButton ~= "LeftButton" or (allow and not allow()) then
			return
		end
		local macro = Lure.ApplyPress(canReplace and IsControlKeyDown(), down)
		if macro then
			self:SetAttribute("type", "macro")
			self:SetAttribute("macrotext", macro)
		end
	end)
	button:HookScript("PostClick", function(self)
		if not InCombatLockdown() then
			self:SetAttribute("type", nil)
			self:SetAttribute("macrotext", nil)
		end
	end)
end

-- The Apply lure key binding's button: never shown, so it works with the tackle box hidden.
local keyButton = CreateFrame("Button", "OneCastApplyLureButton", UIParent, "SecureActionButtonTemplate")
Lure.WireButton(keyButton)
_G["BINDING_NAME_CLICK OneCastApplyLureButton:LeftButton"] = "上饵"
_G.BINDING_NAME_ONECAST_TACKLE = "工具箱"

-- Would a lure in the bags close a gap of `short` skill? For the zone verdict. Your chosen lure
-- if it covers it, else the smallest that does, so it never nudges you to overspend.
function Lure.CoverHint(short)
	if Lure.IsActive() then
		return nil
	end
	local function Fits(lure)
		return lure and lure.bonus >= short and Lure.Count(lure) > 0 and Lure.SkillOK(lure)
	end
	local pick = byID[Lure.Choice()]
	if not Fits(pick) then
		pick = nil
		for _, lure in ipairs(LURES) do
			if Fits(lure) and (not pick or lure.bonus < pick.bonus) then
				pick = lure
			end
		end
	end
	return pick and string.format("你的 %s（+%d）可补足差距。", Lure.Name(pick), pick.bonus)
end

-- mm:ss for a time left.
function Lure.Clock(seconds)
	seconds = math.ceil(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The lure for the minimap tooltip, and true if it's a problem (none left, skill too low).
-- Nil if this character doesn't use lures.
function Lure.StatusLine()
	local left = Lure.Left()
	if left > 0 then
		local shown = Lure.Shown()
		return string.format("%s  ·  剩余 %s", shown and Lure.Name(shown) or "已装上", Lure.Clock(left))
	end
	if Lure.Choice() == Lure.NONE then
		return nil
	end
	local lure, reason, about = Lure.Selected()
	if lure then
		return string.format("%s 就绪（x%d）", Lure.Name(lure), Lure.Count(lure))
	elseif reason == "out" then
		return Lure.Name(about) .. " 已用完", true
	elseif reason == "skill" then
		return string.format("%s 需要钓鱼 %d", Lure.Name(about), about.req), true
	end
	return "背包中没有你能用的诱饵", true
end

-- Selling your lure and you're running low? Say so; buying stays up to you.
local function CheckVendor()
	if not ns.db or not ns.db.lureVendorHint or Lure.Choice() == Lure.NONE then
		return
	end
	local sold = {}
	for i = 1, GetMerchantNumItems() do
		local id = GetMerchantItemID(i)
		if id then
			sold[id] = true
		end
	end
	local target
	local chosen = byID[Lure.Choice()]
	if chosen then
		target = sold[chosen.id] and chosen or nil
	else
		for _, lure in ipairs(LURES) do
			if sold[lure.id] and Lure.SkillOK(lure) and (not target or lure.bonus > target.bonus) then
				target = lure
			end
		end
	end
	if target and Lure.Count(target) < LOW_COUNT then
		ns.Print(string.format("此商人出售 %s，你还有 %d 个。", Lure.ChatName(target), Lure.Count(target)))
	end
end

-- Settings ---------------------------------------------------------------------------------

-- Through the options panel's setting where there is one, so the two stay in step.
function Lure.SetOption(key, value)
	local setting = ns.optionSettings and ns.optionSettings[key]
	if setting then
		setting:SetValue(value)
	elseif key == "autoLure" or key == "lureChoice" then
		OneCastCharDB[key] = value
	else
		ns.db[key] = value
	end
	if not setting then
		Changed()
	end
end

-- A new choice is a fresh start: forget what was said and any hold on the cast key.
function Lure.OnSettingChanged()
	noted = {}
	failures, holdUntil = 0, 0
	Changed()
end

-- Events -----------------------------------------------------------------------------------

local function LureForSpell(spellID)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return nil
	end
	-- Two lures can share a spell: the one being pressed or applied is the one it is.
	for _, lure in ipairs({ casting, armed }) do
		if lure and lure.spell == spellID then
			return lure
		end
	end
	return bySpell[spellID]
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_INVENTORY_CHANGED" }) do
	events:RegisterUnitEvent(event, "player")
end
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("MERCHANT_SHOW")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_START" then
		local spellID = select(event == "UNIT_SPELLCAST_SENT" and 4 or 3, ...)
		local lure = LureForSpell(spellID)
		if lure then
			if not casting then
				ns.Print(string.format("正在使用 %s（+%d）。装上后再按一次即可抛竿。", Lure.ChatName(lure), lure.bonus))
			end
			armed = nil
			casting, castingAt = lure, GetTime()
			-- Applying is activity: weapons mustn't go back on halfway through the 5 seconds.
			if ns.Gear and ns.Gear.OnCast then
				ns.Gear.OnCast()
			end
			Changed()
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, _, spellID = ...
		local lure = LureForSpell(spellID)
		if lure then
			local now = GetTime()
			casting, armed = nil, nil
			appliedAt = now
			OneCastCharDB.activeLure = lure.id
			believedUntil = now + lure.minutes * 60
			failures = 0
			noted = {}
			RestartIdleTimer()
			Changed()
		end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		local _, _, spellID = ...
		local lure = LureForSpell(spellID)
		if lure and casting then
			casting = nil
			RestartIdleTimer()
			if event == "UNIT_SPELLCAST_FAILED" then
				NoteFailure(lure) -- an interrupted lure isn't used up: the next press tries again
			else
				Changed()
			end
		end
	elseif event == "MERCHANT_SHOW" then
		CheckVendor()
	else
		-- Every catch fires this. Only a change in the lures themselves is worth saying again.
		if event == "BAG_UPDATE_DELAYED" and notedCounts and notedCounts ~= LureCounts() then
			noted, notedCounts = {}, nil
		end
		Changed()
	end
end)

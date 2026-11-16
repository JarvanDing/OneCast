-- OneCast's fishing wardrobe: choose what you wear to fish, slot by slot, on a page laid out
-- like the character sheet, with your character in the middle wearing it. Each slot is
-- automatic (the bag's biggest Fishing bonus, if it beats what you wear), an item you pick, or
-- left as you wear it; the pole is the best in your bags or one you pick. The outfit goes on
-- with the pole (Wear fishing gear with the pole) and comes off with your weapons.
--
-- Slots that will change glow. Click a slot to choose, right-click for Automatic again,
-- Shift-click to link it. Drag the model to turn it, the wheel zooms, a double-click resets it,
-- and the eye compares the outfit with what you wear now.

local _, ns = ...

local Wardrobe = {}
ns.Wardrobe = Wardrobe

local WIDTH = 760
local EDGE, GAP = 10, 8
local SLOT = 40          -- a slot's icon
local ROWS = 6           -- rows down each side: the pole is on the right side's last
local BOTTOM_ROOM = 96   -- under the slots: the summary and the buttons
local LABEL_WIDTH = 190
local MODEL_WIDTH = WIDTH - 10 - 2 * EDGE - 2 * (SLOT + 8 + LABEL_WIDTH) - 2 * GAP
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.55, 1.5, 0.08
local GOOD, GREY, GOLD, RED = "|cff20ff20", "|cff9d9d9d", "|cffffd100", "|cffff2020"

local frame

local function Gear()
	return ns.Gear
end

local function ItemName(link)
	return link and (C_Item.GetItemInfo(link) or link:match("%[(.-)%]")) or nil
end

local function Icon(id, size)
	local icon = id and C_Item.GetItemIconByID(id)
	return icon and string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", icon, size or 14, size or 14) or ""
end

-- What a slot will have on while you fish, and why: { link, id, bonus, how, worn, changes }.
-- how: "auto", "chosen", "kept", "missing" (chosen but not in your bags) or "none".
local function Plan(invSlot)
	local G = Gear()
	local choice = G.Choice(invSlot)
	local candidates = G.Candidates(invSlot)
	local worn
	for _, c in ipairs(candidates) do
		if c.worn then
			worn = c
		end
	end
	local plan
	if choice == "keep" then
		plan = { link = worn and worn.link, bonus = worn and worn.bonus or 0, how = "kept" }
	elseif type(choice) == "number" then
		for _, c in ipairs(candidates) do
			if c.id == choice then
				plan = { link = c.link, bonus = c.bonus, how = "chosen" }
			end
		end
		if not plan then
			local _, link = C_Item.GetItemInfo(choice)
			plan = { link = link, id = choice, bonus = 0, how = "missing" }
		end
	else
		local best = candidates[1]
		if best and best.bonus > 0 and (not worn or best.bonus > worn.bonus) then
			plan = { link = best.link, bonus = best.bonus, how = "auto" }
		else
			plan = { link = worn and worn.link, bonus = worn and worn.bonus or 0, how = worn and "auto" or "none" }
		end
	end
	plan.worn = worn
	plan.options = #candidates
	local planID = plan.id or (plan.link and C_Item.GetItemInfoInstant(plan.link))
	plan.changes = plan.how ~= "missing" and planID ~= nil and planID ~= (worn and worn.id)
	return plan
end

local function PolePlan()
	local G = Gear()
	local chosen = OneCastCharDB and OneCastCharDB.outfitPole
	local poles = G.Poles()
	local held
	for _, p in ipairs(poles) do
		if p.worn then
			held = p
		end
	end
	local plan
	if chosen then
		for _, p in ipairs(poles) do
			if p.id == chosen then
				plan = { link = p.link, bonus = p.bonus or 0, how = "chosen" }
			end
		end
		if not plan then
			local _, link = C_Item.GetItemInfo(chosen)
			plan = { link = link, id = chosen, bonus = 0, how = "missing" }
		end
	else
		local best
		for _, p in ipairs(poles) do
			local level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(p.link) or 0
			local score = (p.bonus or 0) * 1000 + level
			if not best or score > best.score then
				best = { link = p.link, bonus = p.bonus or 0, score = score }
			end
		end
		plan = { link = best and best.link, bonus = best and best.bonus or 0, how = best and "auto" or "none" }
	end
	plan.worn = held
	plan.options = #poles
	local planID = plan.id or (plan.link and C_Item.GetItemInfoInstant(plan.link))
	plan.changes = plan.how ~= "missing" and planID ~= nil and planID ~= (held and held.id)
	return plan
end

local HOW_TEXT = {
	auto = GREY .. "Automatic|r",
	chosen = GOOD .. "Your pick|r",
	kept = GREY .. "As you wear it|r",
	missing = RED .. "Not in your bags|r",
	none = GREY .. "Nothing to wear|r",
}

local function Mark(on, text)
	return (on and (GOLD .. "> |r") or "   ") .. text
end

-- The menu for a slot: automatic, as worn, or any item that fits it.
local function SlotMenu(info)
	local G = Gear()
	local entries = {}
	local choice = G.Choice(info.slot)
	entries[#entries + 1] = { Mark(choice == nil, "Automatic: the best Fishing bonus"), function()
		G.SetChoice(info.slot, nil)
		Wardrobe.Refresh()
	end }
	entries[#entries + 1] = { Mark(choice == "keep", "Keep what you're wearing"), function()
		G.SetChoice(info.slot, "keep")
		Wardrobe.Refresh()
	end }
	for i, c in ipairs(G.Candidates(info.slot)) do
		if i > 12 then
			break
		end
		local text = Icon(c.id) .. (ItemName(c.link) or "?")
			.. (c.bonus > 0 and (GOOD .. "  +" .. c.bonus .. "|r") or "") .. (c.worn and (GREY .. "  (worn)|r") or "")
		entries[#entries + 1] = { Mark(choice == c.id, text), function()
			G.SetChoice(info.slot, c.id)
			Wardrobe.Refresh()
		end }
	end
	ns.UI.ShowMenu(info.name, entries)
end

local function PoleMenu()
	local G = Gear()
	local chosen = OneCastCharDB and OneCastCharDB.outfitPole
	local entries = {}
	entries[#entries + 1] = { Mark(not chosen, "Automatic: the best in your bags"), function()
		OneCastCharDB.outfitPole = nil
		Wardrobe.Refresh()
	end }
	for _, p in ipairs(G.Poles()) do
		local text = Icon(p.id) .. (ItemName(p.link) or "?")
			.. ((p.bonus or 0) > 0 and (GOOD .. "  +" .. p.bonus .. "|r") or "")
			.. (p.worn and (GREY .. "  (in your hand)|r") or "")
		entries[#entries + 1] = { Mark(chosen == p.id, text), function()
			OneCastCharDB.outfitPole = p.id
			Wardrobe.Refresh()
		end }
	end
	ns.UI.ShowMenu("Fishing pole", entries)
end

local function ResetSlot(info)
	if info.pole then
		OneCastCharDB.outfitPole = nil
	else
		Gear().SetChoice(info.slot, nil)
	end
	Wardrobe.Refresh()
end

-- A slot: its icon in a frame, its name and what it'll be beside it (mirrored on the right).
local function SlotButton(parent, info, x, y, right)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(SLOT, SLOT)
	b:SetPoint("TOPLEFT", x, y)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0, 0, 0, 0.5)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetAllPoints()
	b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	-- A soft glow on a slot that will change when the outfit goes on.
	b.glow = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.glow:SetPoint("CENTER")
	b.glow:SetSize(SLOT * 1.8, SLOT * 1.8)
	b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(0.3, 1, 0.4, 0.8)
	b.glow:Hide()
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b.bonus = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.bonus:SetPoint("BOTTOMRIGHT", -2, 2)
	b.name = b:CreateFontString(nil, "OVERLAY", "OneCastFontNormalSmall")
	b.item = b:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	b.how = b:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	for _, fs in ipairs({ b.name, b.item, b.how }) do
		fs:SetWidth(LABEL_WIDTH)
		fs:SetWordWrap(false)
		fs:SetJustifyH(right and "RIGHT" or "LEFT")
	end
	if right then
		b.name:SetPoint("TOPRIGHT", b, "TOPLEFT", -8, 0)
	else
		b.name:SetPoint("TOPLEFT", b, "TOPRIGHT", 8, 0)
	end
	b.item:SetPoint(right and "TOPRIGHT" or "TOPLEFT", b.name, right and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -2)
	b.how:SetPoint(right and "TOPRIGHT" or "TOPLEFT", b.item, right and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -2)
	b.info = info
	b:SetScript("OnClick", function(self, button)
		if IsModifiedClick and IsModifiedClick("CHATLINK") and self.link then
			if ns.InsertChatLink then
				ns.InsertChatLink(self.link)
			end
			return
		end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if button == "RightButton" then
			ResetSlot(self.info)
		elseif self.info.pole then
			PoleMenu()
		else
			SlotMenu(self.info)
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, right and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
		if self.link then
			GameTooltip:SetHyperlink(self.link)
		else
			GameTooltip:SetText(self.info.name)
		end
		local plan = self.plan
		if plan then
			GameTooltip:AddLine(" ")
			GameTooltip:AddDoubleLine("While you fish", (ItemName(plan.link) or "nothing")
				.. ((plan.bonus or 0) > 0 and (GOOD .. " +" .. plan.bonus .. "|r") or ""), 1, 0.82, 0, 1, 1, 1)
			local worn = plan.worn
			GameTooltip:AddDoubleLine("You wear now", (worn and ItemName(worn.link) or "nothing")
				.. (worn and (worn.bonus or 0) > 0 and (GOOD .. " +" .. worn.bonus .. "|r") or ""), 1, 0.82, 0, 1, 1, 1)
			if plan.how == "missing" then
				GameTooltip:AddLine("Your pick isn't in your bags, so this slot stays as it is.", 1, 0.4, 0.4, true)
			end
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(string.format("Click: choose (%d to pick from)", plan and plan.options or 0), 0.6, 0.8, 1)
		GameTooltip:AddLine("Right-click: back to Automatic", 0.6, 0.8, 1)
		if self.link then
			GameTooltip:AddLine("Shift-click: link it in chat", 0.6, 0.8, 1)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function Paint(b, plan)
	b.plan = plan
	b.link = plan.link
	local id = plan.id or (plan.link and C_Item.GetItemInfoInstant(plan.link))
	local icon = id and C_Item.GetItemIconByID(id)
	b.icon:SetTexture(icon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
	b.icon:SetDesaturated(plan.how == "missing")
	b.icon:SetAlpha(icon and 1 or 0.5)
	local quality = id and C_Item.GetItemQualityByID(id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		b.border:SetVertexColor(color.r, color.g, color.b)
		b.border:Show()
	else
		b.border:Hide()
	end
	b.glow:SetShown(plan.changes and true or false)
	b.bonus:SetText((plan.bonus or 0) > 0 and ("+" .. plan.bonus) or "")
	b.name:SetText(b.info.name)
	local name = ItemName(plan.link)
	b.item:SetText(name and ((color and color.hex or "|cffffffff") .. name .. "|r") or (GREY .. "Empty|r"))
	b.how:SetText((HOW_TEXT[plan.how] or "") .. (plan.changes and (GOOD .. "  · goes on|r") or ""))
end

-- The model's view: kept across refreshes, so a bag change doesn't spin it back.
local function ApplyView(model)
	if model.SetFacing then
		model:SetFacing(model.facingNow or 0)
	end
	if model.SetCamDistanceScale then
		model:SetCamDistanceScale(model.zoom or 1)
	end
end

local function CreateWindow()
	local UI = ns.UI
	local f, inset = UI.CreateShell("OneCastWardrobeFrame", "Fishing wardrobe",
		C_Item.GetItemIconByID(19972) or "Interface\\Icons\\INV_Helmet_31")
	f:SetSize(WIDTH, ns.UI.PAGE_HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	UI.RememberPosition(f, "wardrobe")

	f.status = f:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 62, 6)
	f.status:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
	f.status:SetJustifyH("LEFT")

	-- Two tabs: the outfit you fish in, and every piece of fishing gear there is.
	local outfit = CreateFrame("Frame", nil, inset)
	outfit:SetAllPoints()
	f.outfit = outfit
	f.catalog = ns.Journey.GearView(inset, WIDTH)
	f.catalog:Hide()
	f.Tabs, f.tab = {}, "outfit"
	for i, tab in ipairs({ { "outfit", "Outfit" }, { "gear", "Gear guide" } }) do
		local b = UI.TryCreate("Button", "OneCastWardrobeFrameTab" .. i, f, "PanelTopTabButtonTemplate")
			or CreateFrame("Button", "OneCastWardrobeFrameTab" .. i, f, "UIPanelButtonTemplate")
		b:SetID(i)
		b:SetText(tab[2])
		b:SetWidth(i == 1 and 90 or 110)
		if i == 1 then
			b:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 62, 0)
		else
			b:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", 2, 0)
		end
		b:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			f.tab = tab[1]
			Wardrobe.Refresh()
		end)
		f.Tabs[i] = b
	end
	if PanelTemplates_SetNumTabs then
		PanelTemplates_SetNumTabs(f, #f.Tabs)
	end
	-- The tabs take the place of the line that said what the page is for.
	f.status:Hide()

	-- The slots, down both sides like the character sheet and spread over its full height: six
	-- on the left, four and the pole on the right, the pole on the bottom row.
	f.slots = {}
	local top = -GAP - 4
	local insetHeight = ns.UI.PAGE_HEIGHT - 60 - 28
	local columnHeight = insetHeight - GAP - 4 - BOTTOM_ROOM
	local step = math.floor((columnHeight - SLOT) / (ROWS - 1))
	for i, info in ipairs(ns.Gear.WARDROBE_SLOTS) do
		local right = i > ROWS
		local row = right and (i - ROWS - 1) or (i - 1)
		local x = right and (WIDTH - 10 - EDGE - SLOT) or EDGE
		f.slots[#f.slots + 1] = SlotButton(outfit, info, x, top - row * step, right)
	end

	-- You, in the middle, wearing it, as tall as the columns. Drag to turn, the wheel zooms,
	-- double-click resets.
	local modelLeft = EDGE + SLOT + 8 + LABEL_WIDTH + GAP
	local model = CreateFrame("DressUpModel", nil, outfit)
	model:SetPoint("TOPLEFT", modelLeft, top)
	model:SetSize(MODEL_WIDTH, columnHeight)
	model:EnableMouse(true)
	model:EnableMouseWheel(true)
	model.zoom, model.facingNow = 1, 0
	local floor = model:CreateTexture(nil, "BACKGROUND")
	floor:SetPoint("BOTTOM", 0, -6)
	floor:SetSize(MODEL_WIDTH * 0.9, 40)
	floor:SetTexture("Interface\\Buttons\\WHITE8x8")
	if floor.SetGradient and CreateColor then
		floor:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0))
	else
		floor:SetVertexColor(0, 0, 0, 0.3)
	end
	-- Turned and zoomed with the mouse: nothing for a controller to stop on.
	if ns.Controller then
		ns.Controller.NoStop(model)
	end
	model:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			self.turning = GetCursorPosition()
			self.facing = self:GetFacing() or 0
		end
	end)
	-- A model has no OnDoubleClick (only buttons do): two clicks close together reset the view.
	model:SetScript("OnMouseUp", function(self, button)
		self.turning = nil
		if button ~= "LeftButton" then
			return
		end
		local now = GetTime()
		if self.lastClick and now - self.lastClick < 0.35 then
			self.lastClick = nil
			self.zoom, self.facingNow = 1, 0
			ApplyView(self)
		else
			self.lastClick = now
		end
	end)
	model:SetScript("OnUpdate", function(self)
		if self.turning then
			local x = GetCursorPosition()
			self.facingNow = self.facing + (x - self.turning) / 80
			self:SetFacing(self.facingNow)
		end
	end)
	model:SetScript("OnMouseWheel", function(self, delta)
		self.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, (self.zoom or 1) - delta * ZOOM_STEP))
		ApplyView(self)
	end)
	f.model = model
	-- At the model's foot: how to move it.
	f.modelHint = outfit:CreateFontString(nil, "OVERLAY", "OneCastFontDisableSmall")
	f.modelHint:SetPoint("BOTTOM", model, "BOTTOM", 0, 2)
	-- With a controller, the right stick stays the camera's here: there's nothing to select in
	-- the model, so it never takes the stick to zoom.
	f.modelHint:SetDrawLayer("OVERLAY", 7)
	f.modelHint:SetText("Drag to turn  ·  wheel to zoom  ·  double-click to reset")

	-- At the model's head: the outfit, or what you wear now.
	f.compare = CreateFrame("Button", nil, outfit, "UIPanelButtonTemplate")
	f.compare:SetSize(150, 20)
	f.compare:SetPoint("TOP", model, "TOP", 0, 0)
	f.compare:SetFrameLevel(model:GetFrameLevel() + 2)
	f.compare:SetScript("OnClick", function()
		f.showWorn = not f.showWorn
		Wardrobe.Refresh()
	end)
	f.compare:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(f.showWorn and "Showing what you wear now" or "Showing your fishing outfit")
		GameTooltip:AddLine("Click to switch, to compare the two.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.compare:SetScript("OnLeave", GameTooltip_Hide)

	-- The pole: the right side's last slot.
	local poleInfo = { name = "Fishing pole", pole = true }
	local poleRow = ROWS - 1 -- level with Wrist, a little apart from the armour
	f.pole = SlotButton(outfit, poleInfo, WIDTH - 10 - EDGE - SLOT, top - poleRow * step, true)

	-- The summary: your Fishing now and with the outfit, or what to look for.
	f.total = outfit:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.total:SetPoint("BOTTOM", outfit, "BOTTOM", 0, 64)
	f.total:SetWidth(WIDTH - 60)
	f.totalNote = outfit:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	f.totalNote:SetPoint("TOP", f.total, "BOTTOM", 0, -4)
	f.totalNote:SetWidth(WIDTH - 60)
	f.totalNote:SetWordWrap(true)

	f.wear = CreateFrame("Button", nil, outfit, "UIPanelButtonTemplate")
	f.wear:SetSize(150, 24)
	f.wear:SetPoint("BOTTOMRIGHT", outfit, "BOTTOM", -4, 14)
	f.wear:SetText("Wear it now")
	f.wear:SetScript("OnClick", function()
		ns.Gear.WearNow()
	end)
	f.off = CreateFrame("Button", nil, outfit, "UIPanelButtonTemplate")
	f.off:SetSize(150, 24)
	f.off:SetPoint("BOTTOMLEFT", outfit, "BOTTOM", 4, 14)
	f.off:SetText("Take it off")
	f.off:SetScript("OnClick", function()
		if not ns.Gear.Restore() then
			ns.Print("nothing to take off: your weapons are already on.")
		end
	end)
	for _, b in ipairs({ f.wear, f.off }) do
		b:SetMotionScriptsWhileDisabled(true)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if self == f.wear then
				GameTooltip:SetText("Wear it now")
				GameTooltip:AddLine("Put your pole and this outfit on, without casting. Your weapons and what you wore come back with Take it off, or after fishing.", 1, 1, 1, true)
			else
				GameTooltip:SetText("Take it off")
				GameTooltip:AddLine("Put your weapons and what you wore back on.", 1, 1, 1, true)
			end
			if ns.Gear.Locked() then
				GameTooltip:AddLine("Not in combat: gear can't change until it ends.", 1, 0.4, 0.4, true)
			elseif self == f.off and not ns.Gear.HasSaved() then
				GameTooltip:AddLine("Nothing to take off: your weapons are on.", 0.6, 0.6, 0.6, true)
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end

	-- Along the bottom: whether it goes on with the pole, and starting over.
	f.auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.auto:SetSize(22, 22)
	f.auto:SetPoint("BOTTOMLEFT", 8, 3)
	f.auto.label = f:CreateFontString(nil, "OVERLAY", "OneCastFontHighlightSmall")
	f.auto.label:SetPoint("LEFT", f.auto, "RIGHT", 2, 0)
	f.auto.label:SetText("Wear it whenever the cast key puts your pole on")
	f.auto:SetScript("OnClick", function(self)
		local setting = ns.optionSettings and ns.optionSettings.fishingOutfit
		if setting then
			setting:SetValue(self:GetChecked() and true or false)
		else
			ns.db.fishingOutfit = self:GetChecked() and true or false
		end
	end)
	f.reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.reset:SetSize(120, 20)
	f.reset:SetPoint("BOTTOMRIGHT", -24, 5)
	f.reset:SetText("Reset choices")
	f.reset:SetScript("OnClick", function()
		if OneCastCharDB then
			OneCastCharDB.outfit, OneCastCharDB.outfitPole = nil, nil
		end
		ns.Print("wardrobe reset: every slot and the pole are automatic again.")
		Wardrobe.Refresh()
	end)
	f.reset:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Reset choices")
		GameTooltip:AddLine("Every slot and the pole back to Automatic: the best Fishing bonus in your bags.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.reset:SetScript("OnLeave", GameTooltip_Hide)

	f:SetScript("OnShow", function()
		f.showWorn = false
		Wardrobe.Refresh()
	end)
	local events = CreateFrame("Frame", nil, f)
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- A swap or a loot fires these in bursts: one refresh for the lot, a moment later.
	local pending = false
	events:SetScript("OnEvent", function()
		if f:IsShown() and not pending then
			pending = true
			C_Timer.After(0.1, function()
				pending = false
				Wardrobe.Refresh()
			end)
		end
	end)
	f:Hide()
	ns.Hub.Attach("wardrobe", f)
	return f
end

function Wardrobe.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	-- The tab: the outfit, or every piece of fishing gear.
	local gear = frame.tab == "gear"
	frame.outfit:SetShown(not gear)
	frame.catalog:SetShown(gear)
	frame.auto:SetShown(not gear)
	frame.auto.label:SetShown(not gear)
	frame.reset:SetShown(not gear)
	if PanelTemplates_SetTab then
		PanelTemplates_SetTab(frame, gear and 2 or 1)
	end
	if gear then
		frame.catalog:Paint()
		return
	end
	local model = frame.model
	if model.SetUnit then
		model:SetUnit("player")
	end
	ApplyView(model)
	local outfit, worn, changes, chosenMissing = 0, 0, 0, false
	for _, b in ipairs(frame.slots) do
		local plan = Plan(b.info.slot)
		Paint(b, plan)
		outfit = outfit + (plan.bonus or 0)
		worn = worn + (plan.worn and plan.worn.bonus or 0)
		changes = changes + (plan.changes and 1 or 0)
		chosenMissing = chosenMissing or plan.how == "missing"
		if not frame.showWorn and plan.link and plan.how ~= "missing" and model.TryOn then
			model:TryOn(plan.link)
		end
	end
	local pole = PolePlan()
	Paint(frame.pole, pole)
	outfit = outfit + (pole.bonus or 0)
	worn = worn + (pole.worn and pole.worn.bonus or 0)
	changes = changes + (pole.changes and 1 or 0)
	if not frame.showWorn and pole.link and pole.how ~= "missing" and model.TryOn then
		model:TryOn(pole.link)
	end
	frame.compare:SetText(frame.showWorn and "What you wear now" or "Your fishing outfit")

	-- Your Fishing now, and with the outfit on.
	local rank, modifier
	if ns.Stats and ns.Stats.FishingSkill then
		local _
		rank, _, modifier = ns.Stats.FishingSkill()
	end
	local gain = outfit - worn
	if outfit > 0 and rank then
		local now = rank + (modifier or 0)
		if gain > 0 then
			frame.total:SetText(string.format("Fishing %d %s->|r %s%d|r with this outfit  %s(+%d from gear)|r",
				now, GREY, GOOD, now + gain, GREY, outfit))
		else
			-- Nothing to gain: an arrow from a number to itself says nothing.
			frame.total:SetText(string.format("Fishing %d  %s+%d from this outfit|r", now, GOOD, outfit))
		end
	elseif outfit > 0 then
		frame.total:SetText(string.format("This outfit: %s+%d Fishing|r", GOOD, outfit))
	else
		frame.total:SetText(GREY .. "No gear with a Fishing bonus yet.|r")
	end
	if outfit == 0 then
		frame.totalNote:SetText(GREY .. "A fishing hat, Nat Pagle's boots or gloves with the Fishing enchant in your bags show up here, and go on with your pole.|r")
	elseif chosenMissing then
		frame.totalNote:SetText(RED .. "A piece you picked isn't in your bags: that slot stays as it is.|r")
	elseif changes == 0 then
		frame.totalNote:SetText(GREY .. "You're wearing all of it already.|r")
	else
		frame.totalNote:SetText(string.format("%s%d piece%s go%s on with the pole, glowing above.|r", GREY, changes,
			changes == 1 and "" or "s", changes == 1 and "es" or ""))
	end

	local locked = ns.Gear.Locked()
	frame.wear:SetEnabled(not locked)
	frame.off:SetEnabled(not locked and ns.Gear.HasSaved())
	local any = OneCastCharDB and (OneCastCharDB.outfitPole or (OneCastCharDB.outfit and next(OneCastCharDB.outfit)))
	frame.reset:SetEnabled(any and true or false)
	frame.auto:SetChecked(ns.db and ns.db.fishingOutfit and true or false)
end

-- Open on every piece of fishing gear.
function Wardrobe.ShowGear()
	frame = frame or CreateWindow()
	frame.tab = "gear"
	frame:Show()
	Wardrobe.Refresh()
end

function Wardrobe.Show()
	frame = frame or CreateWindow()
	frame:Show()
end

-- Global for the "Fishing wardrobe" key binding.
function OneCast_ToggleWardrobe()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Wardrobe.Show()
	end
end

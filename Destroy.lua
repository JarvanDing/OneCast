-- OneCast auto-destroy: with the option on, delete stacks of items you've listed from the bags
-- when general bag free slots are down to 1 or 0 (leave room for the next catch). Only while a
-- fishing pole is equipped. Merchant open, combat, or a busy cursor skips a pass. The list is
-- account-wide (OneCastDB.autoDestroyItems).

local _, ns = ...

local Destroy = {}
ns.Destroy = Destroy

local STEP = 0.2 -- seconds between deletes, so the server keeps up
local busy = false
local listFrame
local editBox
local linkHooked = false

-- Classic fishing trash the collection ignores on purpose (Report.lua's junk set).
Destroy.COMMON_JUNK = { 6456, 6297, 6301, 6455, 6457 }

local function Store()
	if not ns.db then
		return nil
	end
	-- SavedVariables may reload number keys as strings; keep a real table either way.
	local items = ns.db.autoDestroyItems
	if type(items) ~= "table" then
		items = {}
		ns.db.autoDestroyItems = items
	end
	return items
end

-- Normalize SavedVariables string keys and callers' IDs to numbers.
local function NormID(id)
	return tonumber(id)
end

function Destroy.Enabled()
	return ns.db and ns.db.autoDestroy and true or false
end

function Destroy.Items()
	return Store() or {}
end

function Destroy.Count()
	local n = 0
	for id in pairs(Destroy.Items()) do
		if NormID(id) then
			n = n + 1
		end
	end
	return n
end

function Destroy.Has(itemID)
	itemID = NormID(itemID)
	if not itemID then
		return false
	end
	local items = Destroy.Items()
	return (items[itemID] or items[tostring(itemID)]) and true or false
end

-- Item ID from a number, an item link, or "item:12345".
function Destroy.ParseItem(text)
	if not text or text == "" then
		return nil
	end
	text = strtrim(text)
	local id = tonumber(text)
	if id then
		return id
	end
	-- Full link, or a bare item:12345 / Hitem:12345 fragment.
	id = tonumber(text:match("item:(%d+)")) or tonumber(text:match("Hitem:(%d+)"))
	return id
end

local function ItemLabel(itemID)
	itemID = NormID(itemID)
	if not itemID then
		return "?"
	end
	local name = C_Item.GetItemNameByID(itemID)
	local link = select(2, C_Item.GetItemInfo(itemID))
	return link or name or ("物品 " .. itemID)
end

function Destroy.Add(itemID)
	itemID = NormID(itemID)
	if not itemID then
		return false, "需要物品链接或物品 ID（可 Shift-点击背包物品，或把物品拖到输入框）。"
	end
	local items = Store()
	if not items then
		return false, "设置尚未就绪。"
	end
	if Destroy.Has(itemID) then
		return false, ItemLabel(itemID) .. " 已在列表中。"
	end
	-- Drop any string-key duplicate from an older save.
	items[tostring(itemID)] = nil
	items[itemID] = true
	if C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(itemID)
	end
	if listFrame and listFrame.Refresh then
		listFrame:Refresh()
	end
	return true, "已加入丢弃列表：" .. ItemLabel(itemID)
end

function Destroy.Remove(itemID)
	itemID = NormID(itemID)
	local items = Store()
	if not (itemID and items) then
		return false, "列表中没有该物品。"
	end
	if not (items[itemID] or items[tostring(itemID)]) then
		return false, "列表中没有该物品。"
	end
	items[itemID] = nil
	items[tostring(itemID)] = nil
	if listFrame and listFrame.Refresh then
		listFrame:Refresh()
	end
	return true, "已移出丢弃列表：" .. ItemLabel(itemID)
end

function Destroy.Clear()
	local items = Store()
	if not items then
		return 0
	end
	local n = Destroy.Count()
	wipe(items)
	if listFrame and listFrame.Refresh then
		listFrame:Refresh()
	end
	return n
end

function Destroy.AddCommonJunk()
	local added = 0
	for _, id in ipairs(Destroy.COMMON_JUNK) do
		local ok = Destroy.Add(id)
		if ok then
			added = added + 1
		end
	end
	return added
end

-- Sorted item IDs currently on the list.
function Destroy.List()
	local seen, ids = {}, {}
	for key in pairs(Destroy.Items()) do
		local id = NormID(key)
		if id and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	return ids
end

-- Free slots left in general bags (family 0). Specialty bags don't count.
local function FreeGeneralSlots()
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then
		return 0
	end
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local slots, family = C_Container.GetContainerNumFreeSlots(bag)
		if (family or 0) == 0 then
			free = free + (slots or 0)
		end
	end
	return free
end

-- Start clearing when only one slot remains, so the next catch still fits.
local function BagsTight()
	return FreeGeneralSlots() <= 1
end

local function CanRun()
	if not Destroy.Enabled() then
		return false
	end
	if not next(Destroy.Items()) then
		return false
	end
	if not BagsTight() then
		return false
	end
	-- Never runs without a fishing pole equipped.
	if not (ns.HasFishingPole and ns.HasFishingPole()) then
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		return false
	end
	if MerchantFrame and MerchantFrame:IsShown() then
		return false
	end
	if CursorHasItem and CursorHasItem() then
		return false
	end
	if not (C_Container and C_Container.PickupContainerItem and DeleteCursorItem) then
		return false
	end
	return true
end

-- Delete one matching stack, then schedule another pass.
function Destroy.Try()
	if busy or not CanRun() then
		return
	end
	local want = Destroy.Items()
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and (want[id] or want[tostring(id)]) and not info.isLocked then
				busy = true
				ClearCursor()
				C_Container.PickupContainerItem(bag, slot)
				if CursorHasItem and CursorHasItem() then
					local count = info.stackCount or 1
					local label = info.hyperlink or ItemLabel(id)
					DeleteCursorItem()
					ns.Print(string.format("已丢弃 %s×%d。", label, count))
				else
					ClearCursor()
				end
				C_Timer.After(STEP, function()
					busy = false
					Destroy.Try()
				end)
				return
			end
		end
	end
end

local function CursorItemID()
	local kind, id = GetCursorInfo()
	if kind == "item" then
		return NormID(id)
	end
end

function Destroy.Slash(arg)
	arg = strtrim(arg or "")
	local sub, rest = arg:match("^(%S+)%s*(.-)%s*$")
	sub = strlower(sub or "")
	if sub == "" or sub == "list" then
		local ids = Destroy.List()
		if #ids == 0 then
			ns.Print("丢弃列表为空。用法：/onecast destroy add <物品链接或 ID>")
		else
			ns.Print(string.format("丢弃列表（%d）：", #ids))
			for _, id in ipairs(ids) do
				ns.Print("  · " .. ItemLabel(id))
			end
		end
		Destroy.ShowList()
		return
	elseif sub == "add" then
		local id = Destroy.ParseItem(rest) or CursorItemID()
		if id and CursorItemID() == id then
			ClearCursor()
		end
		local ok, msg = Destroy.Add(id)
		ns.Print(msg)
		if ok then
			Destroy.Try()
		end
		return
	elseif sub == "remove" or sub == "rm" or sub == "del" then
		local id = Destroy.ParseItem(rest)
		local ok, msg = Destroy.Remove(id)
		ns.Print(msg)
		return
	elseif sub == "clear" then
		local n = Destroy.Clear()
		ns.Print(n > 0 and string.format("已清空丢弃列表（%d 项）。", n) or "丢弃列表已是空的。")
		return
	elseif sub == "junk" then
		local n = Destroy.AddCommonJunk()
		ns.Print(n > 0 and string.format("已加入 %d 种常见钓鱼垃圾。", n) or "常见钓鱼垃圾已在列表中。")
		Destroy.Try()
		return
	end
	ns.Print("用法：/onecast destroy [list|add <链接|ID>|remove <链接|ID>|clear|junk]")
end

-- Shift-click item links into our edit box (hooksecurefunc can't swallow the return).
local function HookLinkInsert()
	if linkHooked then
		return
	end
	linkHooked = true
	local function Take(link)
		if not (link and editBox and listFrame and listFrame:IsShown()) then
			return false
		end
		-- While the list is open, take shift-clicked links even if the box isn't focused.
		editBox:SetText(link)
		editBox:SetFocus()
		editBox:HighlightText()
		return true
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		local orig = ChatFrameUtil.InsertLink
		ChatFrameUtil.InsertLink = function(link, ...)
			if Take(link) then
				return true
			end
			return orig(link, ...)
		end
	end
	if ChatEdit_InsertLink then
		local orig = ChatEdit_InsertLink
		ChatEdit_InsertLink = function(link, ...)
			if Take(link) then
				return true
			end
			return orig(link, ...)
		end
	end
end

-- Manage window: add by link/ID/cursor/drag, remove rows, one-click common junk.
function Destroy.ShowList()
	HookLinkInsert()
	if listFrame then
		listFrame:Show()
		listFrame:Raise()
		if listFrame.Refresh then
			listFrame:Refresh()
		end
		if editBox then
			editBox:SetFocus()
		end
		return
	end

	local UI = ns.UI
	if not (UI and UI.CreateShell) then
		ns.Print("无法打开丢弃列表：界面尚未就绪。")
		return
	end

	local f, inset = UI.CreateShell("OneCastDestroyFrame", "自动丢弃列表", "Interface\\Icons\\INV_Misc_Bag_05")
	if not (f and inset) then
		ns.Print("无法打开丢弃列表：创建窗口失败。")
		return
	end
	f:SetSize(420, 440)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	f:SetClampedToScreen(true)
	if UI.RememberPosition then
		UI.RememberPosition(f, "destroy")
	end
	if UI.EscapeCloses then
		UI.EscapeCloses(f, false)
	end

	local tip = inset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tip:SetPoint("TOPLEFT", 10, -10)
	tip:SetPoint("RIGHT", -10, 0)
	tip:SetJustifyH("LEFT")
	tip:SetSpacing(2)
	tip:SetText("Shift-点击背包物品，或把物品拖进输入框，再点「添加」。也可输入物品 ID。「常见钓鱼垃圾」可一键加入。仅在装备鱼竿、且普通背包只剩 ≤1 格空位时才会自动丢弃。")

	local box = UI.TryCreate and UI.TryCreate("EditBox", "OneCastDestroyEdit", inset, "InputBoxTemplate")
		or CreateFrame("EditBox", "OneCastDestroyEdit", inset, "InputBoxTemplate")
	editBox = box
	box:SetAutoFocus(false)
	box:SetHeight(24)
	box:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 4, -14)
	box:SetPoint("RIGHT", inset, "RIGHT", -86, 0)
	if box.SetTextInsets then
		box:SetTextInsets(6, 6, 0, 0)
	end
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnReceiveDrag", function()
		local id = CursorItemID()
		if id then
			ClearCursor()
			box:SetText("item:" .. id)
		end
	end)
	box:SetScript("OnMouseUp", function()
		local id = CursorItemID()
		if id then
			ClearCursor()
			box:SetText("item:" .. id)
		end
	end)

	local function DoAdd()
		local id = Destroy.ParseItem(box:GetText()) or CursorItemID()
		if CursorItemID() and CursorItemID() == id then
			ClearCursor()
		end
		local ok, msg = Destroy.Add(id)
		ns.Print(msg)
		if ok then
			box:SetText("")
			Destroy.Try()
		end
		box:ClearFocus()
	end
	box:SetScript("OnEnterPressed", DoAdd)

	local add = CreateFrame("Button", nil, inset, "UIPanelButtonTemplate")
	add:SetSize(72, 24)
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	add:SetText("添加")
	add:SetScript("OnClick", DoAdd)

	local junk = CreateFrame("Button", nil, inset, "UIPanelButtonTemplate")
	junk:SetSize(120, 22)
	junk:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -10)
	junk:SetText("常见钓鱼垃圾")
	junk:SetScript("OnClick", function()
		local n = Destroy.AddCommonJunk()
		ns.Print(n > 0 and string.format("已加入 %d 种常见钓鱼垃圾。", n) or "常见钓鱼垃圾已在列表中。")
		Destroy.Try()
	end)
	junk:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("常见钓鱼垃圾")
		GameTooltip:AddLine("加入经典钓鱼常出的灰色杂物（旧头骨、旧车轮等）。", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	junk:SetScript("OnLeave", GameTooltip_Hide)

	local clear = CreateFrame("Button", nil, inset, "UIPanelButtonTemplate")
	clear:SetSize(64, 22)
	clear:SetPoint("LEFT", junk, "RIGHT", 6, 0)
	clear:SetText("清空")
	clear:SetScript("OnClick", function()
		local n = Destroy.Clear()
		ns.Print(n > 0 and string.format("已清空丢弃列表（%d 项）。", n) or "丢弃列表已是空的。")
	end)

	local status = inset:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	status:SetPoint("LEFT", clear, "RIGHT", 10, 0)
	status:SetJustifyH("LEFT")

	local scroll = CreateFrame("ScrollFrame", "OneCastDestroyScroll", inset, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", junk, "BOTTOMLEFT", 0, -12)
	scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -30, 12)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(320, 1)
	scroll:SetScrollChild(child)
	f.rows = {}

	local ROW = 24
	local function EnsureRows(n)
		while #f.rows < n do
			local i = #f.rows + 1
			local row = CreateFrame("Button", nil, child)
			row:SetHeight(ROW)
			row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
			row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(18, 18)
			row.icon:SetPoint("LEFT", 4, 0)
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row.name:SetPoint("RIGHT", -28, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row.del = CreateFrame("Button", nil, row)
			row.del:SetSize(22, 22)
			row.del:SetPoint("RIGHT", -2, 0)
			row.del:SetNormalFontObject("GameFontNormalLarge")
			row.del:SetHighlightFontObject("GameFontHighlightLarge")
			row.del:SetText("×")
			row.del:SetScript("OnClick", function()
				if row.itemID then
					local _, msg = Destroy.Remove(row.itemID)
					ns.Print(msg)
				end
			end)
			row:EnableMouse(true)
			row:SetScript("OnEnter", function(self)
				if self.itemID and GameTooltip.SetItemByID then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetItemByID(self.itemID)
					GameTooltip:Show()
				end
			end)
			row:SetScript("OnLeave", GameTooltip_Hide)
			f.rows[i] = row
		end
	end

	function f:Refresh()
		local ids = Destroy.List()
		status:SetText(string.format("%d 项", #ids))
		local width = scroll:GetWidth()
		if not width or width < 40 then
			width = 320
		end
		child:SetWidth(width - 4)
		EnsureRows(#ids)
		for i, row in ipairs(self.rows) do
			local id = ids[i]
			if id then
				row.itemID = id
				row:Show()
				row.icon:SetTexture(C_Item.GetItemIconByID(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
				row.name:SetText(ItemLabel(id))
			else
				row.itemID = nil
				row:Hide()
			end
		end
		child:SetHeight(math.max(1, #ids * ROW))
	end

	f:SetScript("OnShow", function(self)
		self:Raise()
		self:Refresh()
	end)
	listFrame = f
	f:Show()
	f:Raise()
	f:Refresh()
	box:SetFocus()
end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
	Destroy.Try()
end)

-- OneCast fishing junk: at a vendor, sell the grey junk you fished up, and only that. An item
-- counts if it's poor quality (grey) and this character has fished one up (its lifetime
-- catches), so nothing bought, looted from a mob or carried for any other reason is touched.
-- "Fishing junk at vendors" (junkMode): a button under the vendor window that says what it
-- would sell and for how much, selling as soon as the vendor opens, or neither.

local _, ns = ...

local Junk = {}
ns.Junk = Junk

local STEP = 0.15 -- seconds between sales, so the server keeps up

local button
local selling = false

-- "button", "auto" or "off".
function Junk.Mode()
	return ns.db and ns.db.junkMode or "button"
end

-- Every stack of fishing junk in the bags: { bag, slot, id, count, price }, and the total.
function Junk.Find()
	local list, total = {}, 0
	local caught = OneCastCharDB and OneCastCharDB.lifetime and OneCastCharDB.lifetime.items or {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and caught[id] and info.quality == 0 and not info.isLocked and not info.hasNoValue then
				local price = select(11, C_Item.GetItemInfo(id)) or 0
				if price > 0 then
					local count = info.stackCount or 1
					list[#list + 1] = { bag = bag, slot = slot, id = id, count = count, price = price * count }
					total = total + price * count
				end
			end
		end
	end
	return list, total
end

local function Coins(copper)
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	return (g > 0 and g .. "g " or "") .. ((g > 0 or s > 0) and s .. "s " or "") .. c .. "c"
end

function Junk.Sell()
	if selling or not (MerchantFrame and MerchantFrame:IsShown()) then
		return
	end
	local list = Junk.Find()
	if #list == 0 then
		return
	end
	selling = true
	-- Counted as each one goes, so a vendor closed partway says what really sold.
	local i, stacks, total = 0, 0, 0
	local function Next()
		i = i + 1
		local entry = list[i]
		if not entry or not (MerchantFrame and MerchantFrame:IsShown()) then
			selling = false
			if stacks > 0 then
				ns.Print(string.format("sold %d stack%s of fishing junk for %s.", stacks, stacks == 1 and "" or "s", Coins(total)))
			end
			Junk.UpdateButton()
			return
		end
		local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
		if info and info.itemID == entry.id and not info.isLocked then
			C_Container.UseContainerItem(entry.bag, entry.slot)
			stacks, total = stacks + 1, total + entry.price
		end
		C_Timer.After(STEP, Next)
	end
	Next()
end

function Junk.UpdateButton()
	if not button then
		return
	end
	local list, total = Junk.Find()
	if #list == 0 or selling or Junk.Mode() == "off" or not (MerchantFrame and MerchantFrame:IsShown()) then
		button:Hide()
		return
	end
	button:SetText(string.format("Sell fishing junk (%s)", Coins(total)))
	button:SetWidth(math.max(160, button:GetFontString():GetStringWidth() + 28))
	button:Show()
end

local function CreateButton()
	button = CreateFrame("Button", "OneCastSellJunkButton", MerchantFrame, "UIPanelButtonTemplate")
	button:SetHeight(22)
	button:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", 0, -2)
	button:SetScript("OnClick", Junk.Sell)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Sell fishing junk")
		GameTooltip:AddLine("Sells the grey junk you've fished up, and nothing else:", 1, 1, 1, true)
		local list = Junk.Find()
		local names = {}
		for _, entry in ipairs(list) do
			names[entry.id] = (names[entry.id] or 0) + entry.count
		end
		for id, count in pairs(names) do
			GameTooltip:AddDoubleLine(C_Item.GetItemNameByID(id) or ("item " .. id), "x" .. count, 0.62, 0.62, 0.62, 1, 1, 1)
		end
		GameTooltip:AddLine("Sell it automatically, or hide this button, under Fishing junk at vendors in OneCast's options.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(_, event)
	if event == "MERCHANT_SHOW" then
		if not button and MerchantFrame then
			CreateButton()
		end
		if Junk.Mode() == "auto" then
			Junk.Sell()
		end
		Junk.UpdateButton()
	elseif event == "MERCHANT_CLOSED" then
		if button then
			button:Hide()
		end
	elseif button and MerchantFrame and MerchantFrame:IsShown() then
		Junk.UpdateButton()
	end
end)

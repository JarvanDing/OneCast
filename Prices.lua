-- OneCast auction prices via Auctionator: "scan now" hands every item this character has
-- caught to Auctionator's own search (Auctionator.API.v1.MultiSearchExact), which runs in
-- its Shopping tab and stores the prices in its database. The stats window then reads
-- them back with GetAuctionPriceByItemID, and refreshes when Auctionator's data changes.
-- The search needs the auction house open and is started by a click (the stats window
-- button, or /onecast scan).

local ADDON, ns = ...

local Prices = {}
ns.Prices = Prices

local auctionOpen = false
local registered = false

local function API()
	return Auctionator and Auctionator.API and Auctionator.API.v1
end

function Prices.CanScan()
	local api = API()
	return api ~= nil and (api.MultiSearchExact or api.MultiSearch) ~= nil
end

-- Naowh Forever scans the auction house itself.
function Prices.NaowhScans()
	return type(_G.NaowhForever) == "table" and type(_G.NaowhForever.AuctionPrice) == "function"
end

function Prices.IsAuctionOpen()
	return auctionOpen
end

-- Every item this character has ever caught, by name.
local function CaughtItemNames()
	local names = {}
	local life = OneCastCharDB and OneCastCharDB.lifetime
	if life then
		for id, item in pairs(life.items) do
			local name = item.name or C_Item.GetItemNameByID(id)
			if name then
				names[#names + 1] = name
			end
		end
	end
	table.sort(names)
	return names
end

function Prices.Scan()
	if not Prices.CanScan() then
		ns.Print(Prices.NaowhScans() and "Naowh Forever scans the auction house itself: open it and its prices update."
			or "scanning needs Auctionator installed.")
		return
	end
	if not auctionOpen then
		ns.Print("open the auction house first, then scan.")
		return
	end
	local names = CaughtItemNames()
	if #names == 0 then
		ns.Print("nothing caught yet to price.")
		return
	end
	local api = API()
	local search = api.MultiSearchExact or api.MultiSearch
	local ok, err = pcall(search, ADDON, names)
	if ok then
		ns.Print(string.format("Auctionator is searching %d items. Prices update as it finishes.", #names))
	else
		ns.Print("Auctionator search failed: " .. tostring(err))
	end
end

-- Redraw the stats window whenever Auctionator's price database changes.
local naowhHooked = false
local function RegisterForUpdates()
	-- Naowh Forever says when its prices change through its own namespace.
	local naowh = _G.NaowhForever
	if not naowhHooked and type(naowh) == "table" and type(naowh.AuctionPricesChanged) == "function" then
		naowhHooked = true
		hooksecurefunc(naowh, "AuctionPricesChanged", function()
			if ns.Stats and ns.Stats.RefreshIfShown then
				ns.Stats.RefreshIfShown()
			end
		end)
	end
	local api = API()
	if registered or not api or not api.RegisterForDBUpdate then
		return
	end
	registered = pcall(api.RegisterForDBUpdate, ADDON, function()
		if ns.Stats and ns.Stats.RefreshIfShown then
			ns.Stats.RefreshIfShown()
		end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		RegisterForUpdates()
		return
	end
	auctionOpen = event == "AUCTION_HOUSE_SHOW"
	if auctionOpen then
		RegisterForUpdates()
	end
	if ns.Stats and ns.Stats.RefreshIfShown then
		ns.Stats.RefreshIfShown()
	end
end)

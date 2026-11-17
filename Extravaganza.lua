-- OneCast: the Stranglethorn Fishing Extravaganza. A countdown to the next contest, a
-- Tastyfish counter while it runs, and chat reminders.
--
-- Every Sunday, 14:00 to 16:00 realm time, Speckled Tastyfish and the contest's rare fish bite
-- in Stranglethorn Vale: Classic's schedule, which Forever kept (warcraft.wiki.gg's Forever
-- pages, 14 November 2026).
--
-- The prizes are Forever's (its client data, Wowhead and warcraft.wiki.gg, 16 November 2026): the
-- first 50 players on each ruleset to hand 40 Tastyfish to Riggle Bassbait in Booty Bay get the
-- Arcanite Fishing Pole, an Extravagant Extravaganza Coin and the Master Angler! title for a
-- week. Jang trades one coin for any one of her prizes. Fishbot 5000 trades each rare fish for
-- a piece of fishing gear.

local _, ns = ...

local X = {}
ns.Extravaganza = X

X.ZONE = "Stranglethorn Vale"
X.TASTYFISH = 19807
X.GOAL = 40
X.SCHEDULE = "服务器时间周日 14:00–16:00"
X.WINNERS = 50
X.COIN = 274026
-- Jang's prizes, a coin each: the swim-form trinket, water-walking shoes, the cosmetic hat and
-- bucket, and a pet.
X.JANG = { 19979, 276274, 276272, 276273, 276275 }
-- Fishbot 5000's trades: rare fish -> { item, its name until the game has it }.
X.RARE = {
	[19805] = { 19972, "Lucky Fishing Hat" },
	[19806] = { 19971, "High Test Eternium Fishing Line" },
	[19803] = { 19969, "Nat Pagle's Extreme Anglin' Boots" },
}

local WEEKDAY = 1          -- calendar weekday: 1 is Sunday
local START_HOUR = 14
local LENGTH = 2 * 3600
local WEEK = 7 * 86400
local REMIND_BEFORE = 15 * 60

-- Realm time as seconds since Sunday 00:00 of this week, or nil if the calendar isn't ready.
local function WeekSeconds()
	local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
	if not (t and t.weekday and t.hour) then
		return nil
	end
	return (t.weekday - 1) * 86400 + t.hour * 3600 + (t.minute or 0) * 60 + GetServerTime() % 60
end

-- running, seconds: while the contest runs, true and the seconds left; otherwise false and
-- the seconds until it starts. nil if realm time isn't known.
function X.Status()
	local now = WeekSeconds()
	if not now then
		return nil
	end
	local start = (WEEKDAY - 1) * 86400 + START_HOUR * 3600
	if now >= start and now < start + LENGTH then
		return true, start + LENGTH - now
	end
	return false, (start - now) % WEEK
end

-- "2d 4h", "3h 12m" or "12m".
function X.FormatWait(seconds)
	seconds = math.max(0, math.floor(seconds))
	local d, h, m = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
	if d > 0 then
		return string.format("%d天 %d小时", d, h)
	elseif h > 0 then
		return string.format("%d小时 %d分", h, m)
	end
	return string.format("%d分钟", math.max(m, 1))
end

function X.TastyfishInBags()
	return ns.ItemCount(X.TASTYFISH)
end

-- One line for the stats window, or nil when the contest isn't worth mentioning: shown
-- while it runs, in Stranglethorn Vale, or in the last few hours before it starts.
function X.StatusLine(zone)
	local running, seconds = X.Status()
	if running == nil then
		return nil
	end
	if running then
		return string.format("可口鱼 %d/%d  ·  |cff9d9d9d剩余 %s|r", X.TastyfishInBags(), X.GOAL, X.FormatWait(seconds))
	end
	if zone == X.ZONE or seconds <= 3 * 3600 then
		return " 后开始" .. X.FormatWait(seconds)
	end
end

-- A sentence for the fish's page in the book: when it bites, and what it's handed in for.
function X.Describe(fishID)
	local running, seconds = X.Status()
	local text = "仅在荆棘谷钓鱼大赛期间上钩，" .. X.SCHEDULE .. "."
	local rare = fishID and X.RARE[fishID]
	if rare then
		text = text .. " Fishbot 5000 in Booty Bay trades it for " .. (C_Item.GetItemNameByID(rare[1]) or rare[2]) .. "."
	elseif fishID == X.TASTYFISH then
		text = text .. string.format(" The first %d to bring Riggle Bassbait %d win the Arcanite Fishing Pole and a coin for one of Jang's prizes; Jang buys any you have left in fives.", X.WINNERS, X.GOAL)
	end
	if running then
		return text .. " 正在进行中：还剩 " .. X.FormatWait(seconds) .. " left."
	elseif running == false then
		return text .. " 下场大赛还有 " .. X.FormatWait(seconds) .. "."
	end
	return text
end

-- The moment you hold 40 Tastyfish during the contest, say where to go. Checked when the
-- bags change rather than at the catch, since the fish isn't in the bags until it's looted.
-- Speckled Tastyfish as a chat link, or its name until the game has the item.
local function Tastyfish()
	return ns.ItemLink(X.TASTYFISH, "斑点可口鱼")
end

-- A waypoint to Riggle Bassbait in Booty Bay, where the Tastyfish are handed in, without
-- opening the map: the arrow points the way. Classic's spot for him.
X.RIGGLE = { x = 0.276, y = 0.776 }
function X.Waypoint()
	if InCombatLockdown() or not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		return false
	end
	local mapID = ns.Book and ns.Book.ZoneMapID and ns.Book.ZoneMapID(X.ZONE)
	if not mapID or (C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID)) then
		return false
	end
	local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, X.RIGGLE.x, X.RIGGLE.y))
	if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
	end
	if ok then
		ns.Print("已设置路径点：林格·巴斯贝特，藏宝海湾。")
	end
	return ok
end

local announcedGoal = false
local function CheckGoal()
	if announcedGoal or not (ns.db and ns.db.extravaganza) or not X.Status() or X.TastyfishInBags() < X.GOAL then
		return
	end
	announcedGoal = true
	ns.Print(string.format("已有 %d 条%s！交给藏宝海湾的林格·巴斯贝特即可获胜。", X.GOAL, Tastyfish(), X.WINNERS))
	ns.RaidWarning(X.GOAL .. " 条可口鱼：快去藏宝海湾！")
	PlaySound(SOUNDKIT.RAID_WARNING)
	X.Waypoint()
end

-- Called by Stats.lua after a catch: watch the bags only once a Tastyfish bites.
local bagWatch = CreateFrame("Frame")
bagWatch:SetScript("OnEvent", CheckGoal)
function X.OnCatch(loot)
	for _, l in ipairs(loot) do
		if l.id == X.TASTYFISH and ns.db.extravaganza and not announcedGoal and X.Status() then
			bagWatch:RegisterEvent("BAG_UPDATE_DELAYED")
		end
	end
end

-- Chat reminders: shortly before the start, at the start, and once at login while it runs.
local wasRunning, remindedSoon
local function Tick()
	local running, seconds = X.Status()
	if running == nil then
		return
	end
	if not running then
		announcedGoal = false
		bagWatch:UnregisterEvent("BAG_UPDATE_DELAYED")
	end
	if not (ns.db and ns.db.extravaganza) then
		return
	end
	if running and not wasRunning then
		ns.Print(string.format("荆棘谷钓鱼大赛进行中%s！在荆棘谷钓 %d 条%s，交给藏宝海湾的林格·巴斯贝特。",
			wasRunning == nil and (" (" .. X.FormatWait(seconds) .. " left)") or "", X.GOAL, Tastyfish()))
	elseif not running and seconds <= REMIND_BEFORE and not remindedSoon then
		remindedSoon = true
		ns.Print("荆棘谷钓鱼大赛将在 " .. X.FormatWait(seconds) .. ".")
	end
	if not running and seconds > REMIND_BEFORE then
		remindedSoon = false
	end
	wasRunning = running
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	-- Give the login chat a moment, then check every 30 seconds.
	C_Timer.After(6, function()
		Tick()
		C_Timer.NewTicker(30, Tick)
	end)
end)

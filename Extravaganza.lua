-- OneCast: the Stranglethorn Fishing Extravaganza. A countdown to the next contest, a
-- Tastyfish counter while it runs, and chat reminders.
--
-- The schedule is Classic Era's: every Sunday, 14:00 to 16:00 realm time, when Speckled
-- Tastyfish and the contest's rare fish bite in Stranglethorn Vale. The first player to
-- hand 40 Tastyfish to Riggle Bassbait in Booty Bay wins. Forever hasn't confirmed its
-- own schedule yet, so everything shown says it's Classic's.

local _, ns = ...

local X = {}
ns.Extravaganza = X

X.ZONE = "Stranglethorn Vale"
X.TASTYFISH = 19807
X.GOAL = 40
X.SCHEDULE = "服务器时间周日 14:00–16:00"

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

-- "2天 4小时", "3小时 12分" or "12分钟".
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
	if C_Item.GetItemCount then
		return C_Item.GetItemCount(X.TASTYFISH) or 0
	end
	return GetItemCount and GetItemCount(X.TASTYFISH) or 0
end

-- One line for the stats window, or nil when the contest isn't worth mentioning: shown
-- while it runs, in Stranglethorn Vale, or in the last few hours before it starts.
function X.StatusLine(zone)
	local running, seconds = X.Status()
	if running == nil then
		return nil
	end
	if running then
		return string.format("可口鱼 %d/%d  |cff9d9d9d剩余 %s|r", X.TastyfishInBags(), X.GOAL, X.FormatWait(seconds))
	end
	if (ns.SameZone and ns.SameZone(zone, X.ZONE)) or zone == X.ZONE or seconds <= 3 * 3600 then
		return X.FormatWait(seconds) .. " 后开始"
	end
end

-- A sentence for the fish's page in the book.
function X.Describe()
	local running, seconds = X.Status()
	local text = "仅在荆棘谷钓鱼大赛期间上钩，经典日程为 " .. X.SCHEDULE .. "。"
	if running then
		return text .. " 正在进行中：还剩 " .. X.FormatWait(seconds) .. "。"
	elseif running == false then
		return text .. " 下场大赛还有 " .. X.FormatWait(seconds) .. "。"
	end
	return text
end

-- The moment you hold 40 Tastyfish during the contest, say where to go. Checked when the
-- bags change rather than at the catch, since the fish isn't in the bags until it's looted.
local announcedGoal = false
local function CheckGoal()
	if announcedGoal or not (ns.db and ns.db.extravaganza) or not X.Status() or X.TastyfishInBags() < X.GOAL then
		return
	end
	announcedGoal = true
	ns.Print(string.format("已有 %d 条斑点可口鱼！交给藏宝海湾的林格·巴斯贝特即可获胜。", X.GOAL))
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, X.GOAL .. " 条可口鱼：快去藏宝海湾！", ChatTypeInfo.RAID_WARNING)
	end
	PlaySound(SOUNDKIT.RAID_WARNING)
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
		ns.Print(string.format("荆棘谷钓鱼大赛进行中%s！在荆棘谷钓 %d 条斑点可口鱼，交给藏宝海湾的林格·巴斯贝特。",
			wasRunning == nil and ("（还剩 " .. X.FormatWait(seconds) .. "）") or "", X.GOAL))
	elseif not running and seconds <= REMIND_BEFORE and not remindedSoon then
		remindedSoon = true
		ns.Print("荆棘谷钓鱼大赛将在 " .. X.FormatWait(seconds) .. " 后开始。")
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

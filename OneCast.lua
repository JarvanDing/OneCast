-- OneCast: one-button fishing for WoW Forever (interface 16001, modern addon API).
--
-- How it works, without secure snippets (loadstring_untainted is missing on Forever,
-- so SecureHandler templates are out):
--   * OneCastButton is a plain SecureActionButton that casts Fishing. Bind a key to it
--     in Options > Keybindings > OneCast, or double right-click with a pole.
--   * Optional ONECAST_REEL: a second key always mapped to INTERACTTARGET. When bound,
--     the cast key stays cast for the whole cast — pressing it never reels. Soft-interact
--     CVars still turn on while the line is out so the reel key hits the bobber.
--   * One-key mode (no ONECAST_REEL bound): when the Fishing channel starts, the cast key
--     is overridden to INTERACTTARGET; when the channel ends the override is dropped.
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
local REEL_BINDING = "ONECAST_REEL"
ns.BINDING_COMMAND = BINDING_COMMAND

local defaults = {
	largerText = false,      -- accessibility: OneCast's small print at the normal size
	glyphSize = "normal",    -- accessibility: controller button icons, normal, large or largest
	collectionTicks = true,  -- accessibility: a tick on what you've caught
	reduceMotion = false,    -- accessibility: OneCast's animations stopped
	doubleClick = true,
	softInteract = true,
	soundBoost = true,
	quietOthers = false,
	quietLevel = 0, -- percent of the player's own music, ambience and dialog volume
	minimapButton = true,
	minimapAngle = 225,
	closeOnDone = true,
	doneCloses = false,
	escapeCloses = false,
	catchTooltip = true,
	fadeStats = false,
	lockWindow = false,
	tabSide = "right", -- the OneCast window's side tabs: "right" or "left"
	alert = true,
	alertQuality = 2, -- Uncommon
	openOnCast = true,
	openOnPole = false,
	auctionSource = "auto",
	loginMessage = true,
	statsScale = 100, -- percent
	autoEquip = true,
	fishingOutfit = true,
	statsMini = false,
	junkMode = "button",
	poolTooltip = true,
	mapStrip = true,
	newCatchMessage = true,
	goalAlerts = true,
	alertSound = true,
	tabBadges = true,
	skillToast = true,
	restoreOnCombat = true,
	restoreDelay = 60, -- seconds without casting before weapons go back on; 0 = never
	sessionSummary = true,
	autoLootHint = true,
	autoLootFishing = false,
	fastLoot = false,
	padFishing = true,   -- a controller button casts and reels while the pole is on
	padButton = "PAD1",  -- A / Cross
	padStart = "both",   -- LT + RT + the button works with no pole on
	padWindow = "PAD4",  -- Y / Triangle opens the OneCast window
	padHints = true,
	padRumble = true,
	extravaganza = true,
	bagWarning = true,
	tackleBox = true,
	lureVendorHint = true,
	rememberPools = true,
	bobberMarker = false,
	beamColor = "arcane",
	campReminder = true,
}
-- Per character: skill and bags differ, and lures get used up.
local charDefaults = {
	autoLure = false,
	lureChoice = 0, -- Lure.NONE
}

-- Checkboxes in the settings panel, each also toggled by /onecast <cmd>.
local OPTIONS = {
	{ cmd = "largetext", key = "largerText", label = "放大文字",
		tooltip = "把「哇，大鱼」各窗口里的小号字（说明、提示、标签和计数）改成游戏正常字号。长行可能被截短，悬停可看全文。图鉴页面会在下次重绘时更新。" },
	{ cmd = "ticks", key = "collectionTicks", label = "已钓到标记勾",
		tooltip = "在图鉴里你已钓到的鱼和已拥有的钓鱼装备上显示绿色勾。关闭时，已有的为正常彩色、没有的变灰，图标上无覆盖标记。" },
	{ cmd = "motion", key = "reduceMotion", label = "减少动态效果",
		tooltip = "停止「哇，大鱼」的动画：钓鱼条流水、光泽与闪光、侧栏滑动、浮漂光晕呼吸等。提醒仍会显示并淡出。" },
	{ cmd = "doubleclick", key = "doubleClick", label = "双击右键施放钓鱼",
		tooltip = "装备鱼竿时，双击右键世界即可施放；右键浮漂收杆。" },
	{ cmd = "softinteract", key = "softInteract", label = "钓鱼时启用软交互",
		tooltip = "鱼线抛出后，将浮漂设为软交互目标，以便施法键直接收杆。" },
	{ cmd = "bobbermarker", key = "bobberMarker", label = "标记自己的浮漂",
		tooltip = "鱼线抛出后，你的浮漂会发光并升起光柱，方便在人多水域区分别人的浮漂（颜色见下方「光束颜色」）。鱼咬钩时无法提示：游戏不会把咬钩告诉插件。" },
	{ cmd = "bagwarning", key = "bagWarning", label = "背包满时警告",
		tooltip = "背包没有空位时抛竿会警告一次，以免渔获装不下。" },
	{ cmd = "sound", key = "soundBoost", label = "钓鱼时放大水花音效",
		tooltip = "鱼线抛出后，将音效调至最大，方便听清水花声。" },
	{ cmd = "quiet", key = "quietOthers", label = "钓鱼时压低其他声音",
		tooltip = "装备鱼竿时，降低（或关闭）音乐、环境音和对白，突出水花声。换回武器后，或你手动改音量后，会恢复为你自己的音量。" },
	{ cmd = "autoequip", key = "autoEquip", label = "自动装备鱼竿",
		tooltip = "未装备鱼竿时，施法键先从背包装备最好的鱼竿（再按一次才施放）。原武器会记住，之后自动换回。" },
	{ cmd = "outfit", key = "fishingOutfit", label = "拿鱼竿时穿上钓鱼装备",
		tooltip = "装上鱼竿时，自动穿上背包里钓鱼加成更高、且优于当前穿着的装备（钓鱼帽、靴、附魔钓鱼的手套等）。脱竿换回武器时，原装备一并换回。" },
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
	{ cmd = "doneclose", key = "doneCloses", label = "「结束钓鱼」时关闭统计窗口",
		tooltip = "按下「结束钓鱼」时，除了换回武器和装备，还关闭统计窗口（或迷你条）。关闭此选项时，统计窗口保持打开，即使是施放时自动打开的。" },
	{ cmd = "escclose", key = "escapeCloses", label = "Escape 关闭「哇，大鱼」窗口",
		tooltip = "在游戏窗口（背包、地图等）都关闭后，按 Escape 会关闭「哇，大鱼」窗口（先关最上层），然后照常打开游戏菜单。关闭此选项时，Escape 不关插件窗口，用 X 关闭。" },
	{ cmd = "fade", key = "fadeStats", label = "钓鱼时淡化统计窗口",
		tooltip = "钓鱼期间，鼠标不在统计窗口上时，窗口会淡成半透明，少遮挡一点水面。" },
	{ cmd = "lock", key = "lockWindow", label = "锁定窗口",
		tooltip = "防止「哇，大鱼」窗口被误移动或误调整大小。关闭后即可再次移动。" },
	{ cmd = "autoopen", key = "openOnCast", label = "施放时打开统计窗口",
		tooltip = "开始钓鱼时打开统计窗口。若用关闭按钮或小地图按钮关掉，会保持关闭，直到你暂停钓鱼约 2 分钟。" },
	{ cmd = "openpole", key = "openOnPole", label = "装上鱼竿时打开统计窗口",
		tooltip = "每次装备鱼竿时都打开统计窗口（或迷你条），即使你之前钓鱼时关掉过。其他页面已打开时不会抢占「哇，大鱼」窗口。" },
	{ cmd = "mini", key = "statsMini", label = "用迷你条代替统计窗口",
		tooltip = "施放时打开细长条代替统计窗口：技能与区域、渔获与每小时鱼数、诱饵与想要列表。点击打开完整统计。/onecast mini 可开关。" },
	{ cmd = "summary", key = "sessionSummary", label = "聊天中显示会话摘要",
		tooltip = "暂停钓鱼约 2 分钟后，在聊天汇总本次：渔获、每小时鱼数、商人售价、技能提升和图鉴新鱼。" },
	{ cmd = "controller", key = "padFishing", label = "用手柄按钮钓鱼",
		tooltip = "使用手柄时，某一按钮在装备鱼竿期间施放和收杆，代替原本功能（如 A 跳跃）。摘竿或进战斗即恢复。未插手柄时无变化。" },
	{ cmd = "padhints", key = "padHints", label = "显示手柄按钮提示",
		tooltip = "使用手柄时，「哇，大鱼」按游戏样式显示按钮：浮漂上的钓鱼键（代替游戏的互动键，对插件收杆无效）、迷你条上的施放键，以及标签旁的扳机与肩键。" },
	{ cmd = "rumble", key = "padRumble", label = "提醒时手柄震动",
		tooltip = "屏幕提醒时手柄短暂震动：稀有渔获、达成目标、荆棘谷大赛凑满 40 条美味鱼。" },
	{ cmd = "fishloot", key = "autoLootFishing", label = "钓鱼时自动拾取",
		tooltip = "装备鱼竿期间开启游戏自动拾取，渔获直接进包；换回武器后恢复你原来的设置。若本来就开着会自动拾取则保持开启。" },
	{ cmd = "fastloot", key = "fastLoot", label = "快速拾取",
		tooltip = "自动拾取开启时，战利品窗口一出现就一次性拿走，比游戏逐件拾取更快。仅钓鱼战利品及钓上的箱子、匣子；其他交给游戏。" },
	{ cmd = "autoloot", key = "autoLootHint", label = "提示开启自动拾取",
		tooltip = "钓到东西时若未开启自动拾取，每次登录最多提示一次，方便渔获直接进包。" },
	{ cmd = "alertsound", key = "alertSound", label = "播放提醒音效",
		tooltip = "每次稀有渔获提醒时播放团队警告音。关闭则只显示画面提醒。" },
	{ cmd = "skillup", key = "skillToast", label = "技能提升提示",
		tooltip = "钓鱼技能提升时，屏幕上浮现并淡出「+1 钓鱼」；迷你条打开时叠在条上。" },
	{ cmd = "wanted", key = "goalAlerts", label = "想要渔获提醒",
		tooltip = "钓到想要列表里的鱼时提醒（在统计窗口右键渔获可添加）。设了数量时，一半会在聊天提示，集齐再提醒，两种方式都算。" },
	{ cmd = "newcatch", key = "newCatchMessage", label = "新鱼入图鉴时在聊天提示",
		tooltip = "钓到你所有角色都从未钓到过的鱼时，在聊天发一行提示。" },
	{ cmd = "alert", key = "alert", label = "稀有渔获提醒",
		tooltip = "钓到达到提醒品质或以上的物品时，播放音效并闪现团队警告。想要的鱼有单独提醒。" },
	{ cmd = "pools", key = "rememberPools", label = "记住钓鱼鱼群点",
		tooltip = "装备鱼竿时将鼠标悬停在鱼群上并抛竿，会把钓点标在图鉴的区域地图上。鱼群会移动，标记表示曾经出现过的位置。目前仅识别英文鱼群名。/onecast forgetpools 可清除。" },
	{ cmd = "campreminder", key = "campReminder", label = "营地增益提醒",
		tooltip = "钓鱼架或钓鱼小屋提供的优良或稀有钓鱼增益消失时，在聊天提示。图鉴的「营地」标签页有更多营地信息。" },
	{ cmd = "extravaganza", key = "extravaganza", label = "荆棘谷钓鱼大赛提醒",
		tooltip = "荆棘谷钓鱼大赛即将开始及开始时在聊天提示（经典日程：服务器时间周日 14:00–16:00）。" },
	{ cmd = "loginmessage", key = "loginMessage", label = "登录时在聊天显示版本",
		tooltip = "登录时在聊天显示插件版本，并附带「更新内容」链接。" },
	{ cmd = "caughtby", key = "catchTooltip", label = "物品提示显示稀有度与谁钓到",
		tooltip = "在图鉴物品的任何提示上（背包、聊天链接、拍卖行等），显示经典版每次钓到的几率，以及你哪个角色钓到过。" },
	{ cmd = "pooltips", key = "poolTooltip", label = "鱼群提示显示产出",
		tooltip = "鼠标悬停鱼群时，显示产出（含经典几率）以及你尚未钓到的。" },
	{ cmd = "map", key = "mapStrip", label = "世界地图显示钓鱼等级",
		tooltip = "世界地图上显示小卡片：区域钓鱼等级、你的技能对比、该区渔获数。在大陆地图上跟随鼠标所在区域。可拖动到任意位置，在卡片上 Ctrl+滚轮缩放，右键复位。" },
	{ cmd = "badges", key = "tabBadges", label = "侧边标签绿点",
		tooltip = "有可分享发现时，在「数据报告」标签显示绿点；有未读版本时，在「更新内容」标签显示绿点。" },
	{ cmd = "minimap", key = "minimapButton", label = "显示小地图按钮",
		tooltip = "在小地图上显示「哇，大鱼」按钮。可拖动调整位置。" },
}

-- The sub-pages under OneCast in the options, each a list of { heading, keys... }. A key is an
-- OPTIONS entry, or one of the sliders and dropdowns built in SetupSettings.
-- Fishing: how you cast and reel, your pole and gear, and what you catch. While fishing: what
-- you see and hear with the line out.
local OPTION_PAGES = {
	{ name = "钓鱼",
		{ "施放", "castKey", "doubleClick", "softInteract" },
		{ "鱼竿与装备", "autoEquip", "fishingOutfit", "restoreDelay", "restoreOnCombat" },
		{ "拾取与背包", "autoLootFishing", "fastLoot", "autoLootHint", "bagWarning", "junkMode", "auctionSource" },
	},
	{ name = "诱饵",
		{ "你的诱饵", "lureChoice", "autoLure" },
		{ "工具箱", "tackleBox", "lureVendorHint" },
	},
	{ name = "钓鱼时",
		{ "你的浮漂", "bobberMarker", "beamColor" },
		{ "声音", "soundBoost", "quietOthers", "quietLevel" },
	},
	{ name = "手柄",
		{ "钓鱼按钮", "padFishing", "padButton", "padStart", "padWindow" },
		{ "反馈", "padHints", "padRumble" },
	},
	{ name = "无障碍",
		{ "文字与按钮", "largerText", "glyphSize" },
		{ "图鉴与装备", "collectionTicks" },
		{ "动态效果", "reduceMotion" },
	},
	{ name = "统计与提醒",
		{ "窗口", "openOnCast", "openOnPole", "statsMini", "closeOnDone", "doneCloses", "escapeCloses", "fadeStats", "sessionSummary" },
		{ "提醒", "alert", "alertSound", "alertQuality", "skillToast", "goalAlerts", "newCatchMessage", "extravaganza", "campReminder" },
	},
}
-- Greyed out and indented while the option they belong to is off.
local OPTION_PARENT = {
	beamColor = "bobberMarker",
	quietLevel = "quietOthers",
	padButton = "padFishing",
	padStart = "padFishing",
	padWindow = "padFishing",
	alertQuality = "alert",
	alertSound = "alert",
}

local UpdateQuiet -- below: quiet other sounds while fishing
local UpdateLoot -- below: auto loot while fishing

-- Every setting that isn't a checkbox, described once: the options panel and the window's Options
-- page are both built from this. A `list` setting is a dropdown of { value, text } pairs; the others
-- are sliders from `min` to `max` in `step`s, shown with `format`. `char` keeps it per character.
local CHOICES = {
	beamColor = { label = "光束颜色", kind = "string",
		tooltip = "浮漂发光与光柱的颜色。",
		list = function()
			local swatch = function(key, text)
				local c = ns.Bobber and ns.Bobber.COLORS[key]
				return c and string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text) or text
			end
			return { { "arcane", swatch("arcane", "奥术") }, { "gold", swatch("gold", "金色") }, { "white", swatch("white", "白色") },
				{ "blue", swatch("blue", "冰蓝") }, { "teal", swatch("teal", "青绿") }, { "green", swatch("green", "绿色") },
				{ "red", swatch("red", "红色") }, { "purple", swatch("purple", "紫色") }, { "pink", swatch("pink", "粉色") },
				{ "class", "职业颜色" } }
		end,
		onChange = function()
			if ns.Bobber then
				ns.Bobber.Retint()
			end
		end },
	auctionSource = { label = "拍卖价格来源", kind = "string",
		tooltip = "安装了多个价格插件时，统计使用哪一个的拍卖价：「自动」按 Auctionator → TSM → Naowh Forever 依次取有价的。列表只显示你已安装的。",
		list = function()
			local list = { { "auto", "自动" } }
			for _, source in ipairs(ns.Stats and ns.Stats.PriceSources and ns.Stats.PriceSources() or {}) do
				list[#list + 1] = { source.key, source.name }
			end
			return list
		end,
		onChange = function()
			if ns.Stats then
				ns.Stats.RefreshIfShown()
			end
		end },
	junkMode = { label = "向商人出售钓鱼灰装", kind = "string",
		tooltip = "在商人处处理你钓上来的灰色垃圾，且不影响其他物品：商人窗口下显示出售按钮、打开商人即自动出售，或不作处理。",
		list = function()
			return { { "button", "出售按钮" }, { "auto", "自动出售" }, { "off", "不处理" } }
		end,
		onChange = function()
			if ns.Junk then
				ns.Junk.UpdateButton()
			end
		end },
	padButton = { label = "钓鱼按钮", kind = "string",
		tooltip = "装备鱼竿时用于施放和收杆的手柄按钮。A / 十字键在拇指下，摘竿后恢复为跳跃等原功能。",
		list = function()
			local list = {}
			for _, b in ipairs(ns.Controller and ns.Controller.BUTTONS or {}) do
				list[#list + 1] = { b[1], b[2] }
			end
			return list
		end,
		onChange = function()
			if ns.Controller then
				ns.Controller.Update()
			end
		end },
	padStart = { label = "这样拿上鱼竿", kind = "string",
		tooltip = "未装备鱼竿时，钓鱼键仍是跳跃。按住所示扳机再按该键，「哇，大鱼」会帮你拿竿；之后单按即可施放与收杆，直到摘竿。选「关闭」则需自己换竿或用施法键。",
		list = function()
			local list = {}
			for _, s in ipairs(ns.Controller and ns.Controller.STARTS or {}) do
				list[#list + 1] = { s[1], ns.Controller.StartLabel(s[1]) }
			end
			return list
		end,
		onChange = function()
			if ns.Controller then
				ns.Controller.Update()
			end
		end },
	padWindow = { label = "「哇，大鱼」窗口按钮", kind = "string",
		tooltip = "装备鱼竿时，用手柄第二个按钮打开和关闭「哇，大鱼」窗口。选「关闭」则不影响该键。",
		list = function()
			local list = { { "off", "关闭" } }
			for _, b in ipairs(ns.Controller and ns.Controller.BUTTONS or {}) do
				list[#list + 1] = { b[1], b[2] }
			end
			return list
		end,
		onChange = function()
			if ns.Controller then
				ns.Controller.Update()
			end
		end },
	glyphSize = { label = "手柄按钮图示大小", kind = "string",
		tooltip = "「哇，大鱼」绘制手柄按钮图示的大小：各窗口下的按键指南、浮漂上、欢迎界面和提示中。",
		list = function()
			return { { "normal", "正常" }, { "large", "大" }, { "largest", "最大" } }
		end,
		onChange = function()
			if ns.Controller then
				ns.Controller.Update()
			end
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
		tooltip = "「哇，大鱼」窗口的大小，所有页面通用。也可拖动任意页面右下角，或在统计页上按 Ctrl + 鼠标滚轮。",
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
				list[#list + 1] = { lure.id, string.format("%s (+%d)", ns.Lure.Name(lure), lure.bonus) }
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
	{ "外观", "tabSide", "statsScale" },
	{ "常规", "lockWindow", "minimapButton", "tabBadges", "loginMessage" },
	{ "提示与地图", "catchTooltip", "poolTooltip", "mapStrip", "rememberPools" },
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
_G["BINDING_NAME_" .. BINDING_COMMAND] = "施放（抛竿）"
_G["BINDING_NAME_" .. REEL_BINDING] = "收杆（与浮漂互动）"
_G.BINDING_NAME_ONECAST_RESTORE = "换回武器"
_G.BINDING_NAME_ONECAST_DONE = "结束钓鱼（换回武器与装备）"
_G.BINDING_NAME_ONECAST_BOOK = "钓鱼图鉴"
_G.BINDING_NAME_ONECAST_WARDROBE = "钓鱼装扮"
_G.BINDING_NAME_ONECAST_JOURNEY = "渔夫之路"
_G.BINDING_NAME_ONECAST_WINDOW = "「哇，大鱼」窗口（上次使用的页面）"

local db
local fishingName
local fishing = false
local lastRightClick = 0
-- Borrowed CVars by group, each cvar -> { original = value, ours = value }: "cast" for the
-- length of one cast, "quiet" for as long as the pole is equipped. No CVar is in both.
local leases = { cast = {}, quiet = {}, loot = {} }
-- Turned down while the pole is on, to quietLevel percent of the player's own volume.
local QUIET_CVARS = { "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume" }

-- Separate owners so dropping one override never drops the others.
-- reelOwner: one-key mode (cast key → INTERACTTARGET while the line is out).
-- reelKeyOwner: dedicated ONECAST_REEL key → INTERACTTARGET (always, out of combat).
-- clickOwner: double right-click cast.
local reelOwner = CreateFrame("Frame")
local reelKeyOwner = CreateFrame("Frame")
local clickOwner = CreateFrame("Frame")

-- OneCast's small print -------------------------------------------------------------------------
-- Its own font objects, which every OneCast window uses in place of the game's small fonts. A
-- font object's changes reach every text that uses it, so the text size changes everywhere at
-- once. By default a point bigger than the game's small fonts (10 is hard to read), and its grey
-- a little lighter for contrast; with "Larger text" on, the game's normal sizes.
local SMALL_FONTS = {
	{ "OneCastFontHighlightSmall", "GameFontHighlightSmall", "GameFontHighlight" },
	{ "OneCastFontNormalSmall", "GameFontNormalSmall", "GameFontNormal" },
	{ "OneCastFontDisableSmall", "GameFontDisableSmall", "GameFontDisable", { 0.66, 0.66, 0.66 } },
	{ "OneCastFontGreenSmall", "GameFontGreenSmall", "GameFontGreen" },
	{ "OneCastFontHighlightSmallOutline", "GameFontHighlightSmallOutline", "GameFontHighlightOutline" },
}
for _, spec in ipairs(SMALL_FONTS) do
	if CreateFont and not _G[spec[1]] then
		CreateFont(spec[1])
	end
end

function ns.LargerText()
	return ns.db and ns.db.largerText and true or false
end

function ns.ApplyTextSize()
	local large = ns.LargerText()
	for _, spec in ipairs(SMALL_FONTS) do
		local font, from = _G[spec[1]], _G[large and spec[3] or spec[2]]
		if font and from and font.CopyFontObject then
			font:CopyFontObject(from)
			local path, size, flags = font:GetFont()
			if path and size and not large then
				font:SetFont(path, size + 1, flags)
			end
			if spec[4] then
				font:SetTextColor(spec[4][1], spec[4][2], spec[4][3])
			end
		end
	end
end
ns.ApplyTextSize()

-- "Reduce motion": OneCast's animations stopped (the water flowing, shines and glints, the
-- bobber's light breathing).
function ns.ReduceMotion()
	return ns.db and ns.db.reduceMotion and true or false
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33bbff" .. ns.DISPLAY_NAME .. "|r: " .. msg)
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

-- The game's current APIs first, then the old names: those live in Blizzard's deprecated files,
-- which only load while the loadDeprecationFallbacks setting is on, and go at the next expansion.

-- Milliseconds of temporary enchant (a lure) on the main hand, or nil if none.
function ns.MainHandEnchantMs()
	local paperDoll = C_PaperDollInfo
	if paperDoll and paperDoll.GetTemporaryEnchantmentInfo then
		local info = paperDoll.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND or 16)
		local ms = info and info.remainingTimeMs
		if ms and not (issecretvalue and issecretvalue(ms)) then
			return ms
		end
		return nil
	end
	if GetWeaponEnchantInfo then
		local has, ms = GetWeaponEnchantInfo()
		return has and ms or nil
	end
end

-- True if this character knows the spell (a recipe), nil if the game can't say.
function ns.KnowsSpell(spellID)
	local spellBook = C_SpellBook
	if spellBook and spellBook.IsSpellKnown and Enum.SpellBookSpellBank then
		return spellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player) and true or false
	end
	if IsPlayerSpell then
		return IsPlayerSpell(spellID) and true or false
	end
end

-- A raid-warning flash in the middle of the screen.
function ns.RaidWarning(text)
	if ns.Controller then
		ns.Controller.Rumble()
	end
	local color = ChatTypeInfo and ChatTypeInfo.RAID_WARNING
	if RaidWarningUtil and RaidWarningUtil.AddMessage then
		RaidWarningUtil.AddMessage(text, color)
	elseif RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, color)
	end
end

-- Put a link into chat: into the chat box if it's open, else opening it with the link in. The
-- game's current ChatFrameUtil, or the old names it keeps (deprecated) for older clients.
function ns.InsertChatLink(link)
	if not link then
		return false
	end
	local util = ChatFrameUtil
	local insert = (util and util.InsertLink) or ChatEdit_InsertLink
	if insert and insert(link) then
		return true
	end
	local open = (util and util.OpenChat) or ChatFrame_OpenChat
	if open then
		open(link)
		return true
	end
	return false
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

-- The same value, however the game writes it: "0.3" and "0.300000" are one volume.
local function SameValue(a, b)
	if a == b then
		return true
	end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and y ~= nil and math.abs(x - y) < 0.001
end

local CVAR_NAMES = { Sound_MusicVolume = "音乐音量", Sound_AmbienceVolume = "环境音量",
	Sound_DialogVolume = "对白音量", Sound_SFXVolume = "音效音量", Sound_EnableSFX = "音效开关",
	autoLootDefault = "自动拾取" }

-- Give the group's CVars back, each only if it still holds OneCast's value: one changed
-- meanwhile (by you, or by another addon that also turns up the splash) stays as it is. Chat
-- says so once a login for each, not on every cast when another addon does it each time.
local leftAlone = {}
local function ReleaseCVars(group)
	local leased = leases[group]
	for name, lease in pairs(leased) do
		if SameValue(C_CVar.GetCVar(name), lease.ours) then
			C_CVar.SetCVar(name, lease.original)
		elseif CVAR_NAMES[name] and not leftAlone[name] then
			leftAlone[name] = true
			Print("钓鱼期间" .. CVAR_NAMES[name] .. "已被改动（你或其他插件），已保持该设置，本次登录不再重复提示。")
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

-- Auto loot on while a pole is equipped, if the option is on; back as it was after.
function UpdateLoot()
	local want = db and db.autoLootFishing and HasFishingPole()
	local active = next(leases.loot) ~= nil
	if active and not want then
		ReleaseCVars("loot")
	elseif want and not active then
		LeaseCVars("loot", { autoLootDefault = "1" })
	end
end
ns.UpdateLoot = UpdateLoot

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

local function HasDedicatedReelKey()
	return GetBindingKey(REEL_BINDING) ~= nil
end

-- Keep the dedicated reel key on INTERACTTARGET so it never casts.
local function SyncDedicatedReelKeys()
	if InCombatLockdown() then
		return
	end
	ClearOverrideBindings(reelKeyOwner)
	local keys = { GetBindingKey(REEL_BINDING) }
	for i = 1, #keys do
		SetOverrideBinding(reelKeyOwner, true, keys[i], "INTERACTTARGET")
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
	-- Two-key mode: cast key stays cast; reel key (already INTERACTTARGET) hits the bobber.
	-- One-key mode: temporarily turn the cast key into interact for this cast only.
	ClearOverrideBindings(reelOwner)
	if not HasDedicatedReelKey() then
		for _, key in ipairs({ GetBindingKey(BINDING_COMMAND) }) do
			SetOverrideBinding(reelOwner, true, key, "INTERACTTARGET")
		end
		-- A controller's fishing button reels too: its cast binding steps aside first.
		if ns.Controller then
			ns.Controller.Update()
			for _, key in ipairs(ns.Controller.ReelKeys()) do
				SetOverrideBinding(reelOwner, true, key, "INTERACTTARGET")
			end
		end
	elseif ns.Controller then
		ns.Controller.Update()
	end
end

local function StopReelMode()
	if not InCombatLockdown() then
		ClearOverrideBindings(reelOwner)
	end
	ReleaseCVars("cast")
	if ns.Controller then
		ns.Controller.Update() -- the fishing button casts again
	end
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
	local cast = { GetBindingKey(BINDING_COMMAND) }
	local reel = { GetBindingKey(REEL_BINDING) }
	local parts = {}
	if #cast > 0 then
		parts[#parts + 1] = "抛 " .. table.concat(cast, ", ")
	end
	if #reel > 0 then
		parts[#parts + 1] = "收 " .. table.concat(reel, ", ")
	elseif #cast > 0 then
		parts[#parts + 1] = "一键收杆"
	end
	return #parts > 0 and table.concat(parts, " · ") or "未绑定"
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
	if Settings.KEYBINDINGS_CATEGORY_ID then
		-- OneCast's keys have a section of their own (Bindings.xml's category), and the list
		-- scrolls to it. It opens with a click on its +: opening it from here would mean writing
		-- into the game's own settings, which is what got an action blocked on the Social page.
		Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, "OneCast")
		local castName = _G["BINDING_NAME_" .. BINDING_COMMAND] or "施放（抛竿）"
		local reelName = _G["BINDING_NAME_" .. REEL_BINDING] or "收杆（与浮漂互动）"
		Print(string.format("施放键：展开「%s」，绑定「%s」；可选再绑「%s」分键收杆。", ns.DISPLAY_NAME, castName, reelName))
	elseif settingsCategory then
		Settings.OpenToCategory(settingsCategory:GetID())
	end
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

-- Every setting, as one object each: its value from the saved variables, set, and what happens
-- when it changes. The window's Options page and the slash commands use these.
--
-- The game's own options get a page of OneCast's own frames (a word on where everything is, and
-- buttons to open it), not the game's checkboxes, sliders and dropdowns. Those come from a pool
-- the game shares between every page of its options, and a control an addon has set up can be
-- handed to one of the game's own pages afterwards: there, an action only the game may take (the
-- Social page's) is blocked and blamed on the addon.
local function NewSetting(key, store, default, onChange)
	local setting = { key = key, callbacks = {} }
	function setting:GetValue()
		local value = store[key]
		if value == nil then
			return default
		end
		return value
	end
	function setting:SetValue(value)
		store[key] = value
		for _, callback in ipairs(self.callbacks) do
			callback(self, value)
		end
	end
	function setting:SetValueChangedCallback(callback)
		self.callbacks[#self.callbacks + 1] = callback
	end
	if onChange then
		setting:SetValueChangedCallback(onChange)
	end
	ns.optionSettings[key] = setting
	return setting
end

local function SettingsPage()
	local f = CreateFrame("Frame")
	f:Hide()
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(ns.DISPLAY_NAME)
	local version = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
	version:SetText("v" .. (ns.VERSION or "?"))
	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	text:SetPoint("RIGHT", -24, 0)
	text:SetJustifyH("LEFT")
	text:SetSpacing(3)
	text:SetText(string.format(
		"多数设置在插件窗口的「选项」页。施放与收杆按键：选项 > 按键设置 > 插件 > %s（「施放」必填；「收杆」可选，分键后施放键在线出去时不会变成收杆）。当前：%s。",
		ns.DISPLAY_NAME, BoundKeysText()))
	local y = -96
	local function Button(label, onClick, x)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(200, 26)
		b:SetPoint("TOPLEFT", x or 16, y)
		b:SetText(label)
		b:SetScript("OnClick", onClick)
		return b
	end
	Button("打开「哇，大鱼」选项", function()
		ns.Hub.ShowOptions()
	end)
	Button("按键绑定", function()
		ns.OpenSettings()
	end, 232)
	y = y - 46
	local open = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	open:SetPoint("TOPLEFT", 16, y)
	open:SetText("打开")
	y = y - 22
	for i, entry in ipairs({
		{ "统计窗口", function() ns.Stats.Toggle() end },
		{ "工具箱", function() ns.TackleBox.ToggleWindow() end },
		{ "钓鱼装扮", function() ns.Wardrobe.Show() end },
		{ "钓鱼图鉴", function() ns.Book.Show() end },
		{ "渔夫之路", function() ns.Journey.Show() end },
		{ "数据报告", function() ns.Report.Show() end },
		{ "更新内容", function() ns.WhatsNew.Show() end },
	}) do
		Button(entry[1], entry[2], i % 2 == 1 and 16 or 232)
		if i % 2 == 0 then
			y = y - 32
		end
	end
	return f
end

local function SetupSettings()
	ns.optionSettings = {}

	local ON_CHANGE = {
		minimapButton = UpdateMinimapVisibility,
		escapeCloses = function()
			if ns.UI and ns.UI.UpdateEscape then
				ns.UI.UpdateEscape()
			end
		end,
		quietOthers = function()
			UpdateQuiet()
		end,
		autoLootFishing = function()
			UpdateLoot()
		end,
		padFishing = function()
			if ns.Controller then
				ns.Controller.Update()
			end
		end,
		padHints = function()
			if ns.Mini then
				ns.Mini.Refresh()
			end
		end,
		statsMini = function()
			if not db.statsMini and ns.Mini then
				ns.Mini.Hide()
			end
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
		tabBadges = function()
			ns.Hub.UpdateBadges()
		end,
		largerText = function()
			ns.ApplyTextSize()
			if ns.Book and ns.Book.RefreshIfShown then
				ns.Book.RefreshIfShown()
			end
		end,
		collectionTicks = function()
			if ns.Book and ns.Book.RefreshIfShown then
				ns.Book.RefreshIfShown()
			end
			if ns.Journey and ns.Journey.Refresh then
				ns.Journey.Refresh()
			end
		end,

		mapStrip = function()
			if ns.WorldMap then
				ns.WorldMap.Update()
			end
		end,
	}

	for _, opt in ipairs(OPTIONS) do
		opt.setting = NewSetting(opt.key, opt.char and OneCastCharDB or db,
			opt.char and charDefaults[opt.key] or defaults[opt.key], ON_CHANGE[opt.key])
	end
	for key, spec in pairs(CHOICES) do
		local setting = NewSetting(key, spec.char and OneCastCharDB or db,
			spec.char and charDefaults[key] or defaults[key], spec.onChange)
		if key == "statsScale" then
			ns.scaleSetting = setting
		end
	end

	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(SettingsPage(), ns.DISPLAY_NAME)
		if category then
			Settings.RegisterAddOnCategory(category)
			settingsCategory = category
		end
	end
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

	local castKeys = { GetBindingKey(BINDING_COMMAND) }
	local reelKeys = { GetBindingKey(REEL_BINDING) }
	Row("施放", #castKeys > 0 and table.concat(castKeys, ", ") or "未绑定", #castKeys > 0 and WHITE or RED)
	if #reelKeys > 0 then
		Row("收杆", table.concat(reelKeys, ", "))
	elseif #castKeys > 0 then
		Row("收杆", "同一键（一键模式）", GREY)
	else
		Row("收杆", "未绑定", RED)
	end
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
	{ "钓鱼装扮", function() ns.Wardrobe.Show() end },
	{ "钓鱼图鉴", function() ns.Book.Toggle() end },
	{ "渔夫之路", function() ns.Journey.Show() end },
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
	ns.UI.EscapeCloses(f)

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
	-- Open away from the screen edge the button is nearest.
	menuFrame.owner = owner
	menuFrame:ClearAllPoints()
	local x, y = owner:GetCenter()
	local right = x and x > UIParent:GetWidth() / 2
	local top = y and y > UIParent:GetHeight() / 2
	menuFrame:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), owner,
		(top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT"))
	if ns.Controller then
		ns.Controller.Navigate(menuFrame, true)
	end
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
events:RegisterEvent("UPDATE_BINDINGS")
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
			ns.db = db
			-- Settings of features 1.0 removed (themes, milestones, the clean view, the bobber's
			-- styles and height, the auction source, the report's chat hints): gone from the saves.
			for _, key in ipairs({ "theme", "themeEffects", "bobberStyle", "bobberHeight", "beamCustom",
				"cleanView", "reportHint", "milestones", "milestonesSeeded", "milestonesOn",
				"milestoneAlerts", "sellJunk" }) do
				db[key] = nil
			end
			-- A beam colour that followed the theme, or a custom one: the default now.
			if db.beamColor == "theme" or db.beamColor == "custom" then
				db.beamColor = defaults.beamColor
			end
			OneCastCharDB = OneCastCharDB or {}
			OneCastCharDB.milestones, OneCastCharDB.milestonesSeeded = nil, nil
			for k, v in pairs(charDefaults) do
				if OneCastCharDB[k] == nil then
					OneCastCharDB[k] = v
				end
			end
			ns.ApplyTextSize()
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
			UpdateLoot()
			SyncDedicatedReelKeys()
		end
		if event == "PLAYER_LOGIN" and ns.Onboarding then
			ns.Onboarding.OnLogin() -- no cast key yet: the welcome, to choose one
		end
		if event == "PLAYER_LOGIN" and not GetBindingKey(BINDING_COMMAND) then
			Print(string.format(
				"请在 选项 > 按键设置 > 插件 > %s 绑定「施放」；可选再绑「收杆」分键（绑了收杆后，施放键不会再变成收杆）。也可装备鱼竿后双击右键。输入 /onecast 打开选项。",
				ns.DISPLAY_NAME))
		end
	elseif event == "UPDATE_BINDINGS" then
		SyncDedicatedReelKeys()
		-- Re-apply one-key override if the line is still out and no dedicated reel key.
		if fishing and not InCombatLockdown() then
			StartReelMode()
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
		ClearOverrideBindings(reelKeyOwner)
		ClearOverrideBindings(clickOwner)
		ReleaseCVars("cast") -- the quiet ones follow the pole, which combat puts away
	elseif event == "PLAYER_REGEN_ENABLED" then
		ApplyFishingSpell()
		SyncDedicatedReelKeys()
		-- A line still out: combat took the reel key away, and pressing it now would recast.
		local _, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
		if IsFishingSpell(spellID) then
			fishing = true
			StartReelMode()
			Watch()
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		UpdateQuiet()
		UpdateLoot()
	elseif event == "PLAYER_LOGOUT" then
		-- CVars are saved on logout; never save ours.
		ReleaseCVars("cast")
		ReleaseCVars("quiet")
		ReleaseCVars("loot")
	end
end)

SLASH_ONECAST1 = "/onecast"
SlashCmdList.ONECAST = function(msg)
	local cmd = strlower(strtrim(msg or ""))
	if cmd == "" then
		ns.Hub.ShowOptions()
		return
	elseif cmd == "setup" or cmd == "welcome" or cmd == "key" then
		ns.Onboarding.Show() -- choose the cast key
		return
	elseif cmd == "keys" or cmd == "settings" then
		OpenSettings() -- the game's options: the cast key is set there
		return
	elseif cmd == "riggle" then
		-- A waypoint to Riggle Bassbait, for the Fishing Extravaganza.
		if not ns.Extravaganza.Waypoint() then
			ns.Print("暂时无法设置路径点（战斗中，或地图尚未就绪）。")
		end
		return
	elseif cmd == "journey" or cmd == "ranks" then
		ns.Journey.Show()
		return
	elseif cmd == "wardrobe" then
		ns.Wardrobe.Show()
		return
	elseif cmd == "pad" then
		if ns.Controller then
			ns.Controller.Status()
		end
		return
	elseif cmd:match("^search%s") or cmd == "search" then
		local text = msg:match("^%s*%S+%s+(.-)%s*$") or ""
		if ns.Book and ns.Book.Search then
			ns.Book.Search(text)
		end
		return
	elseif cmd == "pad watch" then
		if ns.Controller then
			ns.Controller.Watch()
		end
		return
	elseif cmd == "stats" then
		ns.Stats.Toggle()
		return
	elseif cmd == "session" or cmd == "spots" or cmd == "alltime" or cmd == "farm" or cmd == "records" then
		ns.Stats.Toggle(cmd)
		return
	elseif cmd == "reset" then
		ns.Stats.Reset()
		Print("会话统计已重置。")
		return
	elseif cmd == "gear" then
		OneCast_RestoreWeapons()
		return
	elseif cmd == "done" then
		OneCast_DoneFishing()
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
	elseif cmd == "scale" or cmd:match("^scale%s") then
		local percent = tonumber(cmd:match("^scale%s+(%d+)"))
		if percent then
			ns.Stats.SetScale(percent)
			Print("窗口缩放：" .. db.statsScale .. "%")
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
	Print("/onecast setup - 选择施放键")
	Print("/onecast keys - 打开游戏按键设置")
	Print("/onecast new - 各版本更新内容")
	Print("/onecast pad - 手柄状态（手柄行为异常时用）")
	Print("/onecast search <关键词> - 搜索渔获、区域、配方、装备、等级与设置")
	Print("/onecast wardrobe - 选择钓鱼穿着")
	Print("/onecast journey - 钓鱼等级与下一级学习地点")
	Print("/onecast riggle - 荆棘谷钓鱼大赛：里格尔·巴斯贝特路径点")
	Print("/onecast book - 钓鱼图鉴（/onecast camp 打开「营地」标签页）")
	Print("/onecast report - 把钓鱼数据整理成文本分享，帮助补全 Forever 数据")
	Print("/onecast tackle - 工具箱（/onecast tackle reset 把按钮移回原位）")
	Print("/onecast stats - 统计窗口（或 /onecast session|spots|alltime|farm|records 打开对应标签）")
	Print("/onecast reset - 开始新会话")
	Print("/onecast gear - 换回武器")
	Print("/onecast done - 结束钓鱼：换回武器与装备")
	Print("/onecast scan - 用 Auctionator 估价渔获（需打开拍卖行）")
	Print("/onecast scale 50-200 - 窗口缩放百分比")
	for _, opt in ipairs(OPTIONS) do
		local store = opt.char and OneCastCharDB or db
		Print("/onecast " .. opt.cmd .. " - " .. opt.label .. "（" .. (store[opt.key] and "开" or "关") .. "）")
	end
end

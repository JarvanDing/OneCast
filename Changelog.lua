-- OneCast's changelog, shown in the What's new window (WhatsNew.lua), newest first.
-- Each release: { version, date, sections = { { heading, { { lead, text }, ... } }, ... } }.
-- Add a new entry at the top for every release, with the same version as the TOC.

local _, ns = ...

ns.CHANGELOG = {
	{
		version = "0.5.0",
		date = "7 November 2026",
		sections = {
			{ "New", {
				{ "The tackle box.", "A small button appears while your pole is in your main hand, with your lure, how many you have and the time left. Left-click applies your lure, right-click opens its settings, Shift-drag moves it, and the Tackle box option hides it. Thanks to raffle0 for the idea!" },
				{ "You choose the lure.", "Pick one for each character, or \"Best I can use\". Your choice is never swapped for another: if it runs out, you fish without one. Nothing is spent until you choose." },
				{ "Apply with the cast key.", "An option, off by default. With no lure on, the key applies yours, then casts on the next press. Lures take 5 seconds to go on, and the key waits for that rather than interrupting. Every lure is still your own press." },
				{ "Remembered pools.", "Hover over a fishing pool with your pole on and cast, and the spot you fished it from is marked on the collection book's zone maps. English pool names only for now." },
				{ "Bags full warning.", "A warning when you cast with no free bag space, so a catch doesn't surprise you." },
				{ "Low on lures.", "A vendor selling your lure gets a mention in chat if you have fewer than 5. Buying stays up to you." },
				{ "Lures in your stats.", "The tackle box compares your fish per hour with and without a lure. The minimap tooltip shows your lure too." },
				{ "New key bindings.", "Apply lure and Tackle box, under Keybindings > AddOns." },
			} },
			{ "Changed", {
				{ "A lure that would help.", "When you're short of a zone's level, the verdict names a lure in your bags that would cover it." },
				{ "Getaways know your skill.", "OneCast now notes your skill when a fish gets away. A zone that got away from you earlier can clear once you've outgrown it or caught 10 in a row there, and a getaway above a zone's listed level says the level may be too low." },
				{ "Tidier options.", "The options page is grouped into sections." },
			} },
		},
	},
	{
		version = "0.4.0",
		date = "7 November 2026",
		sections = {
			{ "New", {
				{ "Fishing levels for every zone.", "The collection book has a new Zones tab: every zone by the Fishing skill it needs, checked against your own skill, with how many of its fish you've caught. Click a zone to see its fish. These are Classic's numbers, as Forever's aren't published yet, and zones with no known level are judged from your own catches and getaways. Thanks to Lintence for the idea!" },
				{ "Levels in the zone filter.", "The book's zone menu now shows each zone's level too." },
			} },
		},
	},
	{
		version = "0.3.1",
		date = "2026年11月6日",
		sections = {
			{ "新增", {
				{ "钓鱼时压低其他声音。", "新增选项：装备鱼竿时降低或关闭音乐、环境音和对白，突出水花声。滑块可调节压低程度。换回武器后恢复为你自己的音量。感谢 paxcow55 提出此想法！" },
			} },
		},
	},
	{
		version = "0.3.0",
		date = "2026年11月5日",
		sections = {
			{ "新增", {
				{ "技能提升。", "会话标签显示本次获得的钓鱼技能，以及大约再钓多少次可升一点。低于区域等级时，技能条会估算大概还要多少次才能达标。" },
				{ "会话摘要。", "暂停钓鱼约 2 分钟后，聊天会汇总本次：渔获、每小时鱼数、商人售价、技能提升和图鉴新鱼。" },
				{ "最佳地点。", "区域标签会记录你在该区域的每个钓鱼点（湖泊、海岸或河流）。点击「地点」按每小时鱼数比较，悬停可查看该处渔获。" },
				{ "时段。", "每次钓获记录服务器小时，因此每条鱼的详情页会显示你是白天还是夜间钓到。夜鳞鲷鱼与阳鳞鲑鱼会注明经典中的上钩时段。" },
				{ "查找任意鱼类。", "图鉴支持区域筛选和名称搜索。选中区域后设为「显示：未钓到」，即可查看此处还缺什么。" },
				{ "荆棘谷钓鱼大赛。", "周日大赛倒计时（经典日程）、进行中的可口鱼计数、聊天提醒，以及凑齐 40 条时的提示。" },
				{ "自动拾取。", "若未开启自动拾取，插件会提示一次开启，方便渔获直接进包。" },
			} },
			{ "变更", {
				{ "拍卖行。", "拍卖行窗口上的「扫描鱼价」按钮已移除。请改用统计窗口按钮或 /onecast scan。" },
				{ "生涯标签。", "显示图鉴收集进度。" },
			} },
		},
	},
	{
		version = "0.2.1",
		date = "2026年11月5日",
		sections = {
			{ "适配正式上线", {
				{ "图鉴共 88 种渔获。", "对照 WoW Forever 上线版本核对：新增 12 种奖杯鱼、6 种浮肿鱼、新鱼 Whimsyfin、钓鱼大赛的可口鱼与稀有鱼，以及工匠任务鱼。" },
				{ "诚实标注来源。", "Forever 中尚未确认的区域会标为经典数据或玩家报告。无已知水域的鱼，会根据你自己的钓获补全地点。" },
				{ "地图完整显示。", "每条鱼详情页的区域地图现在显示整张地图，无论是否探索过，而不再是空白羊皮纸。" },
				{ "Riverglades。", "「无最低技能」漏洞仍未关闭。若在该处脱钩，插件会以实际脱钩为准，而不再盲信漏洞报告。" },
			} },
			{ "修复", {
				{ "换回武器。", "升级后或已存武器不在背包时不再卡住。鱼竿也不会再被放进草药袋等特殊背包。" },
				{ "加载中的区域。", "加载界面期间施放的钓鱼不再计入空白区域。" },
				{ "更新内容。", "版本列表在条目过多时可以滚动。" },
			} },
		},
	},
	{
		version = "0.2.0",
		date = "2026年10月23日",
		sections = {
			{ "新增", {
				{ "钓鱼图鉴。", "收录 WoW Forever 全部鱼类：61 种，含普通鱼、特殊渔获、奖杯鱼与浮肿鱼。已钓到的彩色显示并带数量；其余灰色待收集。" },
				{ "每条鱼的详情页。", "点击任意鱼打开专属页面：游戏自带描述、摘要、各角色钓获，以及首次钓到的时间与地点。" },
				{ "出没地点。", "列出所有可钓区域、各区域所需技能、你在该处钓到的数量，以及区域地图。一键打开完整地图。" },
				{ "用途。", "该鱼用于的烹饪、炼金与钓鱼配方，含 WoW Forever 新增配方。" },
				{ "跨角色共享。", "图鉴统计账号下全部角色，包括本更新之前的钓获。" },
				{ "新鱼提示。", "钓到账号上从未有过的鱼时，聊天会提示图鉴新鱼。" },
			} },
			{ "如何打开", {
				{ "多种入口。", "统计窗口的图鉴按钮、Shift+点击小地图按钮、选项中的打开图鉴、按键绑定，或 /onecast book。" },
			} },
		},
	},
	{
		version = "0.1.0",
		date = "2026年10月22日",
		sections = {
			{ "新增", {
				{ "一键钓鱼。", "绑定一个按键（或装备鱼竿后双击右键）：第一次施放，下一次收杆。每次施放与收杆仍是你自己的按键。" },
				{ "自动装备鱼竿。", "未装备鱼竿时，按键先从背包装备最好的鱼竿。暂停后、进入战斗时，或点剑形按钮，可换回武器。" },
				{ "会话统计。", "施放次数、钓获、成功率、每小时鱼数与全部渔获，施放时自动打开窗口。含会话、当前区域、生涯与最近渔获记录标签。" },
				{ "此区域是否合适？", "技能条显示钓鱼技能（含鱼饵加成）并对照区域等级，判断是否会脱钩。无数据的区域根据你自己的钓获与脱钩判断。" },
				{ "渔获价值。", "各标签显示商人与拍卖估价。打开拍卖行后可用 Auctionator 一键扫描渔获。" },
				{ "稀有渔获提醒。", "绿色及以上品质，或右键标记为想要的鱼，会闪现团队警告并播放音效。" },
				{ "Wowhead 链接。", "点击任意渔获可复制其 WoW Forever Wowhead 页面。Shift+点击可在聊天中链接。" },
				{ "听清水花。", "鱼线抛出后提高音效；音乐与环境音保持不变。" },
				{ "随心设置。", "插件选项、小地图按钮，以及可拖动、缩放与关闭的统计窗口。" },
			} },
		},
	},
}

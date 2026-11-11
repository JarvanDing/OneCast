-- OneCast's changelog, shown in the What's new window (WhatsNew.lua), newest first.
-- Each release: { version, date, sections = { { heading, { { lead, text }, ... } }, ... } }.
-- Add a new entry at the top for every release, with the same version as the TOC.

local _, ns = ...

ns.CHANGELOG = {
	{
		version = "0.7.5",
		date = "11 November 2026",
		sections = {
			{ "Fixed", {
				{ "The pole not going back on.", "If you cast from your action bar after OneCast put your pole on, OneCast could later decide the pole couldn't be equipped: after your weapons went back on, the key would put your other pole on, or none at all. 0.7.2 already stopped the worst of it, and now nothing is held over between sessions. Thanks to user_1u9o7vfe00qi4c4k47561 for the report!" },
			} },
			{ "Reported by user_ovzr5k4e4heovaq6", {
				{ "Raw Longjaw Mud Snapper in Dun Morogh.", "It can be caught at Iceflow Lake, so the collection now lists it there." },
				{ "Dun Morogh at 25 holds up.", "Fish got away below 25 Fishing skill, as OneCast expects there." },
			} },
			{ "Reported by Falconetti", {
				{ "Raw Longjaw Mud Snapper in Hillsbrad Foothills.", "Caught there often, so the collection now lists it." },
				{ "Raw Bristle Whisker Catfish in Undercity.", "It bites in the city's canals too, so the collection now lists it there." },
			} },
		},
	},
	{
		version = "0.7.4",
		date = "10 November 2026",
		sections = {
			{ "Reported by pysznyhanys", {
				{ "Raw Sagefish in Silverpine Forest.", "It can be caught at Lordamere Lake, so the collection now lists it there." },
				{ "Orgrimmar confirmed at 75.", "Fish got away below 75 Fishing skill, and not once in 178 catches at 75 or above." },
				{ "Thank you!", "This was OneCast's first data report." },
			} },
		},
	},
	{
		version = "0.7.3",
		date = "10 November 2026",
		sections = {
			{ "Fixed", {
				{ "An error at login.", "OneCast asked the game for an event it no longer has, which showed an error and stopped the camp buff tracking from starting. It now uses the event's current name. Thanks to meleegod for reporting it with the full error!" },
			} },
		},
	},
	{
		version = "0.7.2",
		date = "10 November 2026",
		sections = {
			{ "Fixed", {
				{ "Equipping the pole and weapons on a slow server.", "If the game took a moment longer than usual, OneCast could decide your pole couldn't be equipped and stop trying until a reload, and give up putting your weapons back. It now waits longer, keeps trying, and finishes a swap that lands late. Thanks to xDevastation1988x for the report!" },
				{ "A key stuck on reeling.", "If the game ever didn't say a cast had ended, after a loading screen or a disconnect, your key could stay on reeling in and never cast again until a reload. OneCast now checks, and gives it back." },
				{ "A second lure on a slow server.", "With Apply with the cast key on, a lure slow to show on your pole could be taken for none, and the next press would spend another. OneCast now waits for it." },
				{ "Item is locked.", "Putting your weapons back could ask for the same one twice at once, which the game answered with Item is locked. It now asks once." },
			} },
		},
	},
	{
		version = "0.7.1",
		date = "10 November 2026",
		sections = {
			{ "Fixed", {
				{ "CurseForge links.", "OneCast's CurseForge page has a new, shorter address. The data report's CurseForge link and What's new's link now go there." },
			} },
		},
	},
	{
		version = "0.7.0",
		date = "10 November 2026",
		sections = {
			{ "New", {
				{ "Camp tab.", "Forever's fishing crafts for its camps, in the collection book: the Fish Bowl, Fishing Rack and Fishing Hut, with the Fishing each needs, whether you've learned it, your reagents against what it takes, and what it does. /onecast camp opens it." },
				{ "Camp buffs.", "The stats window shows Uncommon or Rare Fishing from a Rack or Hut with its time left, and chat says when it wears off. What you catch while one is on is kept, to show what their extra rewards really are." },
				{ "Help fill in Forever's numbers.", "/onecast report gives your catches and getaways as text, with the skill each happened at, to paste in a comment or a GitHub issue. Nobody has published Forever's real zone levels yet: shared reports let OneCast replace Classic's with Forever's own. It holds fishing numbers only, no name or realm." },
				{ "Data to share.", "When your fishing shows something OneCast doesn't know yet, such as a zone with no known level, a level that looks wrong or a fish somewhere new, chat says so once, and the minimap button counts it until you copy your report. The stats window's new Report button shows a green dot, the book's Zones tab marks those zones as new data, and the Zones and Camp tabs have a Share your data button." },
			} },
			{ "Quality of life", {
				{ "A menu on the minimap button.", "Left-click it for every OneCast window in one place: the stats window, tackle box, collection, Camp tab, data report, What's new and options. Right-click and Shift-click still open the stats window and the collection." },
				{ "Spots on the map.", "Click a spot on the stats window's Zone tab to open the world map there, with a waypoint: where you fish from once you have, or else the spot's own place on the map, from the game's map data. City districts like Stormwind's canals aren't on it, so those learn their place as you fish them." },
				{ "Tooltips everywhere.", "Hover a recipe on a fish's page for the recipe itself, the fish's name for the fish, and a camp's reagents, campfires and buff for their own tooltips. Shift-click any of them to link it in chat." },
				{ "Maps from the book.", "Right-click a zone on the Zones tab or a fish's page for its world map, click the little map for the big one, and click a pool you've found for a waypoint to it." },
				{ "Windows stay where you put them.", "The collection book, What's new and the data report now open where you last dragged them, like the stats window and tackle box." },
				{ "Links in chat.", "Lures, Speckled Tastyfish and camp buffs in OneCast's chat messages are links you can hover." },
			} },
			{ "Fixed", {
				{ "Riverglades needs 225.", "The first level measured in Forever itself: fish got away below 175 on its coast, and none did at 225. It replaces the old note that Riverglades had no minimum skill. Thanks to the player who tested it with and without a lure!" },
				{ "Getaways.", "Fish getting away weren't being counted in Forever, which shows the message differently. OneCast now catches it however the game shows it, in any language. Thanks to a player whose fish got away in Riverglades while OneCast said none had!" },
				{ "Opening and closing the options.", "Opening OneCast's options from one of its windows no longer closes that window, or any other OneCast window. And options opened from OneCast (the minimap button, /onecast or a window's Options button) now just close, instead of leaving the game menu open. Opened from the game menu, they still go back to it." },
				{ "Dungeons.", "Wailing Caverns, which Forever calls The Wailing Caverns, now has its level. Every dungeon is recognised by the game's map, whatever its name." },
				{ "More places for common fish.", "Raw Bristle Whisker Catfish, Raw Longjaw Mud Snapper and Raw Brilliant Smallfish are caught in Loch Modan, and the Mud Snapper in Wailing Caverns, and Raw Rockscale Cod, Raw Spotted Yellowtail and Oily Blackmouth on Riverglades' coast, from players' reports." },
			} },
		},
	},
	{
		version = "0.6.1",
		date = "10 November 2026",
		sections = {
			{ "Fixed", {
				{ "Zone fishing levels.", "Winterspring, Silithus, Eastern Plaguelands, Burning Steppes and Deadwind Pass need 425 for no getaways, not 300. The capital cities need 75, not 25. Badlands, Blasted Lands and Searing Gorge are gone from the Zones tab: they have no water to fish." },
				{ "Fish found in the wrong places.", "Zulian Mudskunk only comes from Zul'Gurub, and Deviate Fish only from the Barrens and Wailing Caverns. Their pages listed zones they're never caught in." },
				{ "Zul'Gurub's pool.", "Muddy Churning Waters is now remembered on the book's maps, along with Strange Pool and Pure Water." },
				{ "Weapons that won't go back on.", "If the game refuses to re-equip a weapon, OneCast now says so and stops, instead of quietly swapping it back in the next time you change weapons yourself." },
				{ "Commands.", "/onecast theme and /onecast scale no longer react to other words that start the same way." },
			} },
			{ "New", {
				{ "Dungeons and lakes.", "Fishing levels for the Deadmines, Wailing Caverns, Blackfathom Deeps, Scarlet Monastery, Sunken Temple, Maraudon, Zul'Gurub, Stratholme and Scholomance. Waters with a level of their own, like Jademir Lake in Feralas, use it while you stand there, and a getaway there doesn't count against the rest of the zone." },
				{ "Three more catches.", "Steelscale Crushfish, Darkshore Grouper and Oil Covered Fish are in the collection, and the big Mightfish, Lobster and Yellowtail trophies now show where they're caught." },
				{ "\"Secret\" Bait.", "Forever's new lure is in the tackle box, at +25 like a Shiny Bauble." },
				{ "Zephras Isle.", "Listed on the Zones tab with Forever's other new zones." },
			} },
		},
	},
	{
		version = "0.6.0",
		date = "9 November 2026",
		sections = {
			{ "New", {
				{ "Themes.", "Pick the look of OneCast's windows in the options: Forever, the game's own style and still the default, Dark, Tidal, Abyss, Golden Hour, Marsh, Moonlit, the wood-panelled Fisherman's Lodge, or Class Colours to match the character you're playing. Every window changes the moment you pick one, or use /onecast theme." },
			} },
			{ "Changed", {
					{ "A friendlier options menu.", "Themes are now at the very top, with your cast key and a button for every window right below. Everything else moved to short pages under OneCast in the sidebar: Fishing, Lures, Sound, and Stats and alerts. Settings that depend on another one grey out while it's off. Nothing you've set has changed." },
			} },
		},
	},
	{
		version = "0.5.2",
		date = "8 November 2026",
		sections = {
			{ "Fixed", {
				{ "Searching the options.", "OneCast's buttons and key entry no longer appear in the game's settings search, which could raise an error. They're still on OneCast's own options page, and the key is still on the Keybindings page. Thanks to onkl for the report and the fix!" },
			} },
		},
	},
	{
		version = "0.5.1",
		date = "8 November 2026",
		sections = {
			{ "New", {
				{ "Mark your bobber.", "An option, off by default: while your line is out, the game's gear icon shows over your bobber, so you can tell your splash from other people's. Turn on Mark your bobber in the options. Thanks to insertnamehere255 for the idea!" },
			} },
			{ "Fixed", {
				{ "Zones in every language.", "Fishing levels, fish locations and the Fishing Extravaganza now work on non-English clients, using the game's own zone names." },
				{ "Lures and reeling in.", "Letting go of the key after reeling in could count as a failed lure, or recast if your keys act on release." },
				{ "Weapons after a fight.", "With Re-equip weapons when combat starts off, your weapons now still go back after your usual break." },
				{ "Your usual pole.", "The cast key keeps picking the pole you used last, even after you level up." },
				{ "Extravaganza reminders off.", "Turning them off now also stops the raid warning at 40 Tastyfish." },
				{ "Lighter stats window.", "The open Session tab no longer re-prices your whole catch every second." },
				{ "Closing the options.", "OneCast windows now stay open when you close the options." },
				{ "A fight with your line out.", "If your line is still out when combat ends, your key reels it in again instead of recasting." },
				{ "Poles you can't use.", "If the game won't equip a pole, the cast key moves on to your next one." },
				{ "Fonts on fish pages.", "Moving between fish pages could put a heading's font on ordinary text, and the other way round." },
			} },
		},
	},
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
		date = "6 November 2026",
		sections = {
			{ "New", {
				{ "Quiet other sounds while fishing.", "An option to turn music, ambience and dialog down or off while your pole is equipped, so the splash stands out. A slider sets how quiet. Everything goes back to your own levels when your weapons go back on. Thanks to paxcow55 for the idea!" },
			} },
		},
	},
	{
		version = "0.3.0",
		date = "5 November 2026",
		sections = {
			{ "New", {
				{ "Skill-ups.", "The Session tab shows the Fishing skill you've gained and about how many catches until the next point. Below a zone's level, the skill bar says roughly how many catches it'll take to get there." },
				{ "Session summary.", "Take a 2-minute break and chat sums up the session: catches, fish per hour, vendor value, skill gained and new fish for your collection." },
				{ "Best spots.", "The Zone tab now tracks every spot you fish in a zone, a lake, a coast or a river. Click Spots to compare them, best fish per hour first, and hover one to see what bites there." },
				{ "Time of day.", "Every catch notes the realm hour, so each fish's page says whether you caught it by day or at night. Nightfin Snapper and Sunscale Salmon say when they bite in Classic." },
				{ "Find any fish.", "The collection book has a zone filter and a search box. Pick your zone, then Showing: missing, to see what's left to catch here." },
				{ "Fishing Extravaganza.", "A countdown to Stranglethorn's Sunday contest (Classic's schedule), a Tastyfish counter while it runs, chat reminders, and an alert the moment you hold 40." },
				{ "Auto loot.", "If auto loot is off, OneCast offers once to turn it on, so catches go straight to your bags." },
			} },
			{ "Changed", {
				{ "Auction house.", "The Scan fish prices button on the auction house window is gone. Scan from the stats window's button or /onecast scan instead." },
				{ "Lifetime tab.", "Shows how much of the collection you've caught." },
			} },
		},
	},
	{
		version = "0.2.1",
		date = "5 November 2026",
		sections = {
			{ "Updated for launch", {
				{ "88 catches in the collection.", "Checked against WoW Forever's launch build: 12 more trophy fish, 6 more bloated fish, the new Whimsyfin, the Fishing Extravaganza's Tastyfish and rare fish, and the Artisan quest fish." },
				{ "Honest about where fish come from.", "Zones not yet seen in Forever are marked as Classic data or player reports. Fish with no known waters fill in from your own catches." },
				{ "Maps fully revealed.", "The zone map on each fish's page now shows the whole zone, explored or not, instead of blank parchment." },
				{ "Riverglades.", "Its \"no minimum skill\" bug is still open. If a fish gets away there, OneCast now trusts that over the bug report." },
			} },
			{ "Fixed", {
				{ "Putting weapons back.", "No longer gets stuck after you level up, or when a saved weapon has left your bags. The pole is never put into a herb or other special bag." },
				{ "Zone while loading.", "Casts made during a loading screen no longer count under a blank zone." },
				{ "What's new.", "The version list scrolls once there are more versions than fit." },
			} },
		},
	},
	{
		version = "0.2.0",
		date = "23 October 2026",
		sections = {
			{ "New", {
				{ "The fishing collection.", "A book of every fish in WoW Forever: 61 catches across fish, special catches, trophy fish and bloated fish. Caught ones show in colour with your count; the rest wait greyed out." },
				{ "A page for every fish.", "Click any fish for its own page: the game's own description, a summary, your catches on every character, and when and where you first caught it." },
				{ "Where to catch it.", "Every zone it's caught in, the skill each needs, how many you've caught there, and a map of the zone. Open the full map in one click." },
				{ "What it's used in.", "The cooking, alchemy and fishing recipes each fish goes into, including WoW Forever's new ones." },
				{ "Shared across characters.", "The collection counts every character on your account, including everything you caught before this update." },
				{ "New fish announced.", "Catch a fish none of your characters has caught before and chat tells you it's new for your collection." },
			} },
			{ "How to open it", {
				{ "Anywhere you like.", "The book button in the stats window, Shift-click on the minimap button, the Open collection button in options, a key binding, or /onecast book." },
			} },
		},
	},
	{
		version = "0.1.0",
		date = "22 October 2026",
		sections = {
			{ "New", {
				{ "One-button fishing.", "Bind one key (or double right-click with a pole on): the first press casts, the next reels in your bobber. Every cast and every reel is still your own press." },
				{ "Your pole, equipped for you.", "With no pole on, the key equips the best one in your bags. Your weapons go back after a break, when combat starts, or with the sword button." },
				{ "Session stats.", "Casts, catches, catch rate, fish per hour and everything you caught, in a window that opens as you cast. Tabs for the session, the zone you're in, lifetime, and a log of recent catches." },
				{ "Is this zone right for you?", "A skill bar shows your Fishing skill, lure bonus included, against the zone's fishing level, so you know whether fish will get away. Zones without data are judged from your own catches." },
				{ "What your catch is worth.", "Vendor and auction value on every tab. Open the auction house and scan your catch with Auctionator in one click." },
				{ "Rare catch alerts.", "A raid-warning flash and sound for anything green or better, or any fish you mark as wanted with a right-click." },
				{ "Wowhead links.", "Click any caught item for its WoW Forever page on Wowhead, ready to copy. Shift-click links it in chat." },
				{ "Hear the splash.", "Sound effects turn up while your line is out; music and ambience are left alone." },
				{ "Make it yours.", "Options in the AddOns settings, a minimap button, and a stats window you can drag, scale and close." },
			} },
		},
	},
}

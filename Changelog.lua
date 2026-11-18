-- OneCast's changelog, shown in the What's new window (WhatsNew.lua), newest first.
-- Each release: { version, date, sections = { { heading, { { lead, text }, ... } }, ... } }.
-- Add a new entry at the top for every release, with the same version as the TOC.

local _, ns = ...

ns.CHANGELOG = {
	{
		version = "1.0.4",
		date = "18 November 2026",
		sections = {
			{ "Fixed", {
				{ "The world map card.", "On a continent or the whole world, with no zone under the mouse, the card from 1.0.2 could raise a Lua error over and over. It now just stays hidden until there's a zone to show." },
			} },
		},
	},
	{
		version = "1.0.3",
		date = "18 November 2026",
		sections = {
			{ "Fixed", {
				{ "No more chat on every cast.", "When something else changes a volume while you fish (often another addon that also turns up the splash), OneCast leaves it as it is and now says so once a login, not on every cast. Thanks to duerrewildstar for reporting it!" },
			} },
		},
	},
	{
		version = "1.0.2",
		date = "17 November 2026",
		sections = {
			{ "Reported by brisi73", {
				{ "The world map card.", "Fishing on the world map is now a small card you can drag anywhere on the map and size with Ctrl + mouse wheel over it, so it never covers your coordinates. It starts in the middle of the map's foot, stays where you put it at any map size, and right-click puts it back." },
			} },
		},
	},
	{
		version = "1.0.1",
		date = "17 November 2026",
		sections = {
			{ "New", {
				{ "Open stats when your pole goes on.", "A new setting under Stats and alerts: the stats window (or the mini bar) opens every time you equip a fishing pole, even if you closed it earlier. Off by default." },
				{ "For Fishing 300.", "At 300, the highest there is, the Session tab's skill rows make way for two that still matter: your Fishing with your gear and lure, and whether it's enough for these waters (some need 425), and what none of your characters has caught here yet. Click either for the gear guide or the zone's fish." },
				{ "Choose your auction prices.", "Auction prices from is back, under Fishing > Loot and bags: with more than one price addon installed, pick Auctionator, TSM or Naowh Forever, or leave it on Automatic." },
			} },
			{ "Changed", {
				{ "Pool tooltips, corrected.", "Each pool's chances now add up to a whole catch, Stranglekelp included. Most pools come in kinds with their own trunk and rum, which the tooltip used to list all at once: it now says which trunks and rums a pool can give, and once one comes up where you fish, names that one there. Item names are in their quality's colour, and Patch of Elemental Water has a tooltip too." },
				{ "Auction worth, as you'd really sell it.", "Auction value and gold per hour no longer leave out what has no auction price: grey junk, bound items, anything not scanned yet, and anything worth more to a vendor all count at the vendor's price. The Spots tab now counts what was inside the trunks and crates you fished up in each zone, as the Session tab does." },
				{ "New waters, confirmed fish.", "Excavation Site: Wetlands is on the Zones tab, its level still to learn. Keefer's Angelfish, Dezian Queenfish and Speckled Tastyfish are confirmed in Forever's Fishing Extravaganza." },
			} },
			{ "Fixed", {
				{ "Rums aren't containers.", "Drinking a Rumsey Rum could file whatever you looted next under it, as if it had been opened. Only things that open count now, and anything wrongly filed under a rum, bottle or ring is taken back out." },
				{ "At 300.", "With Artisan's 300, the highest Fishing goes in Forever, the stats no longer say to train to go higher. Where a zone needs more than 300, it says a lure or fishing gear makes up the rest, instead of counting catches that can't get you there. And at your cap, the Fishing bar fills right to the end." },
				{ "Dalaran.", "The game sometimes names City of Dalaran just Dalaran, and those catches had no level. Both count as City of Dalaran now, and catches kept under Dalaran join it." },
			} },
			{ "Reported by Cyndaria", {
				{ "City of Dalaran needs 225.", "3 of 19 got away at skill 200-224, and none in 42 catches from 225 up." },
				{ "Casts that miss the water.", "A cast that doesn't land in fishable water no longer counts as a cast, and isn't reported as an unknown message." },
			} },
			{ "Reported by OhhMyGeek", {
				{ "Deviate Scale.", "Fished up in Wailing Caverns, where Classic never gave it: now a special catch in the collection. Stranglethorn Vale's 225 is confirmed too: fish got away less and less up to it, and none in 309 catches from 225 up." },
			} },
			{ "Reported by mooshroomdragon", {
				{ "Deviate Scale in The Barrens.", "Fished up there too, so it's listed in both. Stormwind City's 75 is confirmed again: fish got away up to 74, and none in 70 catches from 75 up." },
			} },
			{ "Reported by jfenn30000", {
				{ "Quest items left out.", "Fishing up Gaffer Jacks for Darkshore's quest no longer shows as something new for your data report." },
			} },
			{ "Reported by more of you", {
				{ "Thank you.", "Tide, SivvyGG, BreadGar, clank0819, user_ylmtyqo58jc23fsc, user_3esotn7e32yjuggw67334 and user_grzw4jp0w7586q7x sent reports that confirmed zone levels and where each rank is learned. Every report helps." },
			} },
		},
	},
	{
		version = "1.0.0",
		date = "16 November 2026",
		sections = {
			{ "New", {
				{ "Choose your cast key in OneCast.", "A welcome window at your first login asks for your key: click, press the key you want, done. It's also the first row of Options > Fishing, and /onecast setup brings the window back." },
				{ "Controller support.", "With your pole on, A / Cross casts and reels; hold both triggers to put the pole on first, and Y / Triangle opens the OneCast window. In Forever's gamepad interface, OneCast's windows join the game's navigation. Your controller's own button icons show throughout, at a size you choose, and alerts can rumble. All of it under Options > Controller; /onecast pad shows what OneCast sees of your controller." },
				{ "Done fishing.", "A button on the stats window and the mini bar, a key binding and /onecast done: your weapons and gear go back on and the session is summed up, without resetting it. Thanks to DashiDoshi for the idea!" },
				{ "Your shirt in the wardrobe.", "The fishing outfit has a Shirt slot. Thanks to clank0819 for the idea!" },
				{ "What was inside.", "Open a trunk, crate or clam you fished up and what it held counts as part of your catch: under it on the Session tab as a tree, in what the session's worth, and in your data report." },
				{ "Each catch's worth.", "The Session tab shows what each catch is worth, how many got away, your fish per hour against your best, and what's new for your collection." },
				{ "Fast loot.", "With auto loot on, your whole catch is taken the moment the loot window opens, quicker than the game's own auto loot. Only fishing loot and what's inside the trunks and crates you fish up. Off by default, under Options > Fishing." },
				{ "Search.", "One search across catches, zones, pools, recipes, gear, ranks and settings, from the collection's search box or /onecast search." },
				{ "The Gear guide.", "The wardrobe's second tab: every fishing pole and piece of fishing gear with its bonus and where it comes from. Click a card for a waypoint (the quest giver, the rare that drops it, Booty Bay's prize vendors, or the nearest fishing vendor on your side), right-click for Wowhead. Gear only the other faction can get is left out." },
				{ "Where to fish, as a ladder.", "The Zones tab is rebuilt: each Fishing level a rung, your skill marked on the ladder, how many of each zone's fish you've caught, and what's still to catch here." },
				{ "Recipe sellers.", "A fish's recipes say who sells each one to you, with a waypoint to the nearest." },
				{ "Camp, rebuilt.", "The Camp tab shows each craft's reagents against what you have, where its blueprint drops with a waypoint to the dungeon, the campfires and where the Journeyman and Expert blueprints come from, and your camp buff right now." },
				{ "The Extravaganza's prizes.", "Forever's Fishing Extravaganza: the first 50 winners get the Arcanite Fishing Pole and a coin for one of Jang's prizes. Each rare contest fish's page says what Fishbot 5000 trades it for, and the High Test Eternium Fishing Line is in the Gear guide." },
				{ "Accessibility.", "A new Options page: larger text in every window, bigger controller buttons, the ticks on what you've caught turned off, and reduced motion." },
				{ "Your windows, your call.", "Two settings under Stats and alerts: whether Done fishing closes the stats window, and whether Escape closes OneCast's windows. Both off: OneCast stays open until you close it." },
			} },
			{ "Changed", {
				{ "A look that's Forever's own.", "Buttons, scrollbars, lists, text and spacing follow the game's own interface throughout. Themes are gone, and so are the bobber marker's styles and the custom beam colour: the beam keeps its colour choices." },
				{ "Your session lasts until you reset it.", "A break, a /reload or putting your weapons back on no longer starts a new session. Only the Reset button does." },
				{ "Escape is the game's.", "Escape no longer closes OneCast's windows along with your bags or map: it's left to the game, unless you turn on Escape closes OneCast windows." },
				{ "One wanted list.", "Wanted fish and catch goals are one list: right-click a catch to want it, or want a number of them." },
				{ "The data report, redesigned.", "Two columns: what you've found, each explained, and the report ready to share. It no longer says anything in chat: a badge on its tab shows when there's something new." },
				{ "Auction prices.", "Prices come from whichever price addon you have, with no setting to choose it." },
				{ "Pools on the map.", "Remembered pools are drawn as the game's fishing-hole icon, grouped where they're close together." },
				{ "Data checked against Forever.", "Every fish, recipe, gear piece, lure and camp craft checked against Forever's newest game data and Wowhead's Forever database. Outland's pools, which Forever doesn't have, are gone from the pool tooltips." },
				{ "Removed.", "The Session tab's Catch next row, and the fish you hadn't caught yet in Caught this session: it lists only what you caught." },
			} },
			{ "Fixed", {
				{ "Closing in combat.", "A window's X works in combat, without an Interface action failed error." },
				{ "Your sound comes back.", "Your music, ambience and dialog volumes come back when your weapons go back on." },
				{ "The game's options.", "OneCast's page in the game's options no longer causes a blocked-action error elsewhere in them, such as Social. Thanks to BreadGar for reporting it!" },
				{ "Larger text.", "Pages that ran out of room with larger text now fit." },
				{ "The journey's zones.", "A rank's Fish in line no longer runs off the end of its card: it lists as many zones as fit, then how many more. Hover the card for all of them." },
				{ "The mini bar.", "Closed by hand, it comes back after a break from fishing, as the stats window does, even if your pole never came off. Turning mini mode off closes a bar that's open." },
				{ "The wardrobe's total.", "When you're already wearing your fishing outfit, it shows your Fishing and what the outfit adds, not an arrow from a number to the same number." },
			} },
			{ "Reported by Cyndaria", {
				{ "Desolace and Stonetalon confirmed.", "Desolace needs 225 in Forever: fish got away less and less as skill rose towards it, and none in 231 catches from 225 up. Stonetalon Mountains needs 150: 2 of 17 got away just under it." },
			} },
		},
	},
	{
		version = "0.9.1a",
		date = "14 November 2026",
		sections = {
			{ "New", {
				{ "Auto loot while fishing.", "Auto loot turns on when you equip your fishing pole and back off when you take it off. It's off by default: turn it on under Fishing in the options. Thanks to JesterClown for the idea!" },
			} },
		},
	},
	{
		version = "0.9.0",
		date = "13 November 2026",
		sections = {
			{ "New", {
				{ "A light beam on your bobber.", "Turn on Mark your bobber and your bobber glows, with a column of light rising from it while the line is out and ripples on the water, so it stands out on busy water. It takes your theme's colour, or pick your own under Beam colour, including any colour you like with Custom (or /onecast beam). Marker chooses the beam, the glow alone, the game's gear icon, or the beam and the icon." },
				{ "Themes with a sense of place.", "Each theme now brings its own scenery along the foot of every window, from Frostfire Ridge's snow to Blackrock Mountain, with particles drifting over it: snow on Winterspring, bubbles on Tidal and Murloc, embers on Ember, fireflies on Marsh and Moonlit, gold glints on Booty Bay. Each has an emblem in the window's title bar and its own water in the Fishing bar: molten metal on Ember, Alchemy's bubbling green on Deviate. Theme effects in the options keeps them still, or turns them off." },
				{ "Mini mode.", "A small window in place of the stats while you fish: your skill, how the zone suits it in plain words, catches and fish per hour, your lure and your goals. It follows your theme. Turn it on under Stats window, or /onecast mini." },
				{ "Skill-ups and what to catch next.", "When your Fishing goes up, +1 Fishing rises and fades on screen, over the mini bar if it's open. The Session tab has a Catch next line: the likeliest fish you're missing in a zone your skill already covers, here if there is one. Hover it for every one, click it to see them in the collection." },
				{ "Fishing Extravaganza help.", "While the contest runs, the mini bar shows your Tastyfish and the time left, and holding 40 sets a waypoint to Riggle Bassbait in Booty Bay. /onecast riggle sets it any time." },
				{ "Hide the tabs you don't use.", "Right-click a side tab to hide it; right-click any tab to bring them back. Options always stays." },
				{ "Catch goals.", "Right-click any catch and set a goal, like 20 Stonescale Eels. Progress shows on its row and in mini mode, with a note halfway and an alert when you get there." },
				{ "What's in a pool.", "Hover a fishing pool and its tooltip lists what it gives, with Classic's odds, and marks what you haven't caught yet." },
				{ "A fisherman's journey.", "A new page for the four Fishing ranks, Apprentice to Artisan: where you stand, how far to your cap in catches, and for each rank how and where to learn it, what it needs, and where to fish while you're at it. Expert's book from Old Man Heming in Booty Bay and Nat Pagle's Artisan quest each have a map waypoint, and Nat's four fish are ticked off as you catch them. Its Gear view lists every fishing pole and piece of fishing gear, from the plain Fishing Pole to the Arcanite Fishing Pole and Forever's Master Angler's Fishing Hat: its Fishing bonus, whether you have it, and where it comes from. /onecast journey opens it." },
				{ "A fishing wardrobe.", "A new page, laid out like the character sheet with you in the middle wearing it, to choose what you fish in: for each slot, the best Fishing bonus in your bags, an item you pick, or what you're wearing, and which pole. It goes on whenever the cast key puts your pole on, or with Wear it now, and comes off with your weapons. /onecast wardrobe opens it." },
				{ "Session history.", "All-time records has a Sessions list: each past session's date, zone, catches and fish per hour, with its time, gold, skill gained and best catch on hover." },
				{ "In reach, on the map and at the vendor.", "Showing: in reach in the collection lists the fish you're missing in zones your skill already covers. The world map shows a zone's fishing level, how your skill stands and your fish caught there, and follows the zone under the mouse on a continent. At a vendor, one click sells the grey junk you fished up and nothing else, or turn on selling it automatically." },
				{ "A new Options page.", "One category at a time, chosen down the left, with each setting's full description, its value and its chat command on the right as you hover it. No more hunting for tooltips." },
				{ "Naowh Forever's auction prices.", "Auction value and gold per hour now work with Naowh Forever's prices too, from its own scans and the prices it comes with, alongside Auctionator and TSM. The auction tooltips say which addon the prices come from, and with more than one installed, Auction prices from in the options picks which to use. Thanks to Zycko for asking!" },
				{ "More treasure.", "The Mithril Bound, Iron Bound and Watertight Trunks from Floating Wreckage join the Treasure tab, and the Rockhide Strongfish joins the trophies." },
			} },
			{ "Changed", {
				{ "Switch off what you don't use.", "Every feature that shows or says something has its own setting: item tooltips, pool tooltips and the world map strip separately (General, under Tooltips and map), the green dots on the tabs, the rare-catch sound, catch goal alerts, the new-for-your-collection line, and fishing junk at vendors (a button, selling automatically, or neither)." },
				{ "Plainer words.", "The zone's status says what it means everywhere: No fish get away instead of Ready, 12 skill short, None got away yet, Watching for getaways." },
				{ "A data report worth sharing.", "It flags anything you fish up that the collection doesn't have (not just fish), the first Forever catch of something OneCast only knew from Classic, where a Blueprint drops, and for the Fisherman's journey: where you learn a Fishing rank, Find Fish or Bait and Tackle (the trainer or quest), and fishing gear it doesn't list, with where it came from. Nothing to share means no report to copy, and a page that says what to look out for." },
				{ "In every language.", "On German, French, Spanish, Russian, Korean and Chinese clients, pools are now recognised by the names you see on the water, for their tooltips and marks, and shown by those names wherever OneCast says where a catch's odds are best. The fishing outfit reads the Fishing bonus in your client's language, and the data report knows a fishing message in it. Zones, sub-zones and dungeons already followed your client's names." },
				{ "An easier What's new.", "Each version's notes are laid out to read at a glance: every section in its own colour, each change's headline on its own line with the details under it, and the version you have marked Installed in the list." },
			} },
			{ "Fixed", {
				{ "Remembering pools.", "Moving the mouse from the water straight onto a pool often went unnoticed, so its spot wasn't marked on the map. OneCast now sees every pool's tooltip as the game fills it." },
				{ "The item menu.", "Right-clicking a catch opened a see-through menu with the list showing through it. It's solid now, and as wide as its longest line." },
				{ "Snappier tooltips and collection.", "A catch's rarity is worked out once instead of on every tooltip and redraw." },
			} },
			{ "Reported by DevanHyrax", {
				{ "The Fishing Hut's Blueprint.", "Reported to drop from Jammal'an the Prophet in the Sunken Temple. The Camp tab says so, as not yet confirmed, and the data report now notes where any Blueprint drops." },
			} },
			{ "Reported by Roezz", {
				{ "The Mithril Bound Trunk.", "Fished up in Tanaris, it wasn't in the collection. That led to a check of everything Classic's fishing can give, which found three more." },
			} },
			{ "Reported by user_hzctcyub5il0ubj3", {
				{ "Zephras Isle needs 25.", "Ten catches at skill 0-24 and none got away, with the starting zones' fish." },
			} },
			{ "Reported by user_wwbl1xmh9xl6rbb7", {
				{ "City of Dalaran.", "Fished in Forever, it now has a place on the Zones tab while its level is worked out." },
			} },
		},
	},
	{
		version = "0.8.2",
		date = "13 November 2026",
		sections = {
			{ "New", {
				{ "Treasure in the collection.", "A new Treasure tab for what you fish up besides fish: The 1 Ring from the city canals, the Tightly Sealed Trunk, the Rumsey Rums (Light, Dark and Black Label), Message in a Bottle, the Broken Wine Bottle, and every chest and crate, from the Battered Chest to the Reinforced Locked Chest. Tangy Clam Meat joins the special catches. Each has its own page with where it's found, and treasure you've already caught counts. Thanks to DevanHyrax for the idea!" },
				{ "A roomier page for each catch.", "Every zone it's found in now shows, in two columns, with your catches there and the Fishing each needs. A fish found almost everywhere has a +N more that opens the rest. The map is bigger, filling the page in its own shape, and the recipes moved across to the left page." },
				{ "Easier to use all round.", "Right-click any catch, on the stats pages or in the collection, for one menu with everything you can do with it: open it in the collection, where it bites best, mark it as wanted, its Wowhead page or a chat link. A plain click opens it in the collection. The stats page's lists scroll with the mouse wheel instead of stopping at \"and N more\". Rare catches wear a gem in the collection, with a Showing: rare filter. Every character shows under Your catches, everything caught with a camp buff shows on the Camp tab, the data report gives its text more room when there's nothing new, and the tackle box shows fish per hour as tiles, with what a lure adds." },
				{ "Wowhead links all through the collection.", "Right-click any fish or treasure in the book, or anything you can hover on its pages and the Camp tab (reagents, recipes, campfires), for its WoW Forever page on Wowhead, ready to copy. Each page also has a Wowhead button, and Shift-click links a catch in chat." },
				{ "How rare is it?", "Every catch now has a rarity, from Common to Very rare, with its odds per catch and where they're best: The 1 Ring is about 1 in 2,000 in the city canals, the 103 Pound Mightfish 1 in 10,000. It shows on each page, with each zone's own odds when you hover it, and how often your own character has caught it. These are Classic's odds from its loot tables: Forever's aren't published." },
				{ "Rarity and who caught it, on item tooltips.", "Anything in the collection now says on its tooltip how rare it is and which of your characters caught it, wherever you see it: your bags, chat links, the auction house. Turn it off under General in the options." },
			} },
			{ "Fixed", {
				{ "Ready for the game's newer APIs.", "Lure timers, learned camp recipes, rare-catch alerts and chat links now use the game's current functions, so they keep working for players who turn off the game's old-API fallbacks, and after Blizzard removes them." },
				{ "A fairer \"level may be lower\" finding.", "Catches just under a zone's level no longer count as a sign the level is lower: fish rarely get away that close to it either way. The data report now flags a zone only when getaways were to be expected." },
			} },
			{ "Reported by user_6zyawui5bf5c0btl", {
				{ "Stormwind City confirmed at 75.", "A third of fish got away at skill 25-49, as a level of 75 would have it, and none in 22 catches from 50." },
			} },
		},
	},
	{
		version = "0.8.1",
		date = "12 November 2026",
		sections = {
			{ "New", {
				{ "More places to catch each fish.", "Wowhead's WoW Forever pages now include Forever's own catches, so 36 fish in the collection gained zones. Among them are Forever's own Zephras Isle, for Raw Brilliant Smallfish and the 10, 12 and 15 Pound Mud Snappers, and Riverglades, for Stonescale Eel, Firefin Snapper and Raw Greater Sagefish. The Session tab's \"not caught yet\" list and the book's zone pages follow." },
			} },
			{ "Fixed", {
				{ "Older catches in the data report.", "A zone fished before 0.7.0, when catches weren't yet recorded by skill, now shows its catches and getaways in the report instead of nothing." },
				{ "Fewer stray messages in the data report.", "\"Target not in line of sight\" is no longer kept as a fishing message." },
				{ "Resizing the window.", "Closing the window while dragging its corner now ends the resize there, instead of carrying on." },
			} },
			{ "Reported by bertas88", {
				{ "The Barrens needs 100.", "Fish got away at skill 75-99 though Classic's level is 75, so OneCast now lists Forever's own." },
			} },
			{ "Reported by user_h2k2opfztmgqkcf2", {
				{ "The Barrens confirmed at 100.", "Fish got away at 75-99 here too, and not once in 33 catches from 100." },
			} },
		},
	},
	{
		version = "0.8.0",
		date = "11 November 2026",
		sections = {
			{ "New", {
				{ "One window for everything.", "The stats window, tackle box, collection, Camp, data report, What's new and options now open as one window, with side tabs down its right edge to move between them. Every page is the same height and follows the Window scale setting, it opens where you last left it, and dragging any page moves the whole window. The tabs can go on the left instead, in the options." },
				{ "A new stats window.", "Three tabs instead of four. Session has this session with fish, vendor gold and auction gold per hour, your skill's progress with time to the next point and your rank's cap, and each fish's share of the catch, then the zone's fish you haven't caught yet. Spots shows whether this zone is worth it, with its spots best first. Pick a fish, or Ctrl-click one anywhere, to see where it bites best. All-time records keeps your personal bests and notable catches." },
				{ "Forever's own Fishing bar.", "The stats window's skill bar is now the professions window's own, its water flowing, with a status strip under it: the zone, the Fishing it needs and whether you're ready, at a glance. Hover it for the details." },
				{ "A clearer data report.", "The report window is smaller, in three parts: what you've found, three steps to share it with the button and links right in them, and the text itself. The text keeps to what OneCast can learn from: what's new, the evidence for zone levels, and camp buffs. Zones that only agree with OneCast's level, cast totals and every fish caught are gone, and a known fish caught in one more zone no longer counts as something new." },
				{ "A window that keeps up.", "Green dots on the side tabs when there's something to share or a version to read. The stats close themselves when your weapons go back on, if they opened when you cast, and can fade while you fish. Lock the window so it can't be moved by accident, and a new key binding opens it on the page you last used. A /reload brings back the page you had open, and resetting a session asks first." },
				{ "Five new themes.", "Booty Bay, in sea-worn verdigris and sand. Murloc, in bright aqua and an orange fin. Winterspring, frosted silver-blue. Deviate, purple with a toxic green glow. Ember, charcoal lit by Un'Goro's hot springs. Pick one under Options, or /onecast theme." },
				{ "Every option in the window.", "The Options tab has every OneCast setting, in two columns as wide as the collection and in the same order as the game's options, so you don't need to leave the window. Settings that belong to another are indented, and greyed out while it's off. Only your cast key is set in the game's options, one click away under Key bindings." },
			} },
		},
	},
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

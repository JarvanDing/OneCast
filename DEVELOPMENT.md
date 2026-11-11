# Developing OneCast

The player-facing description is in [README.md](README.md), the same text as the CurseForge page.

## How it works

Forever runs the modern (Midnight-era) addon API but `loadstring_untainted` is missing, so SecureHandler snippets don't work. OneCast avoids them:

1. `OneCastButton` is a `SecureActionButtonTemplate` button with `type=spell`, `spell=<Fishing>` (name resolved from spell ID 7620, falling back to 131474).
2. On `UNIT_SPELLCAST_CHANNEL_START` for Fishing, the key bound to the button is overridden to `INTERACTTARGET`, and `SoftTargetInteract=3`, `SoftTargetInteractArc=2` and `SoftTargetInteractRange=30` are set so the bobber is the soft-interact target. With "Mark your bobber" on (off by default), `SoftTargetIconGameObject` and `SoftTargetIconInteract` are set too, for the game's gear icon over the bobber. Optionally, SFX volume is raised to full for the cast.
3. On `UNIT_SPELLCAST_CHANNEL_STOP` the override is cleared, and each CVar is restored only if it still holds OneCast's value.
4. `PLAYER_REGEN_DISABLED` drops every override before combat lockdown; `PLAYER_LOGOUT` restores CVars so they're never saved.
5. With "Quiet other sounds" on, `Sound_MusicVolume`, `Sound_AmbienceVolume` and `Sound_DialogVolume` are turned down to `quietLevel` percent of their own value while a pole is equipped (checked on `PLAYER_EQUIPMENT_CHANGED`). They're a separate lease group from the per-cast CVars, so the line coming in or combat starting doesn't give them back; the pole coming off does.

Each cast and reel is still one hardware press; nothing is automated.

### Files

| File | What it holds |
|---|---|
| `Camp.lua` | Forever's camp fishing crafts, the Uncommon and Rare Fishing buffs, and catches made under them |
| `Report.lua` | `/onecast report`: what's new to OneCast and the evidence for zone levels, as copyable text, and the report window |
| `Themes.lua` | The window themes: a table of colours, and tinting what each window registers |
| `OneCast.lua` | Cast button, reel key override, CVar leases, the options (described once in `OPTIONS`, `CHOICES`, `OPTION_MAIN` and `OPTION_PAGES` for both the game's panel and the window's Options tab), minimap button, slash commands |
| `Gear.lua` | Equipping the pole from the bags and putting weapons back |
| `Lure.lua` | Lure data, the character's choice, whether one is on the pole, and the presses that apply it |
| `TackleBox.lua` | The tackle box button (secure, hidden in combat) and its settings window, built from the stats window's parts (`ns.UI`) |
| `Pools.lua` | Remembering fishing pools from their tooltips, for the book's maps |
| `Stats.lua` | Session, zone and lifetime stats, personal bests and notable catches, the stats window (Session, Spots and All-time records), and the parts every window is built from (`ns.UI`) |
| `Prices.lua` | Handing the catch to Auctionator's search |
| `ZoneLevels.lua` | Zone fishing levels (Classic Era data) and notes on Forever zones |
| `ZoneNames.lua` | Area IDs for every zone name, translating the zone tables on non-English clients |
| `FishData.lua` | Every fish in the collection: category, zones (most common first) and recipes |
| `Collection.lua` | Account-wide record of which characters caught each fish, synced from each character's stats |
| `Extravaganza.lua` | The Stranglethorn Fishing Extravaganza: schedule (Classic's), Tastyfish counter and reminders |
| `MapOverlays.lua` | Every explored-area overlay of each zone map, so the book's maps show fully revealed (generated from game data) |
| `Book.lua` | The collection book window: fish grid, each fish's page with zones, map and recipes, and the Zones view of every zone's level |
| `Changelog.lua` | Release notes, shown in the What's new window and used for releases |
| `WhatsNew.lua` | The What's new window and the login chat line |
| `Hub.lua` | One window for everything: the side tabs, each page in the same place at the window's scale, the grip, the lock, the Options tab and reopening after a `/reload` |
| `Media/*.tga` | Button glyphs: white with a dark outline, tinted gold in game |

### Details worth knowing

- **Auto-equip pole:** with no pole equipped, the cast key equips the best pole in the bags (the one used last, else highest item level) from the button's `PreClick`, and that press doesn't cast. Weapons are saved per character and put back after the idle delay (60 s by default; 0 = never), when combat starts (anything blocked in combat finishes when it ends), or on demand. Equipping a different weapon by hand forgets the saved ones. Double right-click needs the pole equipped, so a stray double-click never swaps gear.
- **Lures:** PreClick runs on both key-down and key-up and which one fires depends on `ActionButtonUseKeyDown` and the input, so a press only arms the macro (`/use item:<id>`, `/use 16`) and the lure's own spell events (`UNIT_SPELLCAST_*`, IDs in `Lure.lua`) track what happened. Lures have a 5-second cast, and the cast key waits it out rather than interrupting. Two failed tries in a row make the cast key just cast for a minute, so a lure problem can never stop fishing. Until `GetWeaponEnchantInfo` has reported a lure, `Lure.Left` goes by the clock, so a lure is never spent twice. A press never equips and applies together, even if the pole lands before the key comes up: `/use 16` would target whatever was in the hand. Only Ctrl-click on the tackle box replaces a lure, never a key binding, which could be bound to Ctrl-something. The lure last applied is saved per character, and a lure on the pole with no record shows as unnamed rather than as the chosen one. Only poles in the main hand are supported.
- **Pools:** the game gives no position for a pool and a tooltip shows from far beyond casting range, so `Pools.lua` stores the player's position when the line goes out after hovering over one, or right away if the line is already out. It recognises English names only.
- **Getaways:** each zone keeps `escapeSkill`, the highest skill (lure included) a fish got away at, and `cleanCatches`, its catches since the last getaway. 10 clean catches clear the zone's getaways from `Stats.ZoneStatus`.
- **Sessions:** a cast after 30 minutes idle starts a new session. Fish per hour counts only time actually fishing (gaps over 2 minutes between casts don't count).
- **Opens on cast:** closing the window with its X or the minimap button keeps it closed until a 2-minute break from fishing; Escape, Alt+Z and cutscenes don't count. It doesn't open over another page of the window, and a window that opened itself closes itself when the weapons go back on (`closeOnDone`).
- **One window:** every page is its own frame, attached with `Hub.Attach`. Only one is shown at a time, all at the same height (`ns.UI.PAGE_HEIGHT`) and at the window scale (`statsScale`), each placed at a shared top-left corner saved in UI units (`windowPoints.hub`), so dragging any page moves them all. The side tabs follow the open page.
- **Spots, hours and skill-ups:** each zone's totals keep `spots` by sub-zone (`GetSubZoneText` at the cast). Lifetime items keep `hours`, catches by realm hour (`GetGameTime`), which the collection copies for the book's time of day. `OneCastCharDB.skill` counts catches since the last skill-up; the next-point estimate uses Classic's rule of thumb (1 catch per point to 75, then one more per 25 points).
- **Session summary** prints after `ACTIVE_GAP` (2 minutes) without a cast, once per stretch of new catches.
- **Zone levels** are keyed by English zone name, and `ZoneNames.lua` swaps those for the client's own at load, by area ID (`C_Map.GetAreaInfo`), so they match `GetRealZoneText` in any language. A new zone needs an area ID there. OneCast counts real getaways (`ERR_FISH_ESCAPED`), and zones without data are judged from them. `Stats.ZoneStatus` holds that judgement, and the stats window's zone strip, the book's Zones view and the data report all read it.
- **Auction prices** come from Auctionator (`GetAuctionPriceByItemID`) or TSM (`dbmarket`). The scan hands every caught item to Auctionator's `MultiSearchExact`.
- **Wanted items** are account-wide (`OneCastDB.wanted`); stats are per character (`OneCastCharDB`).
- **Collection:** `OneCastDB.collection.items[itemID].byChar[character]` holds each character's count and zones, copied from that character's `OneCastCharDB` at login and after each catch, so earlier catches count and nothing is counted twice. Any "Meat" trade good you fish up that isn't in `FishData.lua` joins the book as a discovered fish.

### Fish data

Which fish exist, and the recipes they go into, are checked against Forever's launch build (1.60.1.70790) using the client's game data on [wago.tools](https://wago.tools): `ItemSparse` and `Item` for the items, `SpellReagents`, `SkillLineAbility` and `SpellName` for recipes. That data doesn't hold recipes' required skill, so `skill` is left out where it isn't known.

Where fish are caught is server-side and not in the client data. `zones` came from Wowhead's Forever zone Fishing tabs, but those turned out to be copied from Classic Era (identical catch counts), so treat them as Classic data. Zones from anywhere else go in `more` with their source (`"classic"` or `"reported"`). Fish with no known zones are fine: the book shows the zones you've caught them in. When Forever loot data turns up, replace `zones` with it.

## Install for testing

Copy this folder to `World of Warcraft\_<forever folder>_\Interface\AddOns\OneCast`. New files or a changed TOC need a full game restart; other changes need only `/reload`.

## Releasing

`.github/workflows/release.yml` checks every push and pull request: it syntax-checks the Lua files and makes sure `Changelog.lua` has notes for the TOC's `## Version:`.

To release:

1. Add the new version's notes at the top of `Changelog.lua` and bump `## Version:` in `OneCast.toc` to match.
2. Commit, then tag and push: `git tag v0.1.1` and `git push origin main v0.1.1`.
3. The workflow builds `OneCast-0.1.1.zip` with `git archive` (one `OneCast/` folder, leaving out what `.gitattributes` marks `export-ignore`), and publishes a GitHub release with that zip and the notes from `Changelog.lua`. A version containing `alpha` or `beta` is marked as a pre-release.

A tag that doesn't match the TOC version fails the release, so the two can't drift apart.

### CurseForge uploads

The same run uploads the zip to CurseForge once the repository has (Settings → Secrets and variables → Actions):

| Name | Kind | Value |
|---|---|---|
| `CF_API_TOKEN` | secret | An API token from authors.curseforge.com → API Tokens |
| `CURSEFORGE_PROJECT_ID` | variable | The project ID shown on the CurseForge project page |
| `CURSEFORGE_GAME_VERSION_ID` | variable | CurseForge's ID for the WoW Forever game version (comma-separate several) |

To find the game version ID, add the token secret first, then run the workflow by hand (Actions → Build and release → Run workflow, or `gh workflow run release.yml`). Its `curseforge-versions` job lists every CurseForge WoW game version with its ID and type; pick the Forever one.

Until the two variables are set, a release warns that the upload was skipped, and you upload the zip from the GitHub release by hand.

# 开发 OneCast

面向玩家的说明见 [README.md](README.md)，与 CurseForge 页面文案相同。

## 工作原理

Forever 使用现代（Midnight 时代）插件 API，但缺少 `loadstring_untainted`，因此 SecureHandler 片段无法使用。OneCast 的规避方式如下：

1. `OneCastButton` 是一个 `SecureActionButtonTemplate` 按钮，`type=spell`，`spell=<钓鱼>`（由法术 ID 7620 解析名称，失败则回退到 131474）。
2. 在钓鱼的 `UNIT_SPELLCAST_CHANNEL_START` 时，将该按钮绑定的按键覆盖为 `INTERACTTARGET`，并设置 `SoftTargetInteract=3`、`SoftTargetInteractArc=2` 与 `SoftTargetInteractRange=30`，使浮漂成为软交互目标。可选地，在施法期间将音效音量提到最大。
3. 在 `UNIT_SPELLCAST_CHANNEL_STOP` 时清除覆盖；每个 CVar 仅在仍保持 OneCast 写入的值时才还原。
4. `PLAYER_REGEN_DISABLED` 在进入战斗锁定前卸下所有覆盖；`PLAYER_LOGOUT` 还原 CVar，避免被持久化保存。
5. 开启「压低其他声音」时，装备鱼竿期间（在 `PLAYER_EQUIPMENT_CHANGED` 上检查）会将 `Sound_MusicVolume`、`Sound_AmbienceVolume` 与 `Sound_DialogVolume` 降到各自原值的 `quietLevel` 百分比。它们与每次施法的 CVar 属于不同的租约组：收竿或开战不会把它们还回去，只有卸下鱼竿才会。

每次抛竿与收竿仍是一次真实按键；没有任何自动化。

### 文件说明

| 文件 | 内容 |
|---|---|
| `OneCast.lua` | 施法按钮、收竿按键覆盖、CVar 租约、选项面板、小地图按钮、斜杠命令 |
| `Gear.lua` | 从背包装备鱼竿，以及换回武器 |
| `Stats.lua` | 会话、区域、生涯与日志统计，以及统计窗口 |
| `Prices.lua` | 将渔获交给 Auctionator 搜索 |
| `ZoneLevels.lua` | 区域钓鱼等级（经典旧世数据）以及 Forever 区域备注 |
| `FishData.lua` | 图鉴中的全部鱼类：分类、区域（最常见优先）与配方 |
| `Collection.lua` | 账号范围的各角色渔获记录，从各角色统计同步 |
| `Extravaganza.lua` | 荆棘谷钓鱼大赛：赛程（经典版）、美味鱼计数与提醒 |
| `MapOverlays.lua` | 各区域地图的已探索区域叠加层，使图鉴地图完整显示（由游戏数据生成） |
| `Book.lua` | 图鉴窗口：鱼类网格，以及每条鱼的区域、地图与配方页面 |
| `Changelog.lua` | 版本说明，显示在「更新内容」窗口，并用于发布 |
| `WhatsNew.lua` | 「更新内容」窗口与登录时的聊天提示 |
| `Media/*.tga` | 按钮图标：白底深描边，游戏中着色为金色 |

### 值得了解的细节

- **自动装备鱼竿：** 未装备鱼竿时，施法键会在按钮的 `PreClick` 中装备背包里最好的鱼竿（优先上次使用的，否则物品等级最高的），且该次按键不会施法。武器按角色保存，并在空闲延迟后换回（默认 60 秒；0 = 永不）、开战时换回（战斗中被挡住的操作会在结束时完成），或按需换回。手动换上其他武器会忘记已保存的武器。双击右键需要已装备鱼竿，因此误双击不会换装。
- **会话：** 空闲超过 30 分钟后再抛竿会开启新会话。「每小时鱼数」只统计实际钓鱼时间（两次抛竿间隔超过 2 分钟的空隙不计）。
- **随抛竿打开：** 用窗口的 X 或小地图按钮关闭后会保持关闭，直到连续 2 分钟不钓鱼；Esc、Alt+Z 与过场动画不算关闭。
- **钓点、时段与技能提升：** 各区域总计按子区域（抛竿时的 `GetSubZoneText`）记录 `spots`。生涯物品记录 `hours`——按服务器小时（`GetGameTime`）的渔获，图鉴会复制用于时段显示。`OneCastCharDB.skill` 统计自上次技能提升以来的渔获次数；下一点估算沿用经典版经验法则（到 75 点每点 1 次渔获，之后每 25 点多 1 次）。
- **会话摘要** 在 `ACTIVE_GAP`（2 分钟）内无抛竿后打印，每个有新渔获的时段只打印一次。
- **区域等级** 以英文区域名（`GetRealZoneText`）为键。区域页统计真实脱钩（`ERR_FISH_ESCAPED`），没有数据的区域据此判断。
- **拍卖价格** 来自 Auctionator（`GetAuctionPriceByItemID`）或 TSM（`dbmarket`）。扫描会把所有渔获交给 Auctionator 的 `MultiSearchExact`。
- **想要的物品** 为账号范围（`OneCastDB.wanted`）；统计为角色范围（`OneCastCharDB`）。
- **图鉴：** `OneCastDB.collection.items[itemID].byChar[character]` 保存各角色的数量与区域，在登录时及每次渔获后从该角色的 `OneCastCharDB` 复制，使安装前的渔获也计入且不重复计数。钓到但不在 `FishData.lua` 中的「肉类」贸易品会作为新发现的鱼加入图鉴。

### 鱼类数据

哪些鱼存在、以及它们进入哪些配方，已对照 Forever 启动版本（1.60.1.70790），使用客户端游戏数据（[wago.tools](https://wago.tools)）：物品用 `ItemSparse` 与 `Item`，配方用 `SpellReagents`、`SkillLineAbility` 与 `SpellName`。该数据不含配方所需技能，因此在未知时会省略 `skill`。

鱼类出没地点在服务端，客户端数据中没有。`zones` 来自 Wowhead 的 Forever 区域钓鱼页，但那些数据实际上是从经典旧世复制的（渔获数量完全相同），因此应按经典版数据对待。其他来源的区域放在 `more` 中，并标注来源（`"classic"` 或 `"reported"`）。没有已知区域的鱼也可以：图鉴会显示你实际钓到它们的区域。等 Forever 掉落数据出现后，用其替换 `zones`。

## 安装以供测试

将本文件夹复制到 `World of Warcraft\_<forever 文件夹>_\Interface\AddOns\OneCast`。新增文件或 TOC 变更需要完全重启游戏；其他更改只需 `/reload`。

## 发布

`.github/workflows/release.yml` 会检查每次推送与拉取请求：对 Lua 文件做语法检查，并确认 `Changelog.lua` 含有 TOC 中 `## Version:` 对应版本的说明。

发布步骤：

1. 在 `Changelog.lua` 顶部加入新版本说明，并将 `OneCast.toc` 中的 `## Version:` 同步提升。
2. 提交，然后打标签并推送：`git tag v0.1.1` 与 `git push origin main v0.1.1`。
3. 工作流用 `git archive` 构建 `OneCast-0.1.1.zip`（单一 `OneCast/` 文件夹，排除 `.gitattributes` 中标记为 `export-ignore` 的内容），并以该 zip 与 `Changelog.lua` 中的说明发布 GitHub Release。版本号含 `alpha` 或 `beta` 时会标记为预发布。

标签与 TOC 版本不一致时发布会失败，因此两者不会漂移。

### CurseForge 上传

同一流程会在仓库配置好以下内容后（Settings → Secrets and variables → Actions）将 zip 上传到 CurseForge：

| 名称 | 类型 | 值 |
|---|---|---|
| `CF_API_TOKEN` | secret | 来自 authors.curseforge.com → API Tokens 的 API 令牌 |
| `CURSEFORGE_PROJECT_ID` | variable | CurseForge 项目页上显示的项目 ID |
| `CURSEFORGE_GAME_VERSION_ID` | variable | CurseForge 上 WoW Forever 游戏版本的 ID（多个用逗号分隔） |

查找游戏版本 ID：先添加令牌 secret，再手动运行工作流（Actions → Build and release → Run workflow，或 `gh workflow run release.yml`）。其中的 `curseforge-versions` 任务会列出所有 CurseForge WoW 游戏版本及其 ID 与类型；选择 Forever 对应项即可。

在两个变量设置完成前，发布会警告上传已跳过，你需要从 GitHub Release 手动上传 zip。

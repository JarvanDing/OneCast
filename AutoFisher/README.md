# OneCast AutoFisher

.NET Framework 4.8 本地工具：经 WASAPI 环回听溅水声，**抛竿键 / 收杆键分开** 完成循环。配合 [OneCast](../README.md) 的「提升音效」与「压低其他声音」，让溅水相对基线更明显。

**不修改游戏插件，不读内存。** 自动按键通常违反游戏 ToS，有封号风险，请自行评估。

## 前提

1. 游戏内将 OneCast「施放（抛竿）」绑定为 **抛竿键**（默认 **F8**）
2. 将 OneCast「收杆（与浮漂互动）」绑定为 **收杆键**（默认 **F7**）——绑了收杆后，施放键在线出去时不会再变成收杆
3. OneCast 选项中开启 **提升音效**、建议开启 **压低其他声音**
4. Windows 已安装 [.NET Framework 4.8](https://dotnet.microsoft.com/download/dotnet-framework/net48)

## 单文件发布

```powershell
cd AutoFisher
powershell -ExecutionPolicy Bypass -File .\publish.ps1
```

产物：
- `publish/WaveMeter.exe` — 单文件（NAudio 等依赖已用 Costura 嵌入；进程名 WaveMeter）
- `WaveMeter-portable.zip` — 便携包

图标：`Assets/AutoFisher.ico`（源图 `Assets/autofisher-logo.jpg`）。

## 编译运行

```bat
cd AutoFisher
dotnet restore
dotnet build -c Release
dotnet run -c Release
```

或用 Visual Studio 打开 `AutoFisher.sln`，目标框架 `net48`，F5。

## 使用

1. 启动 WaveMeter（会打开默认播放设备的环回监听）
2. 先点 **测试按键**：应自动聚焦游戏并抛竿；失败则改「标题含」，或右键 **以管理员运行**
3. 站到水边，点「开始」或按 **F9**（默认可有 1 秒倒计时）
4. 之后每次发键都会 **自动把游戏拉到前台**，再：抛竿键 → 听水花 → 收杆键 → 延迟 → 再抛
5. 再按 F9 或点「停止」结束

看窗口下方日志：应出现「已聚焦」「已发送 F8/F7」「听水花中」。电平条在有游戏声音时应跳动。

若误触发多：提高「灵敏度比值」或「绝对门槛」；若漏检：略降比值，并确认 OneCast 音量策略已开。抛/拉分键后，误检收杆不会再误触发抛竿。

设置保存在 `%AppData%\OneCastAutoFisher\settings.json`。

## 默认参数

| 项 | 默认 |
|---|---|
| 抛竿键 | F8（OneCast 施放） |
| 收杆键 | F7（OneCast 收杆） |
| 启停热键 | F9 |
| 灵敏度比值 | 3.5 |
| 绝对门槛 | 0.02 |
| 抛竿静默 | 1500 ms |
| 听竿超时 | 22000 ms |
| 收杆等待 | 1000 ms |
| 再抛延迟 | 500–1500 ms（随机） |
| 窗口标题 | 含 `魔兽世界` / Warcraft / Forever / WoW |

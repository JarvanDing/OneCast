using System;
using System.Drawing;
using System.Windows.Forms;
using AutoFisher.Audio;
using AutoFisher.Fishing;
using AutoFisher.Input;

namespace AutoFisher.UI
{
	public sealed class MainForm : Form
	{
		private readonly AppSettings _settings;
		private readonly LoopbackMonitor _monitor;
		private readonly SplashDetector _detector;
		private readonly FishingSession _session;
		private readonly Timer _uiTimer;
		private HotkeyHook _hotkey;
		private Button _btnStart;
		private Button _btnStop;
		private Button _btnResetBaseline;
		private Button _btnTestKey;
		private Label _lblState;
		private Label _lblLevel;
		private ProgressBar _levelBar;
		private NumericUpDown _numRatio;
		private NumericUpDown _numFloor;
		private NumericUpDown _numCastSettle;
		private NumericUpDown _numLootSettle;
		private NumericUpDown _numDelayMin;
		private NumericUpDown _numDelayMax;
		private NumericUpDown _numTimeout;
		private NumericUpDown _numCooldown;
		private NumericUpDown _numStartDelay;
		private CheckBox _chkForeground;
		private TextBox _txtTitle;
		private ListBox _log;
		private Label _hint;

		public MainForm()
		{
			_settings = AppSettings.Load();
			_monitor = new LoopbackMonitor();
			_detector = new SplashDetector();
			_session = new FishingSession(_detector);
			_session.ApplySettings(_settings);
			_uiTimer = new Timer { Interval = 100 };

			Text = "哇，大鱼 · 自动钓鱼";
			Width = 580;
			Height = 680;
			MinimumSize = new Size(540, 600);
			StartPosition = FormStartPosition.CenterScreen;
			Font = new Font("Segoe UI", 9f);
			TrySetIcon();

			BuildUi();
			LoadSettingsIntoUi();

			// Process audio on capture thread — do NOT BeginInvoke every frame (that freezes UI).
			_monitor.RmsFrame += rms => _detector.OnRms(rms);
			_monitor.CaptureError += ex => SafeLog("音频错误: " + ex.Message);
			_detector.SplashDetected += (rms, baseline) =>
			{
				SafeInvoke(() => _session.NotifySplash(rms, baseline));
			};
			_session.StateChanged += (state, msg) =>
			{
				SafeInvoke(() =>
				{
					_lblState.Text = "状态: " + StateLabel(state) + " — " + msg;
					bool running = state != FishingState.Stopped;
					_btnStart.Enabled = !running;
					_btnStop.Enabled = running;
				});
			};
			_session.Log += msg => SafeLog(msg);
			_uiTimer.Tick += (_, __) => UpdateLevelUi();

			Shown += (_, __) =>
			{
				try
				{
					_monitor.Start();
					_uiTimer.Start();
					AppendLog("WASAPI 环回已启动: " + _monitor.DeviceName);
					AppendLog("检测已回退为严格模式（比值 3.5 / 门槛 0.02）");
					AppendLog("当前前台: " + ForegroundChecker.GetForegroundTitle());
				}
				catch (Exception ex)
				{
					AppendLog("无法启动环回: " + ex.Message);
				}

				RegisterHotkey();
			};
			FormClosing += (_, __) =>
			{
				_uiTimer.Stop();
				SaveUiToSettings();
				_settings.Save();
				_session.Stop("退出");
				_hotkey?.Dispose();
				_monitor.Dispose();
				_session.Dispose();
				_uiTimer.Dispose();
			};
		}

		private static string StateLabel(FishingState state)
		{
			switch (state)
			{
				case FishingState.Stopped: return "已停止";
				case FishingState.Arming: return "倒计时";
				case FishingState.Casting: return "抛竿";
				case FishingState.Listening: return "听竿";
				case FishingState.Reeling: return "收杆";
				case FishingState.Waiting: return "等待";
				default: return state.ToString();
			}
		}

		private void TrySetIcon()
		{
			try
			{
				var exeIcon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
				if (exeIcon != null)
				{
					Icon = exeIcon;
				}
			}
			catch
			{
				// ignore missing icon
			}
		}

		protected override void WndProc(ref Message m)
		{
			if (_hotkey != null && _hotkey.ProcessMessage(ref m))
			{
				return;
			}

			base.WndProc(ref m);
		}

		private void BuildUi()
		{
			var root = new TableLayoutPanel
			{
				Dock = DockStyle.Fill,
				ColumnCount = 1,
				RowCount = 4,
				Padding = new Padding(10)
			};
			root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
			root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
			root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
			root.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
			Controls.Add(root);

			_hint = new Label
			{
				AutoSize = true,
				MaximumSize = new Size(540, 0),
				Text = "每次按键前会自动聚焦游戏。OneCast 绑 F8，开「提升音效」+「压低其他声音」。F9 启停。可先点「测试 F8」。"
			};
			root.Controls.Add(_hint, 0, 0);

			var top = new FlowLayoutPanel
			{
				Dock = DockStyle.Top,
				AutoSize = true,
				WrapContents = true
			};
			_btnStart = new Button { Text = "开始", Width = 90, Height = 28 };
			_btnStop = new Button { Text = "停止", Width = 90, Height = 28, Enabled = false };
			_btnTestKey = new Button { Text = "测试 F8", Width = 90, Height = 28 };
			_btnResetBaseline = new Button { Text = "校准基线", Width = 90, Height = 28 };
			_btnStart.Click += (_, __) => StartSession();
			_btnStop.Click += (_, __) => StopSession();
			_btnTestKey.Click += (_, __) => TestKey();
			_btnResetBaseline.Click += (_, __) =>
			{
				_detector.ResetBaseline();
				AppendLog("基线已清空，重新采样");
			};
			top.Controls.Add(_btnStart);
			top.Controls.Add(_btnStop);
			top.Controls.Add(_btnTestKey);
			top.Controls.Add(_btnResetBaseline);
			root.Controls.Add(top, 0, 1);

			var status = new TableLayoutPanel
			{
				Dock = DockStyle.Top,
				AutoSize = true,
				ColumnCount = 1,
				Padding = new Padding(0, 6, 0, 6)
			};
			_lblState = new Label { AutoSize = true, Text = "状态: 已停止" };
			_lblLevel = new Label { AutoSize = true, Text = "电平: —（有声音时数字应变大）" };
			_levelBar = new ProgressBar { Width = 520, Height = 18, Maximum = 1000 };
			status.Controls.Add(_lblState);
			status.Controls.Add(_lblLevel);
			status.Controls.Add(_levelBar);
			root.Controls.Add(status, 0, 2);

			var settingsPanel = new TableLayoutPanel
			{
				Dock = DockStyle.Fill,
				ColumnCount = 4,
				RowCount = 10,
				AutoSize = true
			};
			for (int i = 0; i < 4; i++)
			{
				settingsPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
			}
			for (int r = 0; r < 10; r++)
			{
				settingsPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
			}

			_numRatio = MakeDecimal(1.1m, 20m, 0.1m, (decimal)_settings.SensitivityRatio);
			_numFloor = MakeDecimal(0.001m, 1m, 0.001m, (decimal)_settings.AbsoluteFloor);
			_numCooldown = MakeInt(0, 5000, _settings.DetectCooldownMs);
			_numCastSettle = MakeInt(0, 10000, _settings.CastSettleMs);
			_numLootSettle = MakeInt(0, 10000, _settings.LootSettleMs);
			_numDelayMin = MakeInt(0, 30000, _settings.CastDelayMinMs);
			_numDelayMax = MakeInt(0, 30000, _settings.CastDelayMaxMs);
			_numTimeout = MakeInt(1000, 60000, _settings.ListenTimeoutMs);
			_numStartDelay = MakeInt(0, 15, _settings.StartDelaySeconds);
			_numStartDelay.Increment = 1;
			_chkForeground = new CheckBox
			{
				Text = "自动聚焦游戏",
				AutoSize = true,
				Checked = _settings.AutoFocusGame
			};
			_txtTitle = new TextBox { Width = 200, Text = _settings.GameTitleContains };

			AddSetting(settingsPanel, 0, "灵敏度比值", _numRatio);
			AddSetting(settingsPanel, 1, "绝对门槛", _numFloor);
			AddSetting(settingsPanel, 2, "检测冷却 ms", _numCooldown);
			AddSetting(settingsPanel, 3, "抛竿静默 ms", _numCastSettle);
			AddSetting(settingsPanel, 4, "收杆等待 ms", _numLootSettle);
			AddSetting(settingsPanel, 5, "再抛延迟最小", _numDelayMin);
			AddSetting(settingsPanel, 6, "再抛延迟最大", _numDelayMax);
			AddSetting(settingsPanel, 7, "听竿超时 ms", _numTimeout);
			AddSetting(settingsPanel, 8, "开始倒计时 s", _numStartDelay);

			var fgRow = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
			fgRow.Controls.Add(_chkForeground);
			fgRow.Controls.Add(new Label { Text = "标题含:", AutoSize = true, Padding = new Padding(8, 6, 0, 0) });
			fgRow.Controls.Add(_txtTitle);
			settingsPanel.SetColumnSpan(fgRow, 4);
			settingsPanel.Controls.Add(fgRow, 0, 5);

			// Row math: indices 0-8 use rows 0-4 (2 per row), fg on row 5
			// Wait - AddSetting uses index/2 for row. Index 8 -> row 4. fg at row 5. Good.
			// But I put fg at row 5 while AddSetting(8) is also row 4. Fix: put fg at row 9 end.

			settingsPanel.Controls.Remove(fgRow);
			settingsPanel.Controls.Add(fgRow, 0, 9);

			var settingsGroup = new GroupBox
			{
				Text = "参数（改后点开始会生效并保存）",
				Dock = DockStyle.Top,
				Height = 250,
				Padding = new Padding(8)
			};
			settingsGroup.Controls.Add(settingsPanel);

			_log = new ListBox { Dock = DockStyle.Fill, IntegralHeight = false };

			var mid = new TableLayoutPanel
			{
				Dock = DockStyle.Fill,
				ColumnCount = 1,
				RowCount = 2
			};
			mid.RowStyles.Add(new RowStyle(SizeType.Absolute, 260));
			mid.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
			mid.Controls.Add(settingsGroup, 0, 0);
			mid.Controls.Add(_log, 0, 1);
			root.Controls.Add(mid, 0, 3);
		}

		private static void AddSetting(TableLayoutPanel panel, int index, string label, Control editor)
		{
			int row = index / 2;
			int col = (index % 2) * 2;
			var lbl = new Label
			{
				Text = label,
				AutoSize = true,
				Anchor = AnchorStyles.Left,
				Padding = new Padding(0, 6, 0, 0)
			};
			panel.Controls.Add(lbl, col, row);
			panel.Controls.Add(editor, col + 1, row);
		}

		private static NumericUpDown MakeInt(int min, int max, int value)
		{
			return new NumericUpDown
			{
				Minimum = min,
				Maximum = max,
				Value = Math.Max(min, Math.Min(max, value)),
				Width = 90,
				Increment = 50
			};
		}

		private static NumericUpDown MakeDecimal(decimal min, decimal max, decimal increment, decimal value)
		{
			return new NumericUpDown
			{
				DecimalPlaces = 3,
				Minimum = min,
				Maximum = max,
				Increment = increment,
				Value = Math.Max(min, Math.Min(max, value)),
				Width = 90
			};
		}

		private void LoadSettingsIntoUi()
		{
			_numRatio.Value = Clamp(_numRatio, (decimal)_settings.SensitivityRatio);
			_numFloor.Value = Clamp(_numFloor, (decimal)_settings.AbsoluteFloor);
			_numCooldown.Value = Clamp(_numCooldown, _settings.DetectCooldownMs);
			_numCastSettle.Value = Clamp(_numCastSettle, _settings.CastSettleMs);
			_numLootSettle.Value = Clamp(_numLootSettle, _settings.LootSettleMs);
			_numDelayMin.Value = Clamp(_numDelayMin, _settings.CastDelayMinMs);
			_numDelayMax.Value = Clamp(_numDelayMax, _settings.CastDelayMaxMs);
			_numTimeout.Value = Clamp(_numTimeout, _settings.ListenTimeoutMs);
			_numStartDelay.Value = Clamp(_numStartDelay, _settings.StartDelaySeconds);
			_chkForeground.Checked = _settings.AutoFocusGame;
			_txtTitle.Text = _settings.GameTitleContains ?? "魔兽世界,Warcraft,Forever,WoW";
		}

		private static decimal Clamp(NumericUpDown box, decimal value)
		{
			if (value < box.Minimum)
			{
				return box.Minimum;
			}

			if (value > box.Maximum)
			{
				return box.Maximum;
			}

			return value;
		}

		private void SaveUiToSettings()
		{
			_settings.SensitivityRatio = (double)_numRatio.Value;
			_settings.AbsoluteFloor = (double)_numFloor.Value;
			_settings.DetectCooldownMs = (int)_numCooldown.Value;
			_settings.CastSettleMs = (int)_numCastSettle.Value;
			_settings.LootSettleMs = (int)_numLootSettle.Value;
			_settings.CastDelayMinMs = (int)_numDelayMin.Value;
			_settings.CastDelayMaxMs = (int)_numDelayMax.Value;
			_settings.ListenTimeoutMs = (int)_numTimeout.Value;
			_settings.StartDelaySeconds = (int)_numStartDelay.Value;
			_settings.AutoFocusGame = _chkForeground.Checked;
			_settings.GameTitleContains = string.IsNullOrWhiteSpace(_txtTitle.Text)
				? "魔兽世界,Warcraft,Forever,WoW"
				: _txtTitle.Text.Trim();
			_settings.FishKeyVk = 0x77;
			_settings.ToggleHotkeyVk = 0x78;
		}

		private void StartSession()
		{
			SaveUiToSettings();
			_settings.Save();
			_session.ApplySettings(_settings);
			_session.Start();
			_btnStart.Enabled = false;
			_btnStop.Enabled = true;
		}

		private void StopSession()
		{
			_session.Stop("手动停止");
			_btnStart.Enabled = true;
			_btnStop.Enabled = false;
		}

		private void TestKey()
		{
			SaveUiToSettings();
			AppendLog("测试：当前前台 = " + ForegroundChecker.GetForegroundTitle());
			var hwnd = ForegroundChecker.FindGameWindow(_settings.GameTitleContains);
			if (hwnd == IntPtr.Zero)
			{
				AppendLog("测试失败：未找到游戏窗口，请改「标题含」关键词。");
				return;
			}

			if (_settings.AutoFocusGame)
			{
				bool focused = ForegroundChecker.ForceForeground(hwnd);
				AppendLog(focused
					? "测试：已聚焦 → " + ForegroundChecker.GetTitle(hwnd)
					: "测试：聚焦未完全成功，仍发键 → " + ForegroundChecker.GetTitle(hwnd));
			}

			bool ok = KeySender.Tap(_settings.FishKeyVk);
			AppendLog(ok ? "测试：已发送 F8（游戏内应抛竿/有反应）" : "测试：SendInput 失败，请右键以管理员运行");
		}

		private void ToggleSession()
		{
			if (_session.IsRunning)
			{
				StopSession();
			}
			else
			{
				StartSession();
			}
		}

		private void RegisterHotkey()
		{
			_hotkey?.Dispose();
			_hotkey = new HotkeyHook(Handle, 1, _settings.ToggleHotkeyVk);
			_hotkey.Pressed += () => SafeInvoke(ToggleSession);
			AppendLog(_hotkey.IsRegistered ? "已注册全局热键 F9" : "注册 F9 失败（可能被占用）");
		}

		private void UpdateLevelUi()
		{
			float rms = _detector.LastRms;
			float baseline = _detector.LastBaseline;
			float thr = _detector.LastThreshold;
			string arm = _detector.IsArmed ? "监听中" : "未监听";
			_lblLevel.Text = string.Format(
				"{0}  RMS={1:F4}  基线={2:F4}  门槛={3:F4}",
				arm, rms, baseline, thr);
			int v = (int)Math.Min(_levelBar.Maximum, Math.Max(0, rms * 5000));
			_levelBar.Value = v;
		}

		private void SafeLog(string message)
		{
			SafeInvoke(() => AppendLog(message));
		}

		private void SafeInvoke(Action action)
		{
			if (IsDisposed)
			{
				return;
			}

			try
			{
				if (InvokeRequired)
				{
					BeginInvoke(action);
				}
				else
				{
					action();
				}
			}
			catch (ObjectDisposedException)
			{
			}
		}

		private void AppendLog(string message)
		{
			string line = DateTime.Now.ToString("HH:mm:ss") + "  " + message;
			_log.Items.Insert(0, line);
			while (_log.Items.Count > 200)
			{
				_log.Items.RemoveAt(_log.Items.Count - 1);
			}
		}
	}
}

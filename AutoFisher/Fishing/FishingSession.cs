using System;
using System.Windows.Forms;
using AutoFisher.Audio;
using AutoFisher.Input;

namespace AutoFisher.Fishing
{
	public enum FishingState
	{
		Stopped,
		Arming,
		Casting,
		Listening,
		Reeling,
		Waiting
	}

	public sealed class FishingSession : IDisposable
	{
		private const int GameMissingStopMs = 3000;

		private readonly SplashDetector _detector;
		private readonly Timer _timer;
		private readonly Random _rng = new Random();
		private AppSettings _settings;
		private FishingState _state = FishingState.Stopped;
		private DateTime _phaseUntilUtc = DateTime.MinValue;
		private DateTime? _gameMissingSinceUtc;
		private int _armSecondsLeft;
		private bool _keySentInPhase;

		public event Action<FishingState, string> StateChanged;
		public event Action<string> Log;

		public FishingState State => _state;

		public bool IsRunning => _state != FishingState.Stopped;

		public FishingSession(SplashDetector detector)
		{
			_detector = detector ?? throw new ArgumentNullException(nameof(detector));
			_timer = new Timer { Interval = 50 };
			_timer.Tick += OnTick;
		}

		/// <summary>Must be called on the UI thread when a splash is detected.</summary>
		public void NotifySplash(float rms, float baseline)
		{
			OnSplash(rms, baseline);
		}

		public void ApplySettings(AppSettings settings)
		{
			_settings = settings ?? throw new ArgumentNullException(nameof(settings));
			_detector.Configure(settings.SensitivityRatio, settings.AbsoluteFloor, settings.DetectCooldownMs);
		}

		public void Start()
		{
			if (_settings == null)
			{
				throw new InvalidOperationException("Settings not applied.");
			}

			if (IsRunning)
			{
				return;
			}

			_detector.ResetBaseline();
			_detector.Disarm();
			_gameMissingSinceUtc = null;
			_armSecondsLeft = Math.Max(0, _settings.StartDelaySeconds);
			if (_armSecondsLeft > 0)
			{
				Enter(FishingState.Arming, string.Format("倒计时 {0}s：请切换到游戏窗口", _armSecondsLeft));
				_phaseUntilUtc = DateTime.UtcNow.AddSeconds(1);
			}
			else
			{
				Enter(FishingState.Casting, "开始：抛竿");
				DoCast();
			}

			_timer.Start();
		}

		public void Stop(string reason = "已停止")
		{
			_timer.Stop();
			_detector.Disarm();
			if (_state == FishingState.Stopped)
			{
				EmitLog(reason);
				return;
			}

			SetState(FishingState.Stopped, reason);
		}

		private void OnSplash(float rms, float baseline)
		{
			if (_state != FishingState.Listening)
			{
				return;
			}

			EmitLog(string.Format("检测到溅水 RMS={0:F4} 基线={1:F4}", rms, baseline));
			Enter(FishingState.Reeling, "收杆");
			DoReel();
		}

		private void OnTick(object sender, EventArgs e)
		{
			if (!IsRunning)
			{
				return;
			}

			if (!EnsureGamePresentOrStop())
			{
				return;
			}

			if (DateTime.UtcNow < _phaseUntilUtc)
			{
				return;
			}

			switch (_state)
			{
				case FishingState.Arming:
					_armSecondsLeft--;
					if (_armSecondsLeft > 0)
					{
						Enter(FishingState.Arming, string.Format("倒计时 {0}s：请切换到游戏窗口", _armSecondsLeft));
						_phaseUntilUtc = DateTime.UtcNow.AddSeconds(1);
					}
					else
					{
						Enter(FishingState.Casting, "开始：抛竿");
						DoCast();
					}
					break;

				case FishingState.Casting:
					if (!_keySentInPhase)
					{
						DoCast();
						break;
					}

					Enter(FishingState.Listening, "听水花中…");
					_detector.ArmAfter(0);
					_phaseUntilUtc = DateTime.UtcNow.AddMilliseconds(_settings.ListenTimeoutMs);
					break;

				case FishingState.Listening:
					EmitLog("听竿超时，重新抛竿");
					Enter(FishingState.Casting, "超时重抛");
					DoCast();
					break;

				case FishingState.Reeling:
					if (!_keySentInPhase)
					{
						DoReel();
						break;
					}

					Enter(FishingState.Waiting, "等待再抛");
					int delay = NextCastDelay();
					_phaseUntilUtc = DateTime.UtcNow.AddMilliseconds(delay);
					EmitLog(string.Format("再抛延迟 {0} ms", delay));
					break;

				case FishingState.Waiting:
					Enter(FishingState.Casting, "再抛");
					DoCast();
					break;
			}
		}

		private void DoCast()
		{
			_detector.Disarm();
			_keySentInPhase = false;
			if (!TryPress("抛竿"))
			{
				return;
			}

			_keySentInPhase = true;
			_phaseUntilUtc = DateTime.UtcNow.AddMilliseconds(_settings.CastSettleMs);
		}

		private void DoReel()
		{
			_detector.Disarm();
			_keySentInPhase = false;
			if (!TryPress("收杆"))
			{
				return;
			}

			_keySentInPhase = true;
			_phaseUntilUtc = DateTime.UtcNow.AddMilliseconds(_settings.LootSettleMs);
		}

		/// <summary>
		/// Stops after the game window stays missing for <see cref="GameMissingStopMs"/>.
		/// Covers client close / crash / many disconnect cases where the window disappears.
		/// </summary>
		private bool EnsureGamePresentOrStop()
		{
			var hwnd = ForegroundChecker.FindGameWindow(_settings.GameTitleContains);
			if (hwnd != IntPtr.Zero)
			{
				_gameMissingSinceUtc = null;
				return true;
			}

			if (_gameMissingSinceUtc == null)
			{
				_gameMissingSinceUtc = DateTime.UtcNow;
				EmitLog("未找到游戏窗口（标题需含: " + _settings.GameTitleContains + "），持续丢失将自动停止…");
				return true;
			}

			double missingMs = (DateTime.UtcNow - _gameMissingSinceUtc.Value).TotalMilliseconds;
			if (missingMs >= GameMissingStopMs)
			{
				Stop("游戏窗口消失，已自动停止（可能已掉线或关闭）");
				return false;
			}

			return true;
		}

		private bool TryPress(string action)
		{
			if (!EnsureGamePresentOrStop())
			{
				return false;
			}

			var hwnd = ForegroundChecker.FindGameWindow(_settings.GameTitleContains);
			if (hwnd == IntPtr.Zero)
			{
				_phaseUntilUtc = DateTime.UtcNow.AddMilliseconds(500);
				return false;
			}

			if (_settings.AutoFocusGame)
			{
				bool focused = ForegroundChecker.ForceForeground(hwnd);
				EmitLog(focused
					? action + "：已聚焦 → " + ForegroundChecker.GetTitle(hwnd)
					: action + "：聚焦未完全成功，仍尝试发键 → " + ForegroundChecker.GetTitle(hwnd));
				System.Threading.Thread.Sleep(50);
			}

			bool ok = KeySender.Tap(_settings.FishKeyVk);
			EmitLog(ok
				? action + " → 已发送 F8"
				: action + " → SendInput 失败（请以管理员运行）");
			if (!ok)
			{
				_phaseUntilUtc = DateTime.UtcNow.AddMilliseconds(1500);
			}

			return ok;
		}

		private int NextCastDelay()
		{
			int min = Math.Max(0, _settings.CastDelayMinMs);
			int max = Math.Max(min, _settings.CastDelayMaxMs);
			if (max <= min)
			{
				return min;
			}

			return _rng.Next(min, max + 1);
		}

		private void Enter(FishingState state, string message)
		{
			SetState(state, message);
		}

		private void SetState(FishingState state, string message)
		{
			_state = state;
			StateChanged?.Invoke(state, message);
			EmitLog(message);
		}

		private void EmitLog(string message)
		{
			Log?.Invoke(message);
		}

		public void Dispose()
		{
			_timer.Stop();
			_timer.Tick -= OnTick;
			_timer.Dispose();
		}
	}
}

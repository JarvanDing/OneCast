using System;
using System.Collections.Generic;

namespace AutoFisher.Audio
{
	/// <summary>
	/// Detects splash-like onsets from relative RMS spikes against a short baseline.
	/// </summary>
	public sealed class SplashDetector
	{
		private readonly object _gate = new object();
		private readonly Queue<float> _baselineWindow = new Queue<float>();
		private readonly List<float> _sortedScratch = new List<float>();
		private int _baselineCapacity = 40; // ~1.2s at 30ms frames
		private double _ratio = 3.5;
		private double _absoluteFloor = 0.02;
		private int _cooldownMs = 800;
		private DateTime _armedAfterUtc = DateTime.MinValue;
		private DateTime _lastDetectUtc = DateTime.MinValue;
		private float _lastRms;
		private float _lastBaseline;
		private float _lastThreshold;
		private bool _enabled;

		public event Action<float, float> SplashDetected;

		public float LastRms
		{
			get
			{
				lock (_gate)
				{
					return _lastRms;
				}
			}
		}

		public float LastBaseline
		{
			get
			{
				lock (_gate)
				{
					return _lastBaseline;
				}
			}
		}

		public float LastThreshold
		{
			get
			{
				lock (_gate)
				{
					return _lastThreshold;
				}
			}
		}

		public bool IsArmed
		{
			get
			{
				lock (_gate)
				{
					return _enabled && DateTime.UtcNow >= _armedAfterUtc;
				}
			}
		}

		public void Configure(double ratio, double absoluteFloor, int cooldownMs)
		{
			lock (_gate)
			{
				_ratio = Math.Max(1.1, ratio);
				_absoluteFloor = Math.Max(0.0, absoluteFloor);
				_cooldownMs = Math.Max(0, cooldownMs);
			}
		}

		public void ArmAfter(int settleMs)
		{
			lock (_gate)
			{
				_armedAfterUtc = DateTime.UtcNow.AddMilliseconds(Math.Max(0, settleMs));
				_enabled = true;
			}
		}

		public void Disarm()
		{
			lock (_gate)
			{
				_enabled = false;
				_armedAfterUtc = DateTime.MaxValue;
			}
		}

		public void ResetBaseline()
		{
			lock (_gate)
			{
				_baselineWindow.Clear();
				_lastBaseline = 0;
			}
		}

		public void OnRms(float rms)
		{
			float baseline;
			bool fire = false;

			lock (_gate)
			{
				_lastRms = rms;
				_baselineWindow.Enqueue(rms);
				while (_baselineWindow.Count > _baselineCapacity)
				{
					_baselineWindow.Dequeue();
				}

				baseline = Median(_baselineWindow);
				_lastBaseline = baseline;
				_lastThreshold = Math.Max((float)(Math.Max(baseline, 0.0001f) * _ratio), (float)_absoluteFloor);

				var now = DateTime.UtcNow;
				if (_enabled
					&& now >= _armedAfterUtc
					&& (now - _lastDetectUtc).TotalMilliseconds >= _cooldownMs
					&& rms >= _absoluteFloor
					&& baseline > 0.0001f
					&& rms >= baseline * _ratio)
				{
					_lastDetectUtc = now;
					fire = true;
					_enabled = false;
				}
			}

			if (fire)
			{
				SplashDetected?.Invoke(rms, baseline);
			}
		}

		private float Median(Queue<float> values)
		{
			_sortedScratch.Clear();
			foreach (var v in values)
			{
				_sortedScratch.Add(v);
			}

			if (_sortedScratch.Count == 0)
			{
				return 0;
			}

			_sortedScratch.Sort();
			int mid = _sortedScratch.Count / 2;
			if ((_sortedScratch.Count & 1) == 1)
			{
				return _sortedScratch[mid];
			}

			return (_sortedScratch[mid - 1] + _sortedScratch[mid]) * 0.5f;
		}
	}
}

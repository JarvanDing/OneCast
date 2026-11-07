using System;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace AutoFisher.Audio
{
	/// <summary>
	/// Captures system audio via WASAPI loopback and reports mono RMS frames.
	/// </summary>
	public sealed class LoopbackMonitor : IDisposable
	{
		private WasapiLoopbackCapture _capture;
		private readonly object _gate = new object();
		private float[] _monoScratch = new float[0];
		private bool _started;

		public event Action<float> RmsFrame;
		public event Action<Exception> CaptureError;

		public string DeviceName { get; private set; }

		public bool IsRunning
		{
			get
			{
				lock (_gate)
				{
					return _started;
				}
			}
		}

		public void Start()
		{
			lock (_gate)
			{
				if (_started)
				{
					return;
				}

				_capture = new WasapiLoopbackCapture();
				try
				{
					DeviceName = "默认播放设备 (环回)";
					using (var enumerator = new MMDeviceEnumerator())
					{
						var dev = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
						if (dev != null)
						{
							DeviceName = dev.FriendlyName + " (环回)";
						}
					}
				}
				catch
				{
					DeviceName = "默认播放设备 (环回)";
				}

				_capture.DataAvailable += OnDataAvailable;
				_capture.RecordingStopped += OnRecordingStopped;
				_capture.StartRecording();
				_started = true;
			}
		}

		public void Stop()
		{
			lock (_gate)
			{
				if (!_started)
				{
					return;
				}

				try
				{
					_capture.StopRecording();
				}
				catch
				{
					// ignore stop races
				}

				_started = false;
			}
		}

		private void OnRecordingStopped(object sender, StoppedEventArgs e)
		{
			if (e.Exception != null)
			{
				CaptureError?.Invoke(e.Exception);
			}
		}

		private void OnDataAvailable(object sender, WaveInEventArgs e)
		{
			if (e.BytesRecorded <= 0)
			{
				return;
			}

			var format = _capture.WaveFormat;
			int bytesPerSample = format.BitsPerSample / 8;
			if (bytesPerSample <= 0)
			{
				return;
			}

			int sampleCount = e.BytesRecorded / bytesPerSample;
			int frames = sampleCount / format.Channels;
			if (frames <= 0)
			{
				return;
			}

			if (_monoScratch.Length < frames)
			{
				_monoScratch = new float[frames];
			}

			if (format.Encoding == WaveFormatEncoding.IeeeFloat || format.BitsPerSample == 32)
			{
				ToMonoFloat32(e.Buffer, e.BytesRecorded, format.Channels, _monoScratch, frames);
			}
			else if (format.BitsPerSample == 16)
			{
				ToMonoInt16(e.Buffer, e.BytesRecorded, format.Channels, _monoScratch, frames);
			}
			else
			{
				return;
			}

			int sampleRate = format.SampleRate;
			int frameSamples = Math.Max(1, sampleRate * 30 / 1000);
			int offset = 0;
			while (offset + frameSamples <= frames)
			{
				double sum = 0;
				for (int i = 0; i < frameSamples; i++)
				{
					float s = _monoScratch[offset + i];
					sum += s * s;
				}

				float rms = (float)Math.Sqrt(sum / frameSamples);
				RmsFrame?.Invoke(rms);
				offset += frameSamples;
			}
		}

		private static void ToMonoFloat32(byte[] buffer, int bytesRecorded, int channels, float[] dest, int frames)
		{
			for (int f = 0; f < frames; f++)
			{
				float sum = 0;
				for (int c = 0; c < channels; c++)
				{
					int idx = (f * channels + c) * 4;
					if (idx + 4 > bytesRecorded)
					{
						break;
					}

					sum += BitConverter.ToSingle(buffer, idx);
				}

				dest[f] = sum / channels;
			}
		}

		private static void ToMonoInt16(byte[] buffer, int bytesRecorded, int channels, float[] dest, int frames)
		{
			for (int f = 0; f < frames; f++)
			{
				float sum = 0;
				for (int c = 0; c < channels; c++)
				{
					int idx = (f * channels + c) * 2;
					if (idx + 2 > bytesRecorded)
					{
						break;
					}

					short sample = BitConverter.ToInt16(buffer, idx);
					sum += sample / 32768f;
				}

				dest[f] = sum / channels;
			}
		}

		public void Dispose()
		{
			Stop();
			lock (_gate)
			{
				if (_capture != null)
				{
					_capture.DataAvailable -= OnDataAvailable;
					_capture.RecordingStopped -= OnRecordingStopped;
					_capture.Dispose();
					_capture = null;
				}
			}
		}
	}
}

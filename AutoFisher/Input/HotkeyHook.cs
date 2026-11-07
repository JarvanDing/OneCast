using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace AutoFisher.Input
{
	/// <summary>
	/// Registers a global hotkey on a message-only window handle (the form).
	/// </summary>
	public sealed class HotkeyHook : IDisposable
	{
		private const int WmHotkey = 0x0312;
		private readonly IntPtr _hwnd;
		private readonly int _id;
		private bool _registered;

		public event Action Pressed;

		[DllImport("user32.dll", SetLastError = true)]
		private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

		[DllImport("user32.dll", SetLastError = true)]
		private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

		public HotkeyHook(IntPtr hwnd, int id, ushort virtualKey)
		{
			_hwnd = hwnd;
			_id = id;
			_registered = RegisterHotKey(hwnd, id, 0, virtualKey);
		}

		public bool IsRegistered => _registered;

		public bool ProcessMessage(ref Message m)
		{
			if (m.Msg == WmHotkey && m.WParam.ToInt32() == _id)
			{
				Pressed?.Invoke();
				return true;
			}

			return false;
		}

		public void Dispose()
		{
			if (_registered)
			{
				UnregisterHotKey(_hwnd, _id);
				_registered = false;
			}
		}
	}
}

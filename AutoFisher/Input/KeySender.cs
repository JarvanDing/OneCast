using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace AutoFisher.Input
{
	public static class KeySender
	{
		private const uint InputKeyboard = 1;
		private const uint KeyeventfKeyup = 0x0002;
		private const uint KeyeventfScancode = 0x0008;

		[StructLayout(LayoutKind.Sequential)]
		private struct Input
		{
			public uint type;
			public InputUnion U;
		}

		[StructLayout(LayoutKind.Explicit)]
		private struct InputUnion
		{
			[FieldOffset(0)]
			public MouseInput mi;
			[FieldOffset(0)]
			public KeybdInput ki;
		}

		[StructLayout(LayoutKind.Sequential)]
		private struct MouseInput
		{
			public int dx;
			public int dy;
			public uint mouseData;
			public uint dwFlags;
			public uint time;
			public IntPtr dwExtraInfo;
		}

		[StructLayout(LayoutKind.Sequential)]
		private struct KeybdInput
		{
			public ushort wVk;
			public ushort wScan;
			public uint dwFlags;
			public uint time;
			public IntPtr dwExtraInfo;
		}

		[DllImport("user32.dll", SetLastError = true)]
		private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);

		[DllImport("user32.dll")]
		private static extern uint MapVirtualKey(uint uCode, uint uMapType);

		/// <summary>
		/// Sends a key tap via scan codes (more reliable for games than VK-only).
		/// </summary>
		public static bool Tap(ushort virtualKey)
		{
			ushort scan = (ushort)MapVirtualKey(virtualKey, 0);
			var inputs = new Input[2];
			inputs[0] = MakeKey(scan, 0);
			inputs[1] = MakeKey(scan, KeyeventfKeyup);

			uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Input)));
			if (sent != inputs.Length)
			{
				// Fallback: virtual-key style
				inputs[0] = MakeVk(virtualKey, 0);
				inputs[1] = MakeVk(virtualKey, KeyeventfKeyup);
				sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Input)));
			}

			Thread.Sleep(30);
			return sent == inputs.Length;
		}

		private static Input MakeKey(ushort scan, uint extraFlags)
		{
			return new Input
			{
				type = InputKeyboard,
				U = new InputUnion
				{
					ki = new KeybdInput
					{
						wVk = 0,
						wScan = scan,
						dwFlags = KeyeventfScancode | extraFlags,
						time = 0,
						dwExtraInfo = IntPtr.Zero
					}
				}
			};
		}

		private static Input MakeVk(ushort vk, uint extraFlags)
		{
			return new Input
			{
				type = InputKeyboard,
				U = new InputUnion
				{
					ki = new KeybdInput
					{
						wVk = vk,
						wScan = (ushort)MapVirtualKey(vk, 0),
						dwFlags = extraFlags,
						time = 0,
						dwExtraInfo = IntPtr.Zero
					}
				}
			};
		}
	}
}

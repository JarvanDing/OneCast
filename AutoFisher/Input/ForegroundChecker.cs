using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace AutoFisher.Input
{
	public static class ForegroundChecker
	{
		[DllImport("user32.dll")]
		private static extern IntPtr GetForegroundWindow();

		[DllImport("user32.dll", CharSet = CharSet.Unicode)]
		private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

		[DllImport("user32.dll")]
		private static extern bool SetForegroundWindow(IntPtr hWnd);

		[DllImport("user32.dll")]
		private static extern bool BringWindowToTop(IntPtr hWnd);

		[DllImport("user32.dll")]
		private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

		[DllImport("user32.dll")]
		private static extern bool IsIconic(IntPtr hWnd);

		[DllImport("user32.dll")]
		private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

		[DllImport("kernel32.dll")]
		private static extern uint GetCurrentThreadId();

		[DllImport("user32.dll")]
		private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

		[DllImport("user32.dll")]
		private static extern bool AllowSetForegroundWindow(int dwProcessId);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		private static extern bool IsWindowVisible(IntPtr hWnd);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

		private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

		private const int SwRestore = 9;
		private const int AsfwAny = -1;
		private const uint WmClose = 0x0010;

		public static string GetForegroundTitle()
		{
			return GetTitle(GetForegroundWindow());
		}

		public static string GetTitle(IntPtr hwnd)
		{
			if (hwnd == IntPtr.Zero)
			{
				return string.Empty;
			}

			var sb = new StringBuilder(512);
			GetWindowText(hwnd, sb, sb.Capacity);
			return sb.ToString();
		}

		public static bool TitleMatches(string title, string titleContains)
		{
			if (string.IsNullOrWhiteSpace(titleContains))
			{
				return true;
			}

			if (string.IsNullOrEmpty(title))
			{
				return false;
			}

			foreach (var part in titleContains.Split(new[] { ',', '|', ';' }, StringSplitOptions.RemoveEmptyEntries))
			{
				var token = part.Trim();
				if (token.Length > 0
					&& title.IndexOf(token, StringComparison.OrdinalIgnoreCase) >= 0)
				{
					return true;
				}
			}

			return false;
		}

		public static bool IsGameForeground(string titleContains)
		{
			return TitleMatches(GetForegroundTitle(), titleContains);
		}

		public static IntPtr FindGameWindow(string titleContains)
		{
			IntPtr found = IntPtr.Zero;
			EnumWindows((hWnd, lParam) =>
			{
				if (!IsWindowVisible(hWnd))
				{
					return true;
				}

				var title = GetTitle(hWnd);
				if (TitleMatches(title, titleContains))
				{
					found = hWnd;
					return false;
				}

				return true;
			}, IntPtr.Zero);
			return found;
		}

		/// <summary>
		/// Finds the game window and forcibly brings it to the foreground.
		/// </summary>
		public static bool TryFocusGame(string titleContains)
		{
			var hwnd = FindGameWindow(titleContains);
			if (hwnd == IntPtr.Zero)
			{
				return false;
			}

			return ForceForeground(hwnd);
		}

		/// <summary>
		/// Posts WM_CLOSE to the matched game window so the client can quit.
		/// </summary>
		public static bool CloseGameWindow(string titleContains)
		{
			var hwnd = FindGameWindow(titleContains);
			if (hwnd == IntPtr.Zero)
			{
				return false;
			}

			return PostMessage(hwnd, WmClose, IntPtr.Zero, IntPtr.Zero);
		}

		public static bool ForceForeground(IntPtr hwnd)
		{
			if (hwnd == IntPtr.Zero)
			{
				return false;
			}

			if (GetForegroundWindow() == hwnd)
			{
				return true;
			}

			AllowSetForegroundWindow(AsfwAny);

			if (IsIconic(hwnd))
			{
				ShowWindow(hwnd, SwRestore);
			}

			IntPtr fore = GetForegroundWindow();
			uint foreThread = 0;
			uint targetThread = GetWindowThreadProcessId(hwnd, out _);
			uint curThread = GetCurrentThreadId();

			if (fore != IntPtr.Zero)
			{
				foreThread = GetWindowThreadProcessId(fore, out _);
			}

			bool attachedFore = false;
			bool attachedCur = false;
			try
			{
				if (foreThread != 0 && foreThread != curThread)
				{
					attachedFore = AttachThreadInput(curThread, foreThread, true);
				}

				if (targetThread != 0 && targetThread != curThread)
				{
					attachedCur = AttachThreadInput(curThread, targetThread, true);
				}

				BringWindowToTop(hwnd);
				ShowWindow(hwnd, SwRestore);
				SetForegroundWindow(hwnd);
			}
			finally
			{
				if (attachedCur)
				{
					AttachThreadInput(curThread, targetThread, false);
				}

				if (attachedFore && foreThread != 0)
				{
					AttachThreadInput(curThread, foreThread, false);
				}
			}

			Thread.Sleep(80);
			return GetForegroundWindow() == hwnd || IsGameForegroundFromHwnd(hwnd);
		}

		private static bool IsGameForegroundFromHwnd(IntPtr hwnd)
		{
			return GetForegroundWindow() == hwnd;
		}
	}
}

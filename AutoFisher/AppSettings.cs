using System;
using System.IO;
using System.Web.Script.Serialization;

namespace AutoFisher
{
	public sealed class AppSettings
	{
		public ushort FishKeyVk { get; set; } = 0x77; // F8
		public ushort ToggleHotkeyVk { get; set; } = 0x78; // F9
		public double SensitivityRatio { get; set; } = 3.5;
		public double AbsoluteFloor { get; set; } = 0.02;
		public int DetectCooldownMs { get; set; } = 800;
		public int CastSettleMs { get; set; } = 1500;
		public int LootSettleMs { get; set; } = 1000;
		public int CastDelayMinMs { get; set; } = 500;
		public int CastDelayMaxMs { get; set; } = 1500;
		public int ListenTimeoutMs { get; set; } = 22000;
		public int StartDelaySeconds { get; set; } = 1;
		/// <summary>Always bring the game window to foreground before sending keys.</summary>
		public bool AutoFocusGame { get; set; } = true;
		/// <summary>Legacy; ignored. Kept so old settings.json still deserializes.</summary>
		public bool RequireGameForeground { get; set; }
		/// <summary>Comma-separated title tokens. Match if any token is found.</summary>
		public string GameTitleContains { get; set; } = "魔兽世界,Warcraft,Forever,WoW";

		private static string SettingsPath
		{
			get
			{
				var dir = Path.Combine(
					Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
					"OneCastAutoFisher");
				Directory.CreateDirectory(dir);
				return Path.Combine(dir, "settings.json");
			}
		}

		public static AppSettings Load()
		{
			try
			{
				if (!File.Exists(SettingsPath))
				{
					return new AppSettings();
				}

				var json = File.ReadAllText(SettingsPath);
				var serializer = new JavaScriptSerializer();
				var loaded = serializer.Deserialize<AppSettings>(json) ?? new AppSettings();
				// Upgrade older title defaults that missed Chinese client title
				if (string.Equals(loaded.GameTitleContains, "Warcraft", StringComparison.Ordinal)
					|| string.Equals(loaded.GameTitleContains, "Warcraft,Forever,WoW", StringComparison.Ordinal))
				{
					loaded.GameTitleContains = "魔兽世界,Warcraft,Forever,WoW";
				}
				else if (!string.IsNullOrEmpty(loaded.GameTitleContains)
					&& loaded.GameTitleContains.IndexOf("魔兽世界", StringComparison.Ordinal) < 0)
				{
					loaded.GameTitleContains = "魔兽世界," + loaded.GameTitleContains;
				}

				// Old settings.json had no AutoFocusGame → bool defaulted to false; force on.
				if (json.IndexOf("AutoFocusGame", StringComparison.OrdinalIgnoreCase) < 0)
				{
					loaded.AutoFocusGame = true;
				}

				// Roll back overly sensitive values written by the previous build.
				if (loaded.SensitivityRatio <= 2.5)
				{
					loaded.SensitivityRatio = 3.5;
				}

				if (loaded.AbsoluteFloor <= 0.01)
				{
					loaded.AbsoluteFloor = 0.02;
				}

				if (loaded.DetectCooldownMs < 700)
				{
					loaded.DetectCooldownMs = 800;
				}

				return loaded;
			}
			catch
			{
				return new AppSettings();
			}
		}

		public void Save()
		{
			var serializer = new JavaScriptSerializer();
			File.WriteAllText(SettingsPath, serializer.Serialize(this));
		}
	}
}

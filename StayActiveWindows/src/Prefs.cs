using System;
using Microsoft.Win32;

namespace StayActive
{
    /// <summary>
    /// Einstellungen in HKCU\Software\StayActive (nur Benutzer-Zweig, keine Adminrechte nötig).
    /// Ein laufender Zeitraum (EndDate) wird ebenfalls hier gespeichert und übersteht so einen Neustart.
    /// </summary>
    internal static class Prefs
    {
        private const string KeyPath = @"Software\StayActive";

        public static bool Enabled
        {
            get { return GetBool("Enabled", true); }
            set { SetBool("Enabled", value); }
        }

        /// <summary>Maus-Impuls für den Teams-Status.</summary>
        public static bool JiggleMouse
        {
            get { return GetBool("JiggleMouse", true); }
            set { SetBool("JiggleMouse", value); }
        }

        /// <summary>Sekunden zwischen zwei Impulsen.</summary>
        public static int IntervalSeconds
        {
            get
            {
                int v = GetInt("IntervalSeconds", 60);
                return v >= 10 && v <= 3600 ? v : 60;
            }
            set { SetInt("IntervalSeconds", value); }
        }

        /// <summary>Ende des laufenden Zeitraums (UTC), null = unbegrenzt.</summary>
        public static DateTime? EndUtc
        {
            get { return GetDate("EndUtc"); }
            set { SetDate("EndUtc", value); }
        }

        /// <summary>Beginn des laufenden Zeitraums (UTC).</summary>
        public static DateTime? StartUtc
        {
            get { return GetDate("StartUtc"); }
            set { SetDate("StartUtc", value); }
        }

        /// <summary>Welche Auswahl unter "Starten für …" aktiv ist (für das Häkchen).</summary>
        public static string Preset
        {
            get { return GetString("Preset"); }
            set { SetString("Preset", value); }
        }

        /// <summary>Feierabend als Minuten nach Mitternacht (Standard 17:00).</summary>
        public static int WorkEndMinutes
        {
            get
            {
                int v = GetInt("WorkEndMinutes", 17 * 60);
                return v >= 0 && v < 24 * 60 ? v : 17 * 60;
            }
            set { SetInt("WorkEndMinutes", value); }
        }

        /// <summary>Beim Start immer aktivieren (unbegrenzt), auch wenn zuletzt ausgeschaltet.</summary>
        public static bool ActivateOnLaunch
        {
            get { return GetBool("ActivateOnLaunch", false); }
            set { SetBool("ActivateOnLaunch", value); }
        }

        /// <summary>Restzeit im Tray-Symbol anzeigen.</summary>
        public static bool ShowCountdown
        {
            get { return GetBool("ShowCountdown", true); }
            set { SetBool("ShowCountdown", value); }
        }

        /// <summary>Bestätigung (Benachrichtigung) bei Start/Stopp/Ablauf.</summary>
        public static bool ShowBalloon
        {
            get { return GetBool("ShowBalloon", true); }
            set { SetBool("ShowBalloon", value); }
        }

        /// <summary>Hinweis "Symbol ist im Infobereich" wurde schon einmal gezeigt.</summary>
        public static bool FirstRunDone
        {
            get { return GetBool("FirstRunDone", false); }
            set { SetBool("FirstRunDone", value); }
        }

        // MARK: Registry-Helfer (Fehler werden geschluckt – dann gilt der Standardwert)

        private static object Read(string name)
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(KeyPath))
                {
                    return key == null ? null : key.GetValue(name);
                }
            }
            catch (Exception)
            {
                return null;
            }
        }

        private static void Write(string name, object value, RegistryValueKind kind)
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(KeyPath))
                {
                    if (key == null) return;
                    if (value == null) key.DeleteValue(name, false);
                    else key.SetValue(name, value, kind);
                }
            }
            catch (Exception)
            {
                // Einstellung geht verloren, App läuft weiter.
            }
        }

        private static int GetInt(string name, int fallback)
        {
            object v = Read(name);
            return v is int ? (int)v : fallback;
        }

        private static void SetInt(string name, int value)
        {
            Write(name, value, RegistryValueKind.DWord);
        }

        private static bool GetBool(string name, bool fallback)
        {
            object v = Read(name);
            return v is int ? (int)v != 0 : fallback;
        }

        private static void SetBool(string name, bool value)
        {
            Write(name, value ? 1 : 0, RegistryValueKind.DWord);
        }

        private static string GetString(string name)
        {
            return Read(name) as string;
        }

        private static void SetString(string name, string value)
        {
            Write(name, value, RegistryValueKind.String);
        }

        private static DateTime? GetDate(string name)
        {
            object v = Read(name);
            if (!(v is long)) return null;
            long ticks = (long)v;
            if (ticks <= DateTime.MinValue.Ticks || ticks >= DateTime.MaxValue.Ticks) return null;
            return new DateTime(ticks, DateTimeKind.Utc);
        }

        private static void SetDate(string name, DateTime? value)
        {
            if (value.HasValue) Write(name, value.Value.ToUniversalTime().Ticks, RegistryValueKind.QWord);
            else Write(name, null, RegistryValueKind.QWord);
        }
    }

    /// <summary>
    /// "Mit Windows starten": Eintrag unter HKCU\Software\Microsoft\Windows\CurrentVersion\Run
    /// (gilt nur für den aktuellen Benutzer, keine Adminrechte nötig).
    /// </summary>
    internal static class Autostart
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "StayActive";

        private static string Command
        {
            get { return "\"" + System.Windows.Forms.Application.ExecutablePath + "\""; }
        }

        public static bool IsEnabled
        {
            get
            {
                try
                {
                    using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey))
                    {
                        return key != null && key.GetValue(ValueName) is string;
                    }
                }
                catch (Exception)
                {
                    return false;
                }
            }
        }

        /// <summary>Wirft bei Fehler (z. B. Richtlinie verbietet Schreiben) – der Aufrufer zeigt die Meldung.</summary>
        public static void SetEnabled(bool enabled)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (key == null) throw new InvalidOperationException("Autostart-Schlüssel nicht verfügbar.");
                if (enabled) key.SetValue(ValueName, Command, RegistryValueKind.String);
                else key.DeleteValue(ValueName, false);
            }
        }

        /// <summary>Wurde die .exe verschoben, zeigt der Autostart-Eintrag ins Leere – dann auf den neuen Ort setzen.</summary>
        public static void RepairPathIfMoved()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    string current = key == null ? null : key.GetValue(ValueName) as string;
                    if (current == null) return;
                    if (!string.Equals(current, Command, StringComparison.OrdinalIgnoreCase))
                    {
                        string oldPath = current.Trim().Trim('"');
                        if (!System.IO.File.Exists(oldPath)) key.SetValue(ValueName, Command, RegistryValueKind.String);
                    }
                }
            }
            catch (Exception)
            {
                // Nicht kritisch.
            }
        }
    }
}

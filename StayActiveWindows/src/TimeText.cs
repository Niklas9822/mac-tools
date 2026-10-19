using System;
using System.Globalization;

namespace StayActive
{
    /// <summary>Restzeit- und Uhrzeit-Texte (wie in der macOS-Version).</summary>
    internal static class TimeText
    {
        private static readonly CultureInfo German = CultureInfo.GetCultureInfo("de-DE");

        private static int CeilMinutes(TimeSpan t)
        {
            return (int)Math.Ceiling(t.TotalSeconds / 60.0);
        }

        /// <summary>"1 Std. 23 Min.", "45 Min.", "2 Std.", "30 Sek." (Minuten aufgerundet).</summary>
        public static string Long(TimeSpan t)
        {
            if (t.TotalSeconds < 60) return Math.Max(1, (int)Math.Ceiling(t.TotalSeconds)) + " Sek.";
            int total = CeilMinutes(t);
            int h = total / 60, m = total % 60;
            if (h == 0) return m + " Min.";
            if (m == 0) return h + " Std.";
            return h + " Std. " + m + " Min.";
        }

        /// <summary>Kurzform für den Tooltip: "1:23" (Std:Min) bzw. "45 s" in der letzten Minute.</summary>
        public static string Short(TimeSpan t)
        {
            if (t.TotalSeconds < 60) return Math.Max(1, (int)Math.Ceiling(t.TotalSeconds)) + " s";
            int total = CeilMinutes(t);
            return string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}", total / 60, total % 60);
        }

        /// <summary>
        /// Ganz kurz für das Tray-Symbol (max. 3 Zeichen): "45" (Minuten), "2h" (volle Stunden), "&lt;1" (letzte Minute).
        /// </summary>
        public static string Badge(TimeSpan t)
        {
            if (t.TotalSeconds < 60) return "<1";
            int total = CeilMinutes(t);
            if (total < 60) return total.ToString(CultureInfo.InvariantCulture);
            int hours = total / 60; // volle Stunden der (aufgerundeten) Restminuten, wie in Long()
            if (hours < 100) return hours.ToString(CultureInfo.InvariantCulture) + "h";
            return "99+";
        }

        /// <summary>"15:40", "morgen 08:00" oder "Mi. 08:00".</summary>
        public static string Clock(DateTime utc)
        {
            DateTime local = utc.ToLocalTime();
            string time = local.ToString("HH:mm", German);
            DateTime today = DateTime.Today;
            if (local.Date == today) return time;
            if (local.Date == today.AddDays(1)) return "morgen " + time;
            return local.ToString("ddd", German).TrimEnd('.') + ". " + time;
        }

        public static string ClockMinutes(int minutes)
        {
            return string.Format(CultureInfo.InvariantCulture, "{0:00}:{1:00}", minutes / 60, minutes % 60);
        }

        /// <summary>Eingabe für "Eigene Dauer": "90" (Minuten), "1:30" (Std:Min), "2h" / "1,5 Std" (Stunden).</summary>
        public static TimeSpan? ParseDuration(string input)
        {
            if (input == null) return null;
            string s = input.Trim().ToLowerInvariant().Replace(",", ".");
            if (s.Length == 0) return null;
            double? seconds = null;
            if (s.Contains(":"))
            {
                string[] parts = s.Split(':');
                int h, m;
                if (parts.Length == 2
                    && int.TryParse(parts[0].Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out h)
                    && int.TryParse(parts[1].Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out m))
                {
                    seconds = h * 3600.0 + m * 60.0;
                }
            }
            else if (s.EndsWith("h") || s.Contains("std"))
            {
                string number = s.Replace("std.", "").Replace("std", "").Replace("h", "").Trim();
                double h;
                if (double.TryParse(number, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out h))
                    seconds = h * 3600.0;
            }
            else
            {
                string number = s.Replace("min.", "").Replace("min", "").Replace("m", "").Trim();
                double m;
                if (double.TryParse(number, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out m))
                    seconds = m * 60.0;
            }
            if (!seconds.HasValue || seconds.Value < 60 || seconds.Value > 7 * 24 * 3600) return null;
            return TimeSpan.FromSeconds(seconds.Value);
        }
    }
}

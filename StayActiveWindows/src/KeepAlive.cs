using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace StayActive
{
    /// <summary>
    /// Hält den PC aktiv:
    ///  1. SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED):
    ///     kein Ruhezustand, Bildschirm bleibt an. Gilt für den UI-Thread, solange er läuft.
    ///  2. Optionaler Maus-Impuls: 1 px relativ hin und zurück per SendInput, aber nur wenn du
    ///     gerade selbst nichts tust. Setzt den Leerlauf-Zähler zurück, den Teams für "Abwesend" nutzt.
    /// Alles ohne Administratorrechte. Muss auf dem UI-Thread benutzt werden.
    /// </summary>
    internal sealed class KeepAlive : IDisposable
    {
        private readonly Timer timer = new Timer();

        public bool IsRunning { get; private set; }

        public KeepAlive()
        {
            timer.Tick += (s, e) => Tick();
        }

        public void Start()
        {
            if (IsRunning) return;
            IsRunning = true;
            AssertAwake();
            Tick();
            ScheduleTimer();
        }

        public void Stop()
        {
            if (!IsRunning) return;
            IsRunning = false;
            timer.Stop();
            NativeMethods.SetThreadExecutionState(NativeMethods.ES_CONTINUOUS);
        }

        /// <summary>Nach Änderung des Intervalls neu planen.</summary>
        public void Reschedule()
        {
            if (IsRunning) ScheduleTimer();
        }

        /// <summary>Nach dem Aufwachen o. Ä. den Wach-Zustand erneut setzen (unschädlich, falls schon gesetzt).</summary>
        public void Reassert()
        {
            if (IsRunning) AssertAwake();
        }

        private static void AssertAwake()
        {
            NativeMethods.SetThreadExecutionState(
                NativeMethods.ES_CONTINUOUS | NativeMethods.ES_SYSTEM_REQUIRED | NativeMethods.ES_DISPLAY_REQUIRED);
        }

        private void ScheduleTimer()
        {
            timer.Stop();
            timer.Interval = Prefs.IntervalSeconds * 1000;
            timer.Start();
        }

        /// <summary>Sekunden seit der letzten echten Eingabe (Maus/Tastatur), systemweit.</summary>
        public static double IdleSeconds()
        {
            var info = new NativeMethods.LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.LASTINPUTINFO));
            if (!NativeMethods.GetLastInputInfo(ref info)) return 0;
            uint now = unchecked((uint)Environment.TickCount);
            uint idleMs = unchecked(now - info.dwTime);
            return idleMs / 1000.0;
        }

        private void Tick()
        {
            if (!IsRunning) return;
            AssertAwake();
            if (!Prefs.JiggleMouse) return;

            // Wenn du gerade selbst aktiv bist, nichts tun – kein Zucken beim Arbeiten.
            double threshold = Math.Min(Prefs.IntervalSeconds * 0.8, 50);
            if (IdleSeconds() < threshold) return;
            NudgeMouse();
        }

        /// <summary>Bewegt den Mauszeiger relativ um 1 px nach rechts und sofort wieder zurück.</summary>
        public static void NudgeMouse()
        {
            var inputs = new NativeMethods.INPUT[2];
            inputs[0].type = NativeMethods.INPUT_MOUSE;
            inputs[0].U.mi.dx = 1;
            inputs[0].U.mi.dwFlags = NativeMethods.MOUSEEVENTF_MOVE;
            inputs[1].type = NativeMethods.INPUT_MOUSE;
            inputs[1].U.mi.dx = -1;
            inputs[1].U.mi.dwFlags = NativeMethods.MOUSEEVENTF_MOVE;
            // Liefert 0, wenn Windows die Eingabe blockiert (z. B. gesperrter Bildschirm). Dann einfach beim nächsten Mal.
            NativeMethods.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(NativeMethods.INPUT)));
        }

        public void Dispose()
        {
            Stop();
            timer.Dispose();
        }
    }
}

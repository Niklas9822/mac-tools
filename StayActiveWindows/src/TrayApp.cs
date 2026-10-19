using System;
using System.Drawing;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace StayActive
{
    /// <summary>
    /// Die eigentliche App: Tassen-Symbol im Infobereich (Tray), Menü wie in der macOS-Version
    /// ("Starten für …", Verlängern, Optionen), Restzeit im Symbol und im Tooltip, Bestätigungen.
    /// Kein Hauptfenster (ApplicationContext).
    /// </summary>
    internal sealed class TrayApp : ApplicationContext
    {
        private const string PresetUnlimited = "unlimited";
        private const string PresetWorkEnd = "workEnd";
        private const string PresetUntil = "until";
        private const string PresetCustom = "custom";

        private static readonly int[] DurationMinutes = { 15, 30, 60, 120, 240, 480 };
        private static readonly int[] IntervalValues = { 30, 60, 120, 240 };
        private static readonly string[] IntervalTitles = { "30 Sekunden", "1 Minute", "2 Minuten", "4 Minuten" };

        private readonly SynchronizationContext ui;
        private readonly KeepAlive keepAlive = new KeepAlive();
        private readonly NotifyIcon notifyIcon = new NotifyIcon();
        private readonly ContextMenuStrip menu = new ContextMenuStrip();
        private readonly System.Windows.Forms.Timer uiTimer = new System.Windows.Forms.Timer { Interval = 1000 };
        private readonly System.Windows.Forms.Timer clickTimer = new System.Windows.Forms.Timer();
        private readonly Font boldFont;

        private ToolStripMenuItem headerItem;
        private bool menuOpen;
        private bool dialogOpen;
        private bool exited;
        private OwnedIcon currentIcon;
        private string currentIconKey;

        private static string PresetForMinutes(int minutes)
        {
            return "d" + minutes;
        }

        public TrayApp()
        {
            // Das Menü (ein Control) installiert den WinForms-SynchronizationContext; sicherheitshalber explizit.
            if (!(SynchronizationContext.Current is WindowsFormsSynchronizationContext))
                SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
            ui = SynchronizationContext.Current;

            boldFont = new Font(menu.Font, FontStyle.Bold);
            menu.Opening += (s, e) =>
            {
                BuildMenu();
                e.Cancel = false;
                menuOpen = true;
                UpdateUiTimer();
            };
            menu.Closed += (s, e) =>
            {
                menuOpen = false;
                headerItem = null;
                UpdateUiTimer();
            };

            notifyIcon.ContextMenuStrip = menu; // Rechtsklick öffnet das Menü automatisch.
            notifyIcon.MouseClick += OnNotifyIconClick;
            notifyIcon.MouseDoubleClick += OnNotifyIconDoubleClick;

            // Linksklick: Menü erst nach der Doppelklick-Zeit öffnen, damit ein Doppelklick umschalten kann.
            clickTimer.Interval = Math.Max(100, SystemInformation.DoubleClickTime);
            clickTimer.Tick += (s, e) =>
            {
                clickTimer.Stop();
                ShowMenu();
            };

            uiTimer.Tick += (s, e) => Tick();

            SystemEvents.PowerModeChanged += OnPowerModeChanged;
            SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;

            Autostart.RepairPathIfMoved();
            bool firstRun = !Prefs.FirstRunDone;
            RestoreState();
            BuildMenu();
            RefreshUi();
            notifyIcon.Visible = true;

            if (firstRun)
            {
                Prefs.FirstRunDone = true;
                notifyIcon.ShowBalloonTip(8000, "StayActive läuft",
                    (keepAlive.IsRunning ? "Aktiv – PC bleibt wach. " : "") +
                    "Das Tassen-Symbol findest du unten rechts im Infobereich (ggf. hinter dem Pfeil ^). " +
                    "Klick öffnet das Menü, Doppelklick schaltet ein/aus.",
                    ToolTipIcon.None);
            }
        }

        /// <summary>Zustand nach Neustart wiederherstellen: laufender Zeitraum läuft weiter, abgelaufener ist aus.</summary>
        private void RestoreState()
        {
            DateTime? end = Prefs.EndUtc;
            if (end.HasValue)
            {
                if (Prefs.Enabled && end.Value > DateTime.UtcNow)
                {
                    keepAlive.Start();
                    return;
                }
                ClearPeriod();
                Prefs.Enabled = false;
            }
            if (Prefs.Enabled || Prefs.ActivateOnLaunch)
            {
                Prefs.Enabled = true;
                if (Prefs.Preset == null) Prefs.Preset = PresetUnlimited;
                keepAlive.Start();
            }
        }

        private static void ClearPeriod()
        {
            Prefs.EndUtc = null;
            Prefs.StartUtc = null;
            Prefs.Preset = null;
        }

        // MARK: Systemereignisse

        private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
        {
            if (e.Mode != PowerModes.Resume) return;
            // Nach dem Aufwachen: Ablauf prüfen und Wach-Zustand erneut setzen.
            ui.Post(_ =>
            {
                if (exited) return;
                keepAlive.Reassert();
                Tick();
            }, null);
        }

        private void OnDisplaySettingsChanged(object sender, EventArgs e)
        {
            ui.Post(_ =>
            {
                if (exited) return;
                currentIconKey = null; // Symbol in neuer Größe zeichnen
                UpdateIcon();
            }, null);
        }

        // MARK: Klicks auf das Symbol

        private void OnNotifyIconClick(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            clickTimer.Stop();
            clickTimer.Start();
        }

        private void OnNotifyIconDoubleClick(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            clickTimer.Stop();
            if (keepAlive.IsRunning) Deactivate(false);
            else Activate(null, PresetUnlimited);
        }

        /// <summary>
        /// Öffnet das Kontextmenü wie beim Rechtsklick. NotifyIcon.ShowContextMenu ist privat, setzt aber
        /// vorher das Vordergrundfenster – sonst schließt das Menü nicht beim Klick daneben.
        /// </summary>
        private void ShowMenu()
        {
            MethodInfo show = typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic);
            if (show != null) show.Invoke(notifyIcon, null);
            else menu.Show(Cursor.Position);
        }

        // MARK: Restzeit / Aktualisieren

        /// <summary>Restzeit, falls ein Zeitraum läuft (null = aus oder unbegrenzt).</summary>
        private TimeSpan? Remaining()
        {
            if (!keepAlive.IsRunning) return null;
            DateTime? end = Prefs.EndUtc;
            if (!end.HasValue) return null;
            TimeSpan rem = end.Value - DateTime.UtcNow;
            return rem < TimeSpan.Zero ? TimeSpan.Zero : rem;
        }

        private void Tick()
        {
            DateTime? end = Prefs.EndUtc;
            if (keepAlive.IsRunning && end.HasValue && end.Value <= DateTime.UtcNow)
                Deactivate(true);
            else
                RefreshUi();
        }

        private void RefreshUi()
        {
            UpdateIcon();
            UpdateTooltip();
            UpdateHeader();
            UpdateUiTimer();
        }

        /// <summary>Sekunden-Takt nur, solange ein Zeitraum läuft oder das Menü offen ist.</summary>
        private void UpdateUiTimer()
        {
            bool needed = Remaining().HasValue || menuOpen;
            if (needed && !uiTimer.Enabled) uiTimer.Start();
            else if (!needed && uiTimer.Enabled) uiTimer.Stop();
        }

        private void UpdateIcon()
        {
            bool active = keepAlive.IsRunning;
            TimeSpan? rem = Remaining();
            string badge = Prefs.ShowCountdown && rem.HasValue ? TimeText.Badge(rem.Value) : null;
            int size = Math.Max(16, SystemInformation.SmallIconSize.Width);
            string key = active + "|" + badge + "|" + size;
            if (key == currentIconKey) return;

            OwnedIcon next = IconRenderer.Create(size, active, badge);
            notifyIcon.Icon = next.Icon;
            if (currentIcon != null) currentIcon.Dispose(); // altes HICON freigeben
            currentIcon = next;
            currentIconKey = key;
        }

        private void UpdateTooltip()
        {
            string text;
            TimeSpan? rem = Remaining();
            if (!keepAlive.IsRunning) text = "StayActive: aus – PC darf schlafen";
            else if (rem.HasValue) text = "StayActive: aktiv bis " + TimeText.Clock(Prefs.EndUtc.Value) + " (noch " + TimeText.Short(rem.Value) + ")";
            else text = "StayActive: aktiv – unbegrenzt";
            // NotifyIcon.Text erlaubt unter .NET Framework höchstens 63 Zeichen (sonst Ausnahme).
            notifyIcon.Text = text.Length > 63 ? text.Substring(0, 63) : text;
        }

        private string HeaderText()
        {
            if (!keepAlive.IsRunning) return "Aus – PC darf schlafen";
            TimeSpan? rem = Remaining();
            if (!rem.HasValue) return "Aktiv – unbegrenzt";
            return "Aktiv – noch " + TimeText.Long(rem.Value) + " (bis " + TimeText.Clock(Prefs.EndUtc.Value) + ")";
        }

        private void UpdateHeader()
        {
            if (headerItem != null) headerItem.Text = HeaderText();
        }

        // MARK: Ein / Aus

        private void Activate(DateTime? endUtc, string preset)
        {
            Prefs.Enabled = true;
            Prefs.EndUtc = endUtc;
            Prefs.StartUtc = endUtc.HasValue ? DateTime.UtcNow : (DateTime?)null;
            Prefs.Preset = preset;
            keepAlive.Start();
            RefreshUi();
            if (endUtc.HasValue)
                Confirm("Aktiv für " + TimeText.Long(endUtc.Value - DateTime.UtcNow) + " – bis " + TimeText.Clock(endUtc.Value));
            else
                Confirm("Aktiv – unbegrenzt");
        }

        private void Deactivate(bool expired)
        {
            Prefs.Enabled = false;
            ClearPeriod();
            keepAlive.Stop();
            RefreshUi();
            Confirm(expired ? "StayActive aus – PC darf wieder schlafen" : "Ausgeschaltet – PC darf schlafen");
        }

        /// <summary>Kurze Bestätigung als Benachrichtigung (unter Windows 10/11 als Toast, keine Berechtigung nötig).</summary>
        private void Confirm(string text)
        {
            if (!Prefs.ShowBalloon) return;
            notifyIcon.ShowBalloonTip(3000, "StayActive", text, ToolTipIcon.None);
        }

        // MARK: Menü

        private void BuildMenu()
        {
            DisposeItems(menu.Items);
            bool running = keepAlive.IsRunning;
            bool timed = Remaining().HasValue;

            // Kopfzeile: Status (fett, nicht anklickbar), wird bei offenem Menü sekündlich aktualisiert.
            headerItem = new ToolStripMenuItem(HeaderText()) { Enabled = false, Font = boldFont };
            menu.Items.Add(headerItem);
            menu.Items.Add(new ToolStripSeparator());

            // Schnellaktionen
            if (running)
            {
                menu.Items.Add(Item("Jetzt ausschalten", () => Deactivate(false)));
                if (timed) menu.Items.Add(Item("Verlängern um 30 Min.", Extend30));
            }
            else
            {
                menu.Items.Add(Item("Jetzt aktivieren (unbegrenzt)", () => Activate(null, PresetUnlimited)));
            }

            // Starten für …
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Starten für …") { Enabled = false });

            menu.Items.Add(Check("Unbegrenzt", IsPreset(PresetUnlimited), () => Activate(null, PresetUnlimited)));

            foreach (int minutes in DurationMinutes)
            {
                int m = minutes;
                menu.Items.Add(Check(TimeText.Long(TimeSpan.FromMinutes(m)), IsPreset(PresetForMinutes(m)),
                    () => Activate(DateTime.UtcNow.AddMinutes(m), PresetForMinutes(m))));
            }

            string workEndText = TimeText.ClockMinutes(Prefs.WorkEndMinutes);
            ToolStripMenuItem workEnd = Check("Bis Feierabend (" + workEndText + ")", IsPreset(PresetWorkEnd), StartUntilWorkEnd);
            if (WorkEndUtc() == null)
            {
                workEnd.Text = "Bis Feierabend (" + workEndText + " – schon vorbei)";
                workEnd.Enabled = false;
            }
            menu.Items.Add(workEnd);

            menu.Items.Add(Check("Bis Uhrzeit …", IsPreset(PresetUntil), () => Later(StartUntilTime)));
            menu.Items.Add(Check("Eigene Dauer …", IsPreset(PresetCustom), () => Later(StartCustomDuration)));

            // Optionen
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(BuildOptionsMenu());

            menu.Items.Add(new ToolStripSeparator());
            // Erst nach dem Klick-Ereignis beenden, sonst würde das Menü während seines eigenen Ereignisses entsorgt.
            menu.Items.Add(Item("StayActive beenden", () => ui.Post(_ => ExitThread(), null)));
        }

        private ToolStripMenuItem BuildOptionsMenu()
        {
            var options = new ToolStripMenuItem("Optionen");
            ToolStripItemCollection items = options.DropDownItems;

            items.Add(Check("Maus-Impuls (Teams-Status)", Prefs.JiggleMouse, () =>
            {
                Prefs.JiggleMouse = !Prefs.JiggleMouse;
            }));

            var interval = new ToolStripMenuItem("Impuls-Intervall");
            for (int i = 0; i < IntervalValues.Length; i++)
            {
                int value = IntervalValues[i];
                interval.DropDownItems.Add(Check(IntervalTitles[i], Prefs.IntervalSeconds == value, () =>
                {
                    Prefs.IntervalSeconds = value;
                    keepAlive.Reschedule();
                }));
            }
            items.Add(interval);

            items.Add(new ToolStripSeparator());
            items.Add(Item("Feierabend-Zeit (" + TimeText.ClockMinutes(Prefs.WorkEndMinutes) + ") ändern …",
                () => Later(ChangeWorkEnd)));
            items.Add(Check("Restzeit im Symbol anzeigen", Prefs.ShowCountdown, () =>
            {
                Prefs.ShowCountdown = !Prefs.ShowCountdown;
                RefreshUi();
            }));
            items.Add(Check("Bestätigung einblenden", Prefs.ShowBalloon, () =>
            {
                Prefs.ShowBalloon = !Prefs.ShowBalloon;
            }));

            items.Add(new ToolStripSeparator());
            items.Add(Check("Beim Start automatisch aktivieren", Prefs.ActivateOnLaunch, () =>
            {
                Prefs.ActivateOnLaunch = !Prefs.ActivateOnLaunch;
            }));
            items.Add(Check("Mit Windows starten", Autostart.IsEnabled, () => Later(ToggleAutostart)));

            items.Add(new ToolStripSeparator());
            items.Add(Item("Info …", () => Later(ShowInfo)));
            items.Add(new ToolStripMenuItem("Tipp: Doppelklick auf die Tasse schaltet direkt um") { Enabled = false });
            return options;
        }

        private bool IsPreset(string preset)
        {
            return keepAlive.IsRunning && Prefs.Preset == preset;
        }

        private static ToolStripMenuItem Item(string text, Action action)
        {
            var item = new ToolStripMenuItem(text);
            item.Click += (s, e) => action();
            return item;
        }

        private static ToolStripMenuItem Check(string text, bool isChecked, Action action)
        {
            ToolStripMenuItem item = Item(text, action);
            item.Checked = isChecked;
            return item;
        }

        private static void DisposeItems(ToolStripItemCollection items)
        {
            ToolStripItem[] old = new ToolStripItem[items.Count];
            items.CopyTo(old, 0);
            items.Clear();
            foreach (ToolStripItem item in old) item.Dispose();
        }

        /// <summary>Dialoge erst nach dem Schließen des Menüs öffnen, und nie zwei gleichzeitig.</summary>
        private void Later(Action action)
        {
            ui.Post(_ =>
            {
                if (exited || dialogOpen) return;
                dialogOpen = true;
                try
                {
                    action();
                }
                finally
                {
                    dialogOpen = false;
                }
            }, null);
        }

        /// <summary>Heutiger Feierabend (UTC), oder null wenn er schon (fast) vorbei ist.</summary>
        private static DateTime? WorkEndUtc()
        {
            DateTime local = DateTime.Today.AddMinutes(Prefs.WorkEndMinutes);
            if (local <= DateTime.Now.AddMinutes(1)) return null;
            return local.ToUniversalTime();
        }

        // MARK: Aktionen

        private void StartUntilWorkEnd()
        {
            DateTime? end = WorkEndUtc();
            if (end.HasValue) Activate(end, PresetWorkEnd);
        }

        private void Extend30()
        {
            DateTime? end = Prefs.EndUtc;
            if (!keepAlive.IsRunning || !end.HasValue) return;
            DateTime now = DateTime.UtcNow;
            DateTime newEnd = (end.Value > now ? end.Value : now).AddMinutes(30);
            Prefs.EndUtc = newEnd;
            Prefs.Preset = null;
            RefreshUi();
            Confirm("Verlängert – jetzt bis " + TimeText.Clock(newEnd));
        }

        private void StartUntilTime()
        {
            DateTime initial = (Prefs.EndUtc ?? DateTime.UtcNow.AddHours(1)).ToLocalTime();
            DateTime? picked = Dialogs.AskTime("Aktiv lassen bis …",
                "Bis wann soll der PC wach bleiben?\nLiegt die Uhrzeit heute schon hinter dir, gilt sie für morgen.",
                initial);
            if (!picked.HasValue) return;
            DateTime end = DateTime.Today.AddHours(picked.Value.Hour).AddMinutes(picked.Value.Minute);
            if (end <= DateTime.Now) end = end.AddDays(1);
            Activate(end.ToUniversalTime(), PresetUntil);
        }

        private void StartCustomDuration()
        {
            string input = Dialogs.AskText("Eigene Dauer",
                "Wie lange soll der PC wach bleiben?\nMinuten (90), Std:Min (1:30) oder Stunden (2h).",
                "z. B. 90, 1:30 oder 2h");
            if (input == null) return;
            TimeSpan? duration = TimeText.ParseDuration(input);
            if (!duration.HasValue)
            {
                Dialogs.Message("Dauer nicht erkannt.\n\nBitte z. B. „90“, „1:30“ oder „2h“ eingeben " +
                                "(mindestens 1 Minute, höchstens 7 Tage).", MessageBoxIcon.Warning);
                return;
            }
            Activate(DateTime.UtcNow.Add(duration.Value), PresetCustom);
        }

        private void ChangeWorkEnd()
        {
            DateTime initial = DateTime.Today.AddMinutes(Prefs.WorkEndMinutes);
            DateTime? picked = Dialogs.AskTime("Feierabend-Zeit", "Wird für „Bis Feierabend“ im Menü verwendet.", initial);
            if (!picked.HasValue) return;
            Prefs.WorkEndMinutes = picked.Value.Hour * 60 + picked.Value.Minute;
        }

        private void ToggleAutostart()
        {
            bool enable = !Autostart.IsEnabled;
            try
            {
                Autostart.SetEnabled(enable);
            }
            catch (Exception ex)
            {
                Dialogs.Message("Autostart konnte nicht geändert werden.\n\n" + ex.Message, MessageBoxIcon.Warning);
                return;
            }
            Confirm(enable ? "Startet jetzt automatisch mit Windows" : "Startet nicht mehr mit Windows");
        }

        private void ShowInfo()
        {
            Version v = Assembly.GetExecutingAssembly().GetName().Version;
            Dialogs.Message(
                "StayActive für Windows – Version " + v.ToString(3) + "\n\n" +
                "Hält den PC wach und den Teams-Status grün – unbegrenzt oder mit Timer.\n" +
                "Keine Installation, keine Administratorrechte.\n\n" +
                "Einstellungen: HKEY_CURRENT_USER\\Software\\StayActive\n" +
                "Programm: " + Application.ExecutablePath + "\n\n" +
                "https://github.com/Niklas9822/mac-tools",
                MessageBoxIcon.Information);
        }

        // MARK: Beenden

        protected override void ExitThreadCore()
        {
            Cleanup();
            base.ExitThreadCore();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) Cleanup();
            base.Dispose(disposing);
        }

        /// <summary>
        /// Wach-Zustand aufheben (ES_CONTINUOUS), Symbol entfernen, Handles freigeben.
        /// Enabled/EndUtc bleiben gespeichert, damit ein Neustart den Zeitraum fortsetzt (wie auf dem Mac).
        /// </summary>
        private void Cleanup()
        {
            if (exited) return;
            exited = true;
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
            uiTimer.Stop();
            clickTimer.Stop();
            keepAlive.Dispose();
            notifyIcon.Visible = false;
            notifyIcon.Dispose();
            DisposeItems(menu.Items);
            menu.Dispose();
            uiTimer.Dispose();
            clickTimer.Dispose();
            if (currentIcon != null) currentIcon.Dispose();
            currentIcon = null;
            boldFont.Dispose();
        }
    }
}

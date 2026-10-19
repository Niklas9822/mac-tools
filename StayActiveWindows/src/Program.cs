using System;
using System.Threading;
using System.Windows.Forms;

namespace StayActive
{
    internal static class Program
    {
        // "Local\": eine Instanz pro angemeldetem Benutzer (Sitzung).
        private const string MutexName = @"Local\StayActive-Niklas9822-mac-tools";

        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            bool createdNew;
            using (var mutex = new Mutex(true, MutexName, out createdNew))
            {
                if (!createdNew)
                {
                    MessageBox.Show(
                        "StayActive läuft bereits.\n\nDas Tassen-Symbol findest du unten rechts im Infobereich " +
                        "der Taskleiste (ggf. hinter dem Pfeil ^).",
                        "StayActive", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException += (s, e) => ShowError(e.Exception);

                using (var app = new TrayApp())
                {
                    Application.Run(app);
                }
                GC.KeepAlive(mutex);
            }
        }

        private static bool showingError;

        private static void ShowError(Exception ex)
        {
            if (showingError) return;
            showingError = true;
            try
            {
                MessageBox.Show("Unerwarteter Fehler – StayActive läuft weiter.\n\n" + ex.Message,
                    "StayActive", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            finally
            {
                showingError = false;
            }
        }
    }
}

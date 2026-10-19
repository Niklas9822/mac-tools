using System;
using System.Drawing;
using System.Windows.Forms;

namespace StayActive
{
    /// <summary>Kleine Dialoge (Uhrzeit wählen, Dauer eingeben, Meldungen). Immer im Vordergrund, da es kein Hauptfenster gibt.</summary>
    internal static class Dialogs
    {
        /// <summary>Uhrzeit (Std:Min) wählen. Gibt null zurück bei "Abbrechen".</summary>
        public static DateTime? AskTime(string title, string info, DateTime initialLocal)
        {
            using (Form form = CreateForm(title))
            {
                var picker = new DateTimePicker
                {
                    Format = DateTimePickerFormat.Custom,
                    CustomFormat = "HH:mm",
                    ShowUpDown = true,
                    Value = initialLocal,
                };
                picker.Width = form.Font.Height * 6;
                Build(form, info, picker);
                return form.ShowDialog() == DialogResult.OK ? picker.Value : (DateTime?)null;
            }
        }

        /// <summary>Text eingeben (mit grauem Platzhalter). Gibt null zurück bei "Abbrechen".</summary>
        public static string AskText(string title, string info, string placeholder)
        {
            using (Form form = CreateForm(title))
            {
                var box = new TextBox();
                box.Width = form.Font.Height * 16;
                box.HandleCreated += (s, e) =>
                    NativeMethods.SendMessage(box.Handle, NativeMethods.EM_SETCUEBANNER, (IntPtr)1, placeholder);
                Build(form, info, box);
                return form.ShowDialog() == DialogResult.OK ? box.Text : null;
            }
        }

        /// <summary>Meldung, die garantiert vorne erscheint (über einem unsichtbaren, obersten Hilfsfenster).</summary>
        public static void Message(string text, MessageBoxIcon icon)
        {
            using (var owner = new Form
            {
                ShowInTaskbar = false,
                FormBorderStyle = FormBorderStyle.None,
                StartPosition = FormStartPosition.CenterScreen,
                Size = new Size(1, 1),
                Opacity = 0,
                TopMost = true,
            })
            {
                owner.Show();
                owner.Activate();
                MessageBox.Show(owner, text, "StayActive", MessageBoxButtons.OK, icon);
            }
        }

        private static Form CreateForm(string title)
        {
            return new Form
            {
                Text = title,
                Font = SystemFonts.MessageBoxFont,
                AutoScaleMode = AutoScaleMode.None,
                FormBorderStyle = FormBorderStyle.FixedDialog,
                MaximizeBox = false,
                MinimizeBox = false,
                ShowIcon = false,
                ShowInTaskbar = false,
                StartPosition = FormStartPosition.CenterScreen,
                TopMost = true,
            };
        }

        /// <summary>Aufbau: Hinweistext, Eingabefeld, Knöpfe "OK" / "Abbrechen". Abstände wachsen mit der Schriftgröße (DPI).</summary>
        private static void Build(Form form, string info, Control input)
        {
            int unit = Math.Max(4, form.Font.Height / 2);
            int pad = unit * 2;

            var layout = new TableLayoutPanel
            {
                ColumnCount = 1,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Location = new Point(pad, pad),
                Margin = Padding.Empty,
            };

            var label = new Label
            {
                Text = info,
                AutoSize = true,
                MaximumSize = new Size(form.Font.Height * 22, 0),
                Margin = new Padding(0, 0, 0, unit * 2),
            };
            input.Margin = new Padding(0, 0, 0, unit * 3);
            input.Anchor = AnchorStyles.Left;

            var ok = new Button { Text = "OK", DialogResult = DialogResult.OK, AutoSize = true };
            var cancel = new Button { Text = "Abbrechen", DialogResult = DialogResult.Cancel, AutoSize = true };
            ok.MinimumSize = cancel.MinimumSize = new Size(form.Font.Height * 5, 0);
            ok.Margin = new Padding(unit, 0, 0, 0);
            cancel.Margin = new Padding(unit, 0, 0, 0);

            var buttons = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.RightToLeft,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Dock = DockStyle.Fill,
                Margin = Padding.Empty,
                WrapContents = false,
            };
            buttons.Controls.Add(cancel);
            buttons.Controls.Add(ok);

            layout.Controls.Add(label);
            layout.Controls.Add(input);
            layout.Controls.Add(buttons);
            form.Controls.Add(layout);

            // Fenstergröße aus dem Inhalt berechnen (unabhängig von der DPI-Einstellung).
            Size preferred = layout.GetPreferredSize(Size.Empty);
            layout.Size = preferred;
            form.ClientSize = new Size(preferred.Width + 2 * pad, preferred.Height + 2 * pad);

            form.AcceptButton = ok;
            form.CancelButton = cancel;

            form.Shown += (s, e) =>
            {
                form.Activate();
                input.Focus();
            };
        }
    }
}

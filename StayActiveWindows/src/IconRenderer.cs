using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace StayActive
{
    /// <summary>Ein zur Laufzeit erzeugtes Icon, dessen HICON beim Dispose freigegeben wird (sonst Handle-Leck).</summary>
    internal sealed class OwnedIcon : IDisposable
    {
        private IntPtr handle;

        public Icon Icon { get; private set; }

        public OwnedIcon(IntPtr hIcon)
        {
            handle = hIcon;
            Icon = Icon.FromHandle(hIcon);
        }

        public void Dispose()
        {
            if (Icon != null)
            {
                Icon.Dispose();
                Icon = null;
            }
            if (handle != IntPtr.Zero)
            {
                NativeMethods.DestroyIcon(handle);
                handle = IntPtr.Zero;
            }
        }
    }

    /// <summary>
    /// Zeichnet das Tassen-Symbol mit GDI+:
    ///  - aus:   graue Umriss-Tasse
    ///  - aktiv: gefüllte, farbige Tasse mit Dampf
    ///  - Timer: zusätzlich ein grünes Feld mit der Restzeit ("45", "2h", "&lt;1")
    /// Gleiche Geometrie wie tools/make_icon.py (Programm-Symbol der .exe).
    /// </summary>
    internal static class IconRenderer
    {
        private static readonly Color OffColor = Color.FromArgb(255, 140, 140, 140);
        private static readonly Color CupFill = Color.FromArgb(255, 242, 163, 58);
        private static readonly Color CupLine = Color.FromArgb(255, 217, 130, 43);
        private static readonly Color BadgeFill = Color.FromArgb(255, 30, 142, 62);

        public static OwnedIcon Create(int size, bool active, string badge)
        {
            using (var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.Transparent);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.CompositingQuality = CompositingQuality.HighQuality;
                    Draw(g, size, active, badge);
                }
                return new OwnedIcon(bmp.GetHicon());
            }
        }

        private static void Draw(Graphics g, int size, bool active, string badge)
        {
            float s = size;
            if (string.IsNullOrEmpty(badge))
            {
                DrawCup(g, new RectangleF(0, 0, s, s), active, s);
                return;
            }

            // Mit Restzeit: Tasse klein oben (Dampf + Rand sichtbar), darunter das Zahlenfeld.
            DrawCup(g, new RectangleF(s * 0.16f, -s * 0.02f, s * 0.64f, s * 0.64f), active, s);
            var badgeRect = new RectangleF(0, s * 0.40f, s, s * 0.60f);
            using (GraphicsPath path = RoundedRect(badgeRect, s * 0.16f))
            using (var brush = new SolidBrush(BadgeFill))
            {
                g.FillPath(brush, path);
            }
            DrawText(g, badge, RectangleF.Inflate(badgeRect, -s * 0.05f, -s * 0.07f));
        }

        /// <summary>Tasse in einem quadratischen Bereich; Koordinaten relativ (0…1).</summary>
        private static void DrawCup(Graphics g, RectangleF a, bool active, float iconSize)
        {
            Func<float, float> X = v => a.X + v * a.Width;
            Func<float, float> Y = v => a.Y + v * a.Height;
            float stroke = Math.Max(1f, iconSize / 14f);
            Color line = active ? CupLine : OffColor;

            using (var body = new GraphicsPath())
            {
                body.AddLine(X(0.10f), Y(0.36f), X(0.68f), Y(0.36f));
                body.AddBezier(X(0.68f), Y(0.36f), X(0.68f), Y(0.66f), X(0.62f), Y(0.84f), X(0.52f), Y(0.84f));
                body.AddLine(X(0.52f), Y(0.84f), X(0.26f), Y(0.84f));
                body.AddBezier(X(0.26f), Y(0.84f), X(0.16f), Y(0.84f), X(0.10f), Y(0.66f), X(0.10f), Y(0.36f));
                body.CloseFigure();

                using (var pen = new Pen(line, stroke) { LineJoin = LineJoin.Round })
                {
                    if (active)
                    {
                        using (var brush = new SolidBrush(CupFill)) g.FillPath(brush, body);
                    }
                    g.DrawPath(pen, body);

                    // Henkel
                    g.DrawArc(pen, X(0.56f), Y(0.43f), a.Width * 0.28f, a.Height * 0.26f, 270, 180);
                }
            }

            // Untertasse
            using (var pen = new Pen(line, stroke * 1.15f) { StartCap = LineCap.Round, EndCap = LineCap.Round })
            {
                g.DrawLine(pen, X(0.04f), Y(0.94f), X(0.84f), Y(0.94f));
            }

            // Dampf nur, wenn aktiv
            if (active)
            {
                using (var pen = new Pen(line, Math.Max(1f, stroke * 0.9f)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                {
                    foreach (float x in new[] { 0.30f, 0.48f })
                    {
                        g.DrawBezier(pen, X(x), Y(0.28f), X(x - 0.07f), Y(0.20f), X(x + 0.07f), Y(0.14f), X(x), Y(0.05f));
                    }
                }
            }
        }

        /// <summary>Text als Pfad, so groß wie möglich in den Bereich eingepasst (weiß, fett).</summary>
        private static void DrawText(Graphics g, string text, RectangleF target)
        {
            using (var path = new GraphicsPath())
            using (FontFamily family = PickFamily())
            {
                path.AddString(text, family, (int)FontStyle.Bold, 100f, PointF.Empty, StringFormat.GenericTypographic);
                RectangleF b = path.GetBounds();
                if (b.Width <= 0 || b.Height <= 0) return;
                float scale = Math.Min(target.Width / b.Width, target.Height / b.Height);
                using (var m = new Matrix())
                {
                    m.Translate(target.X + (target.Width - b.Width * scale) / 2f,
                                target.Y + (target.Height - b.Height * scale) / 2f);
                    m.Scale(scale, scale);
                    m.Translate(-b.X, -b.Y);
                    path.Transform(m);
                }
                g.FillPath(Brushes.White, path);
            }
        }

        private static FontFamily PickFamily()
        {
            try
            {
                return new FontFamily("Segoe UI");
            }
            catch (ArgumentException)
            {
                return new FontFamily(System.Drawing.Text.GenericFontFamilies.SansSerif);
            }
        }

        private static GraphicsPath RoundedRect(RectangleF r, float radius)
        {
            float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
            var path = new GraphicsPath();
            path.AddArc(r.X, r.Y, d, d, 180, 90);
            path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }
}

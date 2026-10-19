#!/usr/bin/env python3
"""Erzeugt StayActive.ico (Programm-Symbol der .exe) – aktive, gefüllte Tasse mit Dampf.

Gleiche Geometrie wie src/IconRenderer.cs (Tray-Symbol zur Laufzeit). Nur nötig, wenn sich das
Aussehen ändert; die fertige .ico liegt im Repo, damit der Build keine Python-Abhängigkeit hat.

    pip install pillow
    python3 StayActiveWindows/tools/make_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

SS = 4  # Supersampling-Faktor für glatte Kanten
CUP_FILL = (242, 163, 58, 255)
CUP_LINE = (217, 130, 43, 255)


def bezier(p0, p1, p2, p3, steps=40):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        pts.append((
            u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
        ))
    return pts


def stroke(d, pts, color, width):
    """Linienzug mit runden Ecken und Enden (Kreise an jedem Punkt)."""
    d.line(pts, fill=color, width=int(round(width)))
    r = width / 2
    for x, y in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def render(size: int) -> Image.Image:
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def P(x, y):
        return (x * s, y * s)

    stroke_w = max(1.0, size / 14) * SS
    w = int(round(stroke_w))

    body = [P(0.10, 0.36), P(0.68, 0.36)]
    body += bezier(P(0.68, 0.36), P(0.68, 0.66), P(0.62, 0.84), P(0.52, 0.84))
    body += [P(0.26, 0.84)]
    body += bezier(P(0.26, 0.84), P(0.16, 0.84), P(0.10, 0.66), P(0.10, 0.36))
    d.polygon(body, fill=CUP_FILL)
    stroke(d, body + [body[0]], CUP_LINE, stroke_w)

    # Henkel: rechte Hälfte einer Ellipse (270° … 90°)
    d.arc([P(0.56, 0.43), P(0.84, 0.69)], start=270, end=90, fill=CUP_LINE, width=w)

    # Untertasse
    stroke(d, [P(0.04, 0.94), P(0.84, 0.94)], CUP_LINE, stroke_w * 1.15)

    # Dampf
    steam_w = max(1.0, size / 14 * 0.9) * SS
    for x in (0.30, 0.48):
        pts = bezier(P(x, 0.28), P(x - 0.07, 0.20), P(x + 0.07, 0.14), P(x, 0.05))
        stroke(d, pts, CUP_LINE, steam_w)

    return img.resize((size, size), Image.LANCZOS)


def main():
    out = Path(__file__).resolve().parent.parent / "StayActive.ico"
    sizes = [16, 20, 24, 32, 40, 48, 64, 256]
    images = [render(n) for n in sizes]
    images[-1].save(out, format="ICO", sizes=[(n, n) for n in sizes], append_images=images[:-1])
    print(f"geschrieben: {out}")


if __name__ == "__main__":
    main()

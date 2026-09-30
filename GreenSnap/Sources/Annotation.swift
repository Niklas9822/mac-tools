import Cocoa

enum Tool: Int, CaseIterable {
    case select, rectangle, ellipse, line, arrow, freehand, text, highlight, pixelate, counter, crop

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .freehand: return "scribble"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .pixelate: return "mosaic"
        case .counter: return "1.circle"
        case .crop: return "crop"
        }
    }

    var title: String {
        switch self {
        case .select: return "Auswählen / Verschieben (V)"
        case .rectangle: return "Rechteck (R)"
        case .ellipse: return "Ellipse (E)"
        case .line: return "Linie (L)"
        case .arrow: return "Pfeil (A)"
        case .freehand: return "Freihand (F)"
        case .text: return "Text (T)"
        case .highlight: return "Hervorheben (H)"
        case .pixelate: return "Unkenntlich machen (O)"
        case .counter: return "Nummerierung (N)"
        case .crop: return "Zuschneiden (C)"
        }
    }

    var shortcutKey: String {
        switch self {
        case .select: return "v"
        case .rectangle: return "r"
        case .ellipse: return "e"
        case .line: return "l"
        case .arrow: return "a"
        case .freehand: return "f"
        case .text: return "t"
        case .highlight: return "h"
        case .pixelate: return "o"
        case .counter: return "n"
        case .crop: return "c"
        }
    }

    var annotationKind: Annotation.Kind? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .arrow: return .arrow
        case .freehand: return .freehand
        case .text: return .text
        case .highlight: return .highlight
        case .pixelate: return .pixelate
        case .counter: return .counter
        case .select, .crop: return nil
        }
    }
}

/// Eine Markierung auf dem Bild. Koordinaten in Bildpunkten, Ursprung oben links.
struct Annotation {
    enum Kind { case rectangle, ellipse, line, arrow, freehand, text, highlight, pixelate, counter }

    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var text: String = ""
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat
    var filled: Bool

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    var isRectLike: Bool { [.rectangle, .ellipse, .highlight, .pixelate].contains(kind) }

    var font: NSFont { NSFont.systemFont(ofSize: fontSize, weight: .semibold) }

    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    var counterRadius: CGFloat { fontSize * 0.75 + 4 }

    static let textPadding: CGFloat = 6

    /// Umriss für Auswahl und Trefferprüfung.
    var bounds: CGRect {
        switch kind {
        case .rectangle, .ellipse, .highlight, .pixelate:
            return rect
        case .line, .arrow:
            return rect.insetBy(dx: -lineWidth * 3, dy: -lineWidth * 3)
        case .freehand:
            guard let first = points.first else { return .zero }
            var r = CGRect(origin: first, size: .zero)
            for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
            return r.insetBy(dx: -lineWidth, dy: -lineWidth)
        case .text:
            let size = NSAttributedString(string: text.isEmpty ? " " : text, attributes: textAttributes).size()
            let r = CGRect(origin: start, size: size)
            return filled ? r.insetBy(dx: -Annotation.textPadding, dy: -Annotation.textPadding / 2) : r
        case .counter:
            let r = counterRadius
            return CGRect(x: start.x - r, y: start.y - r, width: 2 * r, height: 2 * r)
        }
    }

    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .line, .arrow:
            return distance(p, toSegment: start, end) <= max(tolerance, lineWidth / 2 + 3)
        case .freehand:
            guard points.count > 1 else {
                return points.first.map { hypot($0.x - p.x, $0.y - p.y) <= tolerance } ?? false
            }
            for i in 1..<points.count where distance(p, toSegment: points[i - 1], points[i]) <= max(tolerance, lineWidth / 2 + 3) {
                return true
            }
            return false
        case .counter:
            return hypot(p.x - start.x, p.y - start.y) <= counterRadius + 2
        default:
            return bounds.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(p)
        }
    }

    mutating func offset(by d: CGVector) {
        start.x += d.dx; start.y += d.dy
        end.x += d.dx; end.y += d.dy
        points = points.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) }
    }

    /// Normalisiert Start/Ende, sodass start = oben links, end = unten rechts.
    mutating func normalize() {
        guard isRectLike else { return }
        let r = rect
        start = r.origin
        end = CGPoint(x: r.maxX, y: r.maxY)
    }
}

func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let len2 = dx * dx + dy * dy
    guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

// MARK: - Zeichnen

enum Renderer {
    static let highlightColor = NSColor(srgbRed: 1.0, green: 0.92, blue: 0.23, alpha: 1)

    /// Zeichnet ein CGImage in einen (gespiegelten) Kontext mit Ursprung oben links.
    static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Zeichnet eine Markierung. `ctx` muss gespiegelt sein (Ursprung oben links, Einheit = Bildpunkt)
    /// und als aktueller NSGraphicsContext gesetzt sein (für Text).
    static func draw(_ a: Annotation, number: Int, base: CGImage, imageScale: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(a.lineWidth)
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)

        switch a.kind {
        case .rectangle:
            let r = a.rect
            if a.filled {
                ctx.fill(r)
            } else {
                ctx.setLineJoin(.miter)
                ctx.stroke(r)
            }

        case .ellipse:
            if a.filled { ctx.fillEllipse(in: a.rect) } else { ctx.strokeEllipse(in: a.rect) }

        case .line:
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.strokePath()

        case .arrow:
            drawArrow(from: a.start, to: a.end, width: a.lineWidth, ctx: ctx)

        case .freehand:
            guard let first = a.points.first else { return }
            ctx.move(to: first)
            if a.points.count == 1 {
                ctx.addLine(to: first)
            } else {
                // Geglättet über Mittelpunkte
                for i in 1..<a.points.count {
                    let prev = a.points[i - 1], cur = a.points[i]
                    let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
                    ctx.addQuadCurve(to: mid, control: prev)
                }
                ctx.addLine(to: a.points[a.points.count - 1])
            }
            ctx.strokePath()

        case .text:
            guard !a.text.isEmpty else { return }
            if a.filled {
                let bg = a.bounds
                let path = CGPath(roundedRect: bg, cornerWidth: 5, cornerHeight: 5, transform: nil)
                ctx.addPath(path)
                ctx.setFillColor(contrastingBackground(for: a.color).cgColor)
                ctx.fillPath()
            }
            NSAttributedString(string: a.text, attributes: a.textAttributes).draw(at: a.start)

        case .highlight:
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(highlightColor.cgColor)
            ctx.fill(a.rect)

        case .pixelate:
            drawPixelated(rect: a.rect, base: base, imageScale: imageScale, ctx: ctx)

        case .counter:
            let r = a.counterRadius
            let circle = CGRect(x: a.start.x - r, y: a.start.y - r, width: 2 * r, height: 2 * r)
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: a.fontSize, weight: .bold),
                .foregroundColor: isLight(a.color) ? NSColor.black : NSColor.white,
            ]
            let str = NSAttributedString(string: "\(number)", attributes: attrs)
            let size = str.size()
            str.draw(at: CGPoint(x: a.start.x - size.width / 2, y: a.start.y - size.height / 2))
        }
    }

    static func drawArrow(from s: CGPoint, to e: CGPoint, width: CGFloat, ctx: CGContext) {
        let length = hypot(e.x - s.x, e.y - s.y)
        guard length > 0.5 else { return }
        let angle = atan2(e.y - s.y, e.x - s.x)
        let headLength = min(max(12, width * 4.5), length)
        let headWidth = headLength * 0.85
        let base = CGPoint(x: e.x - cos(angle) * headLength * 0.8, y: e.y - sin(angle) * headLength * 0.8)

        ctx.move(to: s)
        ctx.addLine(to: base)
        ctx.strokePath()

        let back = CGPoint(x: e.x - cos(angle) * headLength, y: e.y - sin(angle) * headLength)
        let perp = angle + .pi / 2
        let left = CGPoint(x: back.x + cos(perp) * headWidth / 2, y: back.y + sin(perp) * headWidth / 2)
        let right = CGPoint(x: back.x - cos(perp) * headWidth / 2, y: back.y - sin(perp) * headWidth / 2)
        ctx.move(to: e)
        ctx.addLine(to: left)
        ctx.addLine(to: base)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    static func drawPixelated(rect: CGRect, base: CGImage, imageScale: CGFloat, ctx: CGContext) {
        let px = CGRect(x: rect.minX * imageScale, y: rect.minY * imageScale,
                        width: rect.width * imageScale, height: rect.height * imageScale).integral
            .intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !px.isNull, px.width >= 1, px.height >= 1, let crop = base.cropping(to: px) else { return }
        let block = max(6, 9 * imageScale)
        let w = max(1, Int((px.width / block).rounded(.up)))
        let h = max(1, Int((px.height / block).rounded(.up)))
        guard let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let tiny = small.makeImage() else { return }
        let dest = CGRect(x: px.minX / imageScale, y: px.minY / imageScale,
                          width: px.width / imageScale, height: px.height / imageScale)
        ctx.saveGState()
        ctx.interpolationQuality = .none
        drawImage(tiny, in: dest, ctx: ctx)
        ctx.restoreGState()
    }

    static func isLight(_ color: NSColor) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.65
    }

    static func contrastingBackground(for color: NSColor) -> NSColor {
        isLight(color) ? NSColor.black.withAlphaComponent(0.75) : NSColor.white.withAlphaComponent(0.9)
    }
}

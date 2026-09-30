import Cocoa

/// Zeichnet das App-Symbol (grünes Rund-Quadrat mit Sucher), wird auch für die .icns-Datei verwendet.
enum AppIcon {
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
    }

    static func draw(in rect: CGRect) {
        let s = rect.width
        let inset = s * 0.1
        let body = rect.insetBy(dx: inset, dy: inset)
        let radius = body.width * 0.225

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = s * 0.02
        shadow.shadowOffset = CGSize(width: 0, height: -s * 0.01)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.set()
        let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.85, blue: 0.42, alpha: 1),
                                  ending: NSColor(srgbRed: 0.08, green: 0.55, blue: 0.27, alpha: 1))
        gradient?.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Sucher-Ecken
        let frame = body.insetBy(dx: body.width * 0.2, dy: body.width * 0.2)
        let corner = frame.width * 0.28
        let line = NSBezierPath()
        line.lineWidth = s * 0.045
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: frame.minX, y: frame.minY), 1, 1),
            (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),
            (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),
            (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),
        ]
        for (p, dx, dy) in corners {
            line.move(to: CGPoint(x: p.x + dx * corner, y: p.y))
            line.line(to: p)
            line.line(to: CGPoint(x: p.x, y: p.y + dy * corner))
        }
        NSColor.white.setStroke()
        line.stroke()

        // Stift / Markierung in der Mitte
        let pen = NSBezierPath()
        let c = CGPoint(x: frame.midX, y: frame.midY)
        let r = frame.width * 0.22
        pen.move(to: CGPoint(x: c.x - r, y: c.y - r))
        pen.line(to: CGPoint(x: c.x + r, y: c.y + r))
        pen.lineWidth = s * 0.06
        pen.lineCapStyle = .round
        NSColor.white.setStroke()
        pen.stroke()
        let dot = NSBezierPath(ovalIn: CGRect(x: c.x + r - s * 0.035, y: c.y + r - s * 0.035,
                                              width: s * 0.07, height: s * 0.07))
        NSColor(srgbRed: 1, green: 0.85, blue: 0.2, alpha: 1).setFill()
        dot.fill()
    }
}

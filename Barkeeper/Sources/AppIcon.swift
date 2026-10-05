import Cocoa

/// App-Symbol: dunkles Rund-Quadrat mit stilisierter Menüleiste und Klapp-Pfeil (für die .icns-Datei).
enum AppIcon {
    static func draw(in rect: CGRect) {
        let s = rect.width
        let body = rect.insetBy(dx: s * 0.1, dy: s * 0.1)
        let radius = body.width * 0.225

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = s * 0.02
        shadow.shadowOffset = CGSize(width: 0, height: -s * 0.01)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.set()
        let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.62, blue: 0.25, alpha: 1),
                   ending: NSColor(srgbRed: 0.85, green: 0.30, blue: 0.20, alpha: 1))?.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Menüleiste
        let bar = CGRect(x: body.minX + body.width * 0.12, y: body.midY - body.height * 0.09,
                         width: body.width * 0.76, height: body.height * 0.18)
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()

        // Symbole in der Leiste
        let dot = bar.height * 0.42
        let orange = NSColor(srgbRed: 0.88, green: 0.38, blue: 0.20, alpha: 1)
        for i in 0..<3 {
            let x = bar.minX + bar.height * 0.45 + CGFloat(i) * dot * 1.7
            orange.withAlphaComponent(i == 0 ? 1 : 0.55).setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: bar.midY - dot / 2, width: dot, height: dot)).fill()
        }

        // Klapp-Pfeil rechts
        let chevron = NSBezierPath()
        let cx = bar.maxX - bar.height * 0.7
        let h = bar.height * 0.28
        chevron.move(to: CGPoint(x: cx + h * 0.6, y: bar.midY + h))
        chevron.line(to: CGPoint(x: cx - h * 0.4, y: bar.midY))
        chevron.line(to: CGPoint(x: cx + h * 0.6, y: bar.midY - h))
        chevron.lineWidth = s * 0.03
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        orange.setStroke()
        chevron.stroke()

        // Trennlinie
        let sep = NSBezierPath()
        let sx = cx - bar.height * 0.75
        sep.move(to: CGPoint(x: sx, y: bar.midY - bar.height * 0.28))
        sep.line(to: CGPoint(x: sx, y: bar.midY + bar.height * 0.28))
        sep.lineWidth = s * 0.012
        NSColor.black.withAlphaComponent(0.35).setStroke()
        sep.stroke()
    }
}

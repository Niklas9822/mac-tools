import Cocoa

/// Vollbild-Overlay über dem eingefrorenen Bildschirmbild zum Auswählen eines Bereichs oder Fensters.
final class SelectionController {
    enum Result {
        case region(CapturedScreen, CGRect)
        case window(CapturedScreen, WindowInfo, CGRect)
        case fullscreen(CapturedScreen)
    }

    private var windows: [NSWindow] = []
    private var completion: ((Result?) -> Void)?

    init(captures: [CapturedScreen], windowInfos: [WindowInfo], completion: @escaping (Result?) -> Void) {
        self.completion = completion
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        for capture in captures {
            let frame = capture.screen.frame
            let window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let localBounds = CGRect(origin: .zero, size: frame.size)
            let rects: [(WindowInfo, CGRect)] = windowInfos.compactMap { info in
                let r = CGRect(x: info.frame.minX - frame.minX,
                               y: info.frame.minY - (primaryHeight - frame.maxY),
                               width: info.frame.width, height: info.frame.height)
                return r.intersects(localBounds) ? (info, r) : nil
            }
            let view = OverlayView(frame: localBounds, capture: capture, windowRects: rects)
            view.onFinish = { [weak self] result in self?.finish(result) }
            window.contentView = view
            window.setFrame(frame, display: false)
            windows.append(window)
        }
    }

    func begin() {
        windows.forEach { $0.orderFrontRegardless() }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        if let view = keyWindow?.contentView {
            keyWindow?.makeFirstResponder(view)
            (view as? OverlayView)?.syncMouseLocation()
        }
        NSCursor.crosshair.set()
    }

    func cancel() { finish(nil) }

    private func finish(_ result: Result?) {
        guard let completion else { return }
        self.completion = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        completion(result)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class OverlayView: NSView {
    var onFinish: ((SelectionController.Result?) -> Void)?

    private let capture: CapturedScreen
    private let image: NSImage
    private let windowRects: [(WindowInfo, CGRect)]
    private var mouse: CGPoint?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var hover: (WindowInfo, CGRect)?
    private let accent = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)

    init(frame: CGRect, capture: CapturedScreen, windowRects: [(WindowInfo, CGRect)]) {
        self.capture = capture
        self.image = NSImage(cgImage: capture.image, size: frame.size)
        self.windowRects = windowRects
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways,
                                                 .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    func syncMouseLocation() {
        guard let window else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(p) {
            mouse = p
            updateHover()
        }
        needsDisplay = true
    }

    // MARK: Maus / Tastatur

    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func updateHover() {
        guard dragStart == nil, let mouse else { hover = nil; return }
        hover = windowRects.first { $0.1.contains(mouse) }
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        mouse = point(event)
        updateHover()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = point(event)
        updateHover()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard dragStart == nil else { return }
        mouse = nil
        hover = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        mouse = p
        dragStart = p
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        mouse = p
        guard let start = dragStart else { return }
        let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                       width: abs(p.x - start.x), height: abs(p.y - start.y))
        if r.width >= 3 || r.height >= 3 {
            selection = r
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if let sel = selection, sel.width >= 2, sel.height >= 2 {
            onFinish?(.region(capture, sel))
        } else if let hover {
            onFinish?(.window(capture, hover.0, hover.1))
        } else {
            onFinish?(.fullscreen(capture))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish?(nil)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Esc
            onFinish?(nil)
        case 36, 76: // Return / Enter
            if let sel = selection { onFinish?(.region(capture, sel)) } else { onFinish?(.fullscreen(capture)) }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Zeichnen

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        let highlight: CGRect? = selection ?? hover.map { $0.1.intersection(bounds) }

        let dim = NSBezierPath(rect: bounds)
        if let highlight {
            dim.append(NSBezierPath(rect: highlight))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        if let mouse, dragStart == nil || selection == nil {
            drawCrosshair(at: mouse)
        }

        if let highlight {
            let border = NSBezierPath(rect: highlight.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = selection == nil ? 3 : 1
            accent.setStroke()
            border.stroke()
            drawSizeLabel(for: highlight)
        }

        if dragStart == nil && selection == nil {
            drawHint()
        }

        if Prefs.showMagnifier, let mouse {
            drawMagnifier(at: mouse)
        }
    }

    private func drawCrosshair(at p: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 0, y: floor(p.y) + 0.5))
        path.line(to: CGPoint(x: bounds.maxX, y: floor(p.y) + 0.5))
        path.move(to: CGPoint(x: floor(p.x) + 0.5, y: 0))
        path.line(to: CGPoint(x: floor(p.x) + 0.5, y: bounds.maxY))
        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.stroke()
    }

    private func pill(_ text: String, at origin: CGPoint, fontSize: CGFloat = 12) -> CGRect {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var rect = CGRect(x: origin.x, y: origin.y, width: size.width + 14, height: size.height + 6)
        rect.origin.x = min(max(rect.minX, 4), bounds.maxX - rect.width - 4)
        rect.origin.y = min(max(rect.minY, 4), bounds.maxY - rect.height - 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        str.draw(at: CGPoint(x: rect.minX + 7, y: rect.minY + 3))
        return rect
    }

    private func drawSizeLabel(for rect: CGRect) {
        let s = capture.scale
        let text = "\(Int((rect.width * s).rounded())) × \(Int((rect.height * s).rounded()))"
        var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + 24 > bounds.maxY { origin.y = rect.minY - 28 }
        _ = pill(text, at: origin)
    }

    private func drawHint() {
        let text = "Ziehen: Bereich   ·   Klick: Fenster   ·   ↩ Vollbild   ·   Esc: Abbrechen"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]
        let width = NSAttributedString(string: text, attributes: attrs).size().width + 14
        _ = pill(text, at: CGPoint(x: bounds.midX - width / 2, y: 40), fontSize: 13)
    }

    private func drawMagnifier(at p: CGPoint) {
        let scale = capture.scale
        let radius = 8
        let cells = CGFloat(2 * radius + 1)
        let size: CGFloat = 136
        let cell = size / cells

        let px = Int(p.x * scale), py = Int(p.y * scale)
        let src = CGRect(x: px - radius, y: py - radius, width: 2 * radius + 1, height: 2 * radius + 1)
        let imageBounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)

        var origin = CGPoint(x: p.x + 24, y: p.y + 24)
        if origin.x + size > bounds.maxX - 4 { origin.x = p.x - 24 - size }
        if origin.y + size + 30 > bounds.maxY - 4 { origin.y = p.y - 24 - size - 30 }
        let box = CGRect(origin: origin, size: CGSize(width: size, height: size))
        let clip = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)

        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSColor.black.setFill()
        box.fill()
        let inter = src.intersection(imageBounds)
        if !inter.isNull, let crop = capture.image.cropping(to: inter) {
            let dest = CGRect(x: box.minX + (inter.minX - src.minX) * cell,
                              y: box.minY + (inter.minY - src.minY) * cell,
                              width: inter.width * cell, height: inter.height * cell)
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: crop, size: inter.size)
                .draw(in: dest, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
                      hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
        }
        let center = CGRect(x: box.minX + CGFloat(radius) * cell, y: box.minY + CGFloat(radius) * cell,
                            width: cell, height: cell)
        accent.setStroke()
        let c = NSBezierPath(rect: center)
        c.lineWidth = 1.5
        c.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        clip.lineWidth = 2
        clip.stroke()

        _ = pill("\(px), \(py)", at: CGPoint(x: box.minX, y: box.maxY + 6))
    }
}

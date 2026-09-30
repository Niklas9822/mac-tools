import Cocoa

protocol CanvasViewDelegate: AnyObject {
    func canvasDidChange(_ canvas: CanvasView)
    func canvasSelectionDidChange(_ canvas: CanvasView)
    func canvasWantsCopyAndClose(_ canvas: CanvasView)
    func canvas(_ canvas: CanvasView, didRequestTool tool: Tool)
}

/// Zeichenfläche des Editors: Bild + Markierungen, Werkzeuge, Rückgängig.
final class CanvasView: NSView, NSTextViewDelegate {
    struct State {
        var image: CGImage
        var annotations: [Annotation]
    }

    private enum Drag {
        case none
        case drawing
        case moving(last: CGPoint, didPushUndo: Bool)
        case resizing(handle: Int, didPushUndo: Bool)
        case cropping(start: CGPoint)
    }

    weak var delegate: CanvasViewDelegate?

    private(set) var state: State
    let imageScale: CGFloat
    private var undoStack: [State] = []
    private var redoStack: [State] = []

    var tool: Tool = .arrow {
        didSet {
            endTextEditing()
            if tool == .crop { selectedIndex = nil }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    // Aktueller Stil (für neue Markierungen)
    var color: NSColor = Prefs.toolColor
    var lineWidth: CGFloat = Prefs.lineWidth
    var fontSize: CGFloat = Prefs.fontSize
    var filled = false

    private(set) var selectedIndex: Int? {
        didSet { if oldValue != selectedIndex { delegate?.canvasSelectionDidChange(self); needsDisplay = true } }
    }
    private var draft: Annotation?
    private var cropRect: CGRect?
    private var drag: Drag = .none

    private var textView: NSTextView?
    private var editingIndex: Int?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedAnnotation: Annotation? { selectedIndex.map { state.annotations[$0] } }

    var imagePointSize: CGSize {
        CGSize(width: CGFloat(state.image.width) / imageScale, height: CGFloat(state.image.height) / imageScale)
    }

    init(image: CGImage, scale: CGFloat) {
        self.state = State(image: image, annotations: [])
        self.imageScale = max(scale, 1)
        super.init(frame: .zero)
        setFrameSize(imagePointSize)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }

    // MARK: Cursor

    override func resetCursorRects() {
        let cursor: NSCursor
        switch tool {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(visibleRect, cursor: cursor)
    }

    // MARK: Rückgängig

    private func pushUndo() {
        undoStack.append(state)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        endTextEditing()
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(state)
        apply(prev)
    }

    func redo() {
        endTextEditing()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        apply(next)
    }

    private func apply(_ s: State) {
        let sizeChanged = s.image.width != state.image.width || s.image.height != state.image.height
        state = s
        selectedIndex = nil
        if sizeChanged { setFrameSize(imagePointSize) }
        changed()
    }

    private func changed() {
        needsDisplay = true
        delegate?.canvasDidChange(self)
    }

    // MARK: Stil auf Auswahl anwenden

    func applyStyleToSelection(color: NSColor? = nil, lineWidth: CGFloat? = nil,
                               fontSize: CGFloat? = nil, filled: Bool? = nil) {
        guard let i = selectedIndex else { return }
        pushUndo()
        if let color { state.annotations[i].color = color }
        if let lineWidth { state.annotations[i].lineWidth = lineWidth }
        if let fontSize { state.annotations[i].fontSize = fontSize }
        if let filled { state.annotations[i].filled = filled }
        changed()
    }

    func deleteSelection() {
        guard let i = selectedIndex else { return }
        pushUndo()
        state.annotations.remove(at: i)
        selectedIndex = nil
        changed()
    }

    // MARK: Export

    /// Rendert Bild + Markierungen in voller Auflösung.
    func flattenedImage() -> CGImage? {
        endTextEditing()
        let image = state.image
        let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: imageScale, y: -imageScale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        Renderer.drawImage(image, in: CGRect(origin: .zero, size: imagePointSize), ctx: ctx)
        for (i, a) in state.annotations.enumerated() {
            Renderer.draw(a, number: counterNumber(at: i), base: image, imageScale: imageScale, in: ctx)
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    // MARK: Zeichnen

    private func counterNumber(at index: Int) -> Int {
        var n = 0
        for i in 0...index where state.annotations[i].kind == .counter { n += 1 }
        return n
    }

    private var nextCounterNumber: Int {
        state.annotations.filter { $0.kind == .counter }.count + 1
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Renderer.drawImage(state.image, in: CGRect(origin: .zero, size: imagePointSize), ctx: ctx)

        for (i, a) in state.annotations.enumerated() where i != editingIndex {
            Renderer.draw(a, number: counterNumber(at: i), base: state.image, imageScale: imageScale, in: ctx)
        }
        if let draft {
            Renderer.draw(draft, number: nextCounterNumber, base: state.image, imageScale: imageScale, in: ctx)
        }

        if let i = selectedIndex, i < state.annotations.count, i != editingIndex {
            drawSelection(for: state.annotations[i])
        }

        if let crop = cropRect {
            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(rect: crop))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.5).setFill()
            dim.fill()
            let border = NSBezierPath(rect: crop)
            border.lineWidth = 1 / magnification
            border.setLineDash([4 / magnification, 4 / magnification], count: 2, phase: 0)
            NSColor.white.setStroke()
            border.stroke()
        }
    }

    private var handleSize: CGFloat { 9 / magnification }

    private func handlePoints(for a: Annotation) -> [CGPoint] {
        if a.isRectLike {
            let r = a.rect
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        }
        if a.kind == .line || a.kind == .arrow { return [a.start, a.end] }
        return []
    }

    private func drawSelection(for a: Annotation) {
        let outline = NSBezierPath(rect: a.bounds.insetBy(dx: -3 / magnification, dy: -3 / magnification))
        outline.lineWidth = 1 / magnification
        outline.setLineDash([4 / magnification, 3 / magnification], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        outline.stroke()

        for p in handlePoints(for: a) {
            let s = handleSize
            let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
            NSColor.white.setFill()
            let path = NSBezierPath(ovalIn: r)
            path.fill()
            path.lineWidth = 1.5 / magnification
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }
    }

    // MARK: Maus

    private func point(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func handleHit(_ p: CGPoint) -> Int? {
        guard let i = selectedIndex else { return nil }
        let pts = handlePoints(for: state.annotations[i])
        let tol = handleSize
        return pts.firstIndex { hypot($0.x - p.x, $0.y - p.y) <= tol }
    }

    private func annotationHit(_ p: CGPoint) -> Int? {
        let tol = 6 / magnification
        return state.annotations.indices.reversed().first { state.annotations[$0].hitTest(p, tolerance: tol) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let wasEditing = textView != nil
        endTextEditing()
        let p = point(event)

        // Griffe der aktuellen Auswahl haben immer Vorrang
        if tool != .crop, let h = handleHit(p) {
            if let i = selectedIndex { state.annotations[i].normalize() }
            drag = .resizing(handle: h, didPushUndo: false)
            return
        }

        switch tool {
        case .select:
            if let i = annotationHit(p) {
                selectedIndex = i
                if event.clickCount == 2, state.annotations[i].kind == .text {
                    beginTextEditing(index: i)
                    return
                }
                drag = .moving(last: p, didPushUndo: false)
            } else {
                selectedIndex = nil
            }

        case .text:
            if let i = annotationHit(p), state.annotations[i].kind == .text {
                selectedIndex = i
                beginTextEditing(index: i)
                return
            }
            if wasEditing { return } // Klick daneben beendet nur die Bearbeitung
            pushUndo()
            let a = Annotation(kind: .text, start: p, end: p, color: color, lineWidth: lineWidth,
                               fontSize: fontSize, filled: filled)
            state.annotations.append(a)
            selectedIndex = state.annotations.count - 1
            beginTextEditing(index: state.annotations.count - 1, isNew: true)

        case .counter:
            pushUndo()
            let a = Annotation(kind: .counter, start: p, end: p, color: color, lineWidth: lineWidth,
                               fontSize: fontSize, filled: true)
            state.annotations.append(a)
            selectedIndex = state.annotations.count - 1
            drag = .moving(last: p, didPushUndo: true)
            changed()

        case .crop:
            cropRect = nil
            drag = .cropping(start: p)

        default:
            guard let kind = tool.annotationKind else { return }
            // Klick auf eine vorhandene Markierung wählt sie aus, statt neu zu zeichnen
            if event.modifierFlags.contains(.command), let i = annotationHit(p) {
                selectedIndex = i
                drag = .moving(last: p, didPushUndo: false)
                return
            }
            selectedIndex = nil
            draft = Annotation(kind: kind, start: p, end: p, points: [p], color: color,
                               lineWidth: lineWidth, fontSize: fontSize, filled: filled)
            drag = .drawing
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var p = point(event)
        let shift = event.modifierFlags.contains(.shift)

        switch drag {
        case .none:
            return

        case .drawing:
            guard var d = draft else { return }
            if d.kind == .freehand {
                if let last = d.points.last, hypot(last.x - p.x, last.y - p.y) >= 1 / magnification {
                    d.points.append(p)
                }
            } else {
                if shift { p = constrain(p, from: d.start, kind: d.kind) }
                d.end = p
            }
            draft = d

        case .moving(let last, let pushed):
            guard let i = selectedIndex else { return }
            if !pushed { pushUndo() }
            state.annotations[i].offset(by: CGVector(dx: p.x - last.x, dy: p.y - last.y))
            drag = .moving(last: p, didPushUndo: true)
            changed()

        case .resizing(let handle, let pushed):
            guard let i = selectedIndex else { return }
            if !pushed { pushUndo() }
            var a = state.annotations[i]
            if a.isRectLike {
                switch handle {
                case 0: a.start = p
                case 1: a.end.x = p.x; a.start.y = p.y
                case 2: a.start.x = p.x; a.end.y = p.y
                default: a.end = p
                }
            } else if handle == 0 {
                a.start = shift ? constrain(p, from: a.end, kind: a.kind) : p
            } else {
                a.end = shift ? constrain(p, from: a.start, kind: a.kind) : p
            }
            state.annotations[i] = a
            drag = .resizing(handle: handle, didPushUndo: true)
            changed()

        case .cropping(let start):
            let clamped = CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
            cropRect = CGRect(x: min(start.x, clamped.x), y: min(start.y, clamped.y),
                              width: abs(clamped.x - start.x), height: abs(clamped.y - start.y))
        }
        _ = autoscroll(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = .none }
        switch drag {
        case .drawing:
            guard var d = draft else { return }
            draft = nil
            let big: Bool
            switch d.kind {
            case .freehand: big = d.points.count > 1
            case .line, .arrow: big = hypot(d.end.x - d.start.x, d.end.y - d.start.y) > 3
            default: big = d.rect.width > 3 && d.rect.height > 3
            }
            guard big else { needsDisplay = true; return }
            d.normalize()
            pushUndo()
            state.annotations.append(d)
            selectedIndex = state.annotations.count - 1
            changed()

        case .resizing:
            if let i = selectedIndex { state.annotations[i].normalize() }
            needsDisplay = true

        case .cropping:
            if let crop = cropRect, crop.width > 4, crop.height > 4 {
                applyCrop(crop)
            }
            cropRect = nil
            needsDisplay = true

        default:
            break
        }
    }

    private func constrain(_ p: CGPoint, from s: CGPoint, kind: Annotation.Kind) -> CGPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        switch kind {
        case .line, .arrow:
            let angle = atan2(dy, dx)
            let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return CGPoint(x: s.x + cos(snapped) * len, y: s.y + sin(snapped) * len)
        default:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: s.x + (dx < 0 ? -side : side), y: s.y + (dy < 0 ? -side : side))
        }
    }

    private func applyCrop(_ rect: CGRect) {
        guard let cropped = ScreenCapture.crop(state.image, toPoints: rect, scale: imageScale) else { return }
        // tatsächlicher (auf Pixel gerundeter) Ausschnitt in Punkten
        let px = CGRect(x: rect.minX * imageScale, y: rect.minY * imageScale,
                        width: rect.width * imageScale, height: rect.height * imageScale).integral
            .intersection(CGRect(x: 0, y: 0, width: state.image.width, height: state.image.height))
        let offset = CGVector(dx: -px.minX / imageScale, dy: -px.minY / imageScale)
        pushUndo()
        state.image = cropped
        for i in state.annotations.indices { state.annotations[i].offset(by: offset) }
        selectedIndex = nil
        setFrameSize(imagePointSize)
        changed()
        tool = .select
        delegate?.canvas(self, didRequestTool: .select)
    }

    // MARK: Tastatur

    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch code {
        case 51, 117: // Löschen
            deleteSelection()
            return
        case 53: // Esc
            if draft != nil || cropRect != nil {
                draft = nil; cropRect = nil; drag = .none
                needsDisplay = true
            } else {
                selectedIndex = nil
            }
            return
        case 36, 76: // Return
            delegate?.canvasWantsCopyAndClose(self)
            return
        case 123, 124, 125, 126: // Pfeiltasten
            guard let i = selectedIndex else { break }
            let step: CGFloat = flags.contains(.shift) ? 10 : 1
            let d: CGVector
            switch code {
            case 123: d = CGVector(dx: -step, dy: 0)
            case 124: d = CGVector(dx: step, dy: 0)
            case 125: d = CGVector(dx: 0, dy: step)
            default: d = CGVector(dx: 0, dy: -step)
            }
            pushUndo()
            state.annotations[i].offset(by: d)
            changed()
            return
        default:
            break
        }
        if flags.isDisjoint(with: [.command, .control, .option]),
           let ch = event.charactersIgnoringModifiers?.lowercased(),
           let t = Tool.allCases.first(where: { $0.shortcutKey == ch }) {
            tool = t
            delegate?.canvas(self, didRequestTool: t)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Text bearbeiten

    private func beginTextEditing(index: Int, isNew: Bool = false) {
        endTextEditing()
        let a = state.annotations[index]
        if !isNew { pushUndo() }
        editingIndex = index

        let tv = NSTextView(frame: CGRect(origin: a.start, size: CGSize(width: 40, height: a.font.pointSize * 1.4)))
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = a.filled
        tv.backgroundColor = Renderer.contrastingBackground(for: a.color)
        tv.font = a.font
        tv.textColor = a.color
        tv.insertionPointColor = a.color
        tv.typingAttributes = a.textAttributes
        tv.string = a.text
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.minSize = CGSize(width: 20, height: a.font.pointSize * 1.3)
        tv.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.focusRingType = .none
        tv.delegate = self
        tv.wantsLayer = true
        tv.layer?.borderWidth = 1
        tv.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        addSubview(tv)
        textView = tv
        tv.sizeToFit()
        tv.selectAll(nil)
        window?.makeFirstResponder(tv)
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        textView?.sizeToFit()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endTextEditing()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    var isEditingText: Bool { textView != nil }

    func endTextEditing() {
        guard let tv = textView, let i = editingIndex else { return }
        let text = tv.string
        textView = nil
        editingIndex = nil
        tv.removeFromSuperview()
        if i < state.annotations.count {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.annotations.remove(at: i)
                if selectedIndex == i { selectedIndex = nil }
            } else {
                state.annotations[i].text = text
            }
        }
        changed()
    }
}

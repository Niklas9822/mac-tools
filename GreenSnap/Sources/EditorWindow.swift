import Cocoa

/// Editor-Fenster: Werkzeugleiste + Zeichenfläche.
final class EditorWindowController: NSWindowController, NSWindowDelegate, CanvasViewDelegate {
    private static var openEditors: [EditorWindowController] = []
    static var hasOpenEditors: Bool { !openEditors.isEmpty }

    private let canvas: CanvasView
    private let scrollView = NSScrollView()
    private let toolPicker = NSSegmentedControl()
    private let colorWell = NSColorWell(style: .minimal)
    private let widthPopup = NSPopUpButton()
    private let fontPopup = NSPopUpButton()
    private let fillCheckbox = NSButton(checkboxWithTitle: "Füllen", target: nil, action: nil)
    private let undoButton = NSButton()
    private let redoButton = NSButton()

    private let widths: [CGFloat] = [1, 2, 3, 4, 6, 8, 12, 16]
    private let fontSizes: [CGFloat] = [12, 14, 16, 20, 24, 32, 40, 56, 72]

    @discardableResult
    static func open(image: CGImage, scale: CGFloat) -> EditorWindowController {
        let c = EditorWindowController(image: image, scale: scale)
        openEditors.append(c)
        AppDelegate.shared?.updateActivationPolicy()
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        c.window?.makeFirstResponder(c.canvas)
        return c
    }

    private init(image: CGImage, scale: CGFloat) {
        canvas = CanvasView(image: image, scale: scale)
        let window = EditorWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
        super.init(window: window)
        window.controller = self
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 820, height: 360)
        window.tabbingMode = .disallowed
        canvas.delegate = self
        buildUI()
        sizeWindowToFit()
        updateTitle()
        updateControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: UI

    private func symbol(_ name: String, _ fallback: String = "questionmark") -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil) ?? NSImage()
    }

    private func iconButton(_ symbolName: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: symbol(symbolName), target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        return b
    }

    private func buildUI() {
        guard let window, let content = window.contentView else { return }

        // Werkzeuge
        toolPicker.segmentCount = Tool.allCases.count
        toolPicker.trackingMode = .selectOne
        toolPicker.segmentStyle = .texturedRounded
        for t in Tool.allCases {
            let fallback = t == .pixelate ? "eye.slash" : "questionmark"
            toolPicker.setImage(symbol(t.symbol, fallback), forSegment: t.rawValue)
            toolPicker.setToolTip(t.title, forSegment: t.rawValue)
            toolPicker.setWidth(30, forSegment: t.rawValue)
        }
        toolPicker.target = self
        toolPicker.action = #selector(toolChanged)
        toolPicker.selectedSegment = canvas.tool.rawValue

        colorWell.color = canvas.color
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.toolTip = "Farbe"

        widthPopup.addItems(withTitles: widths.map { "\(Int($0)) px" })
        widthPopup.selectItem(at: widths.firstIndex(of: canvas.lineWidth) ?? 2)
        widthPopup.target = self
        widthPopup.action = #selector(widthChanged)
        widthPopup.toolTip = "Linienstärke"
        widthPopup.controlSize = .small

        fontPopup.addItems(withTitles: fontSizes.map { "\(Int($0)) pt" })
        fontPopup.selectItem(at: fontSizes.firstIndex(of: canvas.fontSize) ?? 3)
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged)
        fontPopup.toolTip = "Schriftgröße (Text & Nummern)"
        fontPopup.controlSize = .small

        fillCheckbox.target = self
        fillCheckbox.action = #selector(fillChanged)
        fillCheckbox.toolTip = "Rechtecke/Ellipsen füllen, Text mit Hintergrund"

        undoButton.image = symbol("arrow.uturn.backward")
        undoButton.bezelStyle = .texturedRounded
        undoButton.target = self
        undoButton.action = #selector(undo)
        undoButton.toolTip = "Rückgängig (⌘Z)"
        redoButton.image = symbol("arrow.uturn.forward")
        redoButton.bezelStyle = .texturedRounded
        redoButton.target = self
        redoButton.action = #selector(redo)
        redoButton.toolTip = "Wiederholen (⇧⌘Z)"

        let ocrButton = iconButton("text.viewfinder", "Text erkennen und kopieren", #selector(copyText))
        let pinButton = iconButton("pin", "Auf dem Bildschirm anheften", #selector(pin))
        let saveButton = iconButton("square.and.arrow.down", "Sichern unter … (⌘S)", #selector(save))
        let copyButton = NSButton(title: "Kopieren", target: self, action: #selector(copyImage))
        copyButton.image = symbol("doc.on.doc")
        copyButton.imagePosition = .imageLeading
        copyButton.bezelStyle = .rounded
        copyButton.bezelColor = .controlAccentColor
        copyButton.toolTip = "In die Zwischenablage kopieren (⌘C) – ↩ kopiert und schließt"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let bar = NSStackView(views: [
            toolPicker, separator(), colorWell, widthPopup, fontPopup, fillCheckbox,
            spacer, undoButton, redoButton, separator(), ocrButton, pinButton, saveButton, copyButton,
        ])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.alignment = .centerY
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        bar.setHuggingPriority(.defaultHigh, for: .vertical)
        colorWell.widthAnchor.constraint(equalToConstant: 38).isActive = true

        let barBackground = NSVisualEffectView()
        barBackground.material = .titlebar
        barBackground.blendingMode = .withinWindow
        barBackground.addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator

        // Zeichenfläche
        let clip = CenteringClipView()
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        canvas.wantsLayer = true
        canvas.shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 8
            s.shadowColor = NSColor.black.withAlphaComponent(0.35)
            s.shadowOffset = CGSize(width: 0, height: -2)
            return s
        }()

        for v in [barBackground, divider, scrollView] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            barBackground.topAnchor.constraint(equalTo: content.topAnchor),
            barBackground.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            barBackground.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: barBackground.topAnchor),
            bar.bottomAnchor.constraint(equalTo: barBackground.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: barBackground.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: barBackground.trailingAnchor),
            divider.topAnchor.constraint(equalTo: barBackground.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return box
    }

    private func sizeWindowToFit() {
        guard let window else { return }
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let img = canvas.imagePointSize
        let chrome: CGFloat = 52 + 28 // Werkzeugleiste + Titelleiste
        let margin: CGFloat = 60
        let w = min(max(img.width + margin, window.minSize.width), screen.width * 0.9)
        let h = min(max(img.height + margin + chrome, window.minSize.height), screen.height * 0.9)
        window.setContentSize(CGSize(width: w, height: h - 28))
        window.center()

        let availW = w - margin, availH = h - chrome - margin
        let fit = min(1, availW / img.width, availH / img.height)
        if fit < 1 { scrollView.magnification = max(fit, 0.1) }
    }

    private func updateTitle() {
        let img = canvas.state.image
        window?.title = "GreenSnap – \(img.width) × \(img.height)"
    }

    private func updateControls() {
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
    }

    // MARK: CanvasViewDelegate

    func canvasDidChange(_ canvas: CanvasView) {
        updateControls()
        updateTitle()
    }

    func canvasSelectionDidChange(_ canvas: CanvasView) {
        guard let a = canvas.selectedAnnotation else { return }
        colorWell.color = a.color
        if let i = widths.firstIndex(of: a.lineWidth) { widthPopup.selectItem(at: i) }
        if let i = fontSizes.firstIndex(of: a.fontSize) { fontPopup.selectItem(at: i) }
        fillCheckbox.state = a.filled ? .on : .off
    }

    func canvasWantsCopyAndClose(_ canvas: CanvasView) {
        copyImage()
        window?.close()
    }

    func canvas(_ canvas: CanvasView, didRequestTool tool: Tool) {
        toolPicker.selectedSegment = tool.rawValue
    }

    // MARK: Aktionen

    @objc private func toolChanged() {
        guard let t = Tool(rawValue: toolPicker.selectedSegment) else { return }
        canvas.tool = t
        window?.makeFirstResponder(canvas)
    }

    @objc private func colorChanged() {
        canvas.color = colorWell.color
        Prefs.toolColor = colorWell.color
        canvas.applyStyleToSelection(color: colorWell.color)
    }

    @objc private func widthChanged() {
        let w = widths[max(0, widthPopup.indexOfSelectedItem)]
        canvas.lineWidth = w
        Prefs.lineWidth = w
        canvas.applyStyleToSelection(lineWidth: w)
    }

    @objc private func fontChanged() {
        let s = fontSizes[max(0, fontPopup.indexOfSelectedItem)]
        canvas.fontSize = s
        Prefs.fontSize = s
        canvas.applyStyleToSelection(fontSize: s)
    }

    @objc private func fillChanged() {
        canvas.filled = fillCheckbox.state == .on
        canvas.applyStyleToSelection(filled: canvas.filled)
    }

    @objc func undo() { canvas.undo() }
    @objc func redo() { canvas.redo() }

    @objc func copyImage() {
        guard let img = canvas.flattenedImage() else { return }
        ImageExport.copyToClipboard(img, scale: canvas.imageScale)
        HUD.show("In Zwischenablage kopiert")
    }

    @objc func save() {
        guard let img = canvas.flattenedImage() else { return }
        ImageExport.save(img, scale: canvas.imageScale, from: window)
    }

    @objc func pin() {
        guard let img = canvas.flattenedImage() else { return }
        PinController.pin(img, scale: canvas.imageScale)
    }

    @objc func copyText() {
        OCR.recognizeAndCopy(canvas.state.image)
    }

    func zoom(by factor: CGFloat) {
        scrollView.animator().magnification = min(8, max(0.1, scrollView.magnification * factor))
    }

    func zoomActual() { scrollView.animator().magnification = 1 }

    func zoomFit() {
        let img = canvas.imagePointSize
        let avail = scrollView.contentSize
        scrollView.animator().magnification = min(8, max(0.1, min(avail.width / img.width, avail.height / img.height) * 0.97))
    }

    var isEditingText: Bool { canvas.isEditingText }

    func deleteSelection() { canvas.deleteSelection() }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        EditorWindowController.openEditors.removeAll { $0 === self }
        DispatchQueue.main.async { AppDelegate.shared?.updateActivationPolicy() }
    }
}

/// Fenster-Unterklasse, damit Menübefehle (⌘C, ⌘S, ⌘Z …) im Editor ankommen.
final class EditorWindow: NSWindow {
    weak var controller: EditorWindowController?

    @objc func copy(_ sender: Any?) { controller?.copyImage() }
    @objc func saveDocument(_ sender: Any?) { controller?.save() }
    @objc func editorUndo(_ sender: Any?) { controller?.undo() }
    @objc func editorRedo(_ sender: Any?) { controller?.redo() }
    @objc func zoomIn(_ sender: Any?) { controller?.zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { controller?.zoom(by: 0.8) }
    @objc func zoomActualSize(_ sender: Any?) { controller?.zoomActual() }
    @objc func zoomToFitWindow(_ sender: Any?) { controller?.zoomFit() }
    @objc func pinImage(_ sender: Any?) { controller?.pin() }
    @objc func recognizeText(_ sender: Any?) { controller?.copyText() }
    @objc func delete(_ sender: Any?) { controller?.deleteSelection() }
}

/// Zentriert das Bild, wenn es kleiner als das Fenster ist.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
        if rect.height > doc.frame.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        return rect
    }
}

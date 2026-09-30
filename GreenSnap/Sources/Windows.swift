import Cocoa

// MARK: - HUD (kurze Bestätigung, z. B. "Kopiert")

enum HUD {
    private static var window: NSWindow?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String = "checkmark.circle.fill") {
        hideWork?.cancel()
        window?.orderOut(nil)

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 20)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        let size = stack.fittingSize

        let screen = ScreenCapture.screenUnderMouse.visibleFrame
        let frame = CGRect(x: screen.midX - size.width / 2, y: screen.minY + screen.height * 0.18,
                           width: size.width, height: size.height)
        let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .statusBar
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        w.contentView = effect
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; w.animator().alphaValue = 1 }
        window = w

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; w.animator().alphaValue = 0 },
                                                 completionHandler: { w.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }
}

// MARK: - Angeheftete Screenshots (schweben über allen Fenstern)

final class PinController: NSObject, NSWindowDelegate {
    private static var pins: [PinController] = []

    let image: CGImage
    let scale: CGFloat
    private let window: PinWindow

    static func pin(_ image: CGImage, scale: CGFloat) {
        let c = PinController(image: image, scale: scale)
        pins.append(c)
        c.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let screen = ScreenCapture.screenUnderMouse.visibleFrame
        let maxW = screen.width * 0.6, maxH = screen.height * 0.6
        let f = min(1, maxW / size.width, maxH / size.height)
        size = CGSize(width: size.width * f, height: size.height * f)
        let mouse = NSEvent.mouseLocation
        var origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)

        window = PinWindow(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .resizable],
                           backing: .buffered, defer: false)
        super.init()
        window.level = .floating
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = size
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        let view = PinView(frame: CGRect(origin: .zero, size: size))
        view.image = NSImage(cgImage: image, size: size)
        view.controller = self
        window.contentView = view
    }

    func close() { window.close() }

    func windowWillClose(_ notification: Notification) {
        PinController.pins.removeAll { $0 === self }
    }

    @objc func copyImage() {
        ImageExport.copyToClipboard(image, scale: scale)
        HUD.show("In Zwischenablage kopiert")
    }

    @objc func openInEditor() {
        EditorWindowController.open(image: image, scale: scale)
        close()
    }

    @objc func closePin() { close() }

    @objc func setOpacity(_ sender: NSMenuItem) {
        window.alphaValue = CGFloat(sender.tag) / 100
    }
}

private final class PinWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class PinView: NSView {
    var image: NSImage?
    weak var controller: PinController?

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)
        NSColor.white.withAlphaComponent(0.25).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { controller?.close(); return }
        window?.performDrag(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller?.close(); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            controller?.copyImage(); return
        }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        window.alphaValue = min(1, max(0.2, window.alphaValue + event.scrollingDeltaY * 0.01))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let controller else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = controller
            item.tag = tag
            menu.addItem(item)
            return item
        }
        _ = add("Kopieren", #selector(PinController.copyImage))
        _ = add("Im Editor öffnen", #selector(PinController.openInEditor))
        menu.addItem(.separator())
        for pct in [100, 75, 50, 25] {
            let item = add("Deckkraft \(pct) %", #selector(PinController.setOpacity(_:)), tag: pct)
            item.state = Int((window?.alphaValue ?? 1) * 100 + 0.5) == pct ? .on : .off
        }
        menu.addItem(.separator())
        _ = add("Schließen", #selector(PinController.closePin))
        return menu
    }
}

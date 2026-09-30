import Cocoa
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private var selection: SelectionController?
    private var isCapturing = false

    private struct HistoryItem {
        let image: CGImage
        let scale: CGFloat
        let date: Date
    }
    private var history: [HistoryItem] = []

    private struct LastRegion {
        let displayID: CGDirectDisplayID
        let rect: CGRect // Punkte, Ursprung oben links des Bildschirms
    }
    private var lastRegion: LastRegion?

    // MARK: Start

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.applicationIconImage = AppIcon.image(size: 512)
        buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "GreenSnap")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "GreenSnap"
        statusMenu.delegate = self
        statusItem.menu = statusMenu

        registerHotKeys()

        if !ScreenCapture.hasPermission {
            ScreenCapture.requestPermission()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindowController.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Solange ein Editor/Einstellungsfenster offen ist, erscheint die App im Dock und in ⌘-Tab.
    func updateActivationPolicy() {
        let needsRegular = EditorWindowController.hasOpenEditors || SettingsWindowController.isOpen
        let target: NSApplication.ActivationPolicy = needsRegular ? .regular : .accessory
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
            if target == .regular { NSApp.applicationIconImage = AppIcon.image(size: 512) }
        }
    }

    func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        for action in CaptureAction.allCases {
            guard let s = Prefs.shortcut(for: action) else { continue }
            HotKeyCenter.shared.register(s) { [weak self] in self?.runCapture(action, fromMenu: false) }
        }
    }

    // MARK: Menüleiste

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for action in CaptureAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(menuCapture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: symbol(for: action), accessibilityDescription: nil)
            if let s = Prefs.shortcut(for: action) {
                item.keyEquivalent = s.key.count == 1 ? s.key.lowercased() : ""
                item.keyEquivalentModifierMask = s.flags
                if item.keyEquivalent.isEmpty { item.title += "   (\(s.display))" }
            }
            if action == .lastRegion && lastRegion == nil { item.isEnabled = false }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(item("Bild aus Zwischenablage öffnen", #selector(openFromClipboard), symbol: "doc.on.clipboard"))
        menu.addItem(item("Bilddatei öffnen …", #selector(openFile), symbol: "folder"))

        let historyItem = NSMenuItem(title: "Letzte Aufnahmen", action: nil, keyEquivalent: "")
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let historyMenu = NSMenu()
        if history.isEmpty {
            let empty = NSMenuItem(title: "Keine Aufnahmen", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            let f = DateFormatter()
            f.timeStyle = .medium
            for (i, h) in history.enumerated() {
                let entry = NSMenuItem(title: "\(f.string(from: h.date))  –  \(h.image.width) × \(h.image.height)",
                                       action: #selector(openHistory(_:)), keyEquivalent: "")
                entry.target = self
                entry.tag = i
                let w: CGFloat = 64
                let hgt = max(8, w * CGFloat(h.image.height) / CGFloat(max(1, h.image.width)))
                entry.image = NSImage(cgImage: h.image, size: CGSize(width: w, height: min(hgt, 64)))
                historyMenu.addItem(entry)
            }
            historyMenu.addItem(.separator())
            historyMenu.addItem(item("Verlauf leeren", #selector(clearHistory)))
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        menu.addItem(.separator())

        let afterItem = NSMenuItem(title: "Nach der Aufnahme", action: nil, keyEquivalent: "")
        let afterMenu = NSMenu()
        for option in AfterCapture.allCases {
            let o = item(option.title, #selector(setAfterCapture(_:)))
            o.tag = option.rawValue
            o.state = Prefs.afterCapture == option ? .on : .off
            afterMenu.addItem(o)
        }
        afterItem.submenu = afterMenu
        menu.addItem(afterItem)

        let settings = item("Einstellungen …", #selector(openSettings), symbol: "gearshape")
        settings.keyEquivalent = ","
        menu.addItem(settings)

        if !ScreenCapture.hasPermission {
            menu.addItem(.separator())
            menu.addItem(item("⚠︎ Bildschirmaufnahme erlauben …", #selector(openPermissionSettings)))
        }

        menu.addItem(.separator())
        let quit = item("GreenSnap beenden", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    private func symbol(for action: CaptureAction) -> String {
        switch action {
        case .region: return "rectangle.dashed"
        case .fullscreen: return "macwindow"
        case .lastRegion: return "arrow.counterclockwise"
        case .ocr: return "text.viewfinder"
        }
    }

    @objc private func menuCapture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = CaptureAction(rawValue: raw) else { return }
        runCapture(action, fromMenu: true)
    }

    @objc private func setAfterCapture(_ sender: NSMenuItem) {
        Prefs.afterCapture = AfterCapture(rawValue: sender.tag) ?? .openEditor
    }

    @objc private func openSettings() { SettingsWindowController.show() }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openPermissionSettings() {
        ScreenCapture.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openHistory(_ sender: NSMenuItem) {
        guard history.indices.contains(sender.tag) else { return }
        let h = history[sender.tag]
        EditorWindowController.open(image: h.image, scale: h.scale)
    }

    @objc func clearHistory() { history.removeAll() }

    @objc private func openFromClipboard() {
        guard let image = NSImage(pasteboard: NSPasteboard.general),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            HUD.show("Kein Bild in der Zwischenablage", symbol: "exclamationmark.triangle")
            return
        }
        let scale = max(1, (CGFloat(cg.width) / max(1, image.size.width)).rounded())
        EditorWindowController.open(image: cg, scale: scale)
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = max(1, (CGFloat(cg.width) / max(1, image.size.width)).rounded())
        EditorWindowController.open(image: cg, scale: scale)
    }

    // MARK: Hauptmenü (sichtbar, solange ein Editor offen ist)

    private func buildMainMenu() {
        let main = NSMenu()

        func menu(_ title: String, _ items: [NSMenuItem]) {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            items.forEach(sub.addItem)
            top.submenu = sub
            main.addItem(top)
        }
        func mi(_ title: String, _ action: Selector?, _ key: String = "",
                _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }

        menu("GreenSnap", [
            mi("Über GreenSnap", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            mi("Einstellungen …", #selector(openSettings), ",", target: self),
            .separator(),
            mi("GreenSnap ausblenden", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            mi("GreenSnap beenden", #selector(quit), "q", target: self),
        ])
        menu("Ablage", [
            mi("Bereich aufnehmen", #selector(menuRegion), target: self),
            mi("Bild aus Zwischenablage öffnen", #selector(openFromClipboard), target: self),
            mi("Bilddatei öffnen …", #selector(openFile), "o", target: self),
            .separator(),
            mi("Sichern unter …", #selector(EditorWindow.saveDocument(_:)), "s"),
            mi("Schließen", #selector(NSWindow.performClose(_:)), "w"),
        ])
        menu("Bearbeiten", [
            mi("Widerrufen", #selector(EditorWindow.editorUndo(_:)), "z"),
            mi("Wiederholen", #selector(EditorWindow.editorRedo(_:)), "z", [.command, .shift]),
            .separator(),
            mi("Ausschneiden", #selector(NSText.cut(_:)), "x"),
            mi("Kopieren", #selector(NSText.copy(_:)), "c"),
            mi("Einsetzen", #selector(NSText.paste(_:)), "v"),
            mi("Löschen", #selector(NSText.delete(_:))),
            mi("Alles auswählen", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            mi("Text erkennen und kopieren", #selector(EditorWindow.recognizeText(_:)), "t", [.command, .shift]),
            mi("Anheften", #selector(EditorWindow.pinImage(_:)), "p", [.command, .shift]),
        ])
        menu("Darstellung", [
            mi("Vergrößern", #selector(EditorWindow.zoomIn(_:)), "+"),
            mi("Verkleinern", #selector(EditorWindow.zoomOut(_:)), "-"),
            mi("Originalgröße", #selector(EditorWindow.zoomActualSize(_:)), "0"),
            mi("An Fenster anpassen", #selector(EditorWindow.zoomToFitWindow(_:)), "9"),
        ])
        let windowMenuItems = [
            mi("Im Dock ablegen", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ]
        menu("Fenster", windowMenuItems)
        NSApp.mainMenu = main
        NSApp.windowsMenu = main.items.last?.submenu
    }

    @objc private func menuRegion() { runCapture(.region, fromMenu: true) }

    // MARK: Aufnahme

    func runCapture(_ action: CaptureAction, fromMenu: Bool) {
        guard !isCapturing else {
            if selection != nil { selection?.cancel() }
            return
        }
        guard ScreenCapture.hasPermission else {
            showPermissionAlert()
            return
        }
        isCapturing = true
        Task { @MainActor in
            // Dem Menü Zeit zum Ausblenden geben
            if fromMenu { try? await Task.sleep(nanoseconds: 250_000_000) }
            do {
                switch action {
                case .region, .ocr:
                    try await startSelection(ocr: action == .ocr)
                case .fullscreen:
                    let caps = try await ScreenCapture.capture(screens: [ScreenCapture.screenUnderMouse])
                    isCapturing = false
                    if let cap = caps.first { deliver(cap.image, scale: cap.scale) }
                case .lastRegion:
                    try await captureLastRegion()
                    isCapturing = false
                }
            } catch {
                isCapturing = false
                showError(error)
            }
        }
    }

    @MainActor
    private func startSelection(ocr: Bool) async throws {
        let windows = ScreenCapture.visibleWindows()
        let caps = try await ScreenCapture.capture(screens: NSScreen.screens)
        let controller = SelectionController(captures: caps, windowInfos: windows) { [weak self] result in
            guard let self else { return }
            self.selection = nil
            guard let result else { self.isCapturing = false; return }
            Task { @MainActor in
                await self.handle(result, ocr: ocr)
                self.isCapturing = false
            }
        }
        selection = controller
        controller.begin()
    }

    @MainActor
    private func handle(_ result: SelectionController.Result, ocr: Bool) async {
        let image: CGImage?
        let scale: CGFloat
        switch result {
        case .region(let cap, let rect):
            scale = cap.scale
            image = ScreenCapture.crop(cap.image, toPoints: rect, scale: scale)
            lastRegion = LastRegion(displayID: cap.displayID, rect: rect)
        case .window(let cap, let info, let rect):
            scale = cap.scale
            lastRegion = LastRegion(displayID: cap.displayID, rect: rect)
            if !ocr, let win = try? await ScreenCapture.captureWindow(id: info.id, scale: scale) {
                image = win
            } else {
                image = ScreenCapture.crop(cap.image, toPoints: rect, scale: scale)
            }
        case .fullscreen(let cap):
            scale = cap.scale
            image = cap.image
        }
        guard let image else { return }
        if ocr {
            OCR.recognizeAndCopy(image)
        } else {
            deliver(image, scale: scale)
        }
    }

    @MainActor
    private func captureLastRegion() async throws {
        guard let last = lastRegion,
              let screen = NSScreen.screens.first(where: { ScreenCapture.displayID(of: $0) == last.displayID })
        else {
            HUD.show("Noch kein Bereich aufgenommen", symbol: "exclamationmark.triangle")
            return
        }
        let caps = try await ScreenCapture.capture(screens: [screen])
        guard let cap = caps.first,
              let image = ScreenCapture.crop(cap.image, toPoints: last.rect, scale: cap.scale) else { return }
        deliver(image, scale: cap.scale)
    }

    /// Verteilt eine fertige Aufnahme je nach Einstellung.
    private func deliver(_ image: CGImage, scale: CGFloat) {
        if Prefs.playSound { NSSound(named: "Tink")?.play() }
        if Prefs.keepHistory {
            history.insert(HistoryItem(image: image, scale: scale, date: Date()), at: 0)
            if history.count > 10 { history.removeLast(history.count - 10) }
        }
        switch Prefs.afterCapture {
        case .openEditor:
            EditorWindowController.open(image: image, scale: scale)
        case .copy:
            ImageExport.copyToClipboard(image, scale: scale)
            HUD.show("In Zwischenablage kopiert")
        case .copyAndEditor:
            ImageExport.copyToClipboard(image, scale: scale)
            EditorWindowController.open(image: image, scale: scale)
        case .pin:
            PinController.pin(image, scale: scale)
        }
    }

    private func showPermissionAlert() {
        ScreenCapture.requestPermission()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Bildschirmaufnahme erlauben"
        alert.informativeText = """
        GreenSnap braucht die Berechtigung „Bildschirm- und Systemaudioaufnahme“.

        Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- und Systemaudioaufnahme → GreenSnap aktivieren. \
        Danach GreenSnap einmal beenden und neu starten.
        """
        alert.addButton(withTitle: "Systemeinstellungen öffnen")
        alert.addButton(withTitle: "Später")
        if alert.runModal() == .alertFirstButtonReturn { openPermissionSettings() }
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Aufnahme fehlgeschlagen"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

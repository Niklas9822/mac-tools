import Cocoa

/// Verwaltet die Menüleiste: ein Pfeil zum Auf-/Zuklappen und unsichtbare Trennlinien.
///
/// Prinzip: Wird eine Trennlinie sehr breit (`collapsedLength`), schiebt sie alle Symbole links von ihr
/// aus dem sichtbaren Bereich der Menüleiste. Ist sie schmal, sind die Symbole wieder sichtbar.
///
///   [ immer ausgeblendet ]  ┆  [ ausgeblendet ]  │  [ sichtbar ]  ‹ Pfeil
///                     alwaysHidden          hidden
final class MenuBarController: NSObject, NSMenuDelegate {
    enum State { case collapsed, expanded, showAll }

    private static let collapsedLength: CGFloat = 10_000
    private static let separatorLength: CGFloat = 12

    private let toggleItem: NSStatusItem
    private let hiddenSeparator: NSStatusItem
    private var alwaysHiddenSeparator: NSStatusItem?
    private var autoCollapseTimer: Timer?

    private(set) var state: State = .expanded

    override init() {
        MenuBarController.seedPositions()
        // Reihenfolge wichtig: neu erstellte Symbole erscheinen links der zuvor erstellten.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = "BarkeeperToggle"
        hiddenSeparator = NSStatusBar.system.statusItem(withLength: MenuBarController.separatorLength)
        hiddenSeparator.autosaveName = "BarkeeperHidden"
        super.init()

        for item in [toggleItem, hiddenSeparator] {
            item.button?.target = self
            item.button?.action = #selector(itemClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        toggleItem.button?.toolTip = "Barkeeper – Klick: ein-/ausklappen · ⌥-Klick: alles zeigen · Rechtsklick: Menü"
        hiddenSeparator.button?.toolTip = "Barkeeper: Symbole links dieser Linie werden ausgeblendet (⌘-Ziehen zum Sortieren)"

        updateAlwaysHiddenSection()
        apply()
    }

    /// Startpositionen festlegen, damit der Pfeil rechts der Trennlinien liegt (nur beim allerersten Start).
    private static func seedPositions() {
        let d = UserDefaults.standard
        let seeds: [(String, Double)] = [
            ("BarkeeperToggle", 0), ("BarkeeperHidden", 1), ("BarkeeperAlwaysHidden", 2),
        ]
        for (name, pos) in seeds {
            let key = "NSStatusItem Preferred Position \(name)"
            if d.object(forKey: key) == nil { d.set(pos, forKey: key) }
        }
    }

    // MARK: Einstellungen

    func updateAlwaysHiddenSection() {
        if Prefs.alwaysHiddenEnabled, alwaysHiddenSeparator == nil {
            let item = NSStatusBar.system.statusItem(withLength: MenuBarController.separatorLength)
            item.autosaveName = "BarkeeperAlwaysHidden"
            item.button?.target = self
            item.button?.action = #selector(itemClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.toolTip = "Barkeeper: Symbole links dieser Linie bleiben immer ausgeblendet (⌥-Klick auf den Pfeil zeigt sie)"
            alwaysHiddenSeparator = item
        } else if !Prefs.alwaysHiddenEnabled, let item = alwaysHiddenSeparator {
            NSStatusBar.system.removeStatusItem(item)
            alwaysHiddenSeparator = nil
            if state == .showAll { state = .expanded }
        }
        apply()
    }

    func settingsChanged() {
        updateAlwaysHiddenSection()
    }

    // MARK: Zustände

    func toggle() {
        state == .collapsed ? expand() : collapse()
    }

    func expand() {
        state = .expanded
        apply()
    }

    func showAll() {
        guard alwaysHiddenSeparator != nil else { expand(); return }
        guard checkOrder(includeAlwaysHidden: true) else { return }
        state = .showAll
        apply()
    }

    func collapse() {
        guard checkOrder(includeAlwaysHidden: false) else { return }
        state = .collapsed
        apply()
    }

    /// Sicherheitsprüfung: Liegt der Pfeil links der Trennlinie, würde er sich selbst ausblenden.
    private func checkOrder(includeAlwaysHidden: Bool) -> Bool {
        guard let toggleFrame = toggleItem.button?.window?.frame,
              let hiddenFrame = hiddenSeparator.button?.window?.frame,
              hiddenSeparator.length < MenuBarController.collapsedLength else { return true }
        var ok = toggleFrame.minX >= hiddenFrame.maxX - 1
        if includeAlwaysHidden, let a = alwaysHiddenSeparator?.button?.window?.frame,
           alwaysHiddenSeparator!.length < MenuBarController.collapsedLength {
            ok = ok && hiddenFrame.minX >= a.maxX - 1
        }
        if !ok {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Reihenfolge in der Menüleiste stimmt nicht"
            alert.informativeText = """
            Der Pfeil ‹ muss rechts von der Trennlinie │ stehen\(includeAlwaysHidden ? ", und die gestrichelte Linie ┆ links davon" : "").

            Halte ⌘ gedrückt und ziehe die Symbole in der Menüleiste an die richtige Stelle.
            """
            alert.runModal()
        }
        return ok
    }

    private func apply() {
        let showLines = Prefs.showSeparators
        switch state {
        case .collapsed:
            hiddenSeparator.length = MenuBarController.collapsedLength
            hiddenSeparator.button?.image = nil
            setAlwaysHidden(collapsed: true)
        case .expanded:
            setSeparator(hiddenSeparator, dashed: false, visible: showLines)
            setAlwaysHidden(collapsed: true)
        case .showAll:
            setSeparator(hiddenSeparator, dashed: false, visible: showLines)
            setAlwaysHidden(collapsed: false)
        }

        let symbol = state == .collapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Barkeeper")
        image?.isTemplate = true
        toggleItem.button?.image = image

        scheduleAutoCollapse()
    }

    private func setAlwaysHidden(collapsed: Bool) {
        guard let item = alwaysHiddenSeparator else { return }
        if collapsed {
            item.length = MenuBarController.collapsedLength
            item.button?.image = nil
        } else {
            setSeparator(item, dashed: true, visible: true)
        }
    }

    private func setSeparator(_ item: NSStatusItem, dashed: Bool, visible: Bool) {
        item.length = visible ? MenuBarController.separatorLength : 4
        item.button?.image = visible ? MenuBarController.lineImage(dashed: dashed) : nil
    }

    private static func lineImage(dashed: Bool) -> NSImage {
        let image = NSImage(size: CGSize(width: 6, height: 16), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 3, y: 2))
            path.line(to: CGPoint(x: 3, y: 14))
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            if dashed { path.setLineDash([2, 2.5], count: 2, phase: 0) }
            NSColor.black.withAlphaComponent(0.6).setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Automatisch einklappen

    private func scheduleAutoCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        let seconds = Prefs.autoCollapseSeconds
        guard state != .collapsed, seconds > 0 else { return }
        let t = Timer(timeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            self?.autoCollapseFired()
        }
        RunLoop.main.add(t, forMode: .common)
        autoCollapseTimer = t
    }

    private func autoCollapseFired() {
        // Nicht einklappen, solange die Maus in der Menüleiste ist (z. B. ein Menü offen ist).
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           mouse.y >= screen.frame.maxY - NSStatusBar.system.thickness - 2 {
            scheduleAutoCollapse()
            return
        }
        guard state != .collapsed else { return }
        // Ohne Rückfrage-Dialog: bei falscher Reihenfolge lieber ausgeklappt lassen.
        if let toggleFrame = toggleItem.button?.window?.frame,
           let hiddenFrame = hiddenSeparator.button?.window?.frame,
           toggleFrame.minX < hiddenFrame.maxX - 1 { return }
        state = .collapsed
        apply()
    }

    // MARK: Klicks & Menü

    @objc private func itemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        if event?.modifierFlags.contains(.option) == true, alwaysHiddenSeparator != nil {
            state == .showAll ? collapse() : showAll()
            return
        }
        toggle()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let toggleTitle = state == .collapsed ? "Ausgeblendete Symbole zeigen" : "Symbole ausblenden"
        menu.addItem(item(toggleTitle, #selector(menuToggle)))
        if alwaysHiddenSeparator != nil {
            menu.addItem(item("Alle Symbole zeigen (auch „immer ausgeblendet“)", #selector(menuShowAll)))
        }
        menu.addItem(.separator())
        menu.addItem(item("So funktioniert's …", #selector(menuHelp)))
        let settings = item("Einstellungen …", #selector(menuSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = item("Barkeeper beenden", #selector(menuQuit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Menü wieder lösen, damit ein normaler Klick weiter ein-/ausklappt.
        DispatchQueue.main.async { self.toggleItem.menu = nil }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuShowAll() { showAll() }
    @objc private func menuHelp() { MenuBarController.showHelp() }
    @objc private func menuSettings() { SettingsWindowController.show() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    static func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "So funktioniert Barkeeper"
        alert.informativeText = """
        In deiner Menüleiste gibt es jetzt einen Pfeil ‹ und eine Trennlinie │.

        • Alle Symbole LINKS der Trennlinie werden ausgeblendet, wenn du auf den Pfeil klickst.
        • Symbole RECHTS der Trennlinie bleiben immer sichtbar.
        • Zum Sortieren: ⌘ (Befehlstaste) gedrückt halten und Symbole in der Menüleiste verschieben.
          Vorher ausklappen, damit alle Symbole sichtbar sind.

        Klick auf den Pfeil: ein-/ausklappen
        ⌥-Klick: auch den Bereich „immer ausgeblendet“ zeigen (falls in den Einstellungen aktiviert)
        Rechtsklick: Menü mit Einstellungen
        """
        alert.runModal()
    }
}

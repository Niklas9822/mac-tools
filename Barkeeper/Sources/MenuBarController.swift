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

    /// Breite, mit der das Ausblenden auf diesem System tatsächlich funktioniert (wird gemessen).
    private var fittedLength: [ObjectIdentifier: CGFloat] = [:]
    private var hideGeneration = 0
    private var log: [String] = []
    private var didWarnFailure = false

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

        note("Gestartet")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.note("3 s nach Start") }

        // Die Menüs der aktiven App bestimmen, wie viel Platz es gibt – bei App-Wechsel neu messen.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeAppChanged),
                                                          name: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil)
    }

    @objc private func activeAppChanged() {
        note("App-Wechsel – neu messen")
        fittedLength.removeAll()
        switch state {
        case .collapsed: hide(hiddenSeparator)
        case .expanded: if let a = alwaysHiddenSeparator { hide(a) }
        case .showAll: break
        }
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
        note("Einklappen angefordert")
        guard checkOrder(includeAlwaysHidden: false) else { return }
        state = .collapsed
        apply()
    }

    private func isWide(_ item: NSStatusItem) -> Bool { item.length > 100 }

    /// Sicherheitsprüfung: Liegt der Pfeil links der Trennlinie, würde er sich selbst ausblenden.
    private func checkOrder(includeAlwaysHidden: Bool) -> Bool {
        guard let toggleFrame = toggleItem.button?.window?.frame,
              let hiddenFrame = hiddenSeparator.button?.window?.frame,
              !isWide(hiddenSeparator) else { return true }
        var ok = toggleFrame.minX >= hiddenFrame.maxX - 1
        if includeAlwaysHidden, let a = alwaysHiddenSeparator?.button?.window?.frame,
           !isWide(alwaysHiddenSeparator!) {
            ok = ok && hiddenFrame.minX >= a.maxX - 1
        }
        note("Reihenfolge-Prüfung: Pfeil \(toggleFrame), Linie \(hiddenFrame) → \(ok ? "ok" : "FALSCH")")
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
        hideGeneration += 1 // laufende Messungen abbrechen
        let showLines = Prefs.showSeparators
        switch state {
        case .collapsed:
            // Der Bereich „immer ausgeblendet“ liegt links und wird mit verdrängt.
            if let a = alwaysHiddenSeparator { setSeparator(a, dashed: true, visible: false) }
            hide(hiddenSeparator)
        case .expanded:
            setSeparator(hiddenSeparator, dashed: false, visible: showLines)
            if let a = alwaysHiddenSeparator { hide(a) }
        case .showAll:
            setSeparator(hiddenSeparator, dashed: false, visible: showLines)
            setAlwaysHidden(collapsed: false)
        }

        let symbol = state == .collapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Barkeeper")
        image?.isTemplate = true
        toggleItem.button?.image = image

        scheduleAutoCollapse()
        note("Zustand: \(state)")
        let gen = hideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, gen == self.hideGeneration else { return }
            if !self.isShown(self.toggleItem) { self.note("Achtung: Pfeil nach Zustandswechsel nicht sichtbar") }
            self.writeDiagnosticsFile()
        }
    }

    private func setAlwaysHidden(collapsed: Bool) {
        guard let item = alwaysHiddenSeparator else { return }
        if collapsed { hide(item) } else { setSeparator(item, dashed: true, visible: true) }
    }

    // MARK: Ausblenden mit Messung

    /// Macht eine Trennlinie so breit, dass alle Symbole links von ihr aus der Menüleiste verdrängt werden.
    /// Klassisch genügt eine riesige Breite. Neuere macOS-Versionen verstecken aber ein Symbol, das nicht
    /// mehr passt, statt die anderen zu verdrängen – dann wird die größte noch passende Breite gesucht.
    private func hide(_ item: NSStatusItem) {
        hideGeneration += 1
        let gen = hideGeneration
        let key = ObjectIdentifier(item)

        // 1. Schmal machen, damit die Position stimmt, und die Symbole links davon merken.
        if isWide(item) { item.length = MenuBarController.separatorLength }
        item.button?.image = nil
        after(0.12, gen) {
            guard self.isShown(self.toggleItem) else {
                self.note("Pfeil schon vor dem Ausblenden nicht sichtbar – abgebrochen")
                self.writeDiagnosticsFile()
                return
            }
            let sepFrame = self.cgFrame(of: item)
            let sepX = sepFrame?.minX ?? item.button?.window?.frame.minX ?? 0
            let targets = self.statusWindows(allLayers: true).filter {
                $0.layer > 0 && $0.frame.maxX <= sepX + 1 && (sepFrame == nil || abs($0.frame.minY - sepFrame!.minY) < 30)
            }
            let targetIDs = Set(targets.map(\.id))
            self.note("Ausblenden: \(targets.count) Symbole links der Linie (Linie bei x=\(Int(sepX)), CG \(sepFrame == nil ? "unbekannt" : "ok"))")

            // 2. Zuerst bekannte bzw. klassische Breite probieren.
            item.length = self.fittedLength[key] ?? MenuBarController.collapsedLength
            self.after(0.25, gen) {
                let visible = self.visibleCount(targetIDs)
                let toggleShown = self.isShown(self.toggleItem)
                if toggleShown && !targetIDs.isEmpty && visible == 0 {
                    self.note("OK mit Breite \(Int(item.length))")
                    self.writeDiagnosticsFile()
                    return
                }
                self.note("Breite \(Int(item.length)): Pfeil \(toggleShown ? "sichtbar" : "WEG"), noch \(visible) von \(targetIDs.count) sichtbar – suche passende Breite")
                let screenWidth = (self.toggleItem.button?.window?.screen ?? NSScreen.main)?.frame.width ?? 3000
                self.search(item, key: key, lo: MenuBarController.separatorLength, hi: screenWidth,
                            targets: targetIDs, gen: gen)
            }
        }
    }

    private func search(_ item: NSStatusItem, key: ObjectIdentifier, lo: CGFloat, hi: CGFloat,
                        targets: Set<CGWindowID>, gen: Int) {
        if hi - lo < 4 {
            item.length = lo
            after(0.2, gen) {
                let visible = self.visibleCount(targets)
                let toggleShown = self.isShown(self.toggleItem)
                self.note("Ergebnis: Breite \(Int(lo)), Pfeil \(toggleShown ? "sichtbar" : "WEG"), noch sichtbar: \(visible) von \(targets.count)")
                if !toggleShown {
                    // Sicherheitsnetz: niemals den eigenen Pfeil verstecken.
                    item.length = MenuBarController.separatorLength
                    self.note("Sicherheitsnetz: Linie zurückgesetzt")
                } else {
                    self.fittedLength[key] = lo
                }
                self.writeDiagnosticsFile()
                if !toggleShown || visible > 0 || targets.isEmpty { self.warnFailure() }
            }
            return
        }
        let mid = ((lo + hi) / 2).rounded()
        item.length = mid
        after(0.12, gen) {
            if self.isShown(item) && self.isShown(self.toggleItem) {
                self.search(item, key: key, lo: mid, hi: hi, targets: targets, gen: gen)
            } else {
                self.search(item, key: key, lo: lo, hi: mid, targets: targets, gen: gen)
            }
        }
    }

    private func after(_ seconds: Double, _ gen: Int, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, gen == self.hideGeneration else { return }
            block()
        }
    }

    private struct BarWindow {
        let id: CGWindowID
        let frame: CGRect
        let owner: String
        let layer: Int
    }

    /// Sichtbare Fenster in Höhe der Menüleiste (Status-Symbole), globale Koordinaten oben links.
    private func statusWindows(allLayers: Bool = false) -> [BarWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let screens = NSScreen.screens.map(\.frame)
        let primaryHeight = screens.first?.height ?? 0
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  allLayers || layer == statusLayer,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  frame.height <= 60, frame.width > 0 else { return nil }
            // muss auf einem Bildschirm liegen (oben, in der Menüleiste)
            let onScreen = screens.contains { s in
                let top = primaryHeight - s.maxY
                return frame.minX >= s.minX - 1 && frame.maxX <= s.maxX + 1 && abs(frame.minY - top) < 40
            }
            guard onScreen else { return nil }
            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            return BarWindow(id: number, frame: frame, owner: owner, layer: layer)
        }
    }

    /// Prüft über das eigene Fenster, ob ein Barkeeper-Symbol tatsächlich in der Menüleiste zu sehen ist.
    private func isShown(_ item: NSStatusItem) -> Bool {
        guard let w = item.button?.window, w.isVisible, w.frame.width > 0 else { return false }
        let f = w.frame
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: f.midX, y: f.midY)) }) else { return false }
        return f.minX >= screen.frame.minX - 1 && f.maxX <= screen.frame.maxX + 1 && w.occlusionState.contains(.visible)
    }

    /// Rahmen unseres Status-Symbols, falls es sichtbar in der Menüleiste steht.
    private func cgFrame(of item: NSStatusItem) -> CGRect? {
        guard let number = item.button?.window?.windowNumber, number > 0 else { return nil }
        return statusWindows(allLayers: true).first { $0.id == CGWindowID(number) }?.frame
    }

    private func visibleCount(_ targets: Set<CGWindowID>) -> Int {
        statusWindows(allLayers: true).filter { targets.contains($0.id) }.count
    }

    private func note(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        log.append("\(f.string(from: Date())) \(s)")
        if log.count > 60 { log.removeFirst(log.count - 60) }
        writeDiagnosticsFile()
    }

    private func warnFailure() {
        guard !didWarnFailure else { return }
        didWarnFailure = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Ausblenden hat nicht geklappt"
        alert.informativeText = """
        Auf dieser macOS-Version konnte Barkeeper die Symbole nicht zuverlässig verdrängen. Barkeeper bleibt ausgeklappt.

        Bitte „Diagnose kopieren“ wählen und den Text an den Entwickler schicken – damit lässt sich das gezielt beheben.
        """
        alert.addButton(withTitle: "Diagnose kopieren")
        alert.addButton(withTitle: "Schließen")
        if alert.runModal() == .alertFirstButtonReturn { copyDiagnostics() }
        if state == .collapsed { expand() }
    }

    static var diagnosticsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Barkeeper-Diagnose.txt")
    }

    private func writeDiagnosticsFile() {
        try? FileManager.default.createDirectory(at: MenuBarController.diagnosticsFile.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? diagnosticsText().write(to: MenuBarController.diagnosticsFile, atomically: true, encoding: .utf8)
    }

    func copyDiagnostics() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(diagnosticsText(), forType: .string)
    }

    private func diagnosticsText() -> String {
        var lines: [String] = []
        lines.append("Barkeeper-Diagnose")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        lines.append("Barkeeper: \(version), Zustand: \(state)")
        for (i, s) in NSScreen.screens.enumerated() {
            lines.append("Bildschirm \(i): \(s.frame) sichtbar \(s.visibleFrame) Notch-Bereiche: \(s.auxiliaryTopLeftArea.map { "\($0)" } ?? "-") / \(s.auxiliaryTopRightArea.map { "\($0)" } ?? "-")")
        }
        let ours: [(String, NSStatusItem?)] = [("Pfeil", toggleItem), ("Linie", hiddenSeparator), ("Immer-Linie", alwaysHiddenSeparator)]
        for (name, item) in ours {
            guard let item else { continue }
            let w = item.button?.window
            lines.append("\(name): angezeigt \(isShown(item)), Länge \(Int(item.length)), Fenster \(w?.windowNumber ?? -1), Rahmen \(w?.frame ?? .zero), sichtbar \(w?.occlusionState.contains(.visible) ?? false), CG \(cgFrame(of: item).map { "\($0)" } ?? "nicht sichtbar")")
        }
        lines.append("Fenster in der Menüleiste:")
        for w in statusWindows(allLayers: true).sorted(by: { $0.frame.minX < $1.frame.minX }) {
            lines.append("  #\(w.id) Ebene \(w.layer) \(w.owner): x=\(Int(w.frame.minX)) y=\(Int(w.frame.minY)) b=\(Int(w.frame.width)) h=\(Int(w.frame.height))")
        }
        lines.append("Protokoll:")
        lines.append(contentsOf: log.map { "  " + $0 })
        return lines.joined(separator: "\n")
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
        guard !isWide(hiddenSeparator) else { return }
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
        menu.addItem(item("Diagnose kopieren", #selector(menuDiagnostics)))
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
    @objc private func menuDiagnostics() {
        copyDiagnostics()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Diagnose kopiert"
        alert.informativeText = "Der Text liegt in der Zwischenablage und kann jetzt eingefügt werden (⌘V)."
        alert.runModal()
    }
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

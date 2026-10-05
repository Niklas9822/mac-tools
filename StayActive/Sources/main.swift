// StayActive – kleine Menüleisten-App für macOS, die den Mac aktiv hält,
// damit z. B. Microsoft Teams den Status nicht auf "Abwesend" setzt.
//
// Mechanismen (alle nur, solange StayActive aktiv ist):
//  1. ProcessInfo-Activity: verhindert Ruhezustand von System + Display und App Nap.
//  2. IOPMAssertionDeclareUserActivity: meldet dem System regelmäßig "Nutzer aktiv"
//     (setzt Idle-Timer, Bildschirmschoner usw. zurück).
//  3. Optionaler Maus-Impuls: bewegt den Mauszeiger um 1 px hin und zurück, wenn du
//     gerade nicht aktiv bist. Das ist das, was Teams sicher als Aktivität erkennt.
//     Benötigt "Bedienungshilfen"-Berechtigung.
//
// Bedienung (ähnlich wie Amphetamine):
//  - Klick auf die Tasse öffnet das Menü, ⌥-Klick schaltet direkt ein/aus.
//  - "Starten für …" startet sofort mit fester Dauer; die Restzeit steht neben der Tasse.
//  - Start/Stopp/Ablauf werden kurz eingeblendet (HUD) – ohne Mitteilungs-Berechtigung.

import Cocoa
import IOKit.pwr_mgt
import ApplicationServices
import ServiceManagement

// MARK: - Einstellungen

enum Prefs {
    private static let d = UserDefaults.standard

    static var enabled: Bool {
        get { d.object(forKey: "enabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "enabled") }
    }
    static var jiggleMouse: Bool {
        get { d.object(forKey: "jiggleMouse") as? Bool ?? true }
        set { d.set(newValue, forKey: "jiggleMouse") }
    }
    /// Sekunden zwischen zwei Aktivitäts-Impulsen.
    static var interval: TimeInterval {
        get { d.object(forKey: "interval") as? TimeInterval ?? 60 }
        set { d.set(newValue, forKey: "interval") }
    }
    /// Ende des laufenden Zeitraums (nil = unbegrenzt). Überlebt einen Neustart der App.
    static var endDate: Date? {
        get { d.object(forKey: "endDate") as? Date }
        set { d.set(newValue, forKey: "endDate") }
    }
    /// Beginn des laufenden Zeitraums (für den Fortschrittsbalken).
    static var startDate: Date? {
        get { d.object(forKey: "startDate") as? Date }
        set { d.set(newValue, forKey: "startDate") }
    }
    /// Welche Auswahl unter "Starten für …" aktiv ist (für das Häkchen).
    static var preset: String? {
        get { d.string(forKey: "preset") }
        set { d.set(newValue, forKey: "preset") }
    }
    /// Feierabend als Minuten nach Mitternacht (Standard 17:00).
    static var workEndMinutes: Int {
        get { d.object(forKey: "workEndMinutes") as? Int ?? 17 * 60 }
        set { d.set(newValue, forKey: "workEndMinutes") }
    }
    /// Beim Start der App immer aktivieren (unbegrenzt), auch wenn zuletzt ausgeschaltet.
    static var activateOnLaunch: Bool {
        get { d.object(forKey: "activateOnLaunch") as? Bool ?? false }
        set { d.set(newValue, forKey: "activateOnLaunch") }
    }
    /// Restzeit neben dem Symbol in der Menüleiste anzeigen.
    static var showCountdown: Bool {
        get { d.object(forKey: "showCountdown") as? Bool ?? true }
        set { d.set(newValue, forKey: "showCountdown") }
    }
    /// Kurze Bestätigung (HUD) bei Start/Stopp/Ablauf einblenden.
    static var showHUD: Bool {
        get { d.object(forKey: "showHUD") as? Bool ?? true }
        set { d.set(newValue, forKey: "showHUD") }
    }
}

// MARK: - Zeit-Texte

enum TimeText {
    /// "1 Std. 23 Min.", "45 Min.", "2 Std.", "30 Sek." (Minuten aufgerundet).
    static func long(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds.rounded(.up)))) Sek." }
        let total = Int((seconds / 60).rounded(.up))
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) Min." }
        if m == 0 { return "\(h) Std." }
        return "\(h) Std. \(m) Min."
    }

    /// Kurzform für die Menüleiste: "1:23" (Std:Min) bzw. "45 s" in der letzten Minute.
    static func short(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds.rounded(.up)))) s" }
        let total = Int((seconds / 60).rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "15:40", "morgen 08:00" oder "Mi. 08:00".
    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        let time = f.string(from: date)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time }
        if cal.isDateInTomorrow(date) { return "morgen \(time)" }
        f.dateFormat = "EEE HH:mm"
        return f.string(from: date)
    }

    static func clock(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Eingabe für "Eigene Dauer": "90" (Minuten), "1:30" (Std:Min), "2h" / "1,5 Std" (Stunden).
    static func parseDuration(_ input: String) -> TimeInterval? {
        let s = input.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: ",", with: ".")
        if s.isEmpty { return nil }
        var result: TimeInterval?
        if s.contains(":") {
            let parts = s.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h >= 0, m >= 0 {
                result = TimeInterval(h * 3600 + m * 60)
            }
        } else if s.hasSuffix("h") || s.contains("std") {
            let number = s.replacingOccurrences(of: "std.", with: "")
                .replacingOccurrences(of: "std", with: "")
                .replacingOccurrences(of: "h", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let h = Double(number) { result = h * 3600 }
        } else {
            let number = s.replacingOccurrences(of: "min.", with: "")
                .replacingOccurrences(of: "min", with: "")
                .replacingOccurrences(of: "m", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let m = Double(number) { result = m * 60 }
        }
        guard let r = result, r >= 60, r <= 7 * 24 * 3600 else { return nil }
        return r
    }
}

// MARK: - Aktiv-Halten

final class KeepAlive {
    private var activity: NSObjectProtocol?
    private var userActivityID: IOPMAssertionID = IOPMAssertionID(0)
    private var timer: Timer?

    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "StayActive hält den Mac aktiv"
        )
        tick()
        scheduleTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        if userActivityID != 0 {
            IOPMAssertionRelease(userActivityID)
            userActivityID = 0
        }
    }

    /// Nach Änderung des Intervalls neu planen.
    func reschedule() {
        guard isRunning else { return }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: Prefs.interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Sekunden seit der letzten echten Eingabe (Maus/Tastatur).
    static func systemIdleSeconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~UInt32(0)) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    private func tick() {
        // Wenn du gerade selbst aktiv bist, nichts tun – kein Zucken beim Arbeiten.
        let idle = Self.systemIdleSeconds()
        guard idle >= min(Prefs.interval * 0.8, 50) else { return }

        IOPMAssertionDeclareUserActivity("StayActive" as CFString, kIOPMUserActiveLocal, &userActivityID)

        if Prefs.jiggleMouse && AXIsProcessTrusted() {
            Self.nudgeMouse()
        }
    }

    /// Bewegt den Mauszeiger um 1 px und sofort wieder zurück.
    static func nudgeMouse() {
        guard let location = CGEvent(source: nil)?.location else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let shifted = CGPoint(x: location.x + 1, y: location.y)
        for point in [shifted, location] {
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}

// MARK: - HUD (kurze Bestätigung oben in der Bildschirmmitte)

enum HUD {
    private static var window: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String, duration: TimeInterval = 1.6) {
        guard Prefs.showHUD else { return }
        hideWork?.cancel()
        window?.orderOut(nil)

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
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

        // Bildschirm mit der Menüleiste, knapp unterhalb der Menüleiste mittig.
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 14,
                           width: size.width, height: size.height)
        let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            w.animator().alphaValue = 1
        }
        window = w

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                w.animator().alphaValue = 0
            }, completionHandler: {
                w.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

// MARK: - Kopfzeile im Menü (Status + Fortschrittsbalken)

final class ProgressBarView: NSView {
    /// 0 … 1 = verbleibender Anteil.
    var fraction: Double = 1 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let radius = r.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        let f = CGFloat(min(1, max(0, fraction)))
        guard f > 0 else { return }
        let fill = NSRect(x: r.minX, y: r.minY, width: max(r.height, r.width * f), height: r.height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}

final class StatusHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let bar = ProgressBarView()

    private let inset: CGFloat = 16
    private let top: CGFloat = 8
    private let titleHeight: CGFloat = 19
    private let detailHeight: CGFloat = 16
    private let barHeight: CGFloat = 6

    override var isFlipped: Bool { true }

    init(showsBar: Bool) {
        // oben 8 + Titel 19 + 2 + Detail 16 + unten 8, mit Balken zusätzlich 6 + 8.
        let height: CGFloat = showsBar ? 67 : 53
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: height))
        autoresizingMask = [.width]
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        addSubview(detailLabel)
        if showsBar { addSubview(bar) }
        layoutContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    func update(title: String, detail: String, fraction: Double?) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        if let fraction {
            bar.fraction = fraction
            bar.isHidden = false
        } else {
            bar.isHidden = true
        }
        // Breit genug für den Text (das Menü übernimmt die größte Breite).
        let needed = max(titleLabel.fittingSize.width, detailLabel.fittingSize.width) + 2 * inset + 4
        if needed > frame.width { setFrameSize(NSSize(width: needed, height: frame.height)) }
    }

    private func layoutContent() {
        let w = max(0, bounds.width - 2 * inset)
        titleLabel.frame = NSRect(x: inset, y: top, width: w, height: titleHeight)
        detailLabel.frame = NSRect(x: inset, y: top + titleHeight + 2, width: w, height: detailHeight)
        bar.frame = NSRect(x: inset, y: top + titleHeight + 2 + detailHeight + 8, width: w, height: barHeight)
    }
}

// MARK: - App / Menüleiste

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let keepAlive = KeepAlive()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var headerView: StatusHeaderView?
    private var tickTimer: Timer?

    private let intervals: [(String, TimeInterval)] = [
        ("30 Sekunden", 30), ("1 Minute", 60), ("2 Minuten", 120), ("4 Minuten", 240),
    ]
    private let durations: [TimeInterval] = [15 * 60, 30 * 60, 3600, 2 * 3600, 4 * 3600, 8 * 3600]

    private static let presetUnlimited = "unlimited"
    private static let presetWorkEnd = "workEnd"
    private static let presetUntil = "until"
    private static let presetCustom = "custom"
    private static func presetID(_ seconds: TimeInterval) -> String { "d\(Int(seconds))" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        menu.autoenablesItems = false
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            _ = button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        restoreState()
        if Prefs.jiggleMouse && !AXIsProcessTrusted() { requestAccessibility() }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Prefs (enabled/endDate) bleiben stehen, damit ein Neustart den Zeitraum fortsetzt.
        keepAlive.stop()
    }

    /// Zustand nach Neustart wiederherstellen: laufender Zeitraum läuft weiter, abgelaufener ist aus.
    private func restoreState() {
        if let end = Prefs.endDate {
            if Prefs.enabled && end > Date() {
                keepAlive.start()
                return
            }
            Prefs.endDate = nil
            Prefs.startDate = nil
            Prefs.preset = nil
            Prefs.enabled = false
        }
        if Prefs.enabled || Prefs.activateOnLaunch {
            Prefs.enabled = true
            if Prefs.preset == nil { Prefs.preset = Self.presetUnlimited }
            keepAlive.start()
        }
    }

    @objc private func didWake() {
        tick()
    }

    // MARK: Status-Symbol

    @objc private func statusItemClicked(_ sender: Any?) {
        // ⌥-Klick: direkt ein-/ausschalten, ohne Menü.
        if NSEvent.modifierFlags.contains(.option) {
            if keepAlive.isRunning {
                deactivate()
            } else {
                activate(until: nil, preset: Self.presetUnlimited)
            }
            return
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
        headerView = nil
    }

    /// Restzeit, falls ein Zeitraum läuft (nil = aus oder unbegrenzt).
    private func remaining() -> TimeInterval? {
        guard keepAlive.isRunning, let end = Prefs.endDate else { return nil }
        return max(0, end.timeIntervalSinceNow)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let name = keepAlive.isRunning ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "StayActive")
        image?.isTemplate = true
        button.image = image

        var title = ""
        if Prefs.showCountdown, let rem = remaining() {
            title = TimeText.short(rem)
        }
        if title.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        } else {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.attributedTitle = NSAttributedString(string: " " + title, attributes: [.font: font])
            button.imagePosition = .imageLeading
        }

        let hint = "\n⌥-Klick: direkt ein-/ausschalten"
        if !keepAlive.isRunning {
            button.toolTip = "StayActive: aus – Mac darf schlafen" + hint
        } else if let rem = remaining(), let end = Prefs.endDate {
            button.toolTip = "StayActive: aktiv – noch \(TimeText.long(rem)) (bis \(TimeText.clock(end)))" + hint
        } else {
            button.toolTip = "StayActive: aktiv – unbegrenzt" + hint
        }
    }

    // MARK: Aktualisieren / Countdown

    private func refresh() {
        updateStatusButton()
        updateHeader()
        scheduleTick()
    }

    /// Plant die nächste Aktualisierung genau dann, wenn sich die angezeigte Restzeit ändert
    /// (minutengenau, in der letzten Minute sekündlich).
    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = nil
        guard let rem = remaining() else { return }
        let delay: TimeInterval
        if rem <= 61 {
            delay = max(0.05, min(1, rem))
        } else {
            let shownMinutes = (rem / 60).rounded(.up)
            delay = rem - (shownMinutes - 1) * 60 + 0.05
        }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = rem <= 61 ? 0.1 : 1
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func tick() {
        if keepAlive.isRunning, let end = Prefs.endDate, end <= Date() {
            deactivate(expired: true)
        } else {
            refresh()
        }
    }

    // MARK: Ein / Aus

    private func activate(until end: Date?, preset: String?) {
        Prefs.enabled = true
        Prefs.endDate = end
        Prefs.startDate = end == nil ? nil : Date()
        Prefs.preset = preset
        keepAlive.start()
        refresh()
        if let end {
            HUD.show("Aktiv für \(TimeText.long(end.timeIntervalSinceNow)) – bis \(TimeText.clock(end))",
                     symbol: "cup.and.saucer.fill")
        } else {
            HUD.show("Aktiv – unbegrenzt", symbol: "cup.and.saucer.fill")
        }
    }

    private func deactivate(expired: Bool = false) {
        Prefs.enabled = false
        Prefs.endDate = nil
        Prefs.startDate = nil
        Prefs.preset = nil
        keepAlive.stop()
        refresh()
        if expired {
            HUD.show("StayActive aus – Mac darf wieder schlafen", symbol: "moon.zzz.fill", duration: 3)
        } else {
            HUD.show("Ausgeschaltet – Mac darf schlafen", symbol: "moon.zzz.fill")
        }
    }

    // MARK: Menü

    private func headerTexts() -> (title: String, detail: String, fraction: Double?) {
        guard keepAlive.isRunning else {
            return ("Aus – Mac darf schlafen", "Wähle unten, wie lange er wach bleiben soll.", nil)
        }
        guard let rem = remaining(), let end = Prefs.endDate else {
            return ("Aktiv – unbegrenzt", "Mac bleibt wach, bis du ausschaltest.", nil)
        }
        var fraction: Double?
        if let start = Prefs.startDate {
            let total = end.timeIntervalSince(start)
            if total > 0 { fraction = rem / total }
        }
        return ("Aktiv – noch \(TimeText.long(rem))",
                "bis \(TimeText.clock(end)), danach darf er wieder schlafen", fraction)
    }

    private func updateHeader() {
        guard let headerView else { return }
        let t = headerTexts()
        headerView.update(title: t.title, detail: t.detail, fraction: t.fraction)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = keepAlive.isRunning
        let timed = remaining() != nil

        // Kopfzeile: großer Status + Fortschrittsbalken
        let texts = headerTexts()
        let header = StatusHeaderView(showsBar: texts.fraction != nil)
        header.update(title: texts.title, detail: texts.detail, fraction: texts.fraction)
        headerView = header
        let headerItem = NSMenuItem()
        headerItem.view = header
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // Schnellaktionen
        if running {
            menu.addItem(item("Jetzt ausschalten", #selector(turnOff), key: "a"))
            if timed {
                menu.addItem(item("Verlängern um 30 Min.", #selector(extend30)))
            }
        } else {
            menu.addItem(item("Jetzt aktivieren (unbegrenzt)", #selector(startUnlimited), key: "a"))
        }

        if Prefs.jiggleMouse && !AXIsProcessTrusted() {
            menu.addItem(item("⚠︎ Bedienungshilfen-Zugriff erteilen …", #selector(requestAccessibility)))
        }

        // Starten für …
        menu.addItem(.separator())
        let section = NSMenuItem(title: "Starten für …", action: nil, keyEquivalent: "")
        section.isEnabled = false
        menu.addItem(section)

        let unlimited = item("Unbegrenzt", #selector(startUnlimited))
        unlimited.indentationLevel = 1
        unlimited.state = checked(Self.presetUnlimited)
        menu.addItem(unlimited)

        for seconds in durations {
            let i = item(TimeText.long(seconds), #selector(startDuration(_:)))
            i.indentationLevel = 1
            i.representedObject = seconds
            i.state = checked(Self.presetID(seconds))
            menu.addItem(i)
        }

        let workEndText = TimeText.clock(minutes: Prefs.workEndMinutes)
        let workEnd = item("Bis Feierabend (\(workEndText))", #selector(startUntilWorkEnd))
        workEnd.indentationLevel = 1
        workEnd.state = checked(Self.presetWorkEnd)
        if workEndDate() == nil {
            workEnd.title = "Bis Feierabend (\(workEndText) – schon vorbei)"
            workEnd.isEnabled = false
        }
        menu.addItem(workEnd)

        let until = item("Bis Uhrzeit …", #selector(startUntilTime))
        until.indentationLevel = 1
        until.state = checked(Self.presetUntil)
        menu.addItem(until)

        let custom = item("Eigene Dauer …", #selector(startCustomDuration))
        custom.indentationLevel = 1
        custom.state = checked(Self.presetCustom)
        menu.addItem(custom)

        // Optionen
        menu.addItem(.separator())
        let optionsItem = NSMenuItem(title: "Optionen", action: nil, keyEquivalent: "")
        optionsItem.submenu = buildOptionsMenu()
        menu.addItem(optionsItem)

        menu.addItem(.separator())
        menu.addItem(item("StayActive beenden", #selector(quit), key: "q"))
    }

    private func buildOptionsMenu() -> NSMenu {
        let options = NSMenu()
        options.autoenablesItems = false

        let jiggle = item("Maus-Impuls (für Teams-Status)", #selector(toggleJiggle))
        jiggle.state = Prefs.jiggleMouse ? .on : .off
        options.addItem(jiggle)
        if Prefs.jiggleMouse {
            if AXIsProcessTrusted() {
                let ok = NSMenuItem(title: "Bedienungshilfen erlaubt ✓", action: nil, keyEquivalent: "")
                ok.indentationLevel = 1
                ok.isEnabled = false
                options.addItem(ok)
            } else {
                let ask = item("⚠︎ Bedienungshilfen fehlen – erlauben …", #selector(requestAccessibility))
                ask.indentationLevel = 1
                options.addItem(ask)
            }
        }

        let intervalMenu = NSMenu()
        intervalMenu.autoenablesItems = false
        for (title, value) in intervals {
            let i = item(title, #selector(setInterval(_:)))
            i.representedObject = value
            i.state = Prefs.interval == value ? .on : .off
            intervalMenu.addItem(i)
        }
        let intervalItem = NSMenuItem(title: "Impuls-Intervall", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        options.addItem(intervalItem)

        options.addItem(.separator())
        options.addItem(item("Feierabend-Zeit (\(TimeText.clock(minutes: Prefs.workEndMinutes))) ändern …",
                             #selector(changeWorkEnd)))

        let countdown = item("Restzeit in der Menüleiste anzeigen", #selector(toggleCountdown))
        countdown.state = Prefs.showCountdown ? .on : .off
        options.addItem(countdown)

        let hud = item("Bestätigung einblenden", #selector(toggleHUD))
        hud.state = Prefs.showHUD ? .on : .off
        options.addItem(hud)

        options.addItem(.separator())
        let autoStart = item("Beim Start automatisch aktivieren", #selector(toggleActivateOnLaunch))
        autoStart.state = Prefs.activateOnLaunch ? .on : .off
        options.addItem(autoStart)

        if #available(macOS 13.0, *) {
            let login = item("Beim Anmelden starten", #selector(toggleLoginItem))
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            options.addItem(login)
        }

        options.addItem(.separator())
        let tip = NSMenuItem(title: "Tipp: ⌥-Klick auf die Tasse schaltet direkt um", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        options.addItem(tip)
        return options
    }

    private func checked(_ preset: String) -> NSControl.StateValue {
        keepAlive.isRunning && Prefs.preset == preset ? .on : .off
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    /// Heutiger Feierabend als Datum, oder nil wenn er schon (fast) vorbei ist.
    private func workEndDate() -> Date? {
        let minutes = Prefs.workEndMinutes
        guard let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                               second: 0, of: Date()),
              date > Date().addingTimeInterval(60) else { return nil }
        return date
    }

    // MARK: Aktionen

    @objc private func turnOff() {
        deactivate()
    }

    @objc private func startUnlimited() {
        activate(until: nil, preset: Self.presetUnlimited)
    }

    @objc private func startDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        activate(until: Date().addingTimeInterval(seconds), preset: Self.presetID(seconds))
    }

    @objc private func startUntilWorkEnd() {
        guard let end = workEndDate() else { return }
        activate(until: end, preset: Self.presetWorkEnd)
    }

    @objc private func extend30() {
        guard keepAlive.isRunning, let end = Prefs.endDate else { return }
        let newEnd = max(end, Date()).addingTimeInterval(30 * 60)
        Prefs.endDate = newEnd
        Prefs.preset = nil
        refresh()
        HUD.show("Verlängert – jetzt bis \(TimeText.clock(newEnd))", symbol: "plus.circle.fill")
    }

    @objc private func startUntilTime() {
        // Dialog erst nach dem Schließen des Menüs zeigen.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let initial = Prefs.endDate ?? Date().addingTimeInterval(3600)
            guard let picked = self.askTime(title: "Aktiv lassen bis …",
                                            info: "Liegt die Uhrzeit heute schon hinter dir, gilt sie für morgen.",
                                            initial: initial) else { return }
            let comps = Calendar.current.dateComponents([.hour, .minute], from: picked)
            guard var end = Calendar.current.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0,
                                                  second: 0, of: Date()) else { return }
            if end <= Date() { end = end.addingTimeInterval(24 * 3600) }
            self.activate(until: end, preset: Self.presetUntil)
        }
    }

    @objc private func startCustomDuration() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            field.placeholderString = "z. B. 90, 1:30 oder 2h"
            let alert = NSAlert()
            alert.messageText = "Eigene Dauer"
            alert.informativeText = "Wie lange soll der Mac wach bleiben?\nMinuten (90), Std:Min (1:30) oder Stunden (2h)."
            alert.accessoryView = field
            alert.addButton(withTitle: "Starten")
            alert.addButton(withTitle: "Abbrechen")
            alert.window.initialFirstResponder = field
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            guard let seconds = TimeText.parseDuration(field.stringValue) else {
                let err = NSAlert()
                err.messageText = "Dauer nicht erkannt"
                err.informativeText = "Bitte z. B. „90“, „1:30“ oder „2h“ eingeben (mindestens 1 Minute, höchstens 7 Tage)."
                NSApp.activate(ignoringOtherApps: true)
                err.runModal()
                return
            }
            self.activate(until: Date().addingTimeInterval(seconds), preset: Self.presetCustom)
        }
    }

    @objc private func changeWorkEnd() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let minutes = Prefs.workEndMinutes
            let initial = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                                second: 0, of: Date()) ?? Date()
            guard let picked = self.askTime(title: "Feierabend-Zeit",
                                            info: "Wird für „Bis Feierabend“ im Menü verwendet.",
                                            initial: initial) else { return }
            let comps = Calendar.current.dateComponents([.hour, .minute], from: picked)
            Prefs.workEndMinutes = (comps.hour ?? 17) * 60 + (comps.minute ?? 0)
        }
    }

    /// Kleiner Dialog mit Uhrzeit-Auswahl (Std:Min). Gibt nil zurück bei "Abbrechen".
    private func askTime(title: String, info: String, initial: Date) -> Date? {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.locale = Locale(identifier: "de_DE")
        picker.dateValue = initial
        picker.sizeToFit()

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.accessoryView = picker
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = picker
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return picker.dateValue
    }

    @objc private func toggleJiggle() {
        Prefs.jiggleMouse.toggle()
        if Prefs.jiggleMouse && !AXIsProcessTrusted() { requestAccessibility() }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? TimeInterval else { return }
        Prefs.interval = value
        keepAlive.reschedule()
    }

    @objc private func toggleCountdown() {
        Prefs.showCountdown.toggle()
        refresh()
    }

    @objc private func toggleHUD() {
        Prefs.showHUD.toggle()
    }

    @objc private func toggleActivateOnLaunch() {
        Prefs.activateOnLaunch.toggle()
    }

    @objc private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @objc private func toggleLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Autostart konnte nicht geändert werden"
            alert.informativeText = "\(error.localizedDescription)\n\nTipp: Lege StayActive in den Ordner „Programme“."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Start

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

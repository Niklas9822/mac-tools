// StayActive – kleine Menüleisten-App für macOS, die den Mac aktiv hält,
// damit z. B. Microsoft Teams den Status nicht auf "Abwesend" setzt.
//
// Mechanismen (alle nur, solange "Aktiv halten" eingeschaltet ist):
//  1. ProcessInfo-Activity: verhindert Ruhezustand von System + Display und App Nap.
//  2. IOPMAssertionDeclareUserActivity: meldet dem System regelmäßig "Nutzer aktiv"
//     (setzt Idle-Timer, Bildschirmschoner usw. zurück).
//  3. Optionaler Maus-Impuls: bewegt den Mauszeiger um 1 px hin und zurück, wenn du
//     gerade nicht aktiv bist. Das ist das, was Teams sicher als Aktivität erkennt.
//     Benötigt "Bedienungshilfen"-Berechtigung.

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

// MARK: - App / Menüleiste

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let keepAlive = KeepAlive()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let intervals: [(String, TimeInterval)] = [
        ("30 Sekunden", 30), ("1 Minute", 60), ("2 Minuten", 120), ("4 Minuten", 240),
    ]
    private let durations: [(String, TimeInterval?)] = [
        ("Unbegrenzt", nil), ("1 Stunde", 3600), ("2 Stunden", 7200),
        ("4 Stunden", 14400), ("8 Stunden", 28800),
    ]
    private var autoOffTimer: Timer?
    private var autoOffDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        if Prefs.enabled { keepAlive.start() }
        if Prefs.jiggleMouse && !AXIsProcessTrusted() { requestAccessibility() }
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        keepAlive.stop()
    }

    // MARK: Icon

    private func updateIcon() {
        let name = keepAlive.isRunning ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "StayActive")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = keepAlive.isRunning ? "StayActive: aktiv" : "StayActive: aus"
    }

    // MARK: Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let toggle = item("Aktiv halten", #selector(toggleEnabled), key: "a")
        toggle.state = keepAlive.isRunning ? .on : .off
        menu.addItem(toggle)

        let jiggle = item("Maus-Impuls (für Teams-Status)", #selector(toggleJiggle))
        jiggle.state = Prefs.jiggleMouse ? .on : .off
        menu.addItem(jiggle)

        let intervalMenu = NSMenu()
        for (title, value) in intervals {
            let i = item(title, #selector(setInterval(_:)))
            i.representedObject = value
            i.state = Prefs.interval == value ? .on : .off
            intervalMenu.addItem(i)
        }
        let intervalItem = NSMenuItem(title: "Intervall", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let durationMenu = NSMenu()
        for (title, value) in durations {
            let i = item(title, #selector(setDuration(_:)))
            i.representedObject = value
            i.state = (value == nil && autoOffDate == nil) ? .on : .off
            durationMenu.addItem(i)
        }
        let durationItem = NSMenuItem(title: "Aktiv lassen für", action: nil, keyEquivalent: "")
        durationItem.submenu = durationMenu
        menu.addItem(durationItem)

        menu.addItem(.separator())

        if Prefs.jiggleMouse && !AXIsProcessTrusted() {
            menu.addItem(item("⚠︎ Bedienungshilfen-Zugriff erteilen …", #selector(requestAccessibility)))
        }

        if #available(macOS 13.0, *) {
            let login = item("Beim Anmelden starten", #selector(toggleLoginItem))
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }

        menu.addItem(.separator())
        menu.addItem(item("StayActive beenden", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func statusText() -> String {
        guard keepAlive.isRunning else { return "Status: aus" }
        if let date = autoOffDate {
            let f = DateFormatter()
            f.timeStyle = .short
            return "Status: aktiv bis \(f.string(from: date))"
        }
        return "Status: aktiv"
    }

    // MARK: Aktionen

    @objc private func toggleEnabled() {
        setEnabled(!keepAlive.isRunning)
    }

    private func setEnabled(_ on: Bool) {
        Prefs.enabled = on
        if on {
            keepAlive.start()
        } else {
            keepAlive.stop()
            clearAutoOff()
        }
        updateIcon()
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

    @objc private func setDuration(_ sender: NSMenuItem) {
        clearAutoOff()
        setEnabled(true)
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        autoOffDate = Date().addingTimeInterval(seconds)
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            self?.setEnabled(false)
        }
        RunLoop.main.add(t, forMode: .common)
        autoOffTimer = t
    }

    private func clearAutoOff() {
        autoOffTimer?.invalidate()
        autoOffTimer = nil
        autoOffDate = nil
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

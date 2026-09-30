import Cocoa
import ServiceManagement

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static var shared: SettingsWindowController?

    static func show() {
        if shared == nil { shared = SettingsWindowController() }
        AppDelegate.shared?.updateActivationPolicy()
        shared?.showWindow(nil)
        shared?.window?.center()
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static var isOpen: Bool { shared?.window?.isVisible ?? false }

    private init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "GreenSnap – Einstellungen"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }

    private func checkbox(_ title: String, _ value: Bool, _ action: Selector) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: action)
        b.state = value ? .on : .off
        return b
    }

    private func build() {
        guard let content = window?.contentView else { return }

        let after = NSPopUpButton()
        after.addItems(withTitles: AfterCapture.allCases.map(\.title))
        after.selectItem(at: Prefs.afterCapture.rawValue)
        after.target = self
        after.action = #selector(afterChanged(_:))

        var rows: [[NSView]] = [[label("Nach der Aufnahme:"), after]]
        rows.append([NSView(), NSView()])

        for (i, action) in CaptureAction.allCases.enumerated() {
            let rec = ShortcutRecorder()
            rec.shortcut = Prefs.shortcut(for: action)
            rec.onChange = { s in
                Prefs.setShortcut(s, for: action)
                AppDelegate.shared?.registerHotKeys()
            }
            rec.onRecordingChanged = { recording in
                if recording { HotKeyCenter.shared.unregisterAll() } else { AppDelegate.shared?.registerHotKeys() }
            }
            rows.append([label(i == 0 ? "Tastenkürzel:" : ""), labeled(rec, action.title)])
        }
        rows.append([NSView(), hint("Klicken und neues Kürzel drücken. ⌫ entfernt es, Esc bricht ab.")])
        rows.append([NSView(), NSView()])

        rows.append([label("Aufnahme:"), checkbox("Lupe bei der Bereichsauswahl anzeigen", Prefs.showMagnifier, #selector(magnifierChanged(_:)))])
        rows.append([NSView(), checkbox("Mauszeiger mit aufnehmen", Prefs.captureCursor, #selector(cursorChanged(_:)))])
        rows.append([NSView(), checkbox("Auslöseton abspielen", Prefs.playSound, #selector(soundChanged(_:)))])
        rows.append([label("Kopieren:"), checkbox("Retina-Bilder in Standardgröße (1×) kopieren/speichern", Prefs.downscaleRetina, #selector(retinaChanged(_:)))])
        rows.append([NSView(), hint("Hilfreich für Teams, Outlook & Co., damit Bilder nicht doppelt so groß erscheinen.")])
        rows.append([label("Verlauf:"), checkbox("Letzte 10 Aufnahmen im Menü behalten (nur im Arbeitsspeicher)", Prefs.keepHistory, #selector(historyChanged(_:)))])
        rows.append([label("System:"), checkbox("Beim Anmelden starten", SMAppService.mainApp.status == .enabled, #selector(loginChanged(_:)))])

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func labeled(_ recorder: ShortcutRecorder, _ title: String) -> NSView {
        let stack = NSStackView(views: [recorder, NSTextField(labelWithString: title)])
        stack.spacing = 8
        return stack
    }

    private func hint(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 360
        return l
    }

    @objc private func afterChanged(_ sender: NSPopUpButton) {
        Prefs.afterCapture = AfterCapture(rawValue: sender.indexOfSelectedItem) ?? .openEditor
    }
    @objc private func magnifierChanged(_ sender: NSButton) { Prefs.showMagnifier = sender.state == .on }
    @objc private func cursorChanged(_ sender: NSButton) { Prefs.captureCursor = sender.state == .on }
    @objc private func soundChanged(_ sender: NSButton) { Prefs.playSound = sender.state == .on }
    @objc private func retinaChanged(_ sender: NSButton) { Prefs.downscaleRetina = sender.state == .on }
    @objc private func historyChanged(_ sender: NSButton) {
        Prefs.keepHistory = sender.state == .on
        if !Prefs.keepHistory { AppDelegate.shared?.clearHistory() }
    }
    @objc private func loginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
            let alert = NSAlert()
            alert.messageText = "Autostart konnte nicht geändert werden"
            alert.informativeText = "\(error.localizedDescription)\n\nTipp: Lege GreenSnap in den Ordner „Programme“."
            alert.runModal()
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { AppDelegate.shared?.updateActivationPolicy() }
    }
}

/// Knopf, der ein Tastenkürzel aufzeichnet.
final class ShortcutRecorder: NSButton {
    var shortcut: Shortcut? { didSet { updateTitle() } }
    var onChange: ((Shortcut?) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private var recording = false {
        didSet {
            guard oldValue != recording else { return }
            updateTitle()
            onRecordingChanged?(recording)
        }
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked)
        widthAnchor.constraint(equalToConstant: 120).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateTitle() {
        title = recording ? "Kürzel drücken …" : (shortcut?.display ?? "—")
    }

    @objc private func clicked() {
        recording = true
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording && window?.firstResponder === self {
            record(event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if recording { record(event) } else { super.keyDown(with: event) }
    }

    private func record(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Esc
            recording = false
            return
        case 51, 117: // Löschen
            shortcut = nil
            recording = false
            onChange?(nil)
            return
        default:
            break
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isFunctionKey = (96...122).contains(Int(event.keyCode))
        guard isFunctionKey || !mods.subtracting(.shift).isEmpty else {
            NSSound.beep()
            return
        }
        let s = Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods.rawValue,
                         key: KeyNames.name(for: event.keyCode))
        shortcut = s
        recording = false
        onChange?(s)
    }
}

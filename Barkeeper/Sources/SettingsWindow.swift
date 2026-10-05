import Cocoa
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func show() {
        if shared == nil { shared = SettingsWindowController() }
        shared?.showWindow(nil)
        shared?.window?.center()
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private let autoOptions: [(String, Int)] = [
        ("Nie", 0), ("nach 5 Sekunden", 5), ("nach 10 Sekunden", 10), ("nach 15 Sekunden", 15),
        ("nach 30 Sekunden", 30), ("nach 1 Minute", 60),
    ]

    private init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Barkeeper – Einstellungen"
        window.isReleasedWhenClosed = false
        super.init(window: window)
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

    private func hint(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 320
        return l
    }

    private func build() {
        guard let content = window?.contentView else { return }

        let auto = NSPopUpButton()
        auto.addItems(withTitles: autoOptions.map(\.0))
        auto.selectItem(at: autoOptions.firstIndex { $0.1 == Prefs.autoCollapseSeconds } ?? 2)
        auto.target = self
        auto.action = #selector(autoChanged(_:))

        let recorder = ShortcutRecorder()
        recorder.shortcut = Prefs.toggleShortcut
        recorder.onChange = { s in
            Prefs.toggleShortcut = s
            AppDelegate.shared?.registerHotKey()
        }
        recorder.onRecordingChanged = { recording in
            if recording { HotKeyCenter.shared.unregisterAll() } else { AppDelegate.shared?.registerHotKey() }
        }

        let rows: [[NSView]] = [
            [label("Automatisch einklappen:"), auto],
            [label("Beim Start:"), checkbox("Symbole eingeklappt starten", Prefs.collapseOnLaunch, #selector(launchCollapsedChanged(_:)))],
            [label("Darstellung:"), checkbox("Trennlinie anzeigen, wenn ausgeklappt", Prefs.showSeparators, #selector(separatorsChanged(_:)))],
            [label("Bereiche:"), checkbox("Bereich „Immer ausgeblendet“ verwenden", Prefs.alwaysHiddenEnabled, #selector(alwaysHiddenChanged(_:)))],
            [NSView(), hint("Fügt eine zweite, gestrichelte Linie ┆ hinzu. Symbole links davon bleiben auch ausgeklappt verborgen – ⌥-Klick auf den Pfeil zeigt sie.")],
            [label("Tastenkürzel:"), recorder],
            [NSView(), hint("Klappt die Symbole ein/aus. Klicken und neues Kürzel drücken, ⌫ entfernt es.")],
            [label("System:"), checkbox("Beim Anmelden starten", SMAppService.mainApp.status == .enabled, #selector(loginChanged(_:)))],
        ]

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
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

    @objc private func autoChanged(_ sender: NSPopUpButton) {
        Prefs.autoCollapseSeconds = autoOptions[max(0, sender.indexOfSelectedItem)].1
        AppDelegate.shared?.controller?.settingsChanged()
    }

    @objc private func launchCollapsedChanged(_ sender: NSButton) {
        Prefs.collapseOnLaunch = sender.state == .on
    }

    @objc private func separatorsChanged(_ sender: NSButton) {
        Prefs.showSeparators = sender.state == .on
        AppDelegate.shared?.controller?.settingsChanged()
    }

    @objc private func alwaysHiddenChanged(_ sender: NSButton) {
        Prefs.alwaysHiddenEnabled = sender.state == .on
        AppDelegate.shared?.controller?.settingsChanged()
    }

    @objc private func loginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
            let alert = NSAlert()
            alert.messageText = "Autostart konnte nicht geändert werden"
            alert.informativeText = "\(error.localizedDescription)\n\nTipp: Lege Barkeeper in den Ordner „Programme“."
            alert.runModal()
        }
    }
}

// Barkeeper – Menüleisten-Symbole ein- und ausblenden (Alternative zu Bartender).

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private(set) var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let controller = MenuBarController()
        self.controller = controller
        registerHotKey()

        if !Prefs.didShowIntro {
            Prefs.didShowIntro = true
            // Erst nach dem Aufbau der Menüleiste, damit Pfeil und Linie schon sichtbar sind.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MenuBarController.showHelp() }
        } else if Prefs.collapseOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { controller.collapse() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.show()
        return true
    }

    func registerHotKey() {
        HotKeyCenter.shared.unregisterAll()
        guard let s = Prefs.toggleShortcut else { return }
        HotKeyCenter.shared.register(s) { [weak self] in self?.controller?.toggle() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

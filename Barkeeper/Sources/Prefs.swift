import Cocoa
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt
    var key: String

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key
    }

    static let defaultToggle = Shortcut(keyCode: UInt32(kVK_ANSI_B),
                                        modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue,
                                        key: "B")
}

enum Prefs {
    private static let d = UserDefaults.standard

    private static func bool(_ key: String, _ def: Bool) -> Bool {
        d.object(forKey: key) as? Bool ?? def
    }

    /// Sekunden bis zum automatischen Einklappen, 0 = nie.
    static var autoCollapseSeconds: Int {
        get { d.object(forKey: "autoCollapseSeconds") as? Int ?? 10 }
        set { d.set(newValue, forKey: "autoCollapseSeconds") }
    }
    static var collapseOnLaunch: Bool {
        get { bool("collapseOnLaunch", true) }
        set { d.set(newValue, forKey: "collapseOnLaunch") }
    }
    /// Zweiter Bereich, der auch im ausgeklappten Zustand verborgen bleibt (⌥-Klick zeigt ihn).
    static var alwaysHiddenEnabled: Bool {
        get { bool("alwaysHiddenEnabled", false) }
        set { d.set(newValue, forKey: "alwaysHiddenEnabled") }
    }
    static var showSeparators: Bool {
        get { bool("showSeparators", true) }
        set { d.set(newValue, forKey: "showSeparators") }
    }
    static var didShowIntro: Bool {
        get { bool("didShowIntro", false) }
        set { d.set(newValue, forKey: "didShowIntro") }
    }

    static var toggleShortcut: Shortcut? {
        get {
            guard let data = d.data(forKey: "toggleShortcut") else { return .defaultToggle }
            if data.isEmpty { return nil }
            return try? JSONDecoder().decode(Shortcut.self, from: data)
        }
        set {
            if let s = newValue, let data = try? JSONEncoder().encode(s) {
                d.set(data, forKey: "toggleShortcut")
            } else {
                d.set(Data(), forKey: "toggleShortcut")
            }
        }
    }
}

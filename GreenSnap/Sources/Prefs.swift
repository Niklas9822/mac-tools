import Cocoa
import Carbon.HIToolbox

/// Was nach einer Aufnahme passieren soll.
enum AfterCapture: Int, CaseIterable {
    case openEditor = 0
    case copy = 1
    case copyAndEditor = 2
    case pin = 3

    var title: String {
        switch self {
        case .openEditor: return "Im Editor öffnen"
        case .copy: return "Direkt in die Zwischenablage kopieren"
        case .copyAndEditor: return "Kopieren und im Editor öffnen"
        case .pin: return "Auf dem Bildschirm anheften"
        }
    }
}

/// Aktionen, die per globalem Tastenkürzel ausgelöst werden können.
enum CaptureAction: String, CaseIterable {
    case region, fullscreen, lastRegion, ocr

    var title: String {
        switch self {
        case .region: return "Bereich / Fenster aufnehmen"
        case .fullscreen: return "Vollbild aufnehmen"
        case .lastRegion: return "Letzten Bereich erneut aufnehmen"
        case .ocr: return "Text aus Bereich kopieren (OCR)"
        }
    }

    var defaultShortcut: Shortcut {
        let cmdShift = NSEvent.ModifierFlags([.command, .shift]).rawValue
        switch self {
        case .region: return Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: cmdShift, key: "2")
        case .fullscreen: return Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: cmdShift, key: "1")
        case .lastRegion: return Shortcut(keyCode: UInt32(kVK_ANSI_9), modifiers: cmdShift, key: "9")
        case .ocr: return Shortcut(keyCode: UInt32(kVK_ANSI_8), modifiers: cmdShift, key: "8")
        }
    }
}

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
}

enum Prefs {
    private static let d = UserDefaults.standard

    private static func bool(_ key: String, _ def: Bool) -> Bool {
        d.object(forKey: key) as? Bool ?? def
    }

    static var afterCapture: AfterCapture {
        get { AfterCapture(rawValue: d.integer(forKey: "afterCapture")) ?? .openEditor }
        set { d.set(newValue.rawValue, forKey: "afterCapture") }
    }
    static var showMagnifier: Bool {
        get { bool("showMagnifier", true) }
        set { d.set(newValue, forKey: "showMagnifier") }
    }
    static var captureCursor: Bool {
        get { bool("captureCursor", false) }
        set { d.set(newValue, forKey: "captureCursor") }
    }
    /// Retina-Aufnahmen beim Kopieren/Speichern auf 1× verkleinern.
    static var downscaleRetina: Bool {
        get { bool("downscaleRetina", false) }
        set { d.set(newValue, forKey: "downscaleRetina") }
    }
    static var keepHistory: Bool {
        get { bool("keepHistory", true) }
        set { d.set(newValue, forKey: "keepHistory") }
    }
    static var playSound: Bool {
        get { bool("playSound", false) }
        set { d.set(newValue, forKey: "playSound") }
    }
    static var saveAsJPEG: Bool {
        get { bool("saveAsJPEG", false) }
        set { d.set(newValue, forKey: "saveAsJPEG") }
    }

    // Editor-Werkzeug-Einstellungen
    static var toolColor: NSColor {
        get {
            if let c = d.array(forKey: "toolColor") as? [Double], c.count == 4 {
                return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
            }
            return NSColor(srgbRed: 0.93, green: 0.16, blue: 0.16, alpha: 1)
        }
        set {
            let c = newValue.usingColorSpace(.sRGB) ?? newValue
            d.set([c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map(Double.init),
                  forKey: "toolColor")
        }
    }
    static var lineWidth: CGFloat {
        get { d.object(forKey: "lineWidth") as? CGFloat ?? 3 }
        set { d.set(newValue, forKey: "lineWidth") }
    }
    static var fontSize: CGFloat {
        get { d.object(forKey: "fontSize") as? CGFloat ?? 20 }
        set { d.set(newValue, forKey: "fontSize") }
    }

    // Tastenkürzel
    static func shortcut(for action: CaptureAction) -> Shortcut? {
        let key = "shortcut.\(action.rawValue)"
        guard let data = d.data(forKey: key) else { return action.defaultShortcut }
        if data.isEmpty { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    static func setShortcut(_ s: Shortcut?, for action: CaptureAction) {
        let key = "shortcut.\(action.rawValue)"
        if let s, let data = try? JSONEncoder().encode(s) {
            d.set(data, forKey: key)
        } else {
            d.set(Data(), forKey: key)
        }
    }
}

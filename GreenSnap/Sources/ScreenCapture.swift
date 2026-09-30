import Cocoa
import ScreenCaptureKit

/// Ein "eingefrorenes" Bild eines Bildschirms.
struct CapturedScreen {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let image: CGImage
    /// Pixel pro Punkt (2 bei Retina).
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
}

/// Ein sichtbares Fenster (Koordinaten im globalen CoreGraphics-Raum, Ursprung oben links).
struct WindowInfo {
    let id: CGWindowID
    let frame: CGRect
}

enum CaptureError: LocalizedError {
    case noDisplay
    var errorDescription: String? { "Kein Bildschirm gefunden." }
}

enum ScreenCapture {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    static var screenUnderMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Nimmt die angegebenen Bildschirme vollständig auf.
    static func capture(screens: [NSScreen]) async throws -> [CapturedScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [CapturedScreen] = []
        for screen in screens {
            let id = displayID(of: screen)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int((screen.frame.width * scale).rounded())
            config.height = Int((screen.frame.height * scale).rounded())
            config.showsCursor = Prefs.captureCursor
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(CapturedScreen(screen: screen, displayID: id, image: image))
        }
        if result.isEmpty { throw CaptureError.noDisplay }
        return result
    }

    /// Nimmt ein einzelnes Fenster auf (ohne überlappende andere Fenster, mit transparenten Ecken).
    static func captureWindow(id: CGWindowID, scale: CGFloat) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int((window.frame.width * scale).rounded())
        config.height = Int((window.frame.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Sichtbare normale Fenster, vorderstes zuerst.
    static func visibleWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 30, bounds.height > 30
            else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { return nil }
            return WindowInfo(id: number, frame: bounds)
        }
    }

    /// Schneidet einen Bereich (in Punkten, Ursprung oben links) aus einem Bild aus.
    static func crop(_ image: CGImage, toPoints rect: CGRect, scale: CGFloat) -> CGImage? {
        let px = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                        width: rect.width * scale, height: rect.height * scale).integral
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = px.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return image.cropping(to: clipped)
    }
}

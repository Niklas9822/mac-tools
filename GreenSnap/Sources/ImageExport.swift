import Cocoa
import ImageIO
import UniformTypeIdentifiers
import Vision

enum ImageExport {
    /// Bild ggf. auf 1× verkleinern (Einstellung), liefert (Bild, Skalierung).
    static func prepared(_ image: CGImage, scale: CGFloat) -> (CGImage, CGFloat) {
        guard Prefs.downscaleRetina, scale > 1 else { return (image, scale) }
        let w = max(1, Int((CGFloat(image.width) / scale).rounded()))
        let h = max(1, Int((CGFloat(image.height) / scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return (image, scale)
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (ctx.makeImage() ?? image, 1)
    }

    static func data(_ image: CGImage, scale: CGFloat, type: UTType, quality: CGFloat = 0.9) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * scale,
            kCGImagePropertyDPIHeight: 72 * scale,
        ]
        if type == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Kopiert das Bild in die Zwischenablage (PNG + TIFF), ohne eine Datei anzulegen.
    static func copyToClipboard(_ image: CGImage, scale: CGFloat) {
        let (img, s) = prepared(image, scale: scale)
        let item = NSPasteboardItem()
        if let png = data(img, scale: s, type: .png) { item.setData(png, forType: .png) }
        let ns = NSImage(cgImage: img, size: CGSize(width: CGFloat(img.width) / s, height: CGFloat(img.height) / s))
        if let tiff = ns.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
    }

    static var defaultFileName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        return "Screenshot \(f.string(from: Date()))"
    }

    /// "Sichern unter…"-Dialog.
    static func save(_ image: CGImage, scale: CGFloat, from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let jpeg = Prefs.saveAsJPEG
        panel.nameFieldStringValue = defaultFileName + (jpeg ? ".jpg" : ".png")
        if let last = UserDefaults.standard.url(forKey: "lastSaveFolder") {
            panel.directoryURL = last
        } else {
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        }

        let format = NSPopUpButton()
        format.addItems(withTitles: ["PNG", "JPEG"])
        format.selectItem(at: jpeg ? 1 : 0)
        let formatBox = NSStackView(views: [NSTextField(labelWithString: "Format:"), format])
        formatBox.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = formatBox
        let handler = FormatHandler(panel: panel)
        format.target = handler
        format.action = #selector(FormatHandler.changed(_:))

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            _ = handler // festhalten
            guard response == .OK, let url = panel.url else { return }
            let isJPEG = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
            Prefs.saveAsJPEG = isJPEG
            UserDefaults.standard.set(url.deletingLastPathComponent(), forKey: "lastSaveFolder")
            let (img, s) = ImageExport.prepared(image, scale: scale)
            guard let fileData = ImageExport.data(img, scale: s, type: isJPEG ? .jpeg : .png) else { return }
            do {
                try fileData.write(to: url)
                HUD.show("Gespeichert", symbol: "square.and.arrow.down")
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(panel.runModal()) }
    }

    private final class FormatHandler: NSObject {
        weak var panel: NSSavePanel?
        init(panel: NSSavePanel) { self.panel = panel }
        @objc func changed(_ sender: NSPopUpButton) {
            guard let panel else { return }
            let ext = sender.indexOfSelectedItem == 1 ? "jpg" : "png"
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + "." + ext
        }
    }
}

enum OCR {
    /// Erkennt Text (Deutsch + Englisch) in einem Bild.
    static func recognize(_ image: CGImage, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["de-DE", "en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async { completion(text) }
        }
    }

    static func recognizeAndCopy(_ image: CGImage) {
        recognize(image) { text in
            if text.isEmpty {
                HUD.show("Kein Text erkannt", symbol: "exclamationmark.triangle")
            } else {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                HUD.show("Text kopiert (\(text.count) Zeichen)", symbol: "text.viewfinder")
            }
        }
    }
}

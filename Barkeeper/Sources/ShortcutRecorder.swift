import Cocoa

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

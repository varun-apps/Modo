import AppKit
import Carbon
import SwiftUI

/// SwiftUI control that displays the current hotkey and lets the user record
/// a new one by clicking and pressing the desired combination.
struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onCapture = { code, mods in
            keyCode = code
            modifiers = mods
        }
        view.update(keyCode: keyCode, modifiers: modifiers)
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.update(keyCode: keyCode, modifiers: modifiers)
    }
}

final class HotkeyRecorderNSView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var isRecording = false
    var onCapture: ((UInt32, UInt32) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderWidth = 1.5
        layer?.cornerRadius = 6
        applyBorderColor()

        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBorderColor()
    }

    private func applyBorderColor() {
        let color = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        // Resolve the dynamic color against the current appearance so layer-
        // backed cgColor doesn't get stuck on light/dark when the user toggles
        // their system appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.borderColor = color.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func becomeFirstResponder() -> Bool {
        startRecording()
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func startRecording() {
        isRecording = true
        applyBorderColor()
        label.stringValue = "Press a key combination…"
    }

    private func stopRecording() {
        isRecording = false
        applyBorderColor()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let mods = HotkeyService.carbonModifiers(from: event.modifierFlags)
        // Require at least one modifier to avoid clashing with normal typing.
        guard mods != 0 else {
            NSSound.beep()
            return
        }
        let code = UInt32(event.keyCode)
        onCapture?(code, mods)
        update(keyCode: code, modifiers: mods)
        window?.makeFirstResponder(nil)
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        label.stringValue = HotkeyService.displayString(keyCode: keyCode, modifiers: modifiers)
    }
}

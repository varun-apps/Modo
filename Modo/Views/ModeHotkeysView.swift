import SwiftUI

/// Sheet for assigning a global hotkey to each mode (built-in or custom).
/// Pressing the configured combination from any app runs that mode directly
/// on the current selection without showing the menu.
struct ModeHotkeysView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var allModes: [Mode] = []
    @State private var bindings: [String: HotkeyBinding] = [:]
    @State private var failed: [String: HotkeyBinding] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mode Hotkeys").font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(allModes) { mode in
                        row(for: mode)
                        Divider()
                    }
                }
            }

            Divider()
            HStack {
                Text("Tip: each hotkey requires at least one modifier (⌃ ⌥ ⇧ ⌘).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
        .onAppear { reload() }
    }

    private func row(for mode: Mode) -> some View {
        let binding = bindings[mode.id]
        let hasConflict = failed[mode.id] != nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: mode.systemSymbol)
                    .frame(width: 24)
                Text(mode.title)
                    .font(.callout)
                Spacer()
                ModeHotkeyRecorder(
                    binding: binding,
                    onCapture: { keyCode, modifiers in
                        let new = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
                        bindings[mode.id] = new
                        HotkeyService.shared.setModeBinding(new, forModeID: mode.id)
                        HotkeyService.shared.register()
                        failed = HotkeyService.shared.failedBindings
                    },
                    onClear: {
                        bindings.removeValue(forKey: mode.id)
                        HotkeyService.shared.setModeBinding(nil, forModeID: mode.id)
                        HotkeyService.shared.register()
                        failed = HotkeyService.shared.failedBindings
                    }
                )
                .frame(width: 200)
            }
            if hasConflict {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Already in use elsewhere — try a different combination.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.leading, 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func reload() {
        allModes = Mode.allBuiltIn + CustomModeStore.shared.load()
        bindings = HotkeyService.shared.allModeBindings()
        failed = HotkeyService.shared.failedBindings
    }
}

/// A row-style recorder that shows the currently-bound combination and a
/// clear (✕) button. Clicking the combo area starts recording.
struct ModeHotkeyRecorder: NSViewRepresentable {
    let binding: HotkeyBinding?
    let onCapture: (UInt32, UInt32) -> Void
    let onClear: () -> Void

    func makeNSView(context: Context) -> ModeHotkeyRecorderNSView {
        let view = ModeHotkeyRecorderNSView()
        view.onCapture = onCapture
        view.onClear = onClear
        view.update(binding: binding)
        return view
    }

    func updateNSView(_ nsView: ModeHotkeyRecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onClear = onClear
        nsView.update(binding: binding)
    }
}

final class ModeHotkeyRecorderNSView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private var isRecording = false

    var onCapture: ((UInt32, UInt32) -> Void)?
    var onClear: (() -> Void)?

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

        clearButton.title = "✕"
        clearButton.bezelStyle = .circular
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clearTapped() {
        onClear?()
    }

    override var acceptsFirstResponder: Bool { true }

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
        label.stringValue = "Press keys…"
    }

    private func stopRecording() {
        isRecording = false
        applyBorderColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBorderColor()
    }

    private func applyBorderColor() {
        let color = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.borderColor = color.cgColor
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let mods = HotkeyService.carbonModifiers(from: event.modifierFlags)
        guard mods != 0 else {
            NSSound.beep()
            return
        }
        onCapture?(UInt32(event.keyCode), mods)
        window?.makeFirstResponder(nil)
    }

    func update(binding: HotkeyBinding?) {
        if let binding {
            label.stringValue = HotkeyService.displayString(keyCode: binding.keyCode, modifiers: binding.modifiers)
            clearButton.isHidden = false
        } else {
            label.stringValue = "Click to set"
            clearButton.isHidden = true
        }
    }
}

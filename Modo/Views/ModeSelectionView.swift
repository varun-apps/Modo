import SwiftUI

/// First screen: shows a preview of the captured selection and a 2×3 grid of
/// improvement-mode buttons.
struct ModeSelectionView: View {
    @ObservedObject var viewModel: WindowViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !viewModel.hasAccessibilityPermission {
                accessibilityNotice
            } else {
                if !viewModel.hasAPIKey {
                    noticeBox(text: "Add your API key in Preferences (right-click the menu bar icon).",
                              symbol: "key")
                }

                if viewModel.hasSelection {
                    selectionPreview
                    if let tone = viewModel.detectedTone {
                        toneBadge(tone)
                    }
                    modeGrid
                } else {
                    noticeBox(text: "Select some text first, then click the icon again.",
                              symbol: "text.cursor")
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var accessibilityNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility Permission Required")
                        .font(.callout)
                        .fontWeight(.medium)
                    Text("Modo needs Accessibility access to read your selected text.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Button("Open System Settings") {
                AccessibilityService.shared.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkle")
            Text("Modo").font(.headline)
            Spacer()
        }
    }

    private var selectionPreview: some View {
        let previewLimit = 4000
        let full = viewModel.selectedText
        let truncated = full.count > previewLimit
        let preview = truncated ? String(full.prefix(previewLimit)) + "…" : full
        return VStack(alignment: .leading, spacing: 4) {
            ScrollView {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 90)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor))
            )
            HStack(spacing: 6) {
                if truncated {
                    Text("Preview truncated — Modo will still send the full text.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(TokenEstimator.displayString(for: full))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var modeGrid: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(viewModel.availableModes) { mode in
                    modeButton(for: mode)
                }
            }
            // Hidden buttons that bind ⌘1…⌘9 to the first nine modes. Placing
            // them in the hierarchy lets SwiftUI route the keyboard shortcuts
            // even though the buttons themselves are invisible.
            ForEach(Array(viewModel.availableModes.prefix(9).enumerated()), id: \.element.id) { index, mode in
                Button("") { viewModel.run(mode: mode) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .disabled(!viewModel.hasAPIKey)
            }
        }
    }

    @ViewBuilder
    private func modeButton(for mode: Mode) -> some View {
        let isLastUsed = viewModel.lastUsedMode?.id == mode.id
        let modeHotkey = HotkeyService.shared.binding(forModeID: mode.id)
        let hotkeyLabel = modeHotkey.map {
            HotkeyService.displayString(keyCode: $0.keyCode, modifiers: $0.modifiers)
        }

        let button = Button {
            viewModel.run(mode: mode)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.systemSymbol)
                Text(mode.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let hotkeyLabel {
                    Text(hotkeyLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
        }
        .keyboardShortcut(isLastUsed ? .defaultAction : nil)
        .disabled(!viewModel.hasAPIKey)

        if isLastUsed {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func toneBadge(_ tone: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "waveform")
                .foregroundStyle(.blue)
                .font(.caption)
            Text(tone)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func noticeBox(text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

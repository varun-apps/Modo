import SwiftUI

/// First screen of the popover.
///
/// New layout (top → bottom):
///  1. Multi-line editable text field bound to the captured selection
///  2. Tone + token-estimate row
///  3. Three primary tiles (Improve / Fix Grammar / Rephrase) — hardcoded
///  4. Vertical list of the remaining modes with ⌘N chips
///  5. Keyboard-navigation footer
///
/// Arrow keys move focus through the primary tiles + secondary list. Enter
/// runs the focused mode, or defaults to **Improve** when the user just
/// types in the input and hits return.
struct ModeSelectionView: View {
    @ObservedObject var viewModel: WindowViewModel

    /// -1 means "no tile is focused — input is the focused element".
    /// 0..<3 → primary tiles. 3..<3+secondaryModes.count → secondary list.
    @State private var focusedIndex: Int = -1
    @FocusState private var inputIsFocused: Bool

    private static let primaryModeIDs: [String] = [
        "builtin.\(ImprovementMode.improve.rawValue)",
        "builtin.\(ImprovementMode.fixGrammar.rawValue)",
        "builtin.\(ImprovementMode.rephrase.rawValue)"
    ]

    private var primaryModes: [Mode] {
        Self.primaryModeIDs.compactMap { id in
            viewModel.availableModes.first { $0.id == id }
        }
    }

    private var secondaryModes: [Mode] {
        let primary = Set(Self.primaryModeIDs)
        return viewModel.availableModes.filter { !primary.contains($0.id) }
    }

    private var totalFocusableTiles: Int {
        primaryModes.count + secondaryModes.count
    }

    var body: some View {
        Group {
            if !viewModel.hasAccessibilityPermission {
                accessibilityNotice
            } else {
                mainContent
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial)
        .onAppear { highlightLastUsedOrDefault() }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.hasAPIKey {
                noticeBox(text: "Add your API key in Preferences (right-click the menu bar icon).",
                          symbol: "key")
            }
            if let notice = viewModel.captureNotice, !viewModel.hasSelection {
                noticeBox(text: notice, symbol: "exclamationmark.circle")
            }

            inputField
            metadataRow

            if !primaryModes.isEmpty {
                primaryTilesRow
            }
            if !secondaryModes.isEmpty {
                Divider().opacity(0.6)
                secondaryList
            }

            Divider().opacity(0.6)
            footerHints
        }
        .onKeyPress(.downArrow) { handleArrow(delta: 1) }
        .onKeyPress(.upArrow)   { handleArrow(delta: -1) }
        .onKeyPress(.return)    { handleReturn() }
        .background(hiddenCommandShortcuts)
    }

    // MARK: - Input

    private var inputField: some View {
        ZStack(alignment: .trailing) {
            TextField("Tell Modo what to change…",
                      text: $viewModel.selectedText,
                      axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.trailing, 44) // room for the send button
                .focused($inputIsFocused)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

            Button(action: handleReturn) {
                Image(systemName: "return")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .disabled(!viewModel.hasAPIKey)
        }
        .overlay(alignment: .bottomTrailing) {
            // "..." hint when the captured text exceeds the visible 4-line cap.
            if viewModel.selectedText.split(separator: "\n").count > 4 {
                Text("…")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 50)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let tone = viewModel.detectedTone {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text(toneAttributed(tone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(TokenEstimator.displayString(for: viewModel.selectedText))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .frame(height: 16)
        .animation(.easeInOut(duration: 0.2), value: viewModel.detectedTone)
    }

    /// Bolds the part after "Reads as " so the tone reads like the mockup.
    private func toneAttributed(_ tone: String) -> AttributedString {
        let attr = AttributedString(tone)
        if let range = attr.range(of: "Reads as "),
           range.upperBound < attr.endIndex {
            var bolded = attr
            bolded[range.upperBound..<attr.endIndex].font = .caption.bold()
            return bolded
        }
        return attr
    }

    // MARK: - Primary tiles

    private var primaryTilesRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(primaryModes.enumerated()), id: \.element.id) { index, mode in
                primaryTile(mode: mode, index: index)
            }
        }
        .frame(height: 76)
    }

    private func primaryTile(mode: Mode, index: Int) -> some View {
        let isFocused = focusedIndex == index
        return Button {
            focusedIndex = index
            viewModel.run(mode: mode)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.systemSymbol)
                    .font(.system(size: 18, weight: .medium))
                Text(mode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(isFocused ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tileBackground(isFocused: isFocused))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.clear : Color(nsColor: .separatorColor),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: isFocused ? Color.accentColor.opacity(0.35) : .clear,
                    radius: 8, x: 0, y: 4)
            .scaleEffect(isFocused ? 1.0 : 0.98)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isFocused)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.hasAPIKey)
        .accessibilityLabel(mode.title)
        .accessibilityHint(isFocused ? "Selected. Press return to run." : "")
    }

    private func tileBackground(isFocused: Bool) -> AnyShapeStyle {
        if isFocused {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: - Secondary list

    private var secondaryList: some View {
        VStack(spacing: 2) {
            ForEach(Array(secondaryModes.enumerated()), id: \.element.id) { index, mode in
                secondaryRow(mode: mode, index: index + primaryModes.count, shortcutIndex: index + 1)
            }
        }
    }

    private func secondaryRow(mode: Mode, index: Int, shortcutIndex: Int) -> some View {
        let isFocused = focusedIndex == index
        return Button {
            focusedIndex = index
            viewModel.run(mode: mode)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.systemSymbol)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 22)
                Text(mode.title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                if shortcutIndex <= 9 {
                    KbdChip(text: "⌘\(shortcutIndex)")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isFocused
                          ? Color.accentColor.opacity(0.15)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.hasAPIKey)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .accessibilityLabel(mode.title)
    }

    // MARK: - Footer

    private var footerHints: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                KbdChip(text: "↑↓")
                Text("Navigate").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                KbdChip(text: "↵")
                Text("Run").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            KbdChip(text: "esc")
        }
    }

    // MARK: - Hidden keyboard shortcuts (⌘1…⌘9 for secondary list)

    @ViewBuilder
    private var hiddenCommandShortcuts: some View {
        ForEach(Array(secondaryModes.prefix(9).enumerated()), id: \.element.id) { index, mode in
            Button("") { viewModel.run(mode: mode) }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .disabled(!viewModel.hasAPIKey)
        }
    }

    // MARK: - Key handlers

    private func handleArrow(delta: Int) -> KeyPress.Result {
        // Don't hijack arrow keys while the user is editing text in the field.
        guard !inputIsFocused else { return .ignored }
        guard totalFocusableTiles > 0 else { return .ignored }
        let next = focusedIndex + delta
        focusedIndex = max(0, min(totalFocusableTiles - 1, next))
        return .handled
    }

    private func handleReturn() -> KeyPress.Result {
        guard viewModel.hasAPIKey else { return .ignored }
        if let mode = focusedMode() ?? defaultMode() {
            viewModel.run(mode: mode)
            return .handled
        }
        return .ignored
    }

    /// Overload for the send-button — wraps the keypress-returning handler.
    private func handleReturn() {
        _ = handleReturn() as KeyPress.Result
    }

    private func focusedMode() -> Mode? {
        guard focusedIndex >= 0 else { return nil }
        if focusedIndex < primaryModes.count {
            return primaryModes[focusedIndex]
        }
        let secondaryIdx = focusedIndex - primaryModes.count
        guard secondaryIdx < secondaryModes.count else { return nil }
        return secondaryModes[secondaryIdx]
    }

    /// Default mode when user hits Enter without a focused tile: Improve.
    private func defaultMode() -> Mode? {
        primaryModes.first
    }

    private func highlightLastUsedOrDefault() {
        // If the user has a last-used mode that's currently visible, focus it.
        // Otherwise default to no focus (Enter still runs Improve).
        if let last = viewModel.lastUsedMode {
            if let i = primaryModes.firstIndex(where: { $0.id == last.id }) {
                focusedIndex = i
                return
            }
            if let i = secondaryModes.firstIndex(where: { $0.id == last.id }) {
                focusedIndex = primaryModes.count + i
                return
            }
        }
        // Default focus: first primary tile (Improve) so users see what Enter would do.
        focusedIndex = primaryModes.isEmpty ? -1 : 0
    }

    // MARK: - Notices (preserved from previous design)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Small reusable views

/// Mac-keyboard-style key chip used throughout the footer and secondary list.
struct KbdChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
    }
}

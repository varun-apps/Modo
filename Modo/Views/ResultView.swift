import SwiftUI

/// Second screen: shows the streaming/improved result with Copy, Replace, and
/// Back actions, plus inline error/retry handling.
struct ResultView: View {
    @ObservedObject var viewModel: WindowViewModel
    /// Called when the action should dismiss the window.
    var onClose: () -> Void

    @State private var copied = false
    @State private var showingDiff = false
    @State private var savingAsCustom: Mode?

    private var diffAvailable: Bool {
        guard let mode = viewModel.activeMode else { return false }
        return !mode.isDirectPrompt
            && !viewModel.selectedText.isEmpty
            && !viewModel.resultText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = viewModel.errorMessage {
                errorBox(error)
            } else {
                if showingDiff && diffAvailable {
                    diffBox
                } else {
                    resultBox
                }
            }

            if let notice = viewModel.replaceNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if viewModel.lastReplacedOriginal != nil {
                undoBanner
            }

            actionRow
        }
        .padding(16)
        .frame(width: 340)
        .sheet(item: $savingAsCustom) { mode in
            CustomModeEditor(mode: Mode.custom(
                title: "Copy of \(mode.title)",
                systemSymbol: mode.systemSymbol,
                systemPrompt: mode.systemPrompt,
                isDirectPrompt: mode.isDirectPrompt,
                targetLanguage: mode.targetLanguage
            )) { newMode in
                var all = CustomModeStore.shared.load()
                all.append(newMode)
                CustomModeStore.shared.save(all)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: viewModel.back) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .buttonStyle(.borderless)
            Spacer()
            if let mode = viewModel.activeMode {
                Label(mode.title, systemImage: mode.systemSymbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if diffAvailable {
                Button {
                    showingDiff.toggle()
                } label: {
                    Image(systemName: showingDiff ? "doc.plaintext" : "rectangle.split.2x1")
                }
                .buttonStyle(.borderless)
                .help(showingDiff ? "Show result only" : "Show diff with original")
            }
            if let mode = viewModel.activeMode {
                Button {
                    savingAsCustom = mode
                } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.borderless)
                .help("Save this mode as a reusable custom mode")
                .disabled(viewModel.isStreaming)
            }
        }
    }

    private var diffBox: some View {
        ScrollView {
            Text(diffAttributedString)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 80, maxHeight: 220)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        )
        .overlay(alignment: .topTrailing) {
            if viewModel.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
    }

    private var diffAttributedString: AttributedString {
        var result = AttributedString()
        let segments = WordDiff.diff(original: viewModel.selectedText,
                                     updated: viewModel.resultText)
        for segment in segments {
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .equal:
                break
            case .removed:
                part.foregroundColor = .red
                part.strikethroughStyle = .single
            case .inserted:
                part.foregroundColor = .green
                part.underlineStyle = .single
            }
            result.append(part)
        }
        return result
    }

    private var resultBox: some View {
        ScrollView {
            Text(viewModel.resultText.isEmpty && viewModel.isStreaming
                 ? "…" : viewModel.resultText)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 80, maxHeight: 220)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor))
        )
        .overlay(alignment: .topTrailing) {
            if viewModel.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
    }

    private func errorBox(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if viewModel.errorMessage != nil {
                Button {
                    viewModel.retry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                regenerateMenu

                Button {
                    viewModel.copyResult()
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isStreaming || viewModel.resultText.isEmpty)
                .accessibilityLabel("Copy result")
                .accessibilityHint("Copies the improved text to the clipboard.")

                Button {
                    if viewModel.replaceResult() { onClose() }
                } label: {
                    Label("Replace", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isStreaming || viewModel.resultText.isEmpty)
                .accessibilityLabel("Replace selection")
                .accessibilityHint("Writes the improved text back over your original selection.")
            }
        }
    }

    private var undoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward")
                .foregroundStyle(.blue)
            Text("Replaced — Undo within 30 seconds.")
                .font(.footnote)
            Spacer(minLength: 0)
            Button("Undo") {
                if viewModel.undoReplace() {
                    onClose()
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Regenerate button. If the current provider exposes a model list, the
    /// button doubles as a menu so users can quickly try a different model
    /// without leaving the result screen.
    private var regenerateMenu: some View {
        let provider = AIProvider.current
        let alternates = provider.models.filter { $0.id != provider.currentModelID }

        return Menu {
            Button("Regenerate") { viewModel.regenerate() }
            if !alternates.isEmpty {
                Divider()
                Section("Try Different Model") {
                    ForEach(alternates) { model in
                        Button(model.displayName) {
                            viewModel.regenerate(modelOverride: model.id)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        } primaryAction: {
            viewModel.regenerate()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.isStreaming)
        .help("Regenerate (long-press for other models)")
    }
}

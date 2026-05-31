import SwiftUI

/// Second screen: shows the streaming/improved result with Copy, Replace, and
/// Back actions, plus inline error/retry handling.
struct ResultView: View {
    @ObservedObject var viewModel: WindowViewModel
    /// Called when the action should dismiss the window.
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = viewModel.errorMessage {
                errorBox(error)
            } else {
                resultBox
            }

            if let notice = viewModel.replaceNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            actionRow
        }
        .padding(16)
        .frame(width: 340)
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
        }
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
                .stroke(Color.secondary.opacity(0.2))
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

                Button {
                    if viewModel.replaceResult() { onClose() }
                } label: {
                    Label("Replace", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isStreaming || viewModel.resultText.isEmpty)
            }
        }
    }
}

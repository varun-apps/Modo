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
        ScrollView {
            Text(viewModel.selectedText)
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
                .stroke(Color.secondary.opacity(0.2))
        )
    }

    private var modeGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ImprovementMode.allCases) { mode in
                Button {
                    viewModel.run(mode: mode)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemSymbol)
                        Text(mode.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasAPIKey)
            }
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

import SwiftUI
import UniformTypeIdentifiers

/// Root SwiftUI content hosted inside the floating NSPanel. Switches between
/// the mode-selection and result screens.
struct FloatingPanelContentView: View {
    @ObservedObject var viewModel: WindowViewModel
    var onClose: () -> Void

    var body: some View {
        Group {
            switch viewModel.screen {
            case .modeSelection:
                ModeSelectionView(viewModel: viewModel)
            case .result:
                ResultView(viewModel: viewModel, onClose: onClose)
            }
        }
        // Accept dragged text from any app — overrides the captured AX
        // selection so users can drop a snippet directly into the popover.
        .onDrop(of: [.plainText, .utf8PlainText, .text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            let supported: [UTType] = [.plainText, .utf8PlainText, .text]
            for type in supported where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data, let text = String(data: data, encoding: .utf8) else { return }
                    Task { @MainActor in
                        viewModel.replaceSelection(with: text)
                    }
                }
                return true
            }
            return false
        }
    }
}

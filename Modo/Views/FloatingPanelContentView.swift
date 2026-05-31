import SwiftUI

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
    }
}

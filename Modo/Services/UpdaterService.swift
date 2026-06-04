import AppKit
import Combine
import Sparkle

/// Owns Sparkle's update controller and exposes a small, SwiftUI-friendly
/// surface so the rest of the app doesn't depend on Sparkle types directly.
///
/// `SPUStandardUpdaterController` starts Sparkle's periodic background check
/// as soon as it's instantiated (`startingUpdater: true`). We hold a single
/// shared instance for the lifetime of the app.
@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    /// True when Sparkle is in a state where a check can be triggered right
    /// now. Bound to the menu item / button so it disables while a check or
    /// download is already in flight.
    @Published private(set) var canCheckForUpdates: Bool = true

    /// The user's "check automatically" preference, wired to Sparkle and
    /// observed by Preferences.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            // Avoid a feedback loop if Sparkle itself published the change.
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    /// Trigger a user-initiated update check. Shows Sparkle's standard
    /// "Checking for Updates" panel and any subsequent install prompt.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

import Foundation
import Sparkle

/// Automatic updates (Sparkle 2, EdDSA-signed appcast attached to each GitHub release).
/// With "자동 업데이트" on, a new version is checked every 6 h, downloaded in the background,
/// installed and the app relaunches by itself — no dialogs.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    private(set) var controller: SPUStandardUpdaterController!
    var onBeforeInstall: () -> Void = {}

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    var updater: SPUUpdater { controller.updater }

    func start(auto: Bool) {
        apply(auto: auto)
        do { try updater.start() } catch { NSLog("Updater start failed: \(error)"); return }
        if auto { updater.checkForUpdatesInBackground() }
    }

    func apply(auto: Bool) {
        updater.automaticallyChecksForUpdates = auto
        updater.automaticallyDownloadsUpdates = auto
        updater.updateCheckInterval = 6 * 3600
    }

    /// "지금 확인": shows Sparkle's standard window (found / up to date).
    func checkNow() { controller.checkForUpdates(nil) }

    var canCheck: Bool { updater.canCheckForUpdates }

    // MARK: SPUUpdaterDelegate

    /// Test hook: `-update.feedOverride <url>` points the app at a local appcast.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "update.feedOverride")
    }

    /// A downloaded update is ready: with auto-update on, install it now and relaunch instead of waiting for quit.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            guard GameStore.shared.settings.autoUpdate else { return }
            GameStore.shared.showBanner(L10n.t("새 버전 \(item.displayVersionString)을 설치하고 다시 시작해요"), seconds: 5)
            onBeforeInstall()
            immediateInstallHandler()
        }
        return true
    }
}

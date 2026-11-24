import AppKit
import SwiftUI

@main
struct DeskExpeditionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(onOpenHQ: { delegate.openHQ() })
                .environment(GameStore.shared)
        } label: {
            Image(systemName: "shield.lefthalf.filled")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var strip: StripWindowController?
    private var hq: HQWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            Snapshot.render(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--frames"), args.indices.contains(i + 1) {
            Snapshot.dumpFrames(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
            return
        }

        let store = GameStore.shared
        store.start()
        strip = StripWindowController(store: store, onOpenHQ: { [weak self] in self?.openHQ() })
        hq = HQWindowController(store: store)
        if args.contains("--open-hq") || store.lastOffline != nil { openHQ() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GameStore.shared.save()
    }

    func openHQ() {
        hq?.show()
    }
}

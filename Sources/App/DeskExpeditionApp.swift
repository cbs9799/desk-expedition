import AppKit
import SwiftUI

/// `--mcp` turns the executable into a headless stdio MCP bridge for AI clients; otherwise run the app.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--mcp") { MCPBridge.run() }
        DeskExpeditionApp.main()
    }
}


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
    private var mcp: MCPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            Snapshot.render(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--bench"), args.indices.contains(i + 1) {
            Snapshot.bench(seconds: Double(args[i + 1]) ?? 60, fps: args.contains("--fps30") ? 30 : 60)
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--soak"), args.indices.contains(i + 1) {
            Snapshot.soak(seconds: Double(args[i + 1]) ?? 600)
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--frames"), args.indices.contains(i + 1) {
            Snapshot.dumpFrames(to: URL(fileURLWithPath: args[i + 1]), showcase: args.contains("--showcase"))
            NSApp.terminate(nil)
            return
        }

        let store = GameStore.shared
        store.start()
        CosmeticShop.shared.start()
        mcp = MCPServer(store: store)
        mcp?.start()
        strip = StripWindowController(store: store, onOpenHQ: { [weak self] in self?.openHQ() })
        hq = HQWindowController(store: store)
        if args.contains("--open-hq") || store.lastOffline != nil || OnboardingView.needed || !store.unseenDiary.isEmpty { openHQ() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GameStore.shared.save()
    }

    func openHQ() {
        hq?.show()
    }
}

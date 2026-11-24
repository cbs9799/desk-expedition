import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel pinned just above the Dock.
/// No `.fullScreenAuxiliary` → it never appears over full-screen apps.
@MainActor
final class StripWindowController {
    let panel: NSPanel
    private let store: GameStore

    init(store: GameStore, onOpenHQ: @escaping () -> Void) {
        self.store = store
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: StripLayout.width, height: StripLayout.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: StripView(onOpenHQ: onOpenHQ).environment(store))

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePowerMode() }
        }
        store.onSettingsChanged = { [weak self] in self?.apply() }
        apply()
    }

    func apply() {
        let s = store.settings
        panel.ignoresMouseEvents = s.clickThrough
        let screens = NSScreen.screens
        let screen = screens.indices.contains(s.screenIndex) ? screens[s.screenIndex] : (NSScreen.main ?? screens.first)
        if let screen {
            let vf = screen.visibleFrame
            let w = min(StripLayout.width, vf.width - 16)
            let x: CGFloat
            switch s.alignment {
            case .left: x = vf.minX + 8
            case .center: x = vf.midX - w / 2
            case .right: x = vf.maxX - w - 8
            }
            panel.setFrame(NSRect(x: x, y: vf.minY + 2, width: w, height: StripLayout.height), display: true)
        }
        if s.visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        updatePowerMode()
    }

    private func updatePowerMode() {
        store.lowPower = !(store.settings.visible && panel.occlusionState.contains(.visible))
    }
}

/// The "원정 본부" management window (plain AppKit window so it can be opened from anywhere).
@MainActor
final class HQWindowController {
    private var window: NSWindow?
    private let store: GameStore

    init(store: GameStore) { self.store = store }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "원정 본부"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HQView().environment(store))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

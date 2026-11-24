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
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: StripView(onOpenHQ: onOpenHQ).environment(store))

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePowerMode() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.willSleep() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if note.name == NSWorkspace.didWakeNotification { self?.store.didWake() }
                    self?.apply()
                }
            }
        }
        store.onSettingsChanged = { [weak self] in
            self?.apply()
            Updater.shared.apply(auto: GameStore.shared.settings.autoUpdate)
        }
        apply()
    }

    /// With click-through on, only the HUD (right side) takes clicks — and only while the pointer is over it,
    /// so the rest of the band never gets in the way of work.
    private var hoverTimer: Timer?

    private func updateMouseCapture() {
        guard store.settings.clickThrough else { panel.ignoresMouseEvents = false; return }
        let f = panel.frame
        let s = CGFloat(store.settings.stripScale)
        let hud = NSRect(x: f.minX + StripLayout.battleWidth * s, y: f.minY, width: f.width - StripLayout.battleWidth * s, height: f.height)
        let over = hud.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    func apply() {
        let s = store.settings
        panel.ignoresMouseEvents = s.clickThrough
        if hoverTimer == nil {
            let t = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMouseCapture() }
            }
            RunLoop.main.add(t, forMode: .common)
            hoverTimer = t
        }
        panel.sharingType = s.hideInCapture ? .none : .readOnly
        let screens = NSScreen.screens
        // Prefer the remembered display (stable across unplug/replug), then the index, then the main screen.
        let byID = screens.first { $0.displayID == s.displayID && s.displayID != 0 }
        let screen = byID ?? (screens.indices.contains(s.screenIndex) ? screens[s.screenIndex] : (NSScreen.main ?? screens.first))
        if let screen {
            let vf = screen.visibleFrame
            let scale = CGFloat(s.stripScale)
            let w = min(StripLayout.width * scale, vf.width - 16)
            let x: CGFloat
            switch s.alignment {
            case .left: x = vf.minX + 8
            case .center: x = vf.midX - w / 2
            case .right: x = vf.maxX - w - 8
            }
            panel.setFrame(NSRect(x: x, y: vf.minY + 2, width: w, height: StripLayout.height * scale), display: true)
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

    var hqWindow: NSWindow? { window }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: HQLayout.ideal.width, height: HQLayout.ideal.height),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = L10n.t("원정 본부")
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)   // the HQ is a dark UI: keep title & controls light-on-dark
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: HQView().environment(store))
            host.sizingOptions = [.minSize]          // let the window grow beyond the view's ideal size
            w.contentView = host
            w.contentMinSize = HQLayout.min
            w.collectionBehavior.insert(.fullScreenPrimary)
            // Remember the size and position the player chose.
            if !w.setFrameUsingName("HQWindow") { w.center() }
            w.setFrameAutosaveName("HQWindow")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // Don't drop the player straight into editing the first hero's name.
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

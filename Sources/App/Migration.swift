import Foundation

/// 0.2.16 left the App Sandbox. Data the sandboxed versions wrote lives in the container;
/// copy it to the regular locations once, before anything reads settings or the save.
enum SandboxMigration {
    static func run() {
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
              let id = Bundle.main.bundleIdentifier else { return }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let container = home.appendingPathComponent("Library/Containers/\(id)/Data")
        guard fm.fileExists(atPath: container.path) else { return }

        // Save, MCP token/port, chat files.
        let oldSupport = container.appendingPathComponent("Library/Application Support/DeskExpedition")
        let newSupport = AppPaths.support
        if fm.fileExists(atPath: oldSupport.appendingPathComponent("save.json").path),
           !fm.fileExists(atPath: newSupport.appendingPathComponent("save.json").path) {
            try? fm.createDirectory(at: newSupport, withIntermediateDirectories: true)
            for name in (try? fm.contentsOfDirectory(atPath: oldSupport.path)) ?? [] {
                try? fm.copyItem(at: oldSupport.appendingPathComponent(name), to: newSupport.appendingPathComponent(name))
            }
        }
        // Settings (UserDefaults).
        let oldPrefs = container.appendingPathComponent("Library/Preferences/\(id).plist")
        let newPrefs = home.appendingPathComponent("Library/Preferences/\(id).plist")
        if fm.fileExists(atPath: oldPrefs.path), !fm.fileExists(atPath: newPrefs.path),
           let dict = NSDictionary(contentsOf: oldPrefs) as? [String: Any] {
            let d = UserDefaults.standard
            for (k, v) in dict where d.object(forKey: k) == nil { d.set(v, forKey: k) }
            d.synchronize()
        }
    }
}

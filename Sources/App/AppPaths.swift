import Foundation

/// Where the app keeps its files. Builds with another bundle id (debug, tests) get their own folder
/// so they never touch the player's real save now that the app is not sandboxed.
enum AppPaths {
    static let releaseBundleID = "club.lemongrove.deskexpedition"

    static var folderName: String {
        let id = Bundle.main.bundleIdentifier ?? releaseBundleID
        if id == releaseBundleID { return "DeskExpedition" }
        return "DeskExpedition-" + (id.components(separatedBy: ".").last ?? "dev")
    }

    static var support: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}

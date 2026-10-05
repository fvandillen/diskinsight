import AppKit
import Foundation

/// Full Disk Access detection and the list of locations macOS guards with a
/// per-folder consent prompt.
///
/// Without Full Disk Access a plain filesystem walk trips one TCC prompt per
/// protected location ("DiskInsight would like to access files in your Desktop
/// folder…"), which is exactly the barrage we want to avoid. So the app asks for
/// Full Disk Access up front, and if it does not have it the scanner refuses to
/// open guarded directories at all — no prompts, ever.
enum Permissions {

    // MARK: - Full Disk Access

    /// Probe files that are readable *only* with Full Disk Access. Reading them
    /// is silently denied rather than prompting, so this check is invisible.
    private static let probes: [String] = [
        NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
        "/Library/Application Support/com.apple.TCC/TCC.db"
    ]

    static func hasFullDiskAccess() -> Bool {
        for path in probes {
            let descriptor = open(path, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return true
            }
            // ENOENT means the probe is missing on this system: inconclusive,
            // so fall through and try the next one.
            if errno == EPERM || errno == EACCES { return false }
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Reveals the app in Finder so it can be dragged into the settings list.
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// macOS only hands a running process its new Full Disk Access grant after a
    /// restart, so offer to do that cleanly.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - TCC-guarded locations

    /// Locations that raise a consent prompt when opened without Full Disk Access.
    /// Paths are absolute and compared exactly, or as a prefix for containers.
    private static let guardedExact: Set<String> = {
        let home = NSHomeDirectory()
        return [
            // Verified against tccd: opening these raises
            // kTCCServiceSystemPolicy{Desktop,Documents,Downloads}Folder.
            // ~/Pictures, ~/Movies and ~/Music are deliberately *not* here —
            // they are not folder-guarded, and they hold real bytes worth seeing.
            home + "/Desktop",
            home + "/Documents",
            home + "/Downloads",
            home + "/Library/Mobile Documents",
            home + "/Library/CloudStorage",
            home + "/Library/Containers",
            home + "/Library/Group Containers",
            home + "/Library/Application Support/AddressBook",
            home + "/Library/Application Support/CallHistoryDB",
            home + "/Library/Application Support/com.apple.TCC",
            home + "/Library/Application Support/com.apple.sharedfilelist",
            home + "/Library/Accounts",
            home + "/Library/Calendars",
            home + "/Library/Caches/CloudKit",
            home + "/Library/Cookies",
            home + "/Library/HomeKit",
            home + "/Library/IdentityServices",
            home + "/Library/Mail",
            home + "/Library/Messages",
            home + "/Library/Metadata/CoreSpotlight",
            home + "/Library/PersonalizationPortrait",
            home + "/Library/Safari",
            home + "/Library/Suggestions",
            "/Library/Application Support/com.apple.TCC"
        ]
    }()

    /// Media library bundles are guarded by kTCCServiceMediaLibrary / Photos even
    /// though their parent folders are not; matched by suffix.
    private static let guardedSuffixes = [
        ".photoslibrary", ".musiclibrary", ".tvlibrary", ".imovielibrary", ".theater"
    ]

    /// True when opening `path` would raise a consent prompt.
    static func isGuarded(path: String) -> Bool {
        if guardedExact.contains(path) { return true }
        // Simulator and developer artefacts merely *look* like media libraries;
        // they are not TCC-guarded, so don't over-block them.
        if !path.hasPrefix(NSHomeDirectory() + "/Library/Developer/"),
           guardedSuffixes.contains(where: { path.hasSuffix($0) }) {
            return true
        }
        // Anything mounted under /Volumes is a removable or network volume.
        if path.hasPrefix("/Volumes/"), path.dropFirst("/Volumes/".count).firstIndex(of: "/") == nil {
            return true
        }
        return false
    }

    /// User-facing name for the permission a guarded path needs.
    static func guardDescription(for path: String) -> String {
        if path.hasPrefix("/Volumes/") { return "Needs permission for this volume" }
        return "Needs Full Disk Access"
    }
}

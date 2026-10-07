import Foundation

enum ScanAccessPolicy {
    private static let systemManagedRoots = [
        "/private/var/db",
        "/private/var/protected",
        "/private/var/root",
        "/private/var/audit",
        "/private/var/backups",
        "/private/var/spool",
        "/.DocumentRevisions-V100",
        "/.Spotlight-V100",
        "/.fseventsd"
    ]

    static func isDataVault(flags: UInt32) -> Bool {
        (flags & FileFlags.dataVault) != 0
    }

    /// Only suppress access denials in OS-managed locations, never arbitrary
    /// failures or unreadable user data. Full Disk Access does not override BSD
    /// permissions or the private entitlements protecting these locations.
    static func isExpectedDenial(path: String, errorCode: Int32, hasFullDiskAccess: Bool) -> Bool {
        guard hasFullDiskAccess, errorCode == EPERM || errorCode == EACCES else { return false }

        var path = URL(fileURLWithPath: path).standardizedFileURL.path
        let dataVolume = "/System/Volumes/Data"
        if path.hasPrefix(dataVolume + "/") {
            path = String(path.dropFirst(dataVolume.count))
        }
        if path == "/var" || path.hasPrefix("/var/") {
            path = "/private" + path
        }
        return systemManagedRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

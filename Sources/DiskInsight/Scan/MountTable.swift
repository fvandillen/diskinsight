import Foundation

/// Snapshot of every mounted filesystem, taken once per scan.
///
/// Classifying volumes from this table means the hot scanning loop never issues
/// a `statfs` — important because `statfs` on a stalled network mount blocks.
struct MountTable {

    struct Mount {
        let dev: Int32
        let fsType: String
        let mountPoint: String
        let isBrowsable: Bool
        let isLocal: Bool
        let isAutomounted: Bool
        let deviceSource: String
    }

    private(set) var byDevice: [Int32: Mount] = [:]

    /// Filesystems that are either virtual, remote, or automounted on demand.
    /// Descending into these is slow at best and can hang indefinitely.
    static let excludedTypes: Set<String> = [
        "autofs", "devfs", "fdesc", "procfs", "kernfs",
        "nfs", "smbfs", "afpfs", "webdav", "ftp", "cddafs", "acfs"
    ]

    init() {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return }

        let capacity = Int(count) + 8
        // Note: `statfs()` would resolve to the syscall, not the struct initialiser.
        let buffer = UnsafeMutablePointer<statfs>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        let actual = getfsstat(buffer, Int32(capacity * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        guard actual > 0 else { return }

        for index in 0..<Int(actual) {
            var entry = buffer[index]
            let mount = Mount(dev: entry.f_fsid.val.0,
                              fsType: Self.string(&entry.f_fstypename),
                              mountPoint: Self.string(&entry.f_mntonname),
                              isBrowsable: (entry.f_flags & UInt32(MNT_DONTBROWSE)) == 0,
                              isLocal: (entry.f_flags & UInt32(MNT_LOCAL)) != 0,
                              isAutomounted: (entry.f_flags & UInt32(MNT_AUTOMOUNTED)) != 0,
                              deviceSource: Self.string(&entry.f_mntfromname))
            byDevice[mount.dev] = mount
        }
    }

    func mount(for device: Int32) -> Mount? { byDevice[device] }

    private static func string<T>(_ value: inout T) -> String {
        withUnsafeBytes(of: &value) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
}

/// `st_flags` bits that matter to us. `SF_FIRMLINK` is not surfaced by the
/// Darwin overlay, so the raw values are declared here.
enum FileFlags {
    /// A Data Vault requires private entitlements even with Full Disk Access.
    static let dataVault: UInt32 = 0x0000_0080
    /// Directory is a macOS firmlink (e.g. `/Users` -> the Data volume).
    static let firmlink: UInt32 = 0x0080_0000
    /// Contents live in the cloud; touching it would trigger a download.
    static let dataless: UInt32 = 0x4000_0000
}

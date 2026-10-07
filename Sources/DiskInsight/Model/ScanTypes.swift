import Foundation

enum SizeMode: String, CaseIterable, Identifiable {
    case allocated
    case logical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allocated: return "Size on disk"
        case .logical: return "Logical size"
        }
    }

    var shortTitle: String {
        switch self {
        case .allocated: return "On disk"
        case .logical: return "Logical"
        }
    }
}

struct ScanOptions {
    /// Do not descend into volumes that live on a different physical container.
    var stayOnVolume: Bool = true
    /// Treat app bundles as opaque leaves (much faster, less noise).
    var collapsePackages: Bool = false
    /// When false, TCC-guarded folders are left unopened so macOS never raises a
    /// consent prompt. Set from the Full Disk Access check before each scan.
    var hasFullDiskAccess: Bool = true
}

struct ScanProgress: Equatable {
    var files: Int64 = 0
    var folders: Int64 = 0
    var bytes: Int64 = 0
    var errors: Int64 = 0
    var blocked: Int64 = 0
    var systemProtected: Int64 = 0
    var currentPath: String = ""
    var finished: Bool = false
}

/// Aggregated per-extension statistics, mirroring WinDirStat's extension list.
struct ExtensionStat: Identifiable, Equatable {
    var id: Int32 { index }
    let index: Int32
    var name: String
    var size: Int64 = 0
    var allocated: Int64 = 0
    var count: Int64 = 0
    var colorIndex: Int = 0

    var displayName: String {
        name.isEmpty ? "‹no extension›" : "." + name
    }

    func value(_ mode: SizeMode) -> Int64 {
        mode == .logical ? size : allocated
    }
}

struct ScanIssue: Identifiable {
    var id: String { path }
    let path: String
    let errorCode: Int32

    var message: String { String(cString: strerror(errorCode)) }
}

struct ScanResult {
    var root: FileNode
    var extensions: [ExtensionStat]
    /// Maps `FileNode.extIndex` -> palette color index.
    var colorForExtIndex: [Int]
    var duration: TimeInterval
    var errors: Int64
    /// Folders left unread because Full Disk Access is missing.
    var blocked: Int64
    /// Expected omissions that Full Disk Access cannot resolve.
    var systemProtected: Int64
    /// A bounded sample of unexpected failures, retaining their actual cause.
    var unreadableSamples: [ScanIssue]
    var volumeCapacity: Int64
    var volumeFree: Int64
}

enum SortKey: String, CaseIterable, Identifiable {
    case size
    case name
    case items
    case modified

    var id: String { rawValue }
}

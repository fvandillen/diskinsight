import Foundation

/// Identity-based identifier that also hands the node back, so SwiftUI selection
/// can be mapped to the underlying tree object without a global lookup table.
struct NodeID: Hashable {
    let node: FileNode

    @inline(__always)
    static func == (lhs: NodeID, rhs: NodeID) -> Bool { lhs.node === rhs.node }

    @inline(__always)
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(node)) }
}

/// A single entry (file or directory) in the scanned tree.
///
/// Deliberately a compact final class: a full-system scan can produce millions of
/// these, so every stored property costs real memory.
final class FileNode: Identifiable {
    let name: String
    /// Weak so that a retained selection cannot resurrect a freed subtree.
    weak var parent: FileNode?
    /// `nil` for files, non-nil (possibly empty) for directories.
    var children: [FileNode]?

    var size: Int64 = 0
    var allocated: Int64 = 0
    var fileCount: Int32 = 0
    var folderCount: Int32 = 0
    var mtime: Int64 = 0
    /// Device id, used to detect volume boundaries while scanning.
    var dev: Int32 = 0

    let isDirectory: Bool
    var isSymlink: Bool = false
    var isUnreadable: Bool = false
    var isSkipped: Bool = false
    /// Omitted because macOS protects it independently of Full Disk Access.
    var isSystemProtected: Bool = false
    /// Not opened because it is TCC-guarded and we lack Full Disk Access.
    var needsPermission: Bool = false
    /// Index into `ScanResult.extensions`; -1 for directories and unclassified nodes.
    var extIndex: Int32 = -1

    var id: NodeID { NodeID(node: self) }

    init(name: String, parent: FileNode?, isDirectory: Bool) {
        self.name = name
        self.parent = parent
        self.isDirectory = isDirectory
    }

    var isLeaf: Bool {
        guard let children else { return true }
        return children.isEmpty
    }

    var path: String {
        guard let parent else { return name }
        let base = parent.path
        return base.hasSuffix("/") ? base + name : base + "/" + name
    }

    var url: URL { URL(fileURLWithPath: path) }

    var depthFromRoot: Int {
        var depth = 0
        var cursor = parent
        while let current = cursor {
            depth += 1
            cursor = current.parent
        }
        return depth
    }

    /// Lowercased extension without the dot. Empty string means "no extension".
    var fileExtension: String {
        guard !isDirectory else { return "" }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        let ext = name[name.index(after: dot)...]
        guard !ext.isEmpty, ext.count <= 16 else { return "" }
        return ext.lowercased()
    }

    @inline(__always)
    func value(_ mode: SizeMode) -> Int64 {
        mode == .logical ? size : allocated
    }

    var modifiedDate: Date? {
        mtime == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(mtime))
    }

    /// Total number of entries (files + folders) contained in this node.
    var itemCount: Int64 { Int64(fileCount) + Int64(folderCount) }

    func ancestors() -> [FileNode] {
        var result: [FileNode] = []
        var cursor = parent
        while let current = cursor {
            result.append(current)
            cursor = current.parent
        }
        return result
    }

    func contains(_ other: FileNode) -> Bool {
        var cursor: FileNode? = other
        while let current = cursor {
            if current === self { return true }
            cursor = current.parent
        }
        return false
    }

    /// Depth-first walk over the subtree, including `self`.
    func walk(_ body: (FileNode) -> Void) {
        var stack: [FileNode] = [self]
        while let node = stack.popLast() {
            body(node)
            if let children = node.children {
                stack.append(contentsOf: children)
            }
        }
    }
}

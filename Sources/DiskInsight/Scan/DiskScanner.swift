import Foundation

/// Multi-threaded filesystem walker built directly on `opendir`/`fstatat`.
///
/// Design notes:
/// * A shared LIFO work queue of directories is drained by N worker threads, so a
///   single hot subtree still parallelises (unlike depth-limited fan-out).
/// * Directories are de-duplicated by (device, inode) which neutralises macOS
///   firmlinks — otherwise `/Users` and `/System/Volumes/Data/Users` double count.
/// * Symlinks are never followed; they are counted as their own (tiny) size.
final class DiskScanner: @unchecked Sendable {

    struct DevIno: Hashable {
        let dev: Int32
        let ino: UInt64
    }

    private let options: ScanOptions
    private let cond = NSCondition()

    private var pending: [FileNode] = []
    private var activeWorkers = 0
    private var liveWorkers = 0
    private var cancelled = false

    private var visited = Set<DevIno>()
    private var mounts = MountTable()

    private let pathLock = NSLock()
    private var inFlight: [String] = []

    private var files: Int64 = 0
    private var folders: Int64 = 0
    private var bytes: Int64 = 0
    private var errors: Int64 = 0
    private var blocked: Int64 = 0
    private var currentPath: String = ""

    private var rootDev: Int32 = 0
    private var rootPath: String = "/"

    private static let alwaysExcluded: Set<String> = [
        "/dev", "/net", "/home", "/Network", "/.vol",
        // Reachable through firmlinks from "/" — visiting both would double count.
        "/System/Volumes/Data"
    ]

    init(options: ScanOptions) {
        self.options = options
    }

    // MARK: - Public API

    func cancel() {
        cond.lock()
        cancelled = true
        cond.broadcast()
        cond.unlock()
    }

    var isCancelled: Bool {
        cond.lock()
        defer { cond.unlock() }
        return cancelled
    }

    func snapshot() -> ScanProgress {
        pathLock.lock()
        let active = inFlight.first(where: { !$0.isEmpty }) ?? ""
        pathLock.unlock()

        cond.lock()
        defer { cond.unlock() }
        return ScanProgress(files: files, folders: folders, bytes: bytes,
                            errors: errors, blocked: blocked,
                            currentPath: active.isEmpty ? currentPath : active,
                            finished: false)
    }

    /// Every directory currently being read, for diagnostics.
    func inFlightPaths() -> [String] {
        pathLock.lock()
        defer { pathLock.unlock() }
        return inFlight.filter { !$0.isEmpty }
    }

    /// Runs the scan synchronously on the calling thread (call it off the main thread).
    func scan(rootURL: URL) throws -> ScanResult {
        let started = Date()
        let path = rootURL.path
        rootPath = path

        var st = stat()
        guard lstat(path, &st) == 0 else {
            throw ScanError.unreadableRoot(path)
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            throw ScanError.notADirectory(path)
        }

        rootDev = st.st_dev

        let root = FileNode(name: path, parent: nil, isDirectory: true)
        root.mtime = Int64(st.st_mtimespec.tv_sec)
        root.dev = st.st_dev
        visited.insert(DevIno(dev: st.st_dev, ino: st.st_ino))
        pending.append(root)

        let workerCount = max(2, min(12, ProcessInfo.processInfo.activeProcessorCount))
        liveWorkers = workerCount
        inFlight = [String](repeating: "", count: workerCount)
        for index in 0..<workerCount {
            let thread = Thread { [weak self] in self?.workerLoop(worker: index) }
            thread.name = "DiskInsight.scan.\(index)"
            thread.stackSize = 1 << 20
            thread.qualityOfService = .userInitiated
            thread.start()
        }

        cond.lock()
        while liveWorkers > 0 { cond.wait() }
        let wasCancelled = cancelled
        cond.unlock()

        if wasCancelled { throw ScanError.cancelled }

        var interner = ExtensionInterner()
        Self.rollUp(root, interner: &interner)

        let extensions = interner.finish(root: root)
        let space = Self.volumeSpace(for: rootURL)

        return ScanResult(root: root,
                          extensions: extensions.stats,
                          colorForExtIndex: extensions.colorMap,
                          duration: Date().timeIntervalSince(started),
                          errors: errors,
                          blocked: blocked,
                          volumeCapacity: space.capacity,
                          volumeFree: space.free)
    }

    // MARK: - Workers

    private func workerLoop(worker: Int) {
        while true {
            cond.lock()
            while !cancelled && pending.isEmpty && activeWorkers > 0 {
                cond.wait()
            }
            if cancelled || (pending.isEmpty && activeWorkers == 0) {
                liveWorkers -= 1
                cond.broadcast()
                cond.unlock()
                return
            }
            let node = pending.removeLast()
            activeWorkers += 1
            cond.unlock()

            let harvest = readDirectory(node, worker: worker)

            cond.lock()
            files += harvest.files
            folders += harvest.folders
            bytes += harvest.bytes
            errors += harvest.errors
            blocked += harvest.blocked
            if let sample = harvest.samplePath { currentPath = sample }
            for candidate in harvest.candidates where !cancelled {
                if shouldDescendLocked(candidate) {
                    pending.append(candidate.node)
                } else {
                    candidate.node.children = []
                    candidate.node.isSkipped = true
                }
            }
            activeWorkers -= 1
            cond.broadcast()
            cond.unlock()

            pathLock.lock()
            inFlight[worker] = ""
            pathLock.unlock()
        }
    }

    private struct Candidate {
        let node: FileNode
        let path: String
        let dev: Int32
        let ino: UInt64
        let crossesBoundary: Bool
        let isFirmlink: Bool
    }

    private struct Harvest {
        var files: Int64 = 0
        var folders: Int64 = 0
        var bytes: Int64 = 0
        var errors: Int64 = 0
        var blocked: Int64 = 0
        var candidates: [Candidate] = []
        var samplePath: String?
    }

    private static let direntNameOffset = MemoryLayout<dirent>.offset(of: \.d_name)!

    private func readDirectory(_ node: FileNode, worker: Int) -> Harvest {
        var harvest = Harvest()
        let dirPath = node.path
        harvest.samplePath = dirPath

        pathLock.lock()
        inFlight[worker] = dirPath
        pathLock.unlock()

        guard let handle = opendir(dirPath) else {
            node.isUnreadable = true
            node.children = []
            harvest.errors = 1
            return harvest
        }
        defer { closedir(handle) }

        let descriptor = dirfd(handle)
        var children: [FileNode] = []
        let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"

        while let entry = readdir(handle) {
            let namePtr = UnsafeRawPointer(entry)
                .advanced(by: Self.direntNameOffset)
                .assumingMemoryBound(to: CChar.self)

            if namePtr[0] == 0x2E {                                  // '.'
                if namePtr[1] == 0 { continue }                      // "."
                if namePtr[1] == 0x2E && namePtr[2] == 0 { continue } // ".."
            }

            var st = stat()
            guard fstatat(descriptor, namePtr, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
                harvest.errors += 1
                continue
            }

            let name = String(cString: namePtr)
            let kind = st.st_mode & S_IFMT
            let isDirectory = kind == S_IFDIR

            let child = FileNode(name: name, parent: node, isDirectory: isDirectory)
            child.mtime = Int64(st.st_mtimespec.tv_sec)
            child.dev = st.st_dev
            children.append(child)

            if isDirectory {
                harvest.folders += 1

                // Opening a TCC-guarded folder without Full Disk Access raises a
                // consent prompt. Leave it closed and flag it in the UI instead.
                if !options.hasFullDiskAccess, Permissions.isGuarded(path: prefix + name) {
                    child.children = []
                    child.needsPermission = true
                    harvest.blocked += 1
                    continue
                }

                // Never open a cloud placeholder: that would trigger a download.
                if (st.st_flags & FileFlags.dataless) != 0 {
                    child.children = []
                    child.isSkipped = true
                    continue
                }
                if options.collapsePackages && Self.isPackageName(name) {
                    child.children = []
                    child.size = Int64(st.st_size)
                    child.allocated = Int64(st.st_blocks) * 512
                    continue
                }
                harvest.candidates.append(Candidate(node: child,
                                                    path: prefix + name,
                                                    dev: st.st_dev,
                                                    ino: UInt64(st.st_ino),
                                                    crossesBoundary: st.st_dev != node.dev,
                                                    isFirmlink: (st.st_flags & FileFlags.firmlink) != 0))
            } else {
                child.isSymlink = kind == S_IFLNK
                child.size = Int64(st.st_size)
                child.allocated = Int64(st.st_blocks) * 512
                harvest.files += 1
                harvest.bytes += child.size
            }
        }

        node.children = children
        return harvest
    }

    /// Decides whether a directory should be walked. Pure table lookups, so it is
    /// safe (and fast) to call while holding `cond`.
    private func shouldDescendLocked(_ candidate: Candidate) -> Bool {
        if Self.alwaysExcluded.contains(candidate.path) { return false }

        // A firmlink stays inside the same volume group, so it is always followed;
        // the visited set below stops it from being counted twice.
        if candidate.crossesBoundary && !candidate.isFirmlink {
            guard let mount = mounts.mount(for: candidate.dev) else { return false }
            if MountTable.excludedTypes.contains(mount.fsType) { return false }
            if mount.isAutomounted { return false }
            // Hidden helper volumes (VM, Preboot, Update, Data…) duplicate or hide
            // content the user cannot act on.
            if !mount.isBrowsable { return false }
            if options.stayOnVolume && !mount.isLocal { return false }
            if options.stayOnVolume && candidate.dev != rootDev { return false }
        }

        let key = DevIno(dev: candidate.dev, ino: candidate.ino)
        if visited.contains(key) { return false }
        visited.insert(key)
        return true
    }

    // MARK: - Aggregation

    private static func rollUp(_ node: FileNode, interner: inout ExtensionInterner) {
        guard let children = node.children, !children.isEmpty else { return }

        var size: Int64 = 0
        var allocated: Int64 = 0
        var fileCount: Int32 = 0
        var folderCount: Int32 = 0

        for child in children {
            if child.isDirectory {
                rollUp(child, interner: &interner)
                folderCount += 1 &+ child.folderCount
                fileCount += child.fileCount
            } else {
                child.extIndex = interner.index(for: child.fileExtension)
                interner.add(index: child.extIndex, size: child.size, allocated: child.allocated)
                fileCount += 1
            }
            size += child.size
            allocated += child.allocated
        }

        node.size = size
        node.allocated = allocated
        node.fileCount = fileCount
        node.folderCount = folderCount
        node.children?.sort { $0.allocated == $1.allocated ? $0.size > $1.size : $0.allocated > $1.allocated }
    }

    // MARK: - Helpers

    private static func isPackageName(_ name: String) -> Bool {
        let packageSuffixes = [".app", ".bundle", ".framework", ".photoslibrary", ".fcpbundle", ".rtfd"]
        return packageSuffixes.contains { name.hasSuffix($0) }
    }

    static func volumeSpace(for url: URL) -> (capacity: Int64, free: Int64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let capacity = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return (capacity, free)
    }
}

enum ScanError: LocalizedError {
    case cancelled
    case unreadableRoot(String)
    case notADirectory(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Scan cancelled."
        case .unreadableRoot(let path): return "Can't read “\(path)”. Grant Full Disk Access and try again."
        case .notADirectory(let path): return "“\(path)” is not a folder."
        }
    }
}

/// Interns extension strings during roll-up and produces the ranked colour table.
struct ExtensionInterner {
    private var indexByName: [String: Int32] = [:]
    private var stats: [ExtensionStat] = []

    mutating func index(for name: String) -> Int32 {
        if let existing = indexByName[name] { return existing }
        let index = Int32(stats.count)
        indexByName[name] = index
        stats.append(ExtensionStat(index: index, name: name))
        return index
    }

    mutating func add(index: Int32, size: Int64, allocated: Int64) {
        stats[Int(index)].size += size
        stats[Int(index)].allocated += allocated
        stats[Int(index)].count += 1
    }

    func finish(root: FileNode) -> (stats: [ExtensionStat], colorMap: [Int]) {
        var ranked = stats.sorted { $0.allocated > $1.allocated }
        var colorMap = [Int](repeating: Palette.otherColorIndex, count: stats.count)
        for (rank, stat) in ranked.enumerated() {
            let colorIndex = rank < Palette.distinctColorCount ? rank : Palette.otherColorIndex
            colorMap[Int(stat.index)] = colorIndex
            ranked[rank].colorIndex = colorIndex
        }
        return (ranked, colorMap)
    }
}

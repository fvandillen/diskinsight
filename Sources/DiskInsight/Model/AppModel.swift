import AppKit
import Combine
import Foundation
import SwiftUI

struct OutlineRow: Identifiable {
    let node: FileNode
    let depth: Int
    let expandable: Bool
    var id: NodeID { node.id }
}

struct ScanTarget: Identifiable, Hashable {
    let url: URL
    let title: String
    let isVolume: Bool
    var id: String { url.path }
}

@MainActor
final class AppModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var root: FileNode?
    @Published private(set) var treemapRoot: FileNode?
    @Published private(set) var extensions: [ExtensionStat] = []
    @Published private(set) var progress = ScanProgress()
    @Published private(set) var isScanning = false
    @Published private(set) var statusMessage = "Choose a folder or volume, then press Scan."
    @Published private(set) var lastScanDuration: TimeInterval = 0
    @Published private(set) var volumeCapacity: Int64 = 0
    @Published private(set) var volumeFree: Int64 = 0
    @Published private(set) var errorCount: Int64 = 0

    @Published private(set) var rows: [OutlineRow] = []
    @Published var expanded: Set<NodeID> = []
    @Published var selection: NodeID? {
        didSet { selectionChanged() }
    }
    @Published var selectedExtension: Int32? {
        didSet { scheduleTreemapRender() }
    }

    @Published var sizeMode: SizeMode = .allocated {
        didSet { sizeModeChanged() }
    }
    @Published var sortKey: SortKey = .size { didSet { sortChanged() } }
    @Published var sortAscending = false { didSet { sortChanged() } }
    @Published var options = ScanOptions()

    @Published private(set) var treemapImage: CGImage?
    @Published private(set) var treemapCells: [TreemapCell] = []
    @Published private(set) var treemapNodeRects: [ObjectIdentifier: CGRect] = [:]
    @Published private(set) var treemapPixelSize: CGSize = .zero
    @Published private(set) var treemapScale: CGFloat = 2
    @Published private(set) var isRenderingTreemap = false

    @Published var errorText: String?
    @Published var pendingTrash: FileNode?

    /// Full Disk Access is requested once, up front, so macOS never interrupts a
    /// scan with a folder-by-folder consent prompt.
    @Published private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess()
    @Published private(set) var isAwaitingPermission = false
    @Published private(set) var didBypassPermissionGate = false
    @Published private(set) var blockedCount: Int64 = 0

    /// The gate blocks the app until access is granted, or explicitly bypassed.
    var showsPermissionGate: Bool { !hasFullDiskAccess && !didBypassPermissionGate }

    // MARK: - Private state

    private var scanner: DiskScanner?
    private var progressTimer: Timer?
    private var colorForExtIndex: [Int] = []
    private var sortedChildrenCache: [NodeID: [FileNode]] = [:]
    private var permissionTimer: Timer?
    private var treemapGeneration = 0
    private var pendingRenderWork: DispatchWorkItem?
    private var requestedPixelSize: CGSize = .zero

    /// Serialises every read/write of the node tree that happens off the main thread.
    private let treeQueue = DispatchQueue(label: "com.diskinsight.tree", qos: .userInitiated)

    var scanTargets: [ScanTarget] {
        var targets: [ScanTarget] = [
            ScanTarget(url: FileManager.default.homeDirectoryForCurrentUser, title: "Home Folder", isVolume: false),
            ScanTarget(url: URL(fileURLWithPath: "/"), title: "Macintosh Volume (/)", isVolume: true)
        ]
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsBrowsableKey, .volumeIsLocalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                            options: [.skipHiddenVolumes]) ?? []
        for volume in volumes where volume.path != "/" {
            let values = try? volume.resourceValues(forKeys: Set(keys))
            let name = values?.volumeName ?? volume.lastPathComponent
            targets.append(ScanTarget(url: volume, title: name, isVolume: true))
        }
        return targets
    }

    var selectedNode: FileNode? { selection?.node }

    var canDeleteSelection: Bool {
        guard let node = selectedNode else { return false }
        return node.parent != nil && !isScanning
    }

    // MARK: - Scanning

    func scan(url: URL) {
        guard !isScanning else { return }
        cancelRenderWork()
        selection = nil
        selectedExtension = nil
        expanded = []
        rows = []
        sortedChildrenCache = [:]
        treemapImage = nil
        treemapCells = []
        root = nil
        treemapRoot = nil
        extensions = []
        progress = ScanProgress()
        errorText = nil
        isScanning = true
        statusMessage = "Scanning \(url.path)…"

        var effective = options
        // Re-check each scan: the user may have granted access in the meantime.
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
        effective.hasFullDiskAccess = hasFullDiskAccess

        let scanner = DiskScanner(options: effective)
        self.scanner = scanner

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isScanning else { return }
                self.progress = scanner.snapshot()
            }
        }

        treeQueue.async { [weak self] in
            let outcome: Result<ScanResult, Error>
            do {
                outcome = .success(try scanner.scan(rootURL: url))
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async {
                self?.finishScan(outcome)
            }
        }
    }

    func cancelScan() {
        scanner?.cancel()
        statusMessage = "Cancelling…"
    }

    private func finishScan(_ outcome: Result<ScanResult, Error>) {
        progressTimer?.invalidate()
        progressTimer = nil
        isScanning = false
        scanner = nil

        switch outcome {
        case .failure(let error):
            if case ScanError.cancelled = error {
                statusMessage = "Scan cancelled."
            } else {
                errorText = error.localizedDescription
                statusMessage = "Scan failed."
            }
        case .success(let result):
            root = result.root
            treemapRoot = result.root
            extensions = result.extensions
            colorForExtIndex = result.colorForExtIndex
            lastScanDuration = result.duration
            volumeCapacity = result.volumeCapacity
            volumeFree = result.volumeFree
            errorCount = result.errors
            blockedCount = result.blocked
            expanded = [result.root.id]
            autoExpandLargest(from: result.root, budget: 2)
            rebuildRows()
            // Deferred so the list is not mutated while it renders the new rows.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.root === result.root else { return }
                self.selection = result.root.id
            }
            statusMessage = "Scanned \(Format.count(result.root.itemCount)) items in \(Format.duration(result.duration))."
            scheduleTreemapRender(immediate: true)
        }
    }

    private func autoExpandLargest(from node: FileNode, budget: Int) {
        guard budget > 0 else { return }
        guard let biggest = node.children?.first(where: { $0.isDirectory && !$0.isLeaf }) else { return }
        expanded.insert(biggest.id)
        autoExpandLargest(from: biggest, budget: budget - 1)
    }

    // MARK: - Outline rows

    func toggleExpansion(_ node: FileNode) {
        let key = node.id
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
        }
        rebuildRows()
    }

    func expandAncestors(of node: FileNode) {
        for ancestor in node.ancestors() {
            expanded.insert(ancestor.id)
        }
        rebuildRows()
    }

    func collapseAll() {
        guard let root else { return }
        expanded = [root.id]
        rebuildRows()
    }

    func sortedChildren(of node: FileNode) -> [FileNode] {
        if let cached = sortedChildrenCache[node.id] { return cached }
        guard let children = node.children else { return [] }
        let sorted = children.sorted(by: comparator)
        sortedChildrenCache[node.id] = sorted
        return sorted
    }

    private var comparator: (FileNode, FileNode) -> Bool {
        let ascending = sortAscending
        let mode = sizeMode
        switch sortKey {
        case .size:
            return { lhs, rhs in
                let a = lhs.value(mode), b = rhs.value(mode)
                if a == b { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
                return ascending ? a < b : a > b
            }
        case .name:
            return { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        case .items:
            return { lhs, rhs in
                let a = lhs.isDirectory ? lhs.itemCount : 0
                let b = rhs.isDirectory ? rhs.itemCount : 0
                if a == b { return lhs.value(mode) > rhs.value(mode) }
                return ascending ? a < b : a > b
            }
        case .modified:
            return { lhs, rhs in
                if lhs.mtime == rhs.mtime { return lhs.value(mode) > rhs.value(mode) }
                return ascending ? lhs.mtime < rhs.mtime : lhs.mtime > rhs.mtime
            }
        }
    }

    func rebuildRows() {
        guard let root else {
            rows = []
            return
        }
        var result: [OutlineRow] = []
        result.reserveCapacity(min(4096, rows.count * 2 + 64))
        appendRows(node: root, depth: 0, into: &result)
        rows = result
    }

    private func appendRows(node: FileNode, depth: Int, into result: inout [OutlineRow]) {
        let expandable = node.isDirectory && !(node.children?.isEmpty ?? true)
        result.append(OutlineRow(node: node, depth: depth, expandable: expandable))
        guard expandable, expanded.contains(node.id) else { return }
        for child in sortedChildren(of: node) {
            appendRows(node: child, depth: depth + 1, into: &result)
        }
    }

    private func sortChanged() {
        sortedChildrenCache.removeAll(keepingCapacity: true)
        rebuildRows()
    }

    private func sizeModeChanged() {
        sortedChildrenCache.removeAll(keepingCapacity: true)
        extensions.sort { lhs, rhs in lhs.value(sizeMode) > rhs.value(sizeMode) }
        rebuildRows()
        scheduleTreemapRender()
    }

    /// Selection only moves a SwiftUI overlay, so no re-render is needed.
    private func selectionChanged() {}

    // MARK: - Treemap

    func setTreemapViewport(pixelSize: CGSize, scale: CGFloat) {
        guard pixelSize.width > 1, pixelSize.height > 1 else { return }
        let changed = abs(pixelSize.width - requestedPixelSize.width) > 0.5
            || abs(pixelSize.height - requestedPixelSize.height) > 0.5
            || scale != treemapScale
        guard changed else { return }
        requestedPixelSize = pixelSize
        treemapScale = scale
        scheduleTreemapRender()
    }

    func zoomTreemap(to node: FileNode) {
        guard node.isDirectory, !node.isLeaf else { return }
        treemapRoot = node
        scheduleTreemapRender(immediate: true)
    }

    func zoomTreemapOut() {
        guard let current = treemapRoot, let parent = current.parent else { return }
        treemapRoot = parent
        scheduleTreemapRender(immediate: true)
    }

    func resetTreemapZoom() {
        treemapRoot = root
        scheduleTreemapRender(immediate: true)
    }

    private func cancelRenderWork() {
        pendingRenderWork?.cancel()
        pendingRenderWork = nil
    }

    func scheduleTreemapRender(immediate: Bool = false, layoutOnly: Bool = false, reuseLayout: Bool = false) {
        guard let node = treemapRoot, !isScanning else { return }
        let size = requestedPixelSize
        guard size.width > 1, size.height > 1 else { return }

        cancelRenderWork()
        treemapGeneration += 1
        let generation = treemapGeneration
        let mode = sizeMode
        let colors = colorForExtIndex
        let existingCells = treemapCells
        let existingRects = treemapNodeRects
        let existingSize = treemapPixelSize
        let canReuse = reuseLayout && !existingCells.isEmpty && existingSize == size
        let highlightExt = selectedExtension

        isRenderingTreemap = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var layout: TreemapLayout
            if canReuse {
                layout = TreemapLayout(cells: existingCells,
                                       pixelSize: existingSize,
                                       nodeRects: existingRects,
                                       rootRect: CGRect(origin: .zero, size: existingSize))
            } else {
                layout = TreemapBuilder.build(root: node, pixelSize: size, sizeMode: mode, colorForExtIndex: colors)
            }

            var highlighted: Set<ObjectIdentifier> = []
            if let highlightExt {
                for cell in layout.cells where cell.node.extIndex == highlightExt {
                    highlighted.insert(ObjectIdentifier(cell.node))
                }
            }
            let image = TreemapRenderer.render(layout: layout,
                                               highlighted: highlighted,
                                               highlightAll: highlightExt != nil)
            let finished = layout
            Task { @MainActor [weak self] in
                guard let self, generation == self.treemapGeneration else { return }
                self.treemapCells = finished.cells
                self.treemapNodeRects = finished.nodeRects
                self.treemapPixelSize = finished.pixelSize
                self.treemapImage = image
                self.isRenderingTreemap = false
            }
        }
        pendingRenderWork = work
        treeQueue.asyncAfter(deadline: .now() + (immediate ? 0 : 0.08), execute: work)
    }

    /// Rect (in treemap pixel space) covering the currently selected node.
    var selectionRectInTreemap: CGRect? {
        guard let node = selectedNode else { return nil }
        return treemapNodeRects[ObjectIdentifier(node)]
    }

    func node(atTreemapPoint point: CGPoint) -> FileNode? {
        for cell in treemapCells.reversed() where cell.rect.contains(point) {
            return cell.node
        }
        return nil
    }

    func select(node: FileNode, revealInTree: Bool = true) {
        if revealInTree {
            expandAncestors(of: node)
        }
        selection = node.id
    }

    // MARK: - File operations

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func open(_ node: FileNode) {
        NSWorkspace.shared.open(node.url)
    }

    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    func requestTrash(_ node: FileNode) {
        guard node.parent != nil else { return }
        pendingTrash = node
    }

    func confirmPendingTrash() {
        guard let node = pendingTrash else { return }
        pendingTrash = nil
        moveToTrash(node)
    }

    func moveToTrash(_ node: FileNode) {
        guard let parent = node.parent else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        } catch {
            errorText = "Couldn't move “\(node.name)” to the Trash.\n\(error.localizedDescription)"
            return
        }

        let removedSize = node.size
        let removedAllocated = node.allocated
        let removedFiles = node.isDirectory ? node.fileCount : 1
        let removedFolders = node.isDirectory ? node.folderCount + 1 : 0

        subtractExtensionStats(for: node)

        if selection == node.id { selection = nil }
        expanded.remove(node.id)
        if let treemapRoot, treemapRoot === node || node.contains(treemapRoot) {
            self.treemapRoot = parent
        }

        treeQueue.sync {
            if let index = parent.children?.firstIndex(where: { $0 === node }) {
                parent.children?.remove(at: index)
            }
            var cursor: FileNode? = parent
            while let current = cursor {
                current.size -= removedSize
                current.allocated -= removedAllocated
                current.fileCount -= removedFiles
                current.folderCount -= removedFolders
                cursor = current.parent
            }
        }

        sortedChildrenCache.removeAll(keepingCapacity: true)
        rebuildRows()
        statusMessage = "Moved “\(node.name)” (\(Format.bytes(removedAllocated))) to the Trash."
        scheduleTreemapRender(immediate: true)
    }

    private func subtractExtensionStats(for node: FileNode) {
        var deltas: [Int32: (size: Int64, allocated: Int64, count: Int64)] = [:]
        node.walk { entry in
            guard !entry.isDirectory, entry.extIndex >= 0 else { return }
            var current = deltas[entry.extIndex] ?? (0, 0, 0)
            current.size += entry.size
            current.allocated += entry.allocated
            current.count += 1
            deltas[entry.extIndex] = current
        }
        guard !deltas.isEmpty else { return }
        for index in extensions.indices {
            if let delta = deltas[extensions[index].index] {
                extensions[index].size -= delta.size
                extensions[index].allocated -= delta.allocated
                extensions[index].count -= delta.count
            }
        }
        extensions.removeAll { $0.count <= 0 }
        extensions.sort { $0.value(sizeMode) > $1.value(sizeMode) }
    }

    func color(for node: FileNode) -> Color {
        guard !node.isDirectory else { return Color(nsColor: .controlAccentColor) }
        let index = Int(node.extIndex)
        guard index >= 0, index < colorForExtIndex.count else { return Palette.swiftUIColor(Palette.otherColorIndex) }
        return Palette.swiftUIColor(colorForExtIndex[index])
    }

    // MARK: - Permissions

    func openFullDiskAccessSettings() {
        Permissions.openFullDiskAccessSettings()
    }

    /// Opens System Settings and waits for the grant, so the user never has to
    /// come back and click anything else.
    func beginGrantingFullDiskAccess() {
        Permissions.openFullDiskAccessSettings()
        guard !isAwaitingPermission else { return }
        isAwaitingPermission = true

        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard Permissions.hasFullDiskAccess() else { return }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
                self.isAwaitingPermission = false
                self.hasFullDiskAccess = true
                self.statusMessage = "Full Disk Access granted. Choose a folder or volume, then press Scan."
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func continueWithLimitedAccess() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        isAwaitingPermission = false
        didBypassPermissionGate = true
        statusMessage = "Limited access: protected folders are skipped. Choose a folder, then press Scan."
    }

    /// Called when the app regains focus, in case access was granted elsewhere.
    func refreshPermissionState() {
        guard !hasFullDiskAccess else { return }
        if Permissions.hasFullDiskAccess() {
            hasFullDiskAccess = true
            isAwaitingPermission = false
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder or volume to analyse"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url {
            scan(url: url)
        }
    }
}

import SwiftUI

enum Column {
    static let size: CGFloat = 88
    static let percent: CGFloat = 92
    static let items: CGFloat = 74
    static let files: CGFloat = 66
    static let folders: CGFloat = 66
    static let modified: CGFloat = 128
    static let gap: CGFloat = 10
}

struct DirectoryOutlineView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.rows.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.isScanning ? "Scanning…" : "No scan yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(model.rows, selection: $model.selection) { row in
                OutlineRowView(row: row)
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 8))
                    .contextMenu { NodeContextMenu(node: row.node) }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 20)
            .onChange(of: model.selection) { _, newValue in
                guard let newValue else { return }
                // Deferred: scrolling inside the table's own update is reentrant.
                DispatchQueue.main.async {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Column.gap) {
            SortHeader(title: "Name", key: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            SortHeader(title: model.sizeMode.shortTitle, key: .size, alignment: .trailing)
                .frame(width: Column.size, alignment: .trailing)
            Text("% of parent")
                .frame(width: Column.percent, alignment: .trailing)
            SortHeader(title: "Items", key: .items, alignment: .trailing)
                .frame(width: Column.items, alignment: .trailing)
            Text("Files")
                .frame(width: Column.files, alignment: .trailing)
            Text("Folders")
                .frame(width: Column.folders, alignment: .trailing)
            SortHeader(title: "Modified", key: .modified, alignment: .trailing)
                .frame(width: Column.modified, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SortHeader: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let key: SortKey
    let alignment: Alignment

    var body: some View {
        Button {
            if model.sortKey == key {
                model.sortAscending.toggle()
            } else {
                model.sortKey = key
                model.sortAscending = key == .name
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if model.sortKey == key {
                    Image(systemName: model.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct OutlineRowView: View {
    @EnvironmentObject private var model: AppModel
    let row: OutlineRow

    private var node: FileNode { row.node }

    private var parentFraction: Double {
        guard let parent = node.parent else { return 1 }
        let total = parent.value(model.sizeMode)
        guard total > 0 else { return 0 }
        return Double(node.value(model.sizeMode)) / Double(total)
    }

    var body: some View {
        HStack(spacing: Column.gap) {
            HStack(spacing: 4) {
                Color.clear.frame(width: CGFloat(row.depth) * 13, height: 1)
                disclosure
                Image(nsImage: IconCache.icon(for: node))
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(node.isUnreadable || node.isSkipped || node.needsPermission
                                     ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                if node.needsPermission {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .help(Permissions.guardDescription(for: node.path))
                } else if node.isUnreadable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .help("Not readable — Full Disk Access may be required")
                } else if node.isSkipped {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .help("Skipped: different volume, or already counted elsewhere")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Format.bytes(node.value(model.sizeMode)))
                .frame(width: Column.size, alignment: .trailing)
                .monospacedDigit()

            PercentBar(fraction: parentFraction, color: model.color(for: node))
                .frame(width: Column.percent, alignment: .trailing)

            Text(node.isDirectory ? Format.count(node.itemCount) : "—")
                .frame(width: Column.items, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(node.isDirectory ? Format.count(Int64(node.fileCount)) : "—")
                .frame(width: Column.files, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(node.isDirectory ? Format.count(Int64(node.folderCount)) : "—")
                .frame(width: Column.folders, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(Format.date(node.modifiedDate))
                .frame(width: Column.modified, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .frame(height: 20)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if row.expandable { model.toggleExpansion(node) }
        }
    }

    private var displayName: String {
        node.parent == nil ? node.path : node.name
    }

    @ViewBuilder
    private var disclosure: some View {
        if row.expandable {
            Button {
                model.toggleExpansion(node)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(model.expanded.contains(node.id) ? 90 : 0))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }
}

struct PercentBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .quaternaryLabelColor))
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            Text(Format.percent(fraction))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

struct NodeContextMenu: View {
    @EnvironmentObject private var model: AppModel
    let node: FileNode

    var body: some View {
        Button("Show in Finder") { model.revealInFinder(node) }
        Button("Open") { model.open(node) }
        Button("Copy Path") { model.copyPath(node) }
        Divider()
        if node.isDirectory && !node.isLeaf {
            Button("Zoom Treemap Here") { model.zoomTreemap(to: node) }
        }
        Button("Select in Tree") { model.select(node: node) }
        Divider()
        Button("Move to Trash", role: .destructive) { model.requestTrash(node) }
            .disabled(node.parent == nil)
    }
}

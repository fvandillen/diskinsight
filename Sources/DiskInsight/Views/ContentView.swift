import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.showsPermissionGate {
                PermissionGateView()
            } else {
                mainContent
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear { UISnapshot.startIfRequested(model: model) }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissionState()
        }
        .toolbar { toolbarContent }
        .alert("Move to Trash?",
               isPresented: Binding(get: { model.pendingTrash != nil },
                                    set: { if !$0 { model.pendingTrash = nil } })) {
            Button("Cancel", role: .cancel) { model.pendingTrash = nil }
            Button("Move to Trash", role: .destructive) { model.confirmPendingTrash() }
        } message: {
            if let node = model.pendingTrash {
                Text("“\(node.name)” (\(Format.bytes(node.value(model.sizeMode)))\(node.isDirectory ? ", \(Format.count(node.itemCount)) items" : "")) will be moved to the Trash.\n\n\(node.path)")
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.errorText != nil },
                                    set: { if !$0 { model.errorText = nil } })) {
            Button("OK", role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            ScanBar()
            Divider()
            if model.isScanning {
                progressBar
                Divider()
            }
            VSplitView {
                HSplitView {
                    DirectoryOutlineView()
                        .frame(minWidth: 520, idealWidth: 940)
                    ExtensionListView()
                        .frame(minWidth: 240, idealWidth: 320, maxWidth: 460)
                }
                .frame(minHeight: 200, idealHeight: 540)

                TreemapView()
                    .frame(minHeight: 140, idealHeight: 260)
            }

            Divider()
            statusBar
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                guard let node = model.selectedNode else { return }
                model.revealInFinder(node)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .disabled(model.selectedNode == nil || model.showsPermissionGate)
            .help("Reveal the selection in Finder")
        }

        ToolbarItem {
            Button(role: .destructive) {
                guard let node = model.selectedNode else { return }
                model.requestTrash(node)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(!model.canDeleteSelection || model.showsPermissionGate)
            .help("Move the selected file or folder to the Trash")
        }

        ToolbarItem {
            Menu {
                Toggle("Stay on the same volume", isOn: $model.options.stayOnVolume)
                Toggle("Treat app bundles as single items", isOn: $model.options.collapsePackages)
                Divider()
                Button("Collapse All") { model.collapseAll() }
                Button("Open Full Disk Access Settings…") { model.openFullDiskAccessSettings() }
            } label: {
                Label("Options", systemImage: "gearshape")
            }
        }
    }

    // MARK: - Chrome

    private var progressBar: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Format.count(model.progress.files)) files · \(Format.count(model.progress.folders)) folders · \(Format.bytes(model.progress.bytes))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Text(model.progress.currentPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Stop") { model.cancelScan() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Text(model.statusMessage)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let root = model.root {
                Label(Format.bytes(root.value(model.sizeMode)), systemImage: "chart.pie")
                    .help("Total size of the scanned tree")
                Label("\(Format.count(Int64(root.fileCount)))", systemImage: "doc")
                    .help("Files")
                Label("\(Format.count(Int64(root.folderCount)))", systemImage: "folder")
                    .help("Folders")
            }
            if model.systemProtectedCount > 0 {
                Label("\(Format.count(model.systemProtectedCount)) macOS-protected", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                    .help("Omitted from totals: macOS protects these items independently of Full Disk Access. No additional access is requested.")
            }
            if model.volumeCapacity > 0 {
                Divider().frame(height: 12)
                Text("\(Format.bytes(model.volumeFree)) free of \(Format.bytes(model.volumeCapacity))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

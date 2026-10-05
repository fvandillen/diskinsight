import SwiftUI

struct DiskInsightApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("DiskInsight") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.isScanning || model.showsPermissionGate)
                Button("Rescan") {
                    if let root = model.root { model.scan(url: root.url) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.root == nil || model.isScanning || model.showsPermissionGate)

                Divider()
                Button("Grant Full Disk Access…") { model.beginGrantingFullDiskAccess() }
                    .disabled(model.hasFullDiskAccess)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Move to Trash") {
                    if let node = model.selectedNode { model.requestTrash(node) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.canDeleteSelection)

                Button("Show in Finder") {
                    if let node = model.selectedNode { model.revealInFinder(node) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedNode == nil)

                Button("Copy Path") {
                    if let node = model.selectedNode { model.copyPath(node) }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.selectedNode == nil)
            }
            CommandMenu("Treemap") {
                Button("Zoom Out") { model.zoomTreemapOut() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Whole Tree") { model.resetTreemapZoom() }
                    .keyboardShortcut("]", modifiers: .command)
                Divider()
                Button("Collapse All Folders") { model.collapseAll() }
            }
        }
    }
}

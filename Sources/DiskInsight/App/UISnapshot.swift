import AppKit
import SwiftUI

/// Development helper: renders the app's own window to a PNG without needing
/// Screen Recording permission. Enabled only via `--ui-snapshot=<file>`.
enum UISnapshot {
    private static var timer: Timer?
    private static var started = false

    static func startIfRequested(model: AppModel) {
        guard !started else { return }
        let arguments = CommandLine.arguments
        guard let output = arguments.first(where: { $0.hasPrefix("--ui-snapshot=") })
            .map({ String($0.dropFirst("--ui-snapshot=".count)) }) else { return }
        started = true

        let path = arguments.first(where: { $0.hasPrefix("--ui-path=") })
            .map { String($0.dropFirst("--ui-path=".count)) } ?? NSHomeDirectory()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let window = NSApp.windows.first {
                window.setContentSize(NSSize(width: 1400, height: 880))
                window.center()
            }

            // Capture the permission gate itself rather than a scan.
            if CommandLine.arguments.contains("--ui-gate") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    capture(to: output)
                    NSApp.terminate(nil)
                }
                return
            }

            if model.showsPermissionGate { model.continueWithLimitedAccess() }
            if CommandLine.arguments.contains("--ui-sort-name") {
                model.sortKey = .name
                model.sortAscending = true
            }
            model.scan(url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            waitAndCapture(model: model, output: output)
        }
    }

    private static func waitAndCapture(model: AppModel, output: String) {
        var settleTicks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard !model.isScanning, model.treemapImage != nil else { return }
                settleTicks += 1
                if settleTicks == 2 {
                    simulateTreemapClick(model: model)
                    selectRequestedPath(model: model)
                }
                guard settleTicks >= 6 else { return }
                timer.invalidate()
                capture(to: output)
                NSApp.terminate(nil)
            }
        }
    }

    /// `--ui-select=<path>` reveals a specific node, verifying selection + scroll.
    @MainActor
    private static func selectRequestedPath(model: AppModel) {
        guard let wanted = CommandLine.arguments.first(where: { $0.hasPrefix("--ui-select=") })
            .map({ String($0.dropFirst("--ui-select=".count)) })
            .map({ ($0 as NSString).expandingTildeInPath }) else { return }
        guard let root = model.root else { return }

        var match: FileNode?
        root.walk { node in
            if match == nil, node.path == wanted { match = node }
        }
        guard let match else {
            print("snapshot: no node at \(wanted)")
            return
        }
        print("snapshot: selected \(match.path) needsPermission=\(match.needsPermission)")
        model.select(node: match)
    }

    /// `--ui-click=0.4,0.6` selects whatever sits at that fraction of the treemap,
    /// exercising the full treemap -> tree selection path.
    @MainActor
    private static func simulateTreemapClick(model: AppModel) {
        guard let raw = CommandLine.arguments.first(where: { $0.hasPrefix("--ui-click=") })
            .map({ String($0.dropFirst("--ui-click=".count)) }) else { return }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return }
        let size = model.treemapPixelSize
        let point = CGPoint(x: size.width * parts[0], y: size.height * parts[1])
        guard let node = model.node(atTreemapPoint: point) else {
            print("snapshot: no node at \(point)")
            return
        }
        print("snapshot: treemap hit -> \(node.path) (\(Format.bytes(node.allocated)))")
        model.select(node: node)

        if CommandLine.arguments.contains("--ui-trash") {
            let before = model.root?.allocated ?? 0
            model.requestTrash(node)
            model.confirmPendingTrash()
            let after = model.root?.allocated ?? 0
            print("snapshot: trashed, root \(Format.bytes(before)) -> \(Format.bytes(after))")
            print("snapshot: still on disk? \(FileManager.default.fileExists(atPath: node.path))")
        }
    }

    private static func capture(to output: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else {
            print("snapshot: no window")
            return
        }
        // Prominent controls render greyed while the window is inactive, and the
        // toolbar lives in the frame view rather than the content view.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        print("snapshot: key=\(window.isKeyWindow) main=\(window.isMainWindow) active=\(NSApp.isActive)")

        let view = window.contentView?.superview ?? window.contentView!

        // Read the window's real backing store: unlike cacheDisplay this picks up
        // toolbar and material layers.
        window.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("snapshot: no bitmap")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: output))
        print("snapshot: wrote \(output)")
    }
}


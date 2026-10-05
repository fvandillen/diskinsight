import AppKit
import Foundation
import UniformTypeIdentifiers

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func count(_ value: Int64) -> String {
        decimal.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "—" }
        return dateFormatter.string(from: value)
    }

    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "—" }
        if fraction > 0 && fraction < 0.001 { return "<0.1%" }
        return String(format: "%.1f%%", fraction * 100)
    }

    static func duration(_ value: TimeInterval) -> String {
        value < 1 ? String(format: "%.0f ms", value * 1000) : String(format: "%.1f s", value)
    }
}

/// Cached file-kind icons. `NSWorkspace.icon(forFile:)` is far too slow to call
/// per row, so icons are resolved once per extension.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for node: FileNode) -> NSImage {
        if node.isDirectory {
            return cached("__dir__") { NSWorkspace.shared.icon(for: .folder) }
        }
        let ext = node.fileExtension
        return cached(ext) {
            if ext.isEmpty {
                return NSWorkspace.shared.icon(for: .data)
            }
            let type = UTType(filenameExtension: ext) ?? .data
            return NSWorkspace.shared.icon(for: type)
        }
    }

    private static func cached(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let existing = cache[key] { return existing }
        let image = make()
        image.size = NSSize(width: 16, height: 16)
        cache[key] = image
        return image
    }
}

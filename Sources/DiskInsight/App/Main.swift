import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
enum Main {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--scan") {
            let path = index + 1 < arguments.count ? arguments[index + 1] : FileManager.default.currentDirectoryPath
            HeadlessScan.run(path: path,
                             stayOnVolume: !arguments.contains("--cross-volumes"),
                             limit: Int(arguments.first(where: { $0.hasPrefix("--top=") })?
                                .dropFirst(6) ?? "20") ?? 20,
                             treemapOutput: arguments.first(where: { $0.hasPrefix("--png=") })
                                .map { String($0.dropFirst(6)) })
            return
        }
        if arguments.contains("--probe-paths") {
            // Diagnostic: which locations actually deny access without Full Disk
            // Access. Used to keep the guard list from over-blocking.
            let home = NSHomeDirectory()
            for path in ["/Desktop", "/Documents", "/Downloads", "/Pictures",
                         "/Movies", "/Music", "/Public", "/Library/Mobile Documents"] {
                let full = home + path
                let handle = opendir(full)
                if let handle {
                    var entries = 0
                    while readdir(handle) != nil { entries += 1 }
                    closedir(handle)
                    print("OPEN   (\(entries) entries)  \(full)")
                } else {
                    print("DENIED errno=\(errno)        \(full)")
                }
            }
            return
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            print("""
            DiskInsight — disk usage analyser

            Launch with no arguments for the GUI, or:
              --scan <path>       print the biggest items under <path> and exit
              --top=N             how many entries to print (default 20)
              --png=<file>        also write a treemap image of the scan
              --cross-volumes     follow mount points onto other volumes
              --verbose           live progress while scanning
              --list-blocked      list folders skipped for permissions
              --list-unreadable   show a sample of read failures and their causes
              --probe-paths       report which guarded locations deny access
            """)
            return
        }
        DiskInsightApp.main()
    }
}

/// Terminal mode: handy for scripting and for verifying scan totals against `du`.
enum HeadlessScan {
    static func run(path: String, stayOnVolume: Bool, limit: Int, treemapOutput: String?) {
        var options = ScanOptions()
        options.stayOnVolume = stayOnVolume
        options.hasFullDiskAccess = Permissions.hasFullDiskAccess()
        FileHandle.standardError.write(Data("full disk access: \(options.hasFullDiskAccess)\n".utf8))
        let scanner = DiskScanner(options: options)
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL

        var outcome: Result<ScanResult, Error>?
        let lock = NSLock()
        let thread = Thread {
            let value: Result<ScanResult, Error>
            do { value = .success(try scanner.scan(rootURL: url)) }
            catch { value = .failure(error) }
            lock.lock(); outcome = value; lock.unlock()
        }
        thread.stackSize = 1 << 21
        thread.start()

        let verbose = CommandLine.arguments.contains("--verbose")
        while true {
            Thread.sleep(forTimeInterval: verbose ? 1.0 : 0.2)
            lock.lock(); let done = outcome != nil; lock.unlock()
            if done { break }
            if verbose {
                let progress = scanner.snapshot()
                FileHandle.standardError.write(Data("  \(progress.files) files, \(progress.folders) folders, \(Format.bytes(progress.bytes)) — \(progress.currentPath)\n".utf8))
            }
        }

        lock.lock(); let finished = outcome!; lock.unlock()

        do {
            let result = try finished.get()
            let root = result.root
            print("Scanned \(root.path)")
            print(String(format: "  %@ on disk / %@ logical", Format.bytes(root.allocated), Format.bytes(root.size)))
            print("  \(root.fileCount) files, \(root.folderCount) folders, \(result.errors) unreadable, \(result.blocked) blocked, \(result.systemProtected) macOS-protected, \(Format.duration(result.duration))")
            print("")
            print("Largest entries:")
            for child in (root.children ?? []).prefix(limit) {
                let marker = child.isDirectory ? "/" : " "
                print(String(format: "  %10@ %@%@", Format.bytes(child.allocated), child.name, marker))
            }
            print("")
            print("Largest file types:")
            for stat in result.extensions.prefix(min(limit, 10)) {
                print(String(format: "  %10@  %@ (%d files)", Format.bytes(stat.allocated), stat.displayName, stat.count))
            }

            if CommandLine.arguments.contains("--list-blocked") {
                print("")
                print("Folders skipped for permissions:")
                var found = 0
                root.walk { node in
                    guard node.needsPermission else { return }
                    found += 1
                    print("  \(node.path)")
                }
                if found == 0 { print("  (none)") }
            }

            if CommandLine.arguments.contains("--list-unreadable") {
                print("")
                print("Read failures (showing \(result.unreadableSamples.count) of \(result.errors)):")
                for issue in result.unreadableSamples {
                    print("  \(issue.path): \(issue.message) (errno \(issue.errorCode))")
                }
                if result.errors == 0 { print("  (none)") }
            }

            if let treemapOutput {
                writeTreemap(result: result, to: treemapOutput)
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func writeTreemap(result: ScanResult, to path: String) {
        let size = CGSize(width: 1600, height: 900)
        let layout = TreemapBuilder.build(root: result.root,
                                          pixelSize: size,
                                          sizeMode: .allocated,
                                          colorForExtIndex: result.colorForExtIndex)
        guard let image = TreemapRenderer.render(layout: layout) else {
            print("Could not render treemap.")
            return
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            print("Could not create \(url.path).")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("")
        print("Treemap written to \(url.path) (\(layout.cells.count) cells)")
    }
}

import Foundation
import XCTest
@testable import DiskInsight

final class DiskScannerProgressTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskInsight-ProgressTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: fixture)
    }

    func testEmptyScanReportsZeroInBothSizeModes() throws {
        let scanner = DiskScanner(options: ScanOptions())
        XCTAssertEqual(scanner.snapshot().value(.allocated), 0)
        XCTAssertEqual(scanner.snapshot().value(.logical), 0)
        let result = try scanner.scan(rootURL: fixture)
        assertProgress(scanner.snapshot(), matches: result.root)
        XCTAssertEqual(result.root.size, 0)
        XCTAssertEqual(result.root.allocated, 0)
    }

    func testSparseFileProgressUsesAllocatedBlocksInsteadOfLogicalLength() throws {
        let sparse = fixture.appendingPathComponent("sparse.img")
        let logicalSize: Int64 = 7_000_000_000_000
        try createSparseFile(at: sparse, size: logicalSize)
        let metadata = try fileStat(at: sparse)
        XCTAssertEqual(metadata.st_size, logicalSize)
        let allocated = Int64(metadata.st_blocks) * 512
        XCTAssertGreaterThan(allocated, 0)
        XCTAssertLessThan(allocated, 1_000_000)

        let scanner = DiskScanner(options: ScanOptions())
        let result = try scanner.scan(rootURL: fixture)
        let progress = scanner.snapshot()
        XCTAssertEqual(progress.value(.logical), logicalSize)
        XCTAssertEqual(progress.value(.allocated), allocated)
        assertProgress(progress, matches: result.root)
    }

    func testProgressPreservesRegularFilesHardLinksAndSymlinksAcrossDirectories() throws {
        var expectedSize: Int64 = 0
        var expectedAllocated: Int64 = 0
        let directoryCount = 32
        for index in 0..<directoryCount {
            let directory = fixture.appendingPathComponent("nested-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let file = directory.appendingPathComponent("data.bin")
            try Data(repeating: UInt8(index), count: 8192).write(to: file)
            let hardLink = directory.appendingPathComponent("hard-link.bin")
            try FileManager.default.linkItem(at: file, to: hardLink)
            let symlink = directory.appendingPathComponent("symlink")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
            for entry in [file, hardLink, symlink] {
                let metadata = try fileStat(at: entry)
                expectedSize += Int64(metadata.st_size)
                expectedAllocated += Int64(metadata.st_blocks) * 512
            }
        }

        let scanner = DiskScanner(options: ScanOptions())
        let result = try scanner.scan(rootURL: fixture)
        let progress = scanner.snapshot()
        XCTAssertEqual(progress.files, Int64(directoryCount * 3))
        XCTAssertEqual(progress.folders, Int64(directoryCount))
        XCTAssertEqual(progress.value(.logical), expectedSize)
        XCTAssertEqual(progress.value(.allocated), expectedAllocated)
        assertProgress(progress, matches: result.root)
    }

    func testProgressIncludesCollapsedPackageMetadataButNotItsContents() throws {
        let package = fixture.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try createSparseFile(at: package.appendingPathComponent("ignored.img"), size: 7_000_000_000_000)
        let regularFile = fixture.appendingPathComponent("data.bin")
        try Data(repeating: 1, count: 8192).write(to: regularFile)
        let packageStat = try fileStat(at: package)
        let regularStat = try fileStat(at: regularFile)
        var options = ScanOptions()
        options.collapsePackages = true

        let scanner = DiskScanner(options: options)
        let result = try scanner.scan(rootURL: fixture)
        let progress = scanner.snapshot()
        XCTAssertEqual(progress.files, 1)
        XCTAssertEqual(progress.folders, 1)
        XCTAssertEqual(progress.value(.logical), Int64(packageStat.st_size + regularStat.st_size))
        XCTAssertEqual(progress.value(.allocated), Int64(packageStat.st_blocks + regularStat.st_blocks) * 512)
        assertProgress(progress, matches: result.root)
        let packageNode = try XCTUnwrap(result.root.children?.first { $0.name == "Example.app" })
        XCTAssertTrue(packageNode.isLeaf)
    }

    private func assertProgress(_ progress: ScanProgress, matches root: FileNode,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(progress.files, Int64(root.fileCount), file: file, line: line)
        XCTAssertEqual(progress.folders, Int64(root.folderCount), file: file, line: line)
        for mode in SizeMode.allCases {
            XCTAssertEqual(progress.value(mode), root.value(mode), file: file, line: line)
        }
    }

    private func createSparseFile(at url: URL, size: Int64) throws {
        try Data(repeating: 1, count: 8192).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }

    private func fileStat(at url: URL) throws -> stat {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return metadata
    }
}

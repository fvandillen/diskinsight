import Foundation
import XCTest
@testable import DiskInsight

final class ScanAccessPolicyTests: XCTestCase {
    func testDataVaultFlagIsSpecificToReadProtection() {
        XCTAssertTrue(ScanAccessPolicy.isDataVault(flags: FileFlags.dataVault))
        XCTAssertTrue(ScanAccessPolicy.isDataVault(flags: FileFlags.dataVault | FileFlags.firmlink))
        XCTAssertFalse(ScanAccessPolicy.isDataVault(flags: 0))
        XCTAssertFalse(ScanAccessPolicy.isDataVault(flags: FileFlags.dataless))
        // SIP's restricted flag requires an entitlement for writing, not reading.
        XCTAssertFalse(ScanAccessPolicy.isDataVault(flags: 0x0008_0000))
    }

    func testKnownSystemDenialsWithFullDiskAccessAreExpected() {
        for path in ["/private/var/db", "/private/var/db/ConfigurationProfiles/Store",
                     "/var/db/CoreDuet", "/private/var/protected/trustd",
                     "/private/var/root/Library", "/private/var/audit/current",
                     "/private/var/backups", "/private/var/spool/cups",
                     "/.DocumentRevisions-V100/db", "/.Spotlight-V100", "/.fseventsd/log",
                     "/System/Volumes/Data/private/var/db/lockdown",
                     "/System/Volumes/Data/.Spotlight-V100/Store"] {
            for code in [EPERM, EACCES] {
                XCTAssertTrue(ScanAccessPolicy.isExpectedDenial(path: path, errorCode: code,
                                                               hasFullDiskAccess: true), path)
            }
        }
    }

    func testMissingFullDiskAccessIsNeverDismissedAsASystemDenial() {
        XCTAssertFalse(ScanAccessPolicy.isExpectedDenial(path: "/private/var/db/lockdown",
                                                        errorCode: EPERM, hasFullDiskAccess: false))
    }

    func testUnexpectedErrorCodesAreNeverSuppressed() {
        for code in [EIO, ENOENT, ENOTDIR, EMFILE, ESTALE] {
            XCTAssertFalse(ScanAccessPolicy.isExpectedDenial(path: "/private/var/db/lockdown",
                                                            errorCode: code, hasFullDiskAccess: true))
        }
    }

    func testUserDataAndSimilarPathNamesAreNotSuppressed() {
        for path in ["/Users/test/Documents/private", "/Users/other/Library/Mail",
                     "/Users/test/Library/Containers/com.apple.example",
                     "/Library/Application Support/example", "/System/Library/example",
                     "/private/var/folders/ab/hash/T/user-data",
                     "/private/var/db-backup/private", "/private/var/db/../tmp/private",
                     "/var/root-backup", "/.Spotlight-V100-backup",
                     "/Volumes/Data/private/var/db/example"] {
            XCTAssertFalse(ScanAccessPolicy.isExpectedDenial(path: path, errorCode: EACCES,
                                                            hasFullDiskAccess: true), path)
        }
    }
}

final class ScanWarningTests: XCTestCase {
    func testExpectedOmissionsAloneDoNotProduceAWarning() {
        XCTAssertNil(ScanWarning.message(errors: 0, blocked: 0, hasFullDiskAccess: true))
        XCTAssertNil(ScanWarning.message(errors: 0, blocked: 0, hasFullDiskAccess: false))
    }

    func testWarningDoesNotRequestAnExistingGrant() throws {
        let message = try XCTUnwrap(ScanWarning.message(errors: 1, blocked: 0, hasFullDiskAccess: true))
        XCTAssertTrue(message.contains("1 item couldn't be read."))
        XCTAssertTrue(message.contains("Full Disk Access is enabled"))
        XCTAssertFalse(message.contains("Grant Full Disk Access"))
        XCTAssertFalse(message.contains("complete picture"))
    }

    func testLimitedAccessWarningExplainsIncompleteTotalsWithoutPromisingFullAccess() throws {
        let message = try XCTUnwrap(ScanWarning.message(errors: 0, blocked: 1, hasFullDiskAccess: false))
        XCTAssertTrue(message.contains("1 protected folder was skipped."))
        XCTAssertTrue(message.contains("Totals are incomplete"))
        XCTAssertTrue(message.contains("may allow more items"))
    }

    func testMixedWarningReportsBothKindsOfFailure() throws {
        let message = try XCTUnwrap(ScanWarning.message(errors: 3, blocked: 2, hasFullDiskAccess: false))
        XCTAssertTrue(message.contains("2 protected folders were skipped."))
        XCTAssertTrue(message.contains("3 items couldn't be read."))
    }

    func testGrantAfterLimitedScanStillExplainsThatResultsAreIncomplete() throws {
        let message = try XCTUnwrap(ScanWarning.message(errors: 0, blocked: 1, hasFullDiskAccess: true))
        XCTAssertTrue(message.contains("folder was skipped"))
        XCTAssertTrue(message.contains("Full Disk Access is enabled"))
    }
}

final class DiskScannerAccessTests: XCTestCase {
    private var fixture: URL!
    private var lockedDirectories: [URL] = []

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskInsight-AccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        for directory in lockedDirectories {
            guard chmod(directory.path, S_IRWXU) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
        try FileManager.default.removeItem(at: fixture)
    }

    func testReadableTreePreservesCountsSizesAndSymlinkBehavior() throws {
        let nested = fixture.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data(count: 8192).write(to: nested.appendingPathComponent("data.bin"))
        try Data(count: 4096).write(to: fixture.appendingPathComponent("other.txt"))
        let link = fixture.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: nested)
        var linkStat = stat()
        XCTAssertEqual(lstat(link.path, &linkStat), 0)

        let scanner = DiskScanner(options: ScanOptions())
        let result = try scanner.scan(rootURL: fixture)
        XCTAssertEqual(result.root.fileCount, 3)
        XCTAssertEqual(result.root.folderCount, 1)
        XCTAssertEqual(result.root.size, 12288 + linkStat.st_size)
        XCTAssertEqual(result.errors, 0)
        XCTAssertEqual(result.blocked, 0)
        XCTAssertEqual(result.systemProtected, 0)
        XCTAssertTrue(result.unreadableSamples.isEmpty)
        XCTAssertEqual(scanner.snapshot().errors, 0)
    }

    func testUnreadableUserDirectoryRemainsAnErrorWithOrWithoutFullDiskAccess() throws {
        let locked = try createLockedDirectory(name: "private")
        for hasFullDiskAccess in [true, false] {
            var options = ScanOptions()
            options.hasFullDiskAccess = hasFullDiskAccess
            let scanner = DiskScanner(options: options)
            let result = try scanner.scan(rootURL: fixture)
            XCTAssertEqual(result.errors, 1)
            XCTAssertEqual(result.systemProtected, 0)
            XCTAssertEqual(result.unreadableSamples.count, 1)
            XCTAssertEqual(result.unreadableSamples.first?.path, locked.path)
            XCTAssertEqual(result.unreadableSamples.first?.errorCode, EACCES)
            let node = try XCTUnwrap(result.root.children?.first)
            XCTAssertTrue(node.isUnreadable)
            XCTAssertFalse(node.isSystemProtected)
            XCTAssertEqual(scanner.snapshot().errors, 1)
        }
    }

    func testUnreadableRootFailsInsteadOfReturningAnEmptySuccess() throws {
        let locked = try createLockedDirectory(name: "root")
        XCTAssertThrowsError(try DiskScanner(options: ScanOptions()).scan(rootURL: locked)) { error in
            guard case ScanError.unreadableRoot(let path, let code) = error else {
                return XCTFail("Unexpected root error: \(error)")
            }
            XCTAssertEqual(path, locked.path)
            XCTAssertEqual(code, EACCES)
            XCTAssertFalse(error.localizedDescription.contains("Grant Full Disk Access"))
        }
    }

    func testMissingRootPreservesTheActualError() {
        let missing = fixture.appendingPathComponent("missing")
        XCTAssertThrowsError(try DiskScanner(options: ScanOptions()).scan(rootURL: missing)) { error in
            guard case ScanError.unreadableRoot(let path, let code) = error else {
                return XCTFail("Unexpected root error: \(error)")
            }
            XCTAssertEqual(path, missing.path)
            XCTAssertEqual(code, ENOENT)
        }
    }

    func testDiagnosticSamplesAreBoundedWithoutLosingTheErrorCount() throws {
        let total = DiskScanner.issueSampleLimit + 20
        for index in 0..<total {
            try createLockedDirectory(name: "private-\(index)")
        }
        let result = try DiskScanner(options: ScanOptions()).scan(rootURL: fixture)
        XCTAssertEqual(result.errors, Int64(total))
        XCTAssertEqual(result.unreadableSamples.count, DiskScanner.issueSampleLimit)
        XCTAssertEqual(result.systemProtected, 0)
        XCTAssertTrue(result.unreadableSamples.allSatisfy { $0.errorCode == EACCES })
    }

    @discardableResult
    private func createLockedDirectory(name: String) throws -> URL {
        guard geteuid() != 0 else { throw XCTSkip("Permission-denial fixtures require a non-root user.") }
        let directory = fixture.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        lockedDirectories.append(directory)
        guard chmod(directory.path, 0) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return directory
    }
}

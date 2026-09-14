import XCTest
@testable import PunkteRetterCore

final class SnapshotEngineTests: XCTestCase {
    private let fm = FileManager.default

    private enum SyntheticError: Error { case interrupted }

    private func workspace() throws -> (root: URL, source: URL, destination: URL) {
        let root = fm.temporaryDirectory.appendingPathComponent("PunkteRetterTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        return (root, source, destination)
    }

    private func write(_ value: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private func snapshot(
        source: URL,
        destination: URL,
        kind: BackupSourceKind,
        itemID: UUID = UUID(),
        recordID: UUID = UUID(),
        now: Date? = nil,
        hooks: SnapshotTestHooks = SnapshotTestHooks()
    ) throws -> VerifiedSnapshotResult {
        try VerifiedSnapshotEngine.createSnapshot(
            source: source,
            destination: destination,
            sourceKind: kind,
            itemID: itemID,
            recordID: recordID,
            sourceDisplayName: source.lastPathComponent,
            now: now ?? date("2026-09-12T10:00:00+02:00"),
            stabilityDelay: 0,
            hooks: hooks
        )
    }

    func testFolderWithMultipleFilesCreatesVerifiedAccessibleSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("alpha", to: work.source.appendingPathComponent("Punkte A.xlsx"))
        try write("beta", to: work.source.appendingPathComponent("Punkte B.xlsx"))

        let result = try snapshot(source: work.source, destination: work.destination, kind: .directory)

        XCTAssertEqual(result.fileCount, 2)
        XCTAssertEqual(result.byteCount, 9)
        XCTAssertNotNil(result.manifestSHA256)
        XCTAssertTrue(fm.fileExists(atPath: result.finalURL.appendingPathComponent("Punkte A.xlsx").path))
        XCTAssertTrue(fm.fileExists(atPath: result.finalURL.appendingPathComponent("Punkte B.xlsx").path))
        XCTAssertTrue(fm.fileExists(atPath: result.finalURL.appendingPathComponent(VerifiedSnapshotEngine.directoryManifestFileName).path))
        XCTAssertEqual(try String(contentsOf: work.source.appendingPathComponent("Punkte A.xlsx"), encoding: .utf8), "alpha")
        let manifestData = try Data(contentsOf: result.finalURL.appendingPathComponent(VerifiedSnapshotEngine.directoryManifestFileName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ManagedDirectorySnapshotManifest.self, from: manifestData)
        XCTAssertEqual(manifest.sourceKind, .directory)
        XCTAssertEqual(manifest.schemaVersion, ManagedDirectorySnapshotManifest.currentSchemaVersion)
    }

    func testSubfoldersAndEmptyDirectoriesArePreserved() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let nested = work.source.appendingPathComponent("Klasse 6/Noten", isDirectory: true)
        let empty = work.source.appendingPathComponent("Klasse 6/Leer", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        try write("werte", to: nested.appendingPathComponent("September.xlsx"))

        let result = try snapshot(source: work.source, destination: work.destination, kind: .directory)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: result.finalURL.appendingPathComponent("Klasse 6/Noten/September.xlsx").path))
        XCTAssertTrue(fm.fileExists(atPath: result.finalURL.appendingPathComponent("Klasse 6/Leer").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testNewFileIsIncludedInNextSnapshotOnly() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("eins", to: work.source.appendingPathComponent("A.xlsx"))

        let first = try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            now: date("2026-09-03T10:00:00+02:00")
        )
        try write("zwei", to: work.source.appendingPathComponent("B.xlsx"))
        let second = try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            now: date("2026-09-10T10:00:00+02:00")
        )

        XCTAssertFalse(fm.fileExists(atPath: first.finalURL.appendingPathComponent("B.xlsx").path))
        XCTAssertTrue(fm.fileExists(atPath: second.finalURL.appendingPathComponent("B.xlsx").path))
        XCTAssertEqual(second.fileCount, 2)
    }

    func testFileChangedDuringBackupRejectsEntireFolderSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let sourceFile = work.source.appendingPathComponent("A.xlsx")
        try write("vorher", to: sourceFile)

        XCTAssertThrowsError(try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            hooks: SnapshotTestHooks(afterCopy: { _ in try self.write("nachher und länger", to: sourceFile) })
        )) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .sourceChanging)
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testFileAddedDuringBackupRejectsEntireFolderSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("vorhanden", to: work.source.appendingPathComponent("A.xlsx"))

        XCTAssertThrowsError(try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            hooks: SnapshotTestHooks(afterCopy: { _ in
                try self.write("neu", to: work.source.appendingPathComponent("B.xlsx"))
            })
        )) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .sourceChanging)
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testFileRemovedDuringBackupRejectsEntireFolderSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let file = work.source.appendingPathComponent("A.xlsx")
        try write("vorhanden", to: file)

        XCTAssertThrowsError(try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            hooks: SnapshotTestHooks(afterCopy: { _ in try self.fm.removeItem(at: file) })
        )) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .sourceChanging)
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testFileChangedAfterFinalCopyVerificationStillRejectsSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let sourceFile = work.source.appendingPathComponent("A.xlsx")
        try write("stabil", to: sourceFile)

        XCTAssertThrowsError(try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            hooks: SnapshotTestHooks(afterFinalCopyVerification: {
                try self.write("noch während des Backups verändert", to: sourceFile)
            })
        )) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .sourceChanging)
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testSingleFileChangedDuringBackupIsRejected() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let sourceFile = work.source.appendingPathComponent("Einzel.xlsx")
        try write("vorher", to: sourceFile)

        XCTAssertThrowsError(try snapshot(
            source: sourceFile,
            destination: work.destination,
            kind: .file,
            hooks: SnapshotTestHooks(afterCopy: { _ in
                try self.write("nachher", to: sourceFile)
            })
        )) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .sourceChanging)
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testSingleFileRemovedDuringBackupIsRejected() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let sourceFile = work.source.appendingPathComponent("Einzel.xlsx")
        try write("daten", to: sourceFile)

        XCTAssertThrowsError(try snapshot(
            source: sourceFile,
            destination: work.destination,
            kind: .file,
            hooks: SnapshotTestHooks(afterCopy: { _ in
                try self.fm.removeItem(at: sourceFile)
            })
        ))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testSingleFileHashMismatchRejectsSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let sourceFile = work.source.appendingPathComponent("Einzel.xlsx")
        try write("original", to: sourceFile)

        XCTAssertThrowsError(try snapshot(
            source: sourceFile,
            destination: work.destination,
            kind: .file,
            hooks: SnapshotTestHooks(afterCopy: { payload in
                try self.write("beschädigt", to: payload)
            })
        )) { error in
            guard case SnapshotEngineError.hashMismatch = error else {
                return XCTFail("Erwartet wurde eine Hash-Abweichung, erhalten: \(error)")
            }
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testEmptyFolderIsAValidSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }

        let result = try snapshot(source: work.source, destination: work.destination, kind: .directory)

        XCTAssertEqual(result.fileCount, 0)
        XCTAssertEqual(result.byteCount, 0)
        XCTAssertTrue(fm.fileExists(atPath: result.finalURL.path))
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: result.finalURL.path)), [VerifiedSnapshotEngine.directoryManifestFileName])
    }

    func testTemporaryOfficeAndMacMetadataFilesAreIgnored() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("echt", to: work.source.appendingPathComponent("Noten.xlsx"))
        for name in ["~$Noten.xlsx", ".DS_Store", "._Noten.xlsx", ".localized"] {
            try write("ignorieren", to: work.source.appendingPathComponent(name))
        }

        let result = try snapshot(source: work.source, destination: work.destination, kind: .directory)
        let names = Set(try fm.contentsOfDirectory(atPath: result.finalURL.path))

        XCTAssertEqual(result.fileCount, 1)
        XCTAssertEqual(names, ["Noten.xlsx", VerifiedSnapshotEngine.directoryManifestFileName])
    }

    func testReservedManifestNameRejectsSourceFolder() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("fremd", to: work.source.appendingPathComponent(VerifiedSnapshotEngine.directoryManifestFileName))

        XCTAssertThrowsError(try snapshot(source: work.source, destination: work.destination, kind: .directory)) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .reservedEntry(VerifiedSnapshotEngine.directoryManifestFileName))
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testIgnoredOfficeFileCanAppearDuringStabilityCheck() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("echt", to: work.source.appendingPathComponent("Noten.xlsx"))

        let result = try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            hooks: SnapshotTestHooks(afterInitialCapture: {
                try self.write("lock", to: work.source.appendingPathComponent("~$Noten.xlsx"))
            })
        )

        XCTAssertEqual(result.fileCount, 1)
        XCTAssertFalse(fm.fileExists(atPath: result.finalURL.appendingPathComponent("~$Noten.xlsx").path))
    }

    func testFolderNameCollisionDoesNotOverwriteExistingData() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("quelle", to: work.source.appendingPathComponent("A.xlsx"))
        let now = date("2026-09-12T10:00:00+02:00")
        let preferred = BackupNaming.make(originalName: work.source.lastPathComponent, sourceKind: .directory, date: now)
        let collision = work.destination.appendingPathComponent(preferred, isDirectory: true)
        try fm.createDirectory(at: collision, withIntermediateDirectories: true)
        try write("fremd", to: collision.appendingPathComponent("Nicht löschen.txt"))

        let result = try snapshot(source: work.source, destination: work.destination, kind: .directory, now: now)

        XCTAssertEqual(result.finalName, "\(preferred)-2")
        XCTAssertEqual(try String(contentsOf: collision.appendingPathComponent("Nicht löschen.txt"), encoding: .utf8), "fremd")
    }

    func testInterruptedSnapshotLeavesNoTemporaryOrValidSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("daten", to: work.source.appendingPathComponent("A.xlsx"))

        XCTAssertThrowsError(try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            hooks: SnapshotTestHooks(beforePromotion: { _ in throw SyntheticError.interrupted })
        ))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testAbandonedRegisteredPartialSnapshotIsCleaned() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("daten", to: work.source.appendingPathComponent("A.xlsx"))
        let itemID = UUID()
        let operationID = UUID()
        let name = VerifiedSnapshotEngine.partialDirectoryName(itemID: itemID, operationID: operationID)
        let abandoned = work.destination.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: abandoned, withIntermediateDirectories: true)
        let marker = try VerifiedSnapshotEngine.makePartialMarkerData(itemID: itemID, operationID: operationID, directoryName: name, createdAt: date("2026-09-12T01:00:00+02:00"))
        try marker.write(to: abandoned.appendingPathComponent(VerifiedSnapshotEngine.partialMarkerFileName))

        _ = try snapshot(source: work.source, destination: work.destination, kind: .directory)

        XCTAssertFalse(fm.fileExists(atPath: abandoned.path))
    }

    func testRecentOwnedPartialSnapshotIsNotRemovedAsPotentiallyActive() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("daten", to: work.source.appendingPathComponent("A.xlsx"))
        let itemID = UUID()
        let operationID = UUID()
        let name = VerifiedSnapshotEngine.partialDirectoryName(itemID: itemID, operationID: operationID)
        let partial = work.destination.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        let marker = try VerifiedSnapshotEngine.makePartialMarkerData(itemID: itemID, operationID: operationID, directoryName: name, createdAt: date("2026-09-12T09:59:00+02:00"))
        try marker.write(to: partial.appendingPathComponent(VerifiedSnapshotEngine.partialMarkerFileName))

        _ = try snapshot(source: work.source, destination: work.destination, kind: .directory)

        XCTAssertTrue(fm.fileExists(atPath: partial.path))
    }

    func testUnclearPartialDirectoryIsNeverDeleted() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("daten", to: work.source.appendingPathComponent("A.xlsx"))
        let unclear = work.destination.appendingPathComponent(".punkteretter-partial-not-owned", isDirectory: true)
        try fm.createDirectory(at: unclear, withIntermediateDirectories: true)
        try write("fremd", to: unclear.appendingPathComponent("data.txt"))

        _ = try snapshot(source: work.source, destination: work.destination, kind: .directory)

        XCTAssertTrue(fm.fileExists(atPath: unclear.appendingPathComponent("data.txt").path))
    }

    func testCopiedHashMismatchRejectsEntireSnapshot() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("original", to: work.source.appendingPathComponent("A.xlsx"))

        XCTAssertThrowsError(try snapshot(
            source: work.source,
            destination: work.destination,
            kind: .directory,
            hooks: SnapshotTestHooks(afterCopy: { payload in
                try self.write("beschädigt", to: payload.appendingPathComponent("A.xlsx"))
            })
        )) { error in
            guard case SnapshotEngineError.hashMismatch = error else {
                return XCTFail("Erwartet wurde eine Hash-Abweichung, erhalten: \(error)")
            }
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testFolderOwnershipRequiresUntamperedManifestAndContents() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("original", to: work.source.appendingPathComponent("A.xlsx"))
        let itemID = UUID()
        let recordID = UUID()
        let now = date("2026-09-12T10:00:00+02:00")
        let result = try snapshot(source: work.source, destination: work.destination, kind: .directory, itemID: itemID, recordID: recordID, now: now)
        let record = BackupRecord(
            id: recordID,
            itemID: itemID,
            sourceDisplayName: work.source.lastPathComponent,
            week: Schedule.isoWeek(for: now),
            createdAt: now,
            fileName: result.finalName,
            sourceKind: .directory,
            sourceSHA256: result.contentSHA256,
            byteCount: result.byteCount,
            fileCount: result.fileCount,
            manifestSHA256: result.manifestSHA256,
            cloudSyncState: .confirmed
        )

        XCTAssertTrue(ManagedBackupOwnership.isSafeToDelete(record: record, at: result.finalURL))
        try write("nicht registriert", to: result.finalURL.appendingPathComponent("Fremd.txt"))
        XCTAssertFalse(ManagedBackupOwnership.isSafeToDelete(record: record, at: result.finalURL))
    }

    func testMissingOrCorruptManifestPreventsOwnershipAndDeletion() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        try write("original", to: work.source.appendingPathComponent("A.xlsx"))
        let itemID = UUID()
        let recordID = UUID()
        let now = date("2026-09-12T10:00:00+02:00")
        let result = try snapshot(source: work.source, destination: work.destination, kind: .directory, itemID: itemID, recordID: recordID, now: now)
        let record = BackupRecord(id: recordID, itemID: itemID, sourceDisplayName: work.source.lastPathComponent, week: Schedule.isoWeek(for: now), createdAt: now, fileName: result.finalName, sourceKind: .directory, sourceSHA256: result.contentSHA256, byteCount: result.byteCount, fileCount: result.fileCount, manifestSHA256: result.manifestSHA256, cloudSyncState: .confirmed)
        let manifest = result.finalURL.appendingPathComponent(VerifiedSnapshotEngine.directoryManifestFileName)

        try fm.removeItem(at: manifest)
        XCTAssertFalse(ManagedBackupOwnership.isSafeToDelete(record: record, at: result.finalURL))
        try write("kein json", to: manifest)
        XCTAssertFalse(ManagedBackupOwnership.isSafeToDelete(record: record, at: result.finalURL))
        XCTAssertTrue(fm.fileExists(atPath: result.finalURL.appendingPathComponent("A.xlsx").path))
    }

    func testSymbolicLinkRejectsEntireFolderSnapshotWithoutFollowingIt() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let outside = work.root.appendingPathComponent("outside.txt")
        try write("fremd", to: outside)
        try fm.createSymbolicLink(at: work.source.appendingPathComponent("link.txt"), withDestinationURL: outside)

        XCTAssertThrowsError(try snapshot(source: work.source, destination: work.destination, kind: .directory)) { error in
            guard case SnapshotEngineError.unsupportedEntry(let path) = error, path == "link.txt" else {
                return XCTFail("Erwartet wurde ein sicher abgelehnter symbolischer Link, erhalten: \(error)")
            }
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "fremd")
    }

    func testFileOwnershipRequiresRegisteredSizeAndHash() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let sourceFile = work.source.appendingPathComponent("A.xlsx")
        try write("original", to: sourceFile)
        let itemID = UUID()
        let recordID = UUID()
        let now = date("2026-09-12T10:00:00+02:00")
        let result = try snapshot(source: sourceFile, destination: work.destination, kind: .file, itemID: itemID, recordID: recordID, now: now)
        let record = BackupRecord(
            id: recordID,
            itemID: itemID,
            sourceDisplayName: sourceFile.lastPathComponent,
            week: Schedule.isoWeek(for: now),
            createdAt: now,
            fileName: result.finalName,
            sourceKind: .file,
            sourceSHA256: result.contentSHA256,
            byteCount: result.byteCount,
            fileCount: 1,
            cloudSyncState: .confirmed
        )

        XCTAssertTrue(ManagedBackupOwnership.isSafeToDelete(record: record, at: result.finalURL))
        try write("verändert", to: result.finalURL)
        XCTAssertFalse(ManagedBackupOwnership.isSafeToDelete(record: record, at: result.finalURL))
    }

    func testRetentionKeepsExactly26FolderSnapshotsPerItem() {
        let itemID = UUID()
        let base = date("2026-01-01T00:00:00Z")
        let records = (0..<27).map { index in
            BackupRecord(
                itemID: itemID,
                sourceDisplayName: "Schulunterlagen",
                week: WeekID(yearForWeekOfYear: 2026, weekOfYear: index + 1),
                createdAt: base.addingTimeInterval(Double(index) * 86400),
                fileName: "Schulunterlagen-\(index)",
                sourceKind: .directory,
                sourceSHA256: "hash-\(index)",
                byteCount: Int64(index),
                fileCount: 6,
                manifestSHA256: "manifest-\(index)",
                cloudSyncState: .confirmed
            )
        }

        let deleted = Retention.recordsToDelete(records, keep: 26)

        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(deleted.first?.fileName, "Schulunterlagen-0")
    }

    func testMovedSourceFailsWithoutCreatingAnything() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let original = work.source.appendingPathComponent("Mappe", isDirectory: true)
        let moved = work.source.appendingPathComponent("Mappe verschoben", isDirectory: true)
        try fm.createDirectory(at: original, withIntermediateDirectories: true)
        try write("daten", to: original.appendingPathComponent("A.xlsx"))
        try fm.moveItem(at: original, to: moved)

        XCTAssertThrowsError(try snapshot(source: original, destination: work.destination, kind: .directory)) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .sourceMissing)
        }
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: work.destination.path).isEmpty)
    }

    func testMovedDestinationFailsWithoutChangingSource() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let sourceFile = work.source.appendingPathComponent("A.xlsx")
        try write("daten", to: sourceFile)
        let oldDestination = work.destination
        try fm.moveItem(at: oldDestination, to: work.root.appendingPathComponent("Destination verschoben"))

        XCTAssertThrowsError(try snapshot(source: sourceFile, destination: oldDestination, kind: .file)) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .destinationMissing)
        }
        XCTAssertEqual(try String(contentsOf: sourceFile, encoding: .utf8), "daten")
    }

    func testDestinationInsideSourceIsRejected() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let nestedDestination = work.source.appendingPathComponent("Backups", isDirectory: true)
        try fm.createDirectory(at: nestedDestination, withIntermediateDirectories: true)

        XCTAssertThrowsError(try snapshot(source: work.source, destination: nestedDestination, kind: .directory)) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .destinationInsideSource)
        }
    }

    func testDestinationOfAnotherJobCannotSitInsideFolderSource() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let otherSource = work.root.appendingPathComponent("Other/A.xlsx")
        let nestedDestination = work.source.appendingPathComponent("Fremdes Backup-Ziel", isDirectory: true)
        try write("daten", to: otherSource)
        try fm.createDirectory(at: nestedDestination, withIntermediateDirectories: true)

        let locations = [
            BackupPlanLocation(itemID: UUID(), source: work.source, sourceKind: .directory, destination: work.destination),
            BackupPlanLocation(itemID: UUID(), source: otherSource, sourceKind: .file, destination: nestedDestination)
        ]

        XCTAssertThrowsError(try BackupPlanSafety.validateNoDestinationInsideDirectorySource(locations)) { error in
            XCTAssertEqual(error as? SnapshotEngineError, .destinationInsideSource)
        }
    }

    func testFileAndFolderJobsCanBeUsedTogether() throws {
        let work = try workspace()
        defer { try? fm.removeItem(at: work.root) }
        let fileRoot = work.root.appendingPathComponent("Single", isDirectory: true)
        let folderRoot = work.root.appendingPathComponent("Folder", isDirectory: true)
        try fm.createDirectory(at: fileRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: folderRoot, withIntermediateDirectories: true)
        let file = fileRoot.appendingPathComponent("Einzel.xlsx")
        try write("einzeln", to: file)
        try write("ordner", to: folderRoot.appendingPathComponent("A.xlsx"))
        let fileItemID = UUID()
        let folderItemID = UUID()
        let now = date("2026-09-12T10:00:00+02:00")

        let fileResult = try snapshot(source: file, destination: work.destination, kind: .file, itemID: fileItemID, now: now)
        let folderResult = try snapshot(source: folderRoot, destination: work.destination, kind: .directory, itemID: folderItemID, now: now)

        var state = RuntimeState()
        let week = Schedule.isoWeek(for: now)
        state.records = [
            BackupRecord(itemID: fileItemID, sourceDisplayName: file.lastPathComponent, week: week, createdAt: now, fileName: fileResult.finalName, sourceKind: .file, sourceSHA256: fileResult.contentSHA256, byteCount: fileResult.byteCount, fileCount: fileResult.fileCount, cloudSyncState: .confirmed),
            BackupRecord(itemID: folderItemID, sourceDisplayName: folderRoot.lastPathComponent, week: week, createdAt: now, fileName: folderResult.finalName, sourceKind: .directory, sourceSHA256: folderResult.contentSHA256, byteCount: folderResult.byteCount, fileCount: folderResult.fileCount, manifestSHA256: folderResult.manifestSHA256, cloudSyncState: .confirmed)
        ]

        XCTAssertEqual(state.securedCount(itemIDs: [fileItemID, folderItemID], week: week), 2)
        XCTAssertTrue(fm.fileExists(atPath: fileResult.finalURL.path))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: folderResult.finalURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testLegacyBackupItemAndRecordDecodeAsFiles() throws {
        let itemJSON = #"{"id":"00000000-0000-0000-0000-000000000010","sourceBookmark":"AQ==","sourceDisplayName":"Alt.xlsx","destinationBookmark":"Ag==","destinationDisplayName":"Backup","targetConfirmedPrivate":true,"enabled":true}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(BackupItem.self, from: itemJSON)
        XCTAssertEqual(item.sourceKind, .file)

        let recordJSON = #"{"id":"00000000-0000-0000-0000-000000000020","itemID":null,"sourceDisplayName":"Alt.xlsx","destinationBookmark":null,"week":{"yearForWeekOfYear":2026,"weekOfYear":37},"createdAt":0,"fileName":"Alt_2026-09-12_KW37.xlsx","sourceSHA256":"abc","byteCount":3,"cloudSyncState":"confirmed","successMailState":"none"}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let record = try decoder.decode(BackupRecord.self, from: recordJSON)
        XCTAssertEqual(record.sourceKind, .file)
        XCTAssertEqual(record.fileCount, 1)
        XCTAssertNil(record.manifestSHA256)
    }

    func testMailHelperTimeoutEndsPredictably() async throws {
        let started = Date()
        do {
            _ = try await ProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.1)
            XCTFail("Ein hängender Mail-Helper muss in den Timeout laufen")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .timedOut(seconds: 1))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testFailingMailHelperReturnsItsExitCodeWithoutHanging() async throws {
        let status = try await ProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], timeout: 1)
        XCTAssertNotEqual(status, 0)
    }

    func testFastMailHelperSuccessIsNotReportedAsTimeout() async throws {
        let status = try await ProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], timeout: 1)
        XCTAssertEqual(status, 0)
    }

    func testMailHelperSuccessShortlyBeforeTimeoutIsPreserved() async throws {
        let status = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 0.15; exit 0"],
            timeout: 1
        )
        XCTAssertEqual(status, 0)
    }

    func testAbnormallyTerminatedMailHelperIsDistinguished() async throws {
        do {
            _ = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "kill -TERM $$"],
                timeout: 2
            )
            XCTFail("Ein Signalabbruch darf nicht als normaler Exit behandelt werden")
        } catch let error as ProcessRunnerError {
            guard case .terminatedBySignal = error else {
                return XCTFail("Unerwarteter Fehler: \(error)")
            }
        }
    }
}

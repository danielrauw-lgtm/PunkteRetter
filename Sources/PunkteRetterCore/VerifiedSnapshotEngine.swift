import Foundation
import CryptoKit

public enum SnapshotEngineError: LocalizedError, Equatable, Sendable {
    case sourceMissing
    case destinationMissing
    case wrongSourceType
    case sourceUnreadable(String)
    case unsupportedEntry(String)
    case reservedEntry(String)
    case sourceChanging
    case emptyFile
    case destinationInsideSource
    case hashMismatch(String)
    case cloudNotReady(String)
    case fileSystem(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "Die Quelle wurde nicht gefunden. Sie wurde möglicherweise verschoben oder umbenannt."
        case .destinationMissing:
            return "Der Backup-Ordner wurde nicht gefunden. Er wurde möglicherweise verschoben oder umbenannt."
        case .wrongSourceType:
            return "Die ausgewählte Quelle ist weder eine normale Datei noch ein normaler Ordner."
        case .sourceUnreadable(let path):
            return "Die Quelle enthält eine nicht lesbare Datei: „\(path)“."
        case .unsupportedEntry(let path):
            return "Die Quelle enthält einen nicht unterstützten Verweis oder Spezialeintrag: „\(path)“."
        case .reservedEntry(let path):
            return "Die Quelle enthält den für PunkteRetter reservierten Namen „\(path)“. Bitte benenne diesen Eintrag um."
        case .sourceChanging:
            return "Die Quelle wurde während der Sicherung verändert. Der gesamte Wochenstand wurde verworfen und wird später erneut versucht."
        case .emptyFile:
            return "Die ausgewählte Datei ist leer."
        case .destinationInsideSource:
            return "Das Backup-Ziel liegt innerhalb der Quellablage."
        case .hashMismatch(let path):
            return "Die SHA-256-Prüfung der Kopie ist fehlgeschlagen: „\(path)“. Der gesamte Wochenstand wurde verworfen."
        case .cloudNotReady(let path):
            return "Die iCloud-Datei „\(path)“ ist lokal noch nicht vollständig verfügbar."
        case .fileSystem(let message):
            return message
        }
    }
}

public struct SnapshotManifestFile: Codable, Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String

    public init(relativePath: String, byteCount: Int64, sha256: String) {
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct ManagedDirectorySnapshotManifest: Codable, Equatable, Sendable {
    public static let markerIdentifier = "de.punkteretter.directory-snapshot"
    public static let currentSchemaVersion = 2

    public let productIdentifier: String
    public let schemaVersion: Int
    public let recordID: UUID
    public let itemID: UUID
    public let week: WeekID
    public let createdAt: Date
    public let snapshotName: String
    public let sourceDisplayName: String
    public let sourceKind: BackupSourceKind
    public let contentSHA256: String
    public let byteCount: Int64
    public let directories: [String]
    public let files: [SnapshotManifestFile]

    public init(recordID: UUID, itemID: UUID, week: WeekID, createdAt: Date, snapshotName: String, sourceDisplayName: String, contentSHA256: String, byteCount: Int64, directories: [String], files: [SnapshotManifestFile]) {
        self.productIdentifier = Self.markerIdentifier
        self.schemaVersion = Self.currentSchemaVersion
        self.recordID = recordID
        self.itemID = itemID
        self.week = week
        self.createdAt = createdAt
        self.snapshotName = snapshotName
        self.sourceDisplayName = sourceDisplayName
        self.sourceKind = .directory
        self.contentSHA256 = contentSHA256
        self.byteCount = byteCount
        self.directories = directories
        self.files = files
    }
}

public struct VerifiedSnapshotResult: Equatable, Sendable {
    public let finalName: String
    public let finalURL: URL
    public let contentSHA256: String
    public let byteCount: Int64
    public let fileCount: Int
    public let manifestSHA256: String?
}

public struct BackupPlanLocation: Equatable, Sendable {
    public let itemID: UUID
    public let source: URL
    public let sourceKind: BackupSourceKind
    public let destination: URL

    public init(itemID: UUID, source: URL, sourceKind: BackupSourceKind, destination: URL) {
        self.itemID = itemID
        self.source = source
        self.sourceKind = sourceKind
        self.destination = destination
    }
}

public enum BackupPlanSafety {
    /// Verhindert auch kreuzweise Verschachtelungen: Das Ziel eines zweiten Auftrags
    /// darf nicht unbemerkt Bestandteil einer als Quelle gewählten Ordnerstruktur sein.
    public static func validateNoDestinationInsideDirectorySource(_ locations: [BackupPlanLocation]) throws {
        for sourceLocation in locations where sourceLocation.sourceKind == .directory {
            for targetLocation in locations where VerifiedSnapshotEngine.isSameOrDescendant(targetLocation.destination, of: sourceLocation.source) {
                throw SnapshotEngineError.destinationInsideSource
            }
        }
    }
}

struct SnapshotTestHooks {
    var afterInitialCapture: (() throws -> Void)? = nil
    var afterCopy: ((URL) throws -> Void)? = nil
    var beforePromotion: ((URL) throws -> Void)? = nil
    var afterFinalCopyVerification: (() throws -> Void)? = nil

}

public enum VerifiedSnapshotEngine {
    public static let directoryManifestFileName = ".punkteretter-snapshot.json"
    static let partialMarkerFileName = ".punkteretter-partial.json"
    static let partialDirectoryPrefix = ".punkteretter-partial-"

    private struct CapturedFile: Equatable {
        let relativePath: String
        let byteCount: Int64
        let modifiedAt: Date
        let sha256: String

        var manifestEntry: SnapshotManifestFile {
            SnapshotManifestFile(relativePath: relativePath, byteCount: byteCount, sha256: sha256)
        }
    }

    private struct Capture: Equatable {
        let directories: [String]
        let files: [CapturedFile]

        var byteCount: Int64 { files.reduce(0) { $0 + $1.byteCount } }
        var manifestFiles: [SnapshotManifestFile] { files.map(\.manifestEntry) }

        func sameContent(as other: Capture) -> Bool {
            directories == other.directories && manifestFiles == other.manifestFiles
        }
    }

    private struct ContentDescription: Codable {
        let directories: [String]
        let files: [SnapshotManifestFile]
    }

    private struct PartialMarker: Codable {
        static let markerIdentifier = "de.punkteretter.partial-snapshot"
        let productIdentifier: String
        let schemaVersion: Int
        let itemID: UUID
        let operationID: UUID
        let directoryName: String
        let createdAt: Date
    }

    public static func createSnapshot(
        source: URL,
        destination: URL,
        sourceKind: BackupSourceKind,
        itemID: UUID,
        recordID: UUID,
        sourceDisplayName: String,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) throws -> VerifiedSnapshotResult {
        try createSnapshot(
            source: source,
            destination: destination,
            sourceKind: sourceKind,
            itemID: itemID,
            recordID: recordID,
            sourceDisplayName: sourceDisplayName,
            now: now,
            calendar: calendar,
            stabilityDelay: 1.5,
            hooks: SnapshotTestHooks()
        )
    }

    static func createSnapshot(
        source: URL,
        destination: URL,
        sourceKind: BackupSourceKind,
        itemID: UUID,
        recordID: UUID,
        sourceDisplayName: String,
        now: Date,
        calendar: Calendar = Calendar(identifier: .iso8601),
        stabilityDelay: TimeInterval,
        hooks: SnapshotTestHooks
    ) throws -> VerifiedSnapshotResult {
        let fm = FileManager.default
        try validateLocations(source: source, destination: destination, sourceKind: sourceKind, fileManager: fm)
        try cleanupAbandonedStaging(in: destination, olderThan: now.addingTimeInterval(-6 * 60 * 60), fileManager: fm)

        let initial = try capture(source: source, sourceKind: sourceKind, excludingDirectoryManifest: false, fileManager: fm)
        if sourceKind == .file, initial.files.first?.byteCount == 0 { throw SnapshotEngineError.emptyFile }

        try hooks.afterInitialCapture?()
        if stabilityDelay > 0 { Thread.sleep(forTimeInterval: stabilityDelay) }
        let stable = try capture(source: source, sourceKind: sourceKind, excludingDirectoryManifest: false, fileManager: fm)
        guard initial == stable else { throw SnapshotEngineError.sourceChanging }

        let operationID = UUID()
        let stagingName = partialDirectoryName(itemID: itemID, operationID: operationID)
        let staging = destination.appendingPathComponent(stagingName, isDirectory: true)
        let payload = staging.appendingPathComponent("payload", isDirectory: sourceKind == .directory)

        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try makePartialMarkerData(itemID: itemID, operationID: operationID, directoryName: stagingName, createdAt: now)
            .write(to: staging.appendingPathComponent(partialMarkerFileName), options: .atomic)

        try copy(capture: initial, source: source, payload: payload, sourceKind: sourceKind, fileManager: fm)
        try hooks.afterCopy?(payload)

        let copied = try capture(source: payload, sourceKind: sourceKind, excludingDirectoryManifest: false, fileManager: fm, requireCloudCurrent: false)
        guard copiedContentMatches(expected: initial, actual: copied, sourceKind: sourceKind) else {
            throw SnapshotEngineError.hashMismatch(firstContentDifference(expected: initial, actual: copied))
        }

        let existingNames = Set((try? fm.contentsOfDirectory(atPath: destination.path)) ?? [])
        let preferredName = BackupNaming.make(originalName: sourceDisplayName, sourceKind: sourceKind, date: now, calendar: calendar)
        let finalName = BackupNaming.collisionSafeName(preferred: preferredName, sourceKind: sourceKind, existingNames: existingNames)
        let finalURL = destination.appendingPathComponent(finalName, isDirectory: sourceKind == .directory)
        let contentSHA256 = sourceKind == .file
            ? (initial.files.first?.sha256 ?? sha256(Data()))
            : try contentSHA256(for: initial)
        var manifestSHA256: String?

        if sourceKind == .directory {
            let manifest = ManagedDirectorySnapshotManifest(
                recordID: recordID,
                itemID: itemID,
                week: Schedule.isoWeek(for: now, calendar: calendar),
                createdAt: now,
                snapshotName: finalName,
                sourceDisplayName: sourceDisplayName,
                contentSHA256: contentSHA256,
                byteCount: initial.byteCount,
                directories: initial.directories,
                files: initial.manifestFiles
            )
            let data = try encoded(manifest)
            try data.write(to: payload.appendingPathComponent(directoryManifestFileName), options: .atomic)
            manifestSHA256 = sha256(data)
        }

        try hooks.beforePromotion?(payload)

        let finalCopiedCapture = try capture(source: payload, sourceKind: sourceKind, excludingDirectoryManifest: sourceKind == .directory, fileManager: fm, requireCloudCurrent: false)
        guard copiedContentMatches(expected: initial, actual: finalCopiedCapture, sourceKind: sourceKind) else {
            throw SnapshotEngineError.hashMismatch(firstContentDifference(expected: initial, actual: finalCopiedCapture))
        }
        if let manifestSHA256 {
            let manifestURL = payload.appendingPathComponent(directoryManifestFileName)
            guard (try? sha256(of: manifestURL)) == manifestSHA256 else {
                throw SnapshotEngineError.hashMismatch(directoryManifestFileName)
            }
        }
        try hooks.afterFinalCopyVerification?()

        // Diese Erfassung bewusst als letzte potenziell längere Prüfung ausführen.
        // So werden Änderungen erkannt, die noch während der erneuten Hash-Prüfung
        // des temporären Snapshots erfolgt sind.
        let finalSourceCapture = try capture(source: source, sourceKind: sourceKind, excludingDirectoryManifest: false, fileManager: fm)
        guard initial == finalSourceCapture else { throw SnapshotEngineError.sourceChanging }

        do {
            try fm.moveItem(at: payload, to: finalURL)
        } catch {
            throw SnapshotEngineError.fileSystem("Der geprüfte Wochenstand konnte nicht atomar fertiggestellt werden: \(error.localizedDescription)")
        }

        return VerifiedSnapshotResult(
            finalName: finalName,
            finalURL: finalURL,
            contentSHA256: contentSHA256,
            byteCount: initial.byteCount,
            fileCount: initial.files.count,
            manifestSHA256: manifestSHA256
        )
    }

    public static func validateLocations(source: URL, destination: URL, sourceKind: BackupSourceKind) throws {
        try validateLocations(source: source, destination: destination, sourceKind: sourceKind, fileManager: .default)
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func makePartialMarkerData(itemID: UUID, operationID: UUID, directoryName: String, createdAt: Date) throws -> Data {
        try encoded(PartialMarker(
            productIdentifier: PartialMarker.markerIdentifier,
            schemaVersion: 1,
            itemID: itemID,
            operationID: operationID,
            directoryName: directoryName,
            createdAt: createdAt
        ))
    }

    static func partialDirectoryName(itemID: UUID, operationID: UUID) -> String {
        "\(partialDirectoryPrefix)\(itemID.uuidString.lowercased())-\(operationID.uuidString.lowercased())"
    }

    private static func validateLocations(source: URL, destination: URL, sourceKind: BackupSourceKind, fileManager: FileManager) throws {
        let sourceValues: URLResourceValues
        do {
            sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw SnapshotEngineError.sourceMissing
        }
        guard sourceValues.isSymbolicLink != true else { throw SnapshotEngineError.wrongSourceType }
        switch sourceKind {
        case .file:
            guard sourceValues.isRegularFile == true else { throw SnapshotEngineError.wrongSourceType }
        case .directory:
            guard sourceValues.isDirectory == true else { throw SnapshotEngineError.wrongSourceType }
        }

        let destinationValues: URLResourceValues
        do {
            destinationValues = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw SnapshotEngineError.destinationMissing
        }
        guard destinationValues.isDirectory == true, destinationValues.isSymbolicLink != true else {
            throw SnapshotEngineError.destinationMissing
        }

        let protectedRoot = sourceKind == .directory ? source : source.deletingLastPathComponent()
        if isSameOrDescendant(destination, of: protectedRoot) {
            throw SnapshotEngineError.destinationInsideSource
        }

        guard fileManager.isReadableFile(atPath: source.path) else {
            throw SnapshotEngineError.sourceUnreadable(source.lastPathComponent)
        }
    }

    fileprivate static func isSameOrDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidateComponents = candidate.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func cleanupAbandonedStaging(in destination: URL, olderThan cutoff: Date, fileManager: FileManager) throws {
        let entries = try fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        for entry in entries where entry.lastPathComponent.hasPrefix(partialDirectoryPrefix) {
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: entry.appendingPathComponent(partialMarkerFileName)),
                  let marker = try? decoded(PartialMarker.self, from: data),
                  marker.productIdentifier == PartialMarker.markerIdentifier,
                  marker.schemaVersion == 1,
                  marker.createdAt <= cutoff,
                  marker.directoryName == entry.lastPathComponent,
                  marker.directoryName == partialDirectoryName(itemID: marker.itemID, operationID: marker.operationID) else {
                continue
            }
            try fileManager.removeItem(at: entry)
        }
    }

    private static func capture(source: URL, sourceKind: BackupSourceKind, excludingDirectoryManifest: Bool, fileManager: FileManager, requireCloudCurrent: Bool = true, ignoringExcludedSourceFiles: Bool = true) throws -> Capture {
        switch sourceKind {
        case .file:
            let file = try captureFile(source, relativePath: source.lastPathComponent, requireCloudCurrent: requireCloudCurrent, fileManager: fileManager)
            return Capture(directories: [], files: [file])
        case .directory:
            return try captureDirectory(source, excludingDirectoryManifest: excludingDirectoryManifest, requireCloudCurrent: requireCloudCurrent, ignoringExcludedSourceFiles: ignoringExcludedSourceFiles, fileManager: fileManager)
        }
    }

    private static func captureDirectory(_ root: URL, excludingDirectoryManifest: Bool, requireCloudCurrent: Bool, ignoringExcludedSourceFiles: Bool, fileManager: FileManager) throws -> Capture {
        var directories: [String] = []
        var files: [CapturedFile] = []
        var enumerationError: Error?
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, error in enumerationError = error; return false }
        ) else {
            throw SnapshotEngineError.sourceUnreadable(root.lastPathComponent)
        }

        while let entry = enumerator.nextObject() as? URL {
            let relativePath = try relativePath(of: entry, below: root)
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(forKeys: Set(keys))
            } catch {
                throw SnapshotEngineError.sourceUnreadable(relativePath)
            }

            if ignoringExcludedSourceFiles, values.isDirectory != true, shouldIgnore(name: entry.lastPathComponent) {
                continue
            }
            if excludingDirectoryManifest, relativePath == directoryManifestFileName { continue }
            if !excludingDirectoryManifest, relativePath == directoryManifestFileName {
                throw SnapshotEngineError.reservedEntry(relativePath)
            }
            if values.isSymbolicLink == true {
                throw SnapshotEngineError.unsupportedEntry(relativePath)
            }
            if values.isDirectory == true {
                directories.append(relativePath)
            } else if values.isRegularFile == true {
                files.append(try captureFile(entry, relativePath: relativePath, requireCloudCurrent: requireCloudCurrent, fileManager: fileManager))
            } else {
                throw SnapshotEngineError.unsupportedEntry(relativePath)
            }
        }

        if let enumerationError {
            throw SnapshotEngineError.fileSystem("Der Ordner konnte nicht vollständig erfasst werden: \(enumerationError.localizedDescription)")
        }
        return Capture(
            directories: directories.sorted(),
            files: files.sorted { $0.relativePath < $1.relativePath }
        )
    }

    private static func captureFile(_ url: URL, relativePath: String, requireCloudCurrent: Bool, fileManager: FileManager) throws -> CapturedFile {
        if shouldIgnore(name: url.lastPathComponent) { throw SnapshotEngineError.unsupportedEntry(relativePath) }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        } catch {
            throw SnapshotEngineError.sourceMissing
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SnapshotEngineError.unsupportedEntry(relativePath)
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw SnapshotEngineError.sourceUnreadable(relativePath)
        }
        if requireCloudCurrent { try ensureCurrentLocalSource(url, relativePath: relativePath) }
        do {
            return CapturedFile(
                relativePath: relativePath,
                byteCount: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                sha256: try sha256(of: url)
            )
        } catch let error as SnapshotEngineError {
            throw error
        } catch {
            throw SnapshotEngineError.sourceUnreadable(relativePath)
        }
    }

    private static func copy(capture: Capture, source: URL, payload: URL, sourceKind: BackupSourceKind, fileManager: FileManager) throws {
        do {
            switch sourceKind {
            case .file:
                try fileManager.copyItem(at: source, to: payload)
            case .directory:
                try fileManager.createDirectory(at: payload, withIntermediateDirectories: false)
                for relativeDirectory in capture.directories.sorted(by: directoryDepthOrder) {
                    try fileManager.createDirectory(at: appending(relativeDirectory, to: payload, isDirectory: true), withIntermediateDirectories: true)
                }
                for file in capture.files {
                    let sourceFile = appending(file.relativePath, to: source, isDirectory: false)
                    let targetFile = appending(file.relativePath, to: payload, isDirectory: false)
                    try fileManager.createDirectory(at: targetFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.copyItem(at: sourceFile, to: targetFile)
                }
            }
        } catch {
            throw SnapshotEngineError.fileSystem("Der temporäre Wochenstand konnte nicht vollständig erstellt werden: \(error.localizedDescription)")
        }
    }

    private static func contentSHA256(for capture: Capture) throws -> String {
        sha256(try encoded(ContentDescription(directories: capture.directories, files: capture.manifestFiles)))
    }

    private static func firstContentDifference(expected: Capture, actual: Capture) -> String {
        if expected.directories != actual.directories { return "Ordnerstruktur" }
        let expectedByPath = Dictionary(uniqueKeysWithValues: expected.manifestFiles.map { ($0.relativePath, $0) })
        let actualByPath = Dictionary(uniqueKeysWithValues: actual.manifestFiles.map { ($0.relativePath, $0) })
        return Set(expectedByPath.keys).union(actualByPath.keys).sorted().first(where: { expectedByPath[$0] != actualByPath[$0] }) ?? "Gesamtinhalt"
    }

    private static func copiedContentMatches(expected: Capture, actual: Capture, sourceKind: BackupSourceKind) -> Bool {
        if sourceKind == .directory { return expected.sameContent(as: actual) }
        guard expected.files.count == 1, actual.files.count == 1 else { return false }
        return expected.files[0].byteCount == actual.files[0].byteCount
            && expected.files[0].sha256 == actual.files[0].sha256
    }

    private static func shouldIgnore(name: String) -> Bool {
        name.hasPrefix("~$") || name == ".DS_Store" || name == ".localized" || name.hasPrefix("._")
    }

    private static func directoryDepthOrder(_ lhs: String, _ rhs: String) -> Bool {
        let leftDepth = lhs.split(separator: "/").count
        let rightDepth = rhs.split(separator: "/").count
        return leftDepth == rightDepth ? lhs < rhs : leftDepth < rightDepth
    }

    private static func relativePath(of child: URL, below root: URL) throws -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              Array(childComponents.prefix(rootComponents.count)) == rootComponents else {
            throw SnapshotEngineError.fileSystem("Ein Eintrag lag unerwartet außerhalb des Quellordners.")
        }
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func appending(_ relativePath: String, to root: URL, isDirectory: Bool) -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        return components.enumerated().reduce(root) { current, element in
            current.appendingPathComponent(String(element.element), isDirectory: isDirectory && element.offset == components.count - 1)
        }
    }

    private static func ensureCurrentLocalSource(_ url: URL, relativePath: String) throws {
#if os(macOS)
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey])
        if let error = values.ubiquitousItemDownloadingError {
            throw SnapshotEngineError.fileSystem("iCloud meldet beim Laden von „\(relativePath)“ einen Fehler: \(error.localizedDescription)")
        }
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
            throw SnapshotEngineError.cloudNotReady(relativePath)
        }
#endif
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func decoded<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func decodedManifest(at url: URL) throws -> (ManagedDirectorySnapshotManifest, String) {
        let data = try Data(contentsOf: url)
        return (try decoded(ManagedDirectorySnapshotManifest.self, from: data), sha256(data))
    }

    fileprivate static func inspectedDirectoryContent(at url: URL) throws -> (directories: [String], files: [SnapshotManifestFile], byteCount: Int64, sha256: String) {
        let capture = try capture(source: url, sourceKind: .directory, excludingDirectoryManifest: true, fileManager: .default, requireCloudCurrent: false, ignoringExcludedSourceFiles: false)
        return (capture.directories, capture.manifestFiles, capture.byteCount, try contentSHA256(for: capture))
    }
}

public enum ManagedBackupOwnership {
    public static func isSafeToDelete(record: BackupRecord, at url: URL) -> Bool {
        guard url.lastPathComponent == record.fileName else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true else { return false }

        switch record.sourceKind {
        case .file:
            guard values.isRegularFile == true,
                  record.fileCount == 1,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  Int64(size) == record.byteCount,
                  let hash = try? VerifiedSnapshotEngine.sha256(of: url),
                  hash == record.sourceSHA256 else { return false }
            return true

        case .directory:
            guard values.isDirectory == true,
                  let expectedManifestHash = record.manifestSHA256,
                  let sourceDisplayName = record.sourceDisplayName,
                  let (manifest, manifestHash) = try? VerifiedSnapshotEngine.decodedManifest(at: url.appendingPathComponent(VerifiedSnapshotEngine.directoryManifestFileName)),
                  manifestHash == expectedManifestHash,
                  manifest.productIdentifier == ManagedDirectorySnapshotManifest.markerIdentifier,
                  manifest.schemaVersion == ManagedDirectorySnapshotManifest.currentSchemaVersion,
                  manifest.recordID == record.id,
                  manifest.itemID == (record.itemID ?? AppConfiguration.legacyItemID),
                  manifest.week == record.week,
                  manifest.snapshotName == record.fileName,
                  manifest.sourceDisplayName == sourceDisplayName,
                  manifest.sourceKind == .directory,
                  manifest.contentSHA256 == record.sourceSHA256,
                  manifest.byteCount == record.byteCount,
                  manifest.files.count == record.fileCount,
                  let inspected = try? VerifiedSnapshotEngine.inspectedDirectoryContent(at: url),
                  inspected.directories == manifest.directories,
                  inspected.files == manifest.files,
                  inspected.byteCount == manifest.byteCount,
                  inspected.sha256 == manifest.contentSHA256 else { return false }
            return true
        }
    }
}

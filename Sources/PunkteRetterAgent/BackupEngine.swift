#if os(macOS)
import Foundation
import PunkteRetterCore

enum BackupError: LocalizedError {
    case setupIncomplete
    case staleBookmark
    case unavailable(String)
    case concurrent

    var errorDescription: String? {
        switch self {
        case .setupIncomplete:
            return "Die Einrichtung ist unvollständig oder das Backup-Ziel wurde noch nicht als privat bestätigt."
        case .staleBookmark:
            return "Quelle oder Backup-Ziel wurde verschoben oder ist nicht mehr erreichbar."
        case .unavailable(let message):
            return message
        case .concurrent:
            return "Ein Backup läuft bereits."
        }
    }
}

struct BackupOutcome {
    let record: BackupRecord
    let finalURL: URL
    let cloudMessage: String
}

enum BackupEngine {
    static func run(item: BackupItem, state: inout RuntimeState, now: Date = Date()) async throws -> BackupOutcome {
        guard item.enabled, item.targetConfirmedPrivate else { throw BackupError.setupIncomplete }
        guard !state.operationInProgress else { throw BackupError.concurrent }

        let week = Schedule.isoWeek(for: now)
        if state.isSecured(itemID: item.id, week: week) {
            throw BackupError.unavailable("Diese Quelle wurde in dieser Kalenderwoche bereits erfolgreich gesichert.")
        }

        state.operationInProgress = true
        defer { state.operationInProgress = false }

        let (source, sourceStale) = try Bookmarking.resolve(item.sourceBookmark)
        let (destination, destinationStale) = try Bookmarking.resolve(item.destinationBookmark)
        guard !sourceStale, !destinationStale else { throw BackupError.staleBookmark }

        let sourceAccess = source.startAccessingSecurityScopedResource()
        let destinationAccess = destination.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if destinationAccess { destination.stopAccessingSecurityScopedResource() }
        }

        var destinationIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory),
              destinationIsDirectory.boolValue else {
            throw BackupError.unavailable("Der Backup-Ordner wurde nicht gefunden.")
        }

        let cloudValues = try destination.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard cloudValues.isUbiquitousItem == true else {
            throw BackupError.unavailable("Der Backup-Ordner wird von macOS nicht mehr als iCloud-Speicher erkannt. Bitte das Backup-Ziel neu auswählen.")
        }

        let recordID = UUID()
        let snapshot = try VerifiedSnapshotEngine.createSnapshot(
            source: source,
            destination: destination,
            sourceKind: item.sourceKind,
            itemID: item.id,
            recordID: recordID,
            sourceDisplayName: item.sourceDisplayName,
            now: now
        )

        let sync = await cloudState(for: snapshot.finalURL, sourceKind: item.sourceKind)
        let record = BackupRecord(
            id: recordID,
            itemID: item.id,
            sourceDisplayName: item.sourceDisplayName,
            destinationBookmark: item.destinationBookmark,
            week: week,
            createdAt: now,
            fileName: snapshot.finalName,
            sourceKind: item.sourceKind,
            sourceSHA256: snapshot.contentSHA256,
            byteCount: snapshot.byteCount,
            fileCount: snapshot.fileCount,
            manifestSHA256: snapshot.manifestSHA256,
            cloudSyncState: sync.state
        )
        return BackupOutcome(record: record, finalURL: snapshot.finalURL, cloudMessage: sync.message)
    }

    private static func cloudState(for url: URL, sourceKind: BackupSourceKind) async -> (state: CloudSyncState, message: String) {
        let targets: [URL]
        do {
            targets = try cloudTargets(for: url, sourceKind: sourceKind)
        } catch {
            return (.notVerifiable, "Backup erstellt – iCloud-Synchronisierung konnte nicht vollständig überprüft werden.")
        }

        for _ in 0..<15 {
            var uploading = false
            var notVerifiable = false

            for target in targets {
                do {
                    let values = try target.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey])
                    if let error = values.ubiquitousItemUploadingError {
                        return (.failed, "iCloud-Synchronisierung fehlgeschlagen: \(error.localizedDescription)")
                    }
                    guard values.isUbiquitousItem == true else {
                        notVerifiable = true
                        continue
                    }
                    if values.ubiquitousItemIsUploaded == true && values.ubiquitousItemIsUploading != true {
                        continue
                    }
                    if values.ubiquitousItemIsUploading == true {
                        uploading = true
                    } else {
                        notVerifiable = true
                    }
                } catch {
                    notVerifiable = true
                }
            }

            if !uploading && !notVerifiable {
                return (.confirmed, "iCloud-Synchronisierung bestätigt.")
            }
            if uploading {
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            return (.notVerifiable, "Backup erstellt – iCloud-Synchronisierung ist noch ausstehend oder nicht abschließend überprüfbar.")
        }
        return (.uploading, "Backup erstellt – iCloud-Synchronisierung läuft noch.")
    }

    private static func cloudTargets(for url: URL, sourceKind: BackupSourceKind) throws -> [URL] {
        guard sourceKind == .directory else { return [url] }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            errorHandler: { _, error in enumerationError = error; return false }
        ) else {
            throw BackupError.unavailable("Der fertige Ordner-Snapshot konnte für die iCloud-Prüfung nicht gelesen werden.")
        }
        var files: [URL] = []
        while let entry = enumerator.nextObject() as? URL {
            if try entry.resourceValues(forKeys: Set(keys)).isRegularFile == true { files.append(entry) }
        }
        if let enumerationError { throw enumerationError }
        return files.isEmpty ? [url] : files
    }
}
#endif

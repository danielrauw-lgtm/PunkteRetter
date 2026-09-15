import Foundation

public struct WeekID: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let yearForWeekOfYear: Int
    public let weekOfYear: Int
    public init(yearForWeekOfYear: Int, weekOfYear: Int) { self.yearForWeekOfYear = yearForWeekOfYear; self.weekOfYear = weekOfYear }
    public static func < (lhs: WeekID, rhs: WeekID) -> Bool { (lhs.yearForWeekOfYear, lhs.weekOfYear) < (rhs.yearForWeekOfYear, rhs.weekOfYear) }
    public var description: String { "\(yearForWeekOfYear)-KW\(String(format: "%02d", weekOfYear))" }
}

public enum CloudSyncState: String, Codable, Sendable { case notApplicable, localVerified, uploading, confirmed, failed, notVerifiable }
public enum BackupSourceKind: String, Codable, Sendable { case file, directory }

public struct BackupItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sourceBookmark: Data
    public var sourceDisplayName: String
    public var sourceKind: BackupSourceKind
    public var destinationBookmark: Data
    public var destinationDisplayName: String
    public var targetConfirmedPrivate: Bool
    public var enabled: Bool
    public init(id: UUID = UUID(), sourceBookmark: Data, sourceDisplayName: String, sourceKind: BackupSourceKind = .file, destinationBookmark: Data, destinationDisplayName: String, targetConfirmedPrivate: Bool = false, enabled: Bool = true) {
        self.id = id
        self.sourceBookmark = sourceBookmark
        self.sourceDisplayName = sourceDisplayName
        self.sourceKind = sourceKind
        self.destinationBookmark = destinationBookmark
        self.destinationDisplayName = destinationDisplayName
        self.targetConfirmedPrivate = targetConfirmedPrivate
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceBookmark, sourceDisplayName, sourceKind, destinationBookmark, destinationDisplayName, targetConfirmedPrivate, enabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sourceBookmark = try values.decode(Data.self, forKey: .sourceBookmark)
        sourceDisplayName = try values.decode(String.self, forKey: .sourceDisplayName)
        sourceKind = try values.decodeIfPresent(BackupSourceKind.self, forKey: .sourceKind) ?? .file
        destinationBookmark = try values.decode(Data.self, forKey: .destinationBookmark)
        destinationDisplayName = try values.decode(String.self, forKey: .destinationDisplayName)
        targetConfirmedPrivate = try values.decode(Bool.self, forKey: .targetConfirmedPrivate)
        enabled = try values.decode(Bool.self, forKey: .enabled)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(sourceBookmark, forKey: .sourceBookmark)
        try values.encode(sourceDisplayName, forKey: .sourceDisplayName)
        try values.encode(sourceKind, forKey: .sourceKind)
        try values.encode(destinationBookmark, forKey: .destinationBookmark)
        try values.encode(destinationDisplayName, forKey: .destinationDisplayName)
        try values.encode(targetConfirmedPrivate, forKey: .targetConfirmedPrivate)
        try values.encode(enabled, forKey: .enabled)
    }
}

public struct BackupRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let itemID: UUID?
    public let sourceDisplayName: String?
    /// Ab 1.1 wird das Ziel-Bookmark zusätzlich am registrierten Sicherungsstand gespeichert.
    /// Dadurch kann die 26-Wochen-Aufbewahrung auch nach einer späteren Umkonfiguration
    /// ausschließlich von PunkteRetter registrierte Dateien sicher zuordnen.
    public let destinationBookmark: Data?
    public let week: WeekID
    public let createdAt: Date
    public let fileName: String
    public let sourceKind: BackupSourceKind
    public let sourceSHA256: String
    public let byteCount: Int64
    public let fileCount: Int
    /// Nur Ordner-Snapshots besitzen ein eingebettetes, zusätzlich gehashtes Besitzmanifest.
    public let manifestSHA256: String?
    public var cloudSyncState: CloudSyncState
    public init(id: UUID = UUID(), itemID: UUID? = nil, sourceDisplayName: String? = nil, destinationBookmark: Data? = nil, week: WeekID, createdAt: Date, fileName: String, sourceKind: BackupSourceKind = .file, sourceSHA256: String, byteCount: Int64, fileCount: Int = 1, manifestSHA256: String? = nil, cloudSyncState: CloudSyncState) {
        self.id = id
        self.itemID = itemID
        self.sourceDisplayName = sourceDisplayName
        self.destinationBookmark = destinationBookmark
        self.week = week
        self.createdAt = createdAt
        self.fileName = fileName
        self.sourceKind = sourceKind
        self.sourceSHA256 = sourceSHA256
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.manifestSHA256 = manifestSHA256
        self.cloudSyncState = cloudSyncState
    }

    private enum CodingKeys: String, CodingKey {
        case id, itemID, sourceDisplayName, destinationBookmark, week, createdAt, fileName, sourceKind, sourceSHA256, byteCount, fileCount, manifestSHA256, cloudSyncState
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        itemID = try values.decodeIfPresent(UUID.self, forKey: .itemID)
        sourceDisplayName = try values.decodeIfPresent(String.self, forKey: .sourceDisplayName)
        destinationBookmark = try values.decodeIfPresent(Data.self, forKey: .destinationBookmark)
        week = try values.decode(WeekID.self, forKey: .week)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        fileName = try values.decode(String.self, forKey: .fileName)
        sourceKind = try values.decodeIfPresent(BackupSourceKind.self, forKey: .sourceKind) ?? .file
        sourceSHA256 = try values.decode(String.self, forKey: .sourceSHA256)
        byteCount = try values.decode(Int64.self, forKey: .byteCount)
        fileCount = try values.decodeIfPresent(Int.self, forKey: .fileCount) ?? 1
        manifestSHA256 = try values.decodeIfPresent(String.self, forKey: .manifestSHA256)
        cloudSyncState = try values.decode(CloudSyncState.self, forKey: .cloudSyncState)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(itemID, forKey: .itemID)
        try values.encodeIfPresent(sourceDisplayName, forKey: .sourceDisplayName)
        try values.encodeIfPresent(destinationBookmark, forKey: .destinationBookmark)
        try values.encode(week, forKey: .week)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(fileName, forKey: .fileName)
        try values.encode(sourceKind, forKey: .sourceKind)
        try values.encode(sourceSHA256, forKey: .sourceSHA256)
        try values.encode(byteCount, forKey: .byteCount)
        try values.encode(fileCount, forKey: .fileCount)
        try values.encodeIfPresent(manifestSHA256, forKey: .manifestSHA256)
        try values.encode(cloudSyncState, forKey: .cloudSyncState)
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var version: Int = 4

    public var sourceBookmark: Data? = nil
    public var destinationBookmark: Data? = nil
    public var sourceDisplayName: String? = nil
    public var sourceKind: BackupSourceKind? = nil
    public var destinationDisplayName: String? = nil
    public var targetConfirmedPrivate: Bool = false

    public var backupItems: [BackupItem]? = nil

    public var automationEnabled: Bool = false
    public var setupCompleted: Bool = false
    public var quietModeUntil: Date? = nil
    public init() {}

    public static let legacyItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public var effectiveBackupItems: [BackupItem] {
        if let backupItems { return backupItems }
        guard let sourceBookmark, let destinationBookmark else { return [] }
        return [BackupItem(
            id: Self.legacyItemID,
            sourceBookmark: sourceBookmark,
            sourceDisplayName: sourceDisplayName ?? "Datei",
            sourceKind: sourceKind ?? .file,
            destinationBookmark: destinationBookmark,
            destinationDisplayName: destinationDisplayName ?? "Backup",
            targetConfirmedPrivate: targetConfirmedPrivate,
            enabled: true
        )]
    }

    public var enabledBackupItems: [BackupItem] { effectiveBackupItems.filter(\.enabled) }
}

public struct RuntimeState: Codable, Equatable, Sendable {
    public var records: [BackupRecord] = []
    public var lastSuccessfulWeek: WeekID? = nil
    public var lastFailureReason: String? = nil
    public var lastAttemptAt: Date? = nil
    public var operationInProgress: Bool = false
    /// Optionale V1.2-Erweiterung, damit alte RuntimeState-Dateien ohne Migration
    /// weiter dekodierbar bleiben. Schlüssel sind UUIDs in Kleinbuchstaben.
    public var failureReasonsByItem: [String: String]? = nil
    public init() {}

    public func isSecured(itemID: UUID, week: WeekID) -> Bool {
        records.contains { record in
            record.week == week && (record.itemID == itemID || (record.itemID == nil && itemID == AppConfiguration.legacyItemID))
        }
    }

    public func securedCount(itemIDs: [UUID], week: WeekID) -> Int {
        itemIDs.filter { isSecured(itemID: $0, week: week) }.count
    }

    public func failureReason(itemID: UUID) -> String? {
        failureReasonsByItem?[itemID.uuidString.lowercased()]
    }

    public mutating func setFailureReason(_ reason: String?, itemID: UUID) {
        let key = itemID.uuidString.lowercased()
        var reasons = failureReasonsByItem ?? [:]
        if let reason { reasons[key] = reason }
        else { reasons.removeValue(forKey: key) }
        failureReasonsByItem = reasons.isEmpty ? nil : reasons
    }

    /// Darf erst aufgerufen werden, nachdem der Agent seine exklusive
    /// Prozesssperre erworben hat. Der persistierte Wert ist nur ein Überbleibsel
    /// aus einem abgebrochenen älteren Lauf, nicht die eigentliche Sperre.
    @discardableResult
    public mutating func clearInterruptedOperationFlag() -> Bool {
        let wasInterrupted = operationInProgress
        operationInProgress = false
        return wasInterrupted
    }
}

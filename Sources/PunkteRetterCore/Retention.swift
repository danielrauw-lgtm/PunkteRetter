import Foundation

public enum Retention {
    /// V2 bewahrt bis zu `keep` erfolgreiche Stände pro Sicherungsauftrag auf.
    /// Alte V1-Records ohne itemID bilden dabei gemeinsam den Legacy-Auftrag.
    public static func recordsToDelete(_ records: [BackupRecord], keep: Int = 26) -> [BackupRecord] {
        guard keep >= 0 else { return [] }
        let grouped = Dictionary(grouping: records) { $0.itemID ?? AppConfiguration.legacyItemID }
        return grouped.values.flatMap { group -> [BackupRecord] in
            guard group.count > keep else { return [] }
            let sorted = group.sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
            return Array(sorted.dropFirst(keep))
        }
    }

    /// Ungültige oder nicht zweifelsfrei eigene Stände werden weder gelöscht noch
    /// auf die 26 gültigen Stände angerechnet.
    public static func safeDeletionCandidates(
        _ records: [BackupRecord],
        keep: Int = 26,
        isOwnedAndValid: (BackupRecord) -> Bool
    ) -> [BackupRecord] {
        recordsToDelete(records.filter(isOwnedAndValid), keep: keep)
    }
}

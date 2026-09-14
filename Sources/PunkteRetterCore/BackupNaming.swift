import Foundation

public enum BackupNaming {
    public static func make(originalName: String, sourceKind: BackupSourceKind = .file, date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        let safeOriginalName = (originalName as NSString).lastPathComponent
        let usableName = safeOriginalName.isEmpty || safeOriginalName == "." || safeOriginalName == "/" ? "Backup" : safeOriginalName
        let ns = usableName as NSString
        let ext = sourceKind == .file ? ns.pathExtension : ""
        let stem = sourceKind == .file ? ns.deletingPathExtension : usableName
        let week = Schedule.isoWeek(for: date, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let base = "\(stem)_\(formatter.string(from: date))_KW\(String(format: "%02d", week.weekOfYear))"
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    public static func collisionSafeName(preferred: String, sourceKind: BackupSourceKind = .file, existingNames: Set<String>) -> String {
        guard existingNames.contains(preferred) else { return preferred }
        let ns = preferred as NSString
        let ext = sourceKind == .file ? ns.pathExtension : ""
        let stem = sourceKind == .file ? ns.deletingPathExtension : preferred
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
            if !existingNames.contains(candidate) { return candidate }
            i += 1
        }
    }
}

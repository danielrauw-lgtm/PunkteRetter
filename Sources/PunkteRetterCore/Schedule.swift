import Foundation

public enum Schedule {
    public static func isoWeek(for date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> WeekID {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return WeekID(yearForWeekOfYear: c.yearForWeekOfYear!, weekOfYear: c.weekOfYear!)
    }

    public static func slots(forWeekContaining date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> [Date] {
        var cal = calendar
        cal.timeZone = calendar.timeZone
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let monday = cal.date(from: DateComponents(calendar: cal, timeZone: cal.timeZone, weekday: 2, weekOfYear: comps.weekOfYear, yearForWeekOfYear: comps.yearForWeekOfYear)) else { return [] }
        var result: [Date] = []
        for dayOffset in [2, 3] {
            for minutes in stride(from: 9 * 60, through: 14 * 60 + 30, by: 30) {
                if let d = cal.date(byAdding: .day, value: dayOffset, to: monday),
                   let slot = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: d) { result.append(slot) }
            }
        }
        return result.sorted()
    }

    public static func quietModeEndOfDay(for selectedDate: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: selectedDate)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? selectedDate
    }

    public static func isQuietModeActive(now: Date, quietModeUntil: Date?, calendar: Calendar = .current) -> Bool {
        guard let quietModeUntil else { return false }
        return now < quietModeEndOfDay(for: quietModeUntil, calendar: calendar)
    }

    public static func nextRegularSlot(after now: Date, lastSuccessfulWeek: WeekID?, automationEnabled: Bool, calendar: Calendar = Calendar(identifier: .iso8601)) -> Date? {
        guard automationEnabled else { return nil }
        let thisWeek = isoWeek(for: now, calendar: calendar)
        if lastSuccessfulWeek == thisWeek { return slots(forWeekContaining: calendar.date(byAdding: .weekOfYear, value: 1, to: now)!, calendar: calendar).first }
        if let next = slots(forWeekContaining: now, calendar: calendar).first(where: { $0 > now }) { return next }
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now)!
        return slots(forWeekContaining: nextWeek, calendar: calendar).first
    }

    public static func isDueRegularAttempt(now: Date, tolerance: TimeInterval = 8 * 60, lastSuccessfulWeek: WeekID?, calendar: Calendar = Calendar(identifier: .iso8601)) -> Bool {
        let week = isoWeek(for: now, calendar: calendar)
        guard lastSuccessfulWeek != week else { return false }
        return slots(forWeekContaining: now, calendar: calendar).contains { now >= $0 && now.timeIntervalSince($0) <= tolerance }
    }

    public static func shouldRunBackupAttempt(
        now: Date,
        manual: Bool,
        quietModeUntil: Date?,
        lastSuccessfulWeek: WeekID?,
        automationEnabled: Bool,
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> Bool {
        if manual { return true }
        guard automationEnabled, !isQuietModeActive(now: now, quietModeUntil: quietModeUntil, calendar: calendar) else { return false }
        return isDueRegularAttempt(now: now, lastSuccessfulWeek: lastSuccessfulWeek, calendar: calendar)
    }

}

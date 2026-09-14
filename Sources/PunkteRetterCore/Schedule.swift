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

    public static func warningCheck(forWeekContaining date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> Date? {
        let cal = calendar
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let monday = cal.date(from: DateComponents(calendar: cal, timeZone: cal.timeZone, weekday: 2, weekOfYear: comps.weekOfYear, yearForWeekOfYear: comps.yearForWeekOfYear)),
              let thursday = cal.date(byAdding: .day, value: 3, to: monday) else { return nil }
        return cal.date(bySettingHour: 14, minute: 45, second: 0, of: thursday)
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

    /// Liefert die Kalenderwoche, für die jetzt eine Warnung fällig ist. Eine bereits
    /// vorgemerkte, aber nicht an Apple Mail übergebene Warnung bleibt auch nach dem
    /// ISO-Wochenwechsel fällig. Zusätzlich wird die unmittelbar vorherige Woche
    /// berücksichtigt, wenn die Konfiguration nachweislich schon vor deren
    /// Warnzeitpunkt bestand. So erzeugt eine frische Einrichtung am Montag keine
    /// rückwirkende Warnung für eine Woche, in der PunkteRetter noch nicht aktiv war.
    public static func warningWeekDue(
        now: Date,
        completedWeeks: Set<WeekID>,
        warningSentWeek: WeekID?,
        warningQueuedWeek: WeekID?,
        quietModeUntil: Date?,
        automationEnabled: Bool,
        configurationEstablishedAt: Date?,
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> WeekID? {
        guard automationEnabled, !isQuietModeActive(now: now, quietModeUntil: quietModeUntil, calendar: calendar) else { return nil }
        let establishedAt = configurationEstablishedAt ?? .distantPast

        func isDue(_ week: WeekID) -> Bool {
            guard warningSentWeek != week, !completedWeeks.contains(week),
                  let warning = warningCheck(for: week, calendar: calendar) else { return false }
            return establishedAt <= warning && now >= warning
        }

        if let queued = warningQueuedWeek, isDue(queued) { return queued }

        let current = isoWeek(for: now, calendar: calendar)
        if isDue(current) { return current }

        if let previousDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now) {
            let previous = isoWeek(for: previousDate, calendar: calendar)
            if isDue(previous) { return previous }
        }
        return nil
    }

    public static func isWarningDue(now: Date, state: RuntimeState, quietModeUntil: Date?, automationEnabled: Bool, calendar: Calendar = Calendar(identifier: .iso8601)) -> Bool {
        let currentWeek = isoWeek(for: now, calendar: calendar)
        let completed = state.lastSuccessfulWeek.map { Set([$0]) } ?? []
        return warningWeekDue(
            now: now,
            completedWeeks: completed,
            warningSentWeek: state.warningSentWeek,
            warningQueuedWeek: state.warningQueuedWeek,
            quietModeUntil: quietModeUntil,
            automationEnabled: automationEnabled,
            configurationEstablishedAt: nil,
            calendar: calendar
        ) == currentWeek
    }

    private static func warningCheck(for week: WeekID, calendar: Calendar) -> Date? {
        guard let monday = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            weekday: 2,
            weekOfYear: week.weekOfYear,
            yearForWeekOfYear: week.yearForWeekOfYear
        )), let thursday = calendar.date(byAdding: .day, value: 3, to: monday) else { return nil }
        return calendar.date(bySettingHour: 14, minute: 45, second: 0, of: thursday)
    }
}

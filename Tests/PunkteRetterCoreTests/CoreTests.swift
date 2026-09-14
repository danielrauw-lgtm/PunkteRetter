import XCTest
@testable import PunkteRetterCore

final class CoreTests: XCTestCase {
    private func brusselsCalendar() -> Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Europe/Brussels")!
        return c
    }
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func testISOWeekAcrossYear() {
        let c = brusselsCalendar()
        XCTAssertEqual(Schedule.isoWeek(for: date("2026-12-31T12:00:00+01:00"), calendar: c), WeekID(yearForWeekOfYear: 2026, weekOfYear: 53))
        XCTAssertEqual(Schedule.isoWeek(for: date("2027-01-01T12:00:00+01:00"), calendar: c), WeekID(yearForWeekOfYear: 2026, weekOfYear: 53))
        XCTAssertEqual(Schedule.isoWeek(for: date("2027-01-04T12:00:00+01:00"), calendar: c), WeekID(yearForWeekOfYear: 2027, weekOfYear: 1))
    }

    func testWednesdayThursdaySlots() {
        let c = brusselsCalendar()
        let slots = Schedule.slots(forWeekContaining: date("2026-09-08T12:00:00+02:00"), calendar: c)
        XCTAssertEqual(slots.count, 24)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.weekday, from: slots.first!), 4)
        XCTAssertEqual(c.component(.hour, from: slots.first!), 9)
        XCTAssertEqual(c.component(.minute, from: slots.last!), 30)
    }

    func testWarningThursday1445() {
        let c = brusselsCalendar()
        let w = Schedule.warningCheck(forWeekContaining: date("2026-09-08T12:00:00+02:00"), calendar: c)!
        XCTAssertEqual(c.component(.weekday, from: w), 5)
        XCTAssertEqual(c.component(.hour, from: w), 14)
        XCTAssertEqual(c.component(.minute, from: w), 45)

        let state = RuntimeState()
        XCTAssertFalse(Schedule.isWarningDue(now: date("2026-09-10T14:44:59+02:00"), state: state, quietModeUntil: nil, automationEnabled: true, calendar: c))
        XCTAssertTrue(Schedule.isWarningDue(now: date("2026-09-10T14:45:00+02:00"), state: state, quietModeUntil: nil, automationEnabled: true, calendar: c))
    }

    func testNoSecondBackupSameWeek() {
        let c = brusselsCalendar()
        let now = date("2026-09-09T10:02:00+02:00")
        let week = Schedule.isoWeek(for: now, calendar: c)
        XCTAssertFalse(Schedule.isDueRegularAttempt(now: now, lastSuccessfulWeek: week, calendar: c))
    }

    func testBackupNamingAndCollision() {
        let c = brusselsCalendar()
        let n = BackupNaming.make(originalName: "Punkte Schüler.xlsx", date: date("2026-09-03T10:00:00+02:00"), calendar: c)
        XCTAssertEqual(n, "Punkte Schüler_2026-09-03_KW36.xlsx")
        XCTAssertEqual(BackupNaming.collisionSafeName(preferred: n, existingNames: [n]), "Punkte Schüler_2026-09-03_KW36-2.xlsx")
        let dottedFolder = "Klasse.6_2026-09-03_KW36"
        XCTAssertEqual(BackupNaming.collisionSafeName(preferred: dottedFolder, sourceKind: .directory, existingNames: [dottedFolder]), "Klasse.6_2026-09-03_KW36-2")
    }

    func testBackupNamingWorksForNonExcelAndWithoutExtension() {
        let c = brusselsCalendar()
        let when = date("2026-09-03T10:00:00+02:00")
        XCTAssertEqual(BackupNaming.make(originalName: "Elternbrief.pdf", date: when, calendar: c), "Elternbrief_2026-09-03_KW36.pdf")
        XCTAssertEqual(BackupNaming.make(originalName: "Notizen", date: when, calendar: c), "Notizen_2026-09-03_KW36")
        XCTAssertEqual(BackupNaming.make(originalName: "Klasse.6.Notizen.docx", date: when, calendar: c), "Klasse.6.Notizen_2026-09-03_KW36.docx")
        XCTAssertEqual(BackupNaming.make(originalName: "Klasse.6", sourceKind: .directory, date: when, calendar: c), "Klasse.6_2026-09-03_KW36")
    }

    func testRetentionOnlyOldRegisteredRecords() {
        let base = date("2026-01-01T00:00:00Z")
        let records = (0..<30).map { i in
            BackupRecord(week: WeekID(yearForWeekOfYear: 2026, weekOfYear: i + 1), createdAt: base.addingTimeInterval(Double(i) * 86400), fileName: "b\(i).xlsx", sourceSHA256: "x", byteCount: 1, cloudSyncState: .confirmed)
        }
        let deleted = Retention.recordsToDelete(records)
        XCTAssertEqual(deleted.count, 4)
        XCTAssertEqual(Set(deleted.map(\.fileName)), Set(["b0.xlsx", "b1.xlsx", "b2.xlsx", "b3.xlsx"]))
    }

    func testRetentionKeeps26PerBackupItem() {
        let base = date("2026-01-01T00:00:00Z")
        let first = UUID(), second = UUID()
        let a = (0..<30).map { i in BackupRecord(itemID: first, sourceDisplayName: "A.pdf", week: WeekID(yearForWeekOfYear: 2026, weekOfYear: i + 1), createdAt: base.addingTimeInterval(Double(i) * 86400), fileName: "a\(i).pdf", sourceSHA256: "a", byteCount: 1, cloudSyncState: .confirmed) }
        let b = (0..<10).map { i in BackupRecord(itemID: second, sourceDisplayName: "B.docx", week: WeekID(yearForWeekOfYear: 2026, weekOfYear: i + 1), createdAt: base.addingTimeInterval(Double(i) * 86400), fileName: "b\(i).docx", sourceSHA256: "b", byteCount: 1, cloudSyncState: .confirmed) }
        let deleted = Retention.recordsToDelete(a + b)
        XCTAssertEqual(deleted.count, 4)
        XCTAssertTrue(deleted.allSatisfy { $0.itemID == first })
    }

    func testRetentionTreatsItemsIndependentlyAtBoundary() {
        let base = date("2026-01-01T00:00:00Z")
        let first = UUID(), second = UUID()
        let a = (0..<27).map { i in BackupRecord(itemID: first, sourceDisplayName: "A.pdf", week: WeekID(yearForWeekOfYear: 2026, weekOfYear: i + 1), createdAt: base.addingTimeInterval(Double(i) * 86400), fileName: "a\(i).pdf", sourceSHA256: "a", byteCount: 1, cloudSyncState: .confirmed) }
        let b = (0..<27).map { i in BackupRecord(itemID: second, sourceDisplayName: "B.docx", week: WeekID(yearForWeekOfYear: 2026, weekOfYear: i + 1), createdAt: base.addingTimeInterval(Double(i) * 86400), fileName: "b\(i).docx", sourceSHA256: "b", byteCount: 1, cloudSyncState: .confirmed) }
        let deleted = Retention.recordsToDelete(a + b)
        XCTAssertEqual(deleted.count, 2)
        XCTAssertEqual(Set(deleted.compactMap(\.itemID)), Set([first, second]))
    }

    func testRetentionDoesNothingAt25Or26ValidSnapshots() {
        let base = date("2026-01-01T00:00:00Z")
        let itemID = UUID()
        let records = (0..<26).map { index in
            BackupRecord(
                itemID: itemID,
                sourceDisplayName: "A.pdf",
                week: WeekID(yearForWeekOfYear: 2026, weekOfYear: index + 1),
                createdAt: base.addingTimeInterval(Double(index) * 60),
                fileName: "a\(index).pdf",
                sourceSHA256: "hash-\(index)",
                byteCount: 1,
                cloudSyncState: .confirmed
            )
        }
        XCTAssertTrue(Retention.recordsToDelete(Array(records.prefix(25))).isEmpty)
        XCTAssertTrue(Retention.recordsToDelete(records).isEmpty)
    }

    func testSafeRetentionDeletesOldestValidSnapshotButNeverForeignRecord() {
        let itemID = UUID()
        let base = date("2026-01-01T00:00:00Z")
        let valid = (0..<27).map { index in
            BackupRecord(
                itemID: itemID,
                sourceDisplayName: "Ordner",
                week: WeekID(yearForWeekOfYear: 2026, weekOfYear: index + 1),
                createdAt: base.addingTimeInterval(Double(index) * 60),
                fileName: "snapshot-\(index)",
                sourceKind: .directory,
                sourceSHA256: "hash",
                byteCount: 1,
                fileCount: 1,
                manifestSHA256: "manifest",
                cloudSyncState: .confirmed
            )
        }
        let foreign = BackupRecord(
            itemID: itemID,
            sourceDisplayName: "Ordner",
            week: WeekID(yearForWeekOfYear: 2025, weekOfYear: 52),
            createdAt: base.addingTimeInterval(-60),
            fileName: "nur-aehnlich-benannt",
            sourceKind: .directory,
            sourceSHA256: "fremd",
            byteCount: 1,
            fileCount: 1,
            manifestSHA256: nil,
            cloudSyncState: .confirmed
        )

        let candidates = Retention.safeDeletionCandidates(valid + [foreign], keep: 26) {
            $0.id != foreign.id
        }
        XCTAssertEqual(candidates.map(\.id), [valid[0].id])
        XCTAssertFalse(candidates.contains { $0.id == foreign.id })
    }

    func testPerItemWeeklyStatus() {
        let week = WeekID(yearForWeekOfYear: 2026, weekOfYear: 37)
        let first = UUID(), second = UUID()
        var state = RuntimeState()
        state.records = [BackupRecord(itemID: first, sourceDisplayName: "A.pdf", week: week, createdAt: Date(), fileName: "A.pdf", sourceSHA256: "x", byteCount: 1, cloudSyncState: .confirmed)]
        XCTAssertTrue(state.isSecured(itemID: first, week: week))
        XCTAssertFalse(state.isSecured(itemID: second, week: week))
        XCTAssertEqual(state.securedCount(itemIDs: [first, second], week: week), 1)
    }

    func testPerItemStatusDoesNotDoubleCountDuplicateRecords() {
        let week = WeekID(yearForWeekOfYear: 2026, weekOfYear: 37)
        let first = UUID(), second = UUID()
        var state = RuntimeState()
        state.records = [
            BackupRecord(itemID: first, sourceDisplayName: "A.pdf", week: week, createdAt: Date(), fileName: "A-1.pdf", sourceSHA256: "x", byteCount: 1, cloudSyncState: .confirmed),
            BackupRecord(itemID: first, sourceDisplayName: "A.pdf", week: week, createdAt: Date(), fileName: "A-2.pdf", sourceSHA256: "y", byteCount: 1, cloudSyncState: .confirmed)
        ]
        XCTAssertEqual(state.securedCount(itemIDs: [first, second], week: week), 1)
    }

    func testDisabledBackupItemsAreExcluded() {
        var config = AppConfiguration()
        let enabled = BackupItem(sourceBookmark: Data([1]), sourceDisplayName: "A.pdf", destinationBookmark: Data([2]), destinationDisplayName: "Backup", targetConfirmedPrivate: true, enabled: true)
        let disabled = BackupItem(sourceBookmark: Data([3]), sourceDisplayName: "B.docx", destinationBookmark: Data([4]), destinationDisplayName: "Backup", targetConfirmedPrivate: true, enabled: false)
        config.backupItems = [enabled, disabled]
        XCTAssertEqual(config.effectiveBackupItems.count, 2)
        XCTAssertEqual(config.enabledBackupItems.map(\.id), [enabled.id])
    }

    func testLegacyRecordCountsForLegacyItem() {
        let week = WeekID(yearForWeekOfYear: 2026, weekOfYear: 37)
        var state = RuntimeState()
        state.records = [BackupRecord(week: week, createdAt: Date(), fileName: "Alt.xlsx", sourceSHA256: "x", byteCount: 1, cloudSyncState: .confirmed)]
        XCTAssertTrue(state.isSecured(itemID: AppConfiguration.legacyItemID, week: week))
    }

    func testOldConfigurationDecodesWithoutBackupItemsKey() throws {
        let json = #"{"version":1,"notificationAddress":"a@b.be","selectedMailAccountID":null,"selectedMailAccountDisplayName":null,"selectedMailSenderAddress":null,"verifiedMailSelectionFingerprint":null,"sourceBookmark":null,"destinationBookmark":null,"sourceDisplayName":null,"destinationDisplayName":null,"targetConfirmedPrivate":false,"automationEnabled":false,"setupCompleted":false,"quietModeUntil":null}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: json)
        XCTAssertNil(decoded.backupItems)
        XCTAssertNil(decoded.lastMailTestFailureReason)
        XCTAssertTrue(decoded.effectiveBackupItems.isEmpty)
    }

    func testLegacyConfigurationMapsToDeterministicBackupItem() {
        var config = AppConfiguration()
        config.sourceBookmark = Data([1, 2, 3])
        config.destinationBookmark = Data([4, 5, 6])
        config.sourceDisplayName = "Punkte.xlsx"
        config.destinationDisplayName = "PunkteRetter"
        config.targetConfirmedPrivate = true
        let items = config.effectiveBackupItems
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, AppConfiguration.legacyItemID)
        XCTAssertEqual(items[0].sourceDisplayName, "Punkte.xlsx")
        XCTAssertTrue(items[0].targetConfirmedPrivate)
    }

    func testEmailValidation() {
        XCTAssertTrue(Validation.isValidEmailSyntax("lehrkraft@example.invalid"))
        XCTAssertFalse(Validation.isValidEmailSyntax("lehrkraft@@example.invalid"))
        XCTAssertFalse(Validation.isValidEmailSyntax("lehrkraft@example"))
    }

    func testQuietModeSuppressesWarning() {
        let c = brusselsCalendar()
        let now = date("2026-09-10T15:00:00+02:00")
        var state = RuntimeState()
        state.lastSuccessfulWeek = nil
        XCTAssertFalse(Schedule.isWarningDue(now: now, state: state, quietModeUntil: date("2026-09-11T00:00:00+02:00"), automationEnabled: true, calendar: c))
        XCTAssertTrue(Schedule.isWarningDue(now: now, state: state, quietModeUntil: nil, automationEnabled: true, calendar: c))
    }

    func testQuietModeIncludesEntireSelectedDate() {
        let c = brusselsCalendar()
        let selected = date("2026-09-10T00:00:00+02:00")
        let end = Schedule.quietModeEndOfDay(for: selected, calendar: c)
        XCTAssertEqual(end, date("2026-09-11T00:00:00+02:00"))
        let state = RuntimeState()
        let thursdayAfternoon = date("2026-09-10T15:00:00+02:00")
        XCTAssertFalse(Schedule.isWarningDue(now: thursdayAfternoon, state: state, quietModeUntil: selected, automationEnabled: true, calendar: c))
    }

    func testQuietModePausesAutomaticBackupButAllowsManualBackup() {
        let c = brusselsCalendar()
        let now = date("2026-09-09T10:02:00+02:00")
        let quietDate = date("2026-09-09T00:00:00+02:00")

        XCTAssertFalse(Schedule.shouldRunBackupAttempt(
            now: now,
            manual: false,
            quietModeUntil: quietDate,
            lastSuccessfulWeek: nil,
            automationEnabled: true,
            calendar: c
        ))
        XCTAssertTrue(Schedule.shouldRunBackupAttempt(
            now: now,
            manual: true,
            quietModeUntil: quietDate,
            lastSuccessfulWeek: nil,
            automationEnabled: true,
            calendar: c
        ))
        XCTAssertTrue(Schedule.shouldRunBackupAttempt(
            now: now,
            manual: false,
            quietModeUntil: nil,
            lastSuccessfulWeek: nil,
            automationEnabled: true,
            calendar: c
        ))
    }

    func testWarningOnlyOncePerWeek() {
        let c = brusselsCalendar()
        let now = date("2026-09-10T15:00:00+02:00")
        var state = RuntimeState()
        state.warningSentWeek = Schedule.isoWeek(for: now, calendar: c)
        XCTAssertFalse(Schedule.isWarningDue(now: now, state: state, quietModeUntil: nil, automationEnabled: true, calendar: c))
    }

    func testQueuedWarningRemainsDueForRetry() {
        let c = brusselsCalendar()
        let now = date("2026-09-10T15:00:00+02:00")
        var state = RuntimeState()
        state.warningQueuedWeek = Schedule.isoWeek(for: now, calendar: c)
        XCTAssertTrue(Schedule.isWarningDue(now: now, state: state, quietModeUntil: nil, automationEnabled: true, calendar: c))
    }

    func testOverdueWarningSurvivesISOWeekRollover() {
        let c = brusselsCalendar()
        let previous = WeekID(yearForWeekOfYear: 2026, weekOfYear: 37)
        let due = Schedule.warningWeekDue(
            now: date("2026-09-14T09:00:00+02:00"),
            completedWeeks: [],
            warningSentWeek: nil,
            warningQueuedWeek: nil,
            quietModeUntil: nil,
            automationEnabled: true,
            configurationEstablishedAt: date("2026-09-01T09:00:00+02:00"),
            calendar: c
        )
        XCTAssertEqual(due, previous)
    }

    func testNewConfigurationDoesNotWarnForEarlierWeek() {
        let c = brusselsCalendar()
        let due = Schedule.warningWeekDue(
            now: date("2026-09-14T09:00:00+02:00"),
            completedWeeks: [],
            warningSentWeek: nil,
            warningQueuedWeek: nil,
            quietModeUntil: nil,
            automationEnabled: true,
            configurationEstablishedAt: date("2026-09-14T08:30:00+02:00"),
            calendar: c
        )
        XCTAssertNil(due)
    }

    func testQueuedWarningRemainsDueAfterWeekRollover() {
        let c = brusselsCalendar()
        let previous = WeekID(yearForWeekOfYear: 2026, weekOfYear: 37)
        let due = Schedule.warningWeekDue(
            now: date("2026-09-16T09:00:00+02:00"),
            completedWeeks: [],
            warningSentWeek: nil,
            warningQueuedWeek: previous,
            quietModeUntil: nil,
            automationEnabled: true,
            configurationEstablishedAt: date("2026-09-01T09:00:00+02:00"),
            calendar: c
        )
        XCTAssertEqual(due, previous)
    }

    func testCompletedPreviousWeekDoesNotProduceOverdueWarning() {
        let c = brusselsCalendar()
        let previous = WeekID(yearForWeekOfYear: 2026, weekOfYear: 37)
        let due = Schedule.warningWeekDue(
            now: date("2026-09-14T09:00:00+02:00"),
            completedWeeks: [previous],
            warningSentWeek: nil,
            warningQueuedWeek: previous,
            quietModeUntil: nil,
            automationEnabled: true,
            configurationEstablishedAt: date("2026-09-01T09:00:00+02:00"),
            calendar: c
        )
        XCTAssertNil(due)
    }

    func testNextAttemptMovesToNextWeekAfterSuccess() {
        let c = brusselsCalendar()
        let now = date("2026-09-09T10:00:00+02:00")
        let week = Schedule.isoWeek(for: now, calendar: c)
        let next = Schedule.nextRegularSlot(after: now, lastSuccessfulWeek: week, automationEnabled: true, calendar: c)!
        XCTAssertEqual(Schedule.isoWeek(for: next, calendar: c), WeekID(yearForWeekOfYear: 2026, weekOfYear: 38))
        XCTAssertEqual(c.component(.weekday, from: next), 4)
        XCTAssertEqual(c.component(.hour, from: next), 9)
    }

    func testAutomationOffHasNoNextAttempt() {
        XCTAssertNil(Schedule.nextRegularSlot(after: Date(), lastSuccessfulWeek: nil, automationEnabled: false))
    }

    func testAtomicJSONStoreRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AtomicJSONStore<RuntimeState>(url: dir.appendingPathComponent("state.json"))
        var state = RuntimeState(); state.lastFailureReason = "Test"; state.warningQueuedWeek = WeekID(yearForWeekOfYear: 2026, weekOfYear: 37)
        try await store.save(state)
        let loaded = try await store.load(default: RuntimeState())
        XCTAssertEqual(loaded, state)
    }

    func testAtomicJSONStoreRejectsCorruptState() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.json")
        try Data("{not-json".utf8).write(to: url)
        let store = AtomicJSONStore<RuntimeState>(url: url)
        do {
            _ = try await store.load(default: RuntimeState())
            XCTFail("Beschädigter Zustand darf nicht stillschweigend als leer akzeptiert werden")
        } catch {
            XCTAssertTrue(true)
        }
    }


    func testRuntimeStateDecodesWithoutPerItemFailuresAndTracksThemSeparately() throws {
        let json = #"{"records":[],"lastSuccessfulWeek":null,"warningSentWeek":null,"warningQueuedWeek":null,"lastFailureReason":null,"lastAttemptAt":null,"operationInProgress":false}"#.data(using: .utf8)!
        var state = try JSONDecoder().decode(RuntimeState.self, from: json)
        let first = UUID(), second = UUID()
        XCTAssertNil(state.failureReason(itemID: first))
        state.setFailureReason("Quelle fehlt", itemID: first)
        state.setFailureReason("Ziel fehlt", itemID: second)
        XCTAssertEqual(state.failureReason(itemID: first), "Quelle fehlt")
        XCTAssertEqual(state.failureReason(itemID: second), "Ziel fehlt")
        state.setFailureReason(nil, itemID: first)
        XCTAssertNil(state.failureReason(itemID: first))
        XCTAssertEqual(state.failureReason(itemID: second), "Ziel fehlt")
    }

    func testInterruptedOperationFlagCanBeRecoveredAfterExclusiveRestart() {
        var state = RuntimeState()
        state.operationInProgress = true

        XCTAssertTrue(state.clearInterruptedOperationFlag())
        XCTAssertFalse(state.operationInProgress)
        XCTAssertFalse(state.clearInterruptedOperationFlag())
    }

    func testAtomicJSONStoreUpdateDoesNotReplaceCorruptState() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let corrupt = Data("{kaputt".utf8)
        try corrupt.write(to: url)
        let store = AtomicJSONStore<RuntimeState>(url: url)

        do {
            _ = try await store.update(default: RuntimeState()) { state in
                state.lastFailureReason = "darf nicht gespeichert werden"
            }
            XCTFail("Beschädigter Zustand darf nicht überschrieben werden")
        } catch {
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
        }
    }

    func testStaleMovedSourceBookmarkIsRefreshedOnlyAfterValidation() throws {
        let old = Data([1]), renewed = Data([2])
        let moved = URL(fileURLWithPath: "/tmp/Quelle verschoben")
        var validated = false
        let result = try BookmarkRefresh.resolve(
            old,
            using: { _ in (moved, true) },
            validate: { url in validated = (url == moved) },
            refresh: { url in XCTAssertEqual(url, moved); return renewed }
        )
        XCTAssertTrue(validated)
        XCTAssertEqual(result.url, moved)
        XCTAssertEqual(result.refreshedBookmark, renewed)
    }

    func testStaleMovedDestinationBookmarkFailureDoesNotFallBackToPath() {
        let moved = URL(fileURLWithPath: "/tmp/Ziel verschoben")
        XCTAssertThrowsError(try BookmarkRefresh.resolve(
            Data([1]),
            using: { _ in (moved, true) },
            validate: { _ in throw CocoaError(.fileNoSuchFile) },
            refresh: { _ in XCTFail("Ein unbestätigtes Ziel darf nicht erneuert werden"); return Data() }
        ))
    }

    func testCurrentBookmarkIsNotRewritten() throws {
        let current = URL(fileURLWithPath: "/tmp/Quelle")
        let result = try BookmarkRefresh.resolve(
            Data([1]),
            using: { _ in (current, false) },
            validate: { _ in XCTFail("Nicht-stale Bookmarks benötigen keine Reparatur") },
            refresh: { _ in XCTFail("Nicht-stale Bookmarks dürfen nicht ersetzt werden"); return Data() }
        )
        XCTAssertEqual(result.url, current)
        XCTAssertNil(result.refreshedBookmark)
    }

    func testProcessLockLivesUntilOwnerIsReleasedAndBlocksConcurrentRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("agent.lock")

        var first: ExclusiveProcessLock? = ExclusiveProcessLock(url: url)
        XCTAssertNotNil(first)
        XCTAssertNil(ExclusiveProcessLock(url: url))
        first = nil
        XCTAssertNotNil(ExclusiveProcessLock(url: url))
    }
}

#if os(macOS)
import Foundation
import Darwin
import PunkteRetterCore

@main
struct PunkteRetterAgentMain {
    private struct BookmarkRefreshFailure: LocalizedError {
        let itemID: UUID
        let sourceName: String
        let detail: String
        var errorDescription: String? {
            "„\(sourceName)“ konnte nicht mehr sicher über den gespeicherten Bookmark erreicht werden: \(detail)"
        }
    }

    static func main() async {
        let mailTestRequested = CommandLine.arguments.contains("--test-mail")
        if CommandLine.arguments.contains("--version") {
            print(PunkteRetterBuildInfo.display)
            return
        }
        guard let processLock = ProcessLock(url: PunkteRetterPaths.supportDirectory().appendingPathComponent("agent.lock")) else {
            if mailTestRequested { Darwin.exit(75) }
            return
        }
        defer { _ = processLock } // Den flock bis zum tatsächlichen Prozessende festhalten.
        let configStore = AtomicJSONStore<AppConfiguration>(url: PunkteRetterPaths.configURL)
        let stateStore = AtomicJSONStore<RuntimeState>(url: PunkteRetterPaths.stateURL)

        do {
            var config = try await configStore.load(default: AppConfiguration())
            // Vor möglichen Bookmark-Migrationen erfassen. Der Zeitstempel belegt,
            // ob diese Konfiguration bereits vor einem verpassten Warntermin bestand.
            let configurationEstablishedAt = try? PunkteRetterPaths.configURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate

            if mailTestRequested {
                try await runMailTest(config: config, configStore: configStore)
                return
            }

            var state = try await stateStore.load(default: RuntimeState())

            // Die exklusive Prozesssperre ist die maßgebliche Laufzeitsperre. Ein in
            // einer älteren Version gespeichertes `operationInProgress` darf nach
            // einem Absturz keinen Auftrag dauerhaft blockieren.
            if state.clearInterruptedOperationFlag() {
                try await stateStore.save(state)
                await SafeLog.shared.write("Veralteten In-Progress-Status nach sicherem Prozessstart zurückgesetzt.")
            }

            do {
                let refreshed = try refreshStaleBookmarks(in: config)
                if refreshed.changed {
                    config = try await configStore.update(default: AppConfiguration()) { latest in
                        let latestRefresh = try refreshStaleBookmarks(in: latest)
                        latest = latestRefresh.config
                    }
                    await SafeLog.shared.write("Veraltete Security-Scoped Bookmarks wurden erfolgreich erneuert.")
                }
            } catch {
                let message = "Quelle oder Backup-Ziel konnte nicht sicher über den gespeicherten Bookmark aufgelöst werden: \(error.localizedDescription)"
                state.lastFailureReason = message
                if let failure = error as? BookmarkRefreshFailure {
                    state.setFailureReason(failure.localizedDescription, itemID: failure.itemID)
                } else {
                    for item in config.enabledBackupItems { state.setFailureReason(message, itemID: item.id) }
                }
                try? await stateStore.save(state)
                await SafeLog.shared.write(message)
                return
            }

            guard config.setupCompleted else { return }
            let items = config.enabledBackupItems
            guard !items.isEmpty else { return }
            guard items.allSatisfy(\.targetConfirmedPrivate) else {
                await SafeLog.shared.write("Agent abgebrochen: Mindestens ein Backup-Ziel ist nicht als privat bestätigt.")
                return
            }

            let now = Date()
            let week = Schedule.isoWeek(for: now)
            let manual = CommandLine.arguments.contains("--manual")
            if !manual && !config.automationEnabled { return }

            let allSecuredBefore = allSecured(items: items, state: state, week: week)
            if allSecuredBefore { state.lastSuccessfulWeek = week }
            else if state.lastSuccessfulWeek == week { state.lastSuccessfulWeek = nil }

            if !allSecuredBefore && Schedule.shouldRunBackupAttempt(
                now: now,
                manual: manual,
                quietModeUntil: config.quietModeUntil,
                lastSuccessfulWeek: state.lastSuccessfulWeek,
                automationEnabled: config.automationEnabled
            ) {
                state.lastAttemptAt = now
                await runPendingBackups(items: items, state: &state, now: now, stateStore: stateStore)
            }

            if allSecured(items: items, state: state, week: week) {
                state.lastSuccessfulWeek = week
                state.lastFailureReason = nil
                try? await stateStore.save(state)
                await sendOrRetryWeeklySuccessMail(config: config, items: items, state: &state, week: week, stateStore: stateStore)
                await cleanup(config: config, state: &state, stateStore: stateStore)
            }

            let completedWeeks = Set(state.records.map(\.week).filter { candidate in
                allSecured(items: items, state: state, week: candidate)
            })
            if let queued = state.warningQueuedWeek, completedWeeks.contains(queued) {
                state.warningQueuedWeek = nil
                try? await stateStore.save(state)
            }
            if let warningWeek = Schedule.warningWeekDue(
                now: now,
                completedWeeks: completedWeeks,
                warningSentWeek: state.warningSentWeek,
                warningQueuedWeek: state.warningQueuedWeek,
                quietModeUntil: config.quietModeUntil,
                automationEnabled: config.automationEnabled,
                configurationEstablishedAt: configurationEstablishedAt
            ) {
                await sendWarning(config: config, items: items, state: &state, week: warningWeek, now: now, stateStore: stateStore)
            }
        } catch {
            if mailTestRequested {
                await SafeLog.shared.write("Mailtest fehlgeschlagen: \(error.localizedDescription)")
                Darwin.exit(EXIT_FAILURE)
            }
            await SafeLog.shared.write("Agent konnte Konfiguration/Zustand nicht sicher laden. Keine Änderungen durchgeführt: \(error.localizedDescription)")
        }
    }

    private static func runPendingBackups(items: [BackupItem], state: inout RuntimeState, now: Date, stateStore: AtomicJSONStore<RuntimeState>) async {
        let week = Schedule.isoWeek(for: now)
        var failures: [String] = []

        if let unsafeReason = unsafePlanReason(items: items) {
            state.lastFailureReason = unsafeReason
            for item in items { state.setFailureReason(unsafeReason, itemID: item.id) }
            await SafeLog.shared.write("Backup-Plan aus Sicherheitsgründen abgebrochen: \(unsafeReason)")
            try? await stateStore.save(state)
            return
        }

        for item in items where !state.isSecured(itemID: item.id, week: week) {
            do {
                let outcome = try await BackupEngine.run(item: item, state: &state, now: now)
                state.records.append(outcome.record)
                state.setFailureReason(nil, itemID: item.id)
                do {
                    try await stateStore.save(state)
                } catch {
                    // Nach einem gemeldeten Schreibfehler zuerst feststellen, ob der
                    // atomare Austausch möglicherweise doch vollständig erfolgt ist.
                    if let persisted = try? await stateStore.load(default: RuntimeState()),
                       persisted.records.contains(where: { $0.id == outcome.record.id }) {
                        state = persisted
                    } else {
                        state.records.removeAll { $0.id == outcome.record.id }
                        if ManagedBackupOwnership.isSafeToDelete(record: outcome.record, at: outcome.finalURL) {
                            try? FileManager.default.removeItem(at: outcome.finalURL)
                        }
                        throw NSError(
                            domain: "PunkteRetter.State",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Der geprüfte Snapshot konnte nicht sicher im Laufzeitstatus registriert werden und gilt nicht als Wochenstand. Der Auftrag wird erneut versucht."]
                        )
                    }
                }
                await SafeLog.shared.write("Backup-Quelle erfolgreich geprüft: \(item.sourceDisplayName)")
            } catch {
                let message = "\(item.sourceDisplayName): \(error.localizedDescription)"
                failures.append(message)
                state.setFailureReason(error.localizedDescription, itemID: item.id)
                await SafeLog.shared.write("Backup-Versuch fehlgeschlagen: \(message)")
                try? await stateStore.save(state)
            }
        }

        state.lastFailureReason = failures.isEmpty ? nil : failures.joined(separator: " | ")
        if allSecured(items: items, state: state, week: week) {
            state.lastSuccessfulWeek = week
        }
        try? await stateStore.save(state)
    }

    private static func unsafePlanReason(items: [BackupItem]) -> String? {
        var locations: [BackupPlanLocation] = []
        for item in items {
            do {
                let (source, sourceStale) = try Bookmarking.resolve(item.sourceBookmark)
                let (destination, destinationStale) = try Bookmarking.resolve(item.destinationBookmark)
                guard !sourceStale, !destinationStale else {
                    return "Quelle oder Backup-Ziel von „\(item.sourceDisplayName)“ wurde während der Sicherheitsprüfung verschoben. Es wurden keine Aufträge ausgeführt."
                }
                locations.append(BackupPlanLocation(itemID: item.id, source: source, sourceKind: item.sourceKind, destination: destination))
            } catch {
                return "Quelle oder Backup-Ziel von „\(item.sourceDisplayName)“ konnte während der Sicherheitsprüfung nicht sicher aufgelöst werden. Es wurden keine Aufträge ausgeführt."
            }
        }
        do {
            try BackupPlanSafety.validateNoDestinationInsideDirectorySource(locations)
            return nil
        } catch {
            return "Ein Backup-Ziel liegt innerhalb eines eingerichteten Quellordners. Es wurden keine Aufträge ausgeführt, damit keine Backups rekursiv in weitere Backups kopiert werden."
        }
    }

    private static func refreshStaleBookmarks(in original: AppConfiguration) throws -> (config: AppConfiguration, changed: Bool) {
        var config = original
        var items = config.effectiveBackupItems
        var changed = config.backupItems == nil && !items.isEmpty

        for index in items.indices {
            let source: (url: URL, refreshedBookmark: Data?)
            do {
                source = try Bookmarking.resolveRefreshingIfNeeded(items[index].sourceBookmark)
            } catch {
                throw BookmarkRefreshFailure(itemID: items[index].id, sourceName: items[index].sourceDisplayName, detail: error.localizedDescription)
            }
            if let bookmark = source.refreshedBookmark {
                items[index].sourceBookmark = bookmark
                items[index].sourceDisplayName = source.url.lastPathComponent
                changed = true
            }
            let destination: (url: URL, refreshedBookmark: Data?)
            do {
                destination = try Bookmarking.resolveRefreshingIfNeeded(items[index].destinationBookmark)
            } catch {
                throw BookmarkRefreshFailure(itemID: items[index].id, sourceName: items[index].sourceDisplayName, detail: error.localizedDescription)
            }
            if let bookmark = destination.refreshedBookmark {
                items[index].destinationBookmark = bookmark
                items[index].destinationDisplayName = destination.url.lastPathComponent
                changed = true
            }
        }

        if changed {
            config.backupItems = items
            config.version = max(config.version, 3)
            if items.count == 1, items[0].id == AppConfiguration.legacyItemID {
                config.sourceBookmark = items[0].sourceBookmark
                config.destinationBookmark = items[0].destinationBookmark
                config.sourceDisplayName = items[0].sourceDisplayName
                config.destinationDisplayName = items[0].destinationDisplayName
                config.sourceKind = items[0].sourceKind
            }
        }
        return (config, changed)
    }

    private static func allSecured(items: [BackupItem], state: RuntimeState, week: WeekID) -> Bool {
        !items.isEmpty && items.allSatisfy { state.isSecured(itemID: $0.id, week: week) }
    }

    private static func runMailTest(config: AppConfiguration, configStore: AtomicJSONStore<AppConfiguration>) async throws {
        guard Validation.isValidEmailSyntax(config.notificationAddress),
              let id = config.selectedMailAccountID,
              let sender = config.selectedMailSenderAddress else {
            throw NSError(domain: "PunkteRetter.Mail", code: 10, userInfo: [NSLocalizedDescriptionKey: "Empfänger oder Apple-Mail-Versandkonto ist nicht vollständig eingerichtet."])
        }

        do {
            try AppleMailBridge.send(
                accountID: id,
                senderAddress: sender,
                to: config.notificationAddress,
                subject: "PunkteRetter – Testmail",
                body: "Guten Tag,\n\ndiese Testmail wurde über denselben PunkteRetter-Hintergrunddienst an Apple Mail übergeben, der später auch die automatischen Backup- und Warnmeldungen verschickt.\n\nPunkteRetter speichert dafür kein Mail-Passwort."
            )
            _ = try await configStore.update(default: AppConfiguration()) { latest in
                guard latest.notificationAddress == config.notificationAddress,
                      latest.selectedMailAccountID == id,
                      latest.selectedMailSenderAddress == sender else {
                    throw NSError(domain: "PunkteRetter.Mail", code: 11, userInfo: [NSLocalizedDescriptionKey: "Die Mail-Einstellungen wurden während des Tests geändert. Bitte den Test erneut starten."])
                }
                latest.verifiedMailSelectionFingerprint = "\(id)|\(sender)"
                latest.lastMailTestFailureReason = nil
            }
            await SafeLog.shared.write("Apple-Mail-Test über Hintergrund-Agent erfolgreich an Mail übergeben.")
        } catch {
            let failureReason = error.localizedDescription
            _ = try? await configStore.update(default: AppConfiguration()) { latest in
                if latest.selectedMailAccountID == id, latest.selectedMailSenderAddress == sender {
                    latest.verifiedMailSelectionFingerprint = nil
                    latest.lastMailTestFailureReason = failureReason
                }
            }
            await SafeLog.shared.write("Apple-Mail-Test über Hintergrund-Agent fehlgeschlagen: \(error.localizedDescription)")
            throw error
        }
    }

    private static func mailReady(_ config: AppConfiguration) -> (String, String, String)? {
        guard Validation.isValidEmailSyntax(config.notificationAddress),
              let id = config.selectedMailAccountID,
              let sender = config.selectedMailSenderAddress,
              config.verifiedMailSelectionFingerprint == "\(id)|\(sender)" else { return nil }
        return (id, sender, config.notificationAddress)
    }

    private static func sendOrRetryWeeklySuccessMail(config: AppConfiguration, items: [BackupItem], state: inout RuntimeState, week: WeekID, stateStore: AtomicJSONStore<RuntimeState>) async {
        let weekRecords = state.records.filter { $0.week == week && recordBelongsToEnabledItem($0, items: items) }
        guard !weekRecords.isEmpty else { return }

        // Pro Kalenderwoche maximal eine zusammenfassende Erfolgsmail. Wenn eine Quelle
        // später ergänzt wird, erzeugt das ein neues Backup, aber keine Mail-Doppelung.
        guard !state.records.contains(where: { $0.week == week && $0.successMailState == .handedToMail }) else { return }
        guard let mail = mailReady(config) else { return }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let names = items.map { item -> String in
            let record = weekRecords
                .filter { ($0.itemID ?? AppConfiguration.legacyItemID) == item.id }
                .max { $0.createdAt < $1.createdAt }
            if item.sourceKind == .directory {
                let count = record?.fileCount ?? 0
                let noun = count == 1 ? "Datei" : "Dateien"
                let snapshot = record?.fileName ?? "unbekannter Snapshot"
                return "• Ordner „\(item.sourceDisplayName)“ → „\(snapshot)“ (\(count) \(noun))"
            }
            let snapshot = record?.fileName ?? "unbekannter Wochenstand"
            return "• Datei „\(item.sourceDisplayName)“ → „\(snapshot)“"
        }.joined(separator: "\n")
        let cloudSummary: String
        if weekRecords.allSatisfy({ $0.cloudSyncState == .confirmed }) {
            cloudSummary = "iCloud-Synchronisierung wurde für alle Sicherungen bestätigt."
        } else if weekRecords.contains(where: { $0.cloudSyncState == .failed }) {
            cloudSummary = "Mindestens eine iCloud-Synchronisierung meldet einen Fehler; die lokalen Kopien wurden dennoch bytegenau geprüft."
        } else {
            cloudSummary = "Alle lokalen Kopien wurden geprüft; mindestens ein iCloud-Status ist noch ausstehend oder nicht abschließend überprüfbar."
        }

        let latest = weekRecords.map(\.createdAt).max() ?? Date()
        let subject = "PunkteRetter: \(items.count) von \(items.count) Backup-Aufträgen für \(week.description) gesichert"
        let body = "Guten Tag,\n\nPunkteRetter hat alle eingerichteten Dateien und Ordner für \(week.description) gesichert.\n\n\(names)\n\nAbschluss: \(formatter.string(from: latest))\nKalenderwoche: \(week.description)\nIntegritätsprüfung: bestanden (jede normale Datei wurde per SHA-256 geprüft)\n\(cloudSummary)\n\nHinweis: Die Nachricht wurde Apple Mail zum Versand übergeben. Eine Zustellung durch den Mailserver kann PunkteRetter nicht garantieren."

        do {
            try AppleMailBridge.send(accountID: mail.0, senderAddress: mail.1, to: mail.2, subject: subject, body: body)
            markWeeklyMail(state: &state, week: week, items: items, delivery: .handedToMail)
            try? await stateStore.save(state)
        } catch {
            markWeeklyMail(state: &state, week: week, items: items, delivery: .failed)
            await SafeLog.shared.write("Erfolgsmail konnte nicht an Apple Mail übergeben werden: \(error.localizedDescription)")
            try? await stateStore.save(state)
        }
    }

    private static func markWeeklyMail(state: inout RuntimeState, week: WeekID, items: [BackupItem], delivery: MailDeliveryState) {
        for index in state.records.indices where state.records[index].week == week && recordBelongsToEnabledItem(state.records[index], items: items) {
            state.records[index].successMailState = delivery
        }
    }

    private static func recordBelongsToEnabledItem(_ record: BackupRecord, items: [BackupItem]) -> Bool {
        let id = record.itemID ?? AppConfiguration.legacyItemID
        return items.contains { $0.id == id }
    }

    private static func sendWarning(config: AppConfiguration, items: [BackupItem], state: inout RuntimeState, week: WeekID, now: Date, stateStore: AtomicJSONStore<RuntimeState>) async {
        guard let mail = mailReady(config) else { return }
        let missing = items.filter { !state.isSecured(itemID: $0.id, week: week) }
        guard !missing.isEmpty else { return }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let referenceDate = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            weekday: 2,
            weekOfYear: week.weekOfYear,
            yearForWeekOfYear: week.yearForWeekOfYear
        )) ?? now
        let warningTime = Schedule.warningCheck(forWeekContaining: referenceDate, calendar: calendar) ?? now
        let late = now > warningTime.addingTimeInterval(5 * 60)
        let noun = missing.count == 1 ? "Backup-Auftrag" : "Backup-Aufträge"
        let subject = late
            ? "PunkteRetter: verspätete Warnung – \(missing.count) \(noun) für \(week.description) fehlt"
            : "PunkteRetter: \(missing.count) \(noun) für \(week.description) fehlt"
        let names = missing.map {
            "• \($0.sourceKind == .directory ? "Ordner" : "Datei") „\($0.sourceDisplayName)“"
        }.joined(separator: "\n")
        let reason = state.lastFailureReason.map { "Bekannte Ursache: \($0)" } ?? "Die genaue Ursache ist nicht bekannt."
        let body = "Guten Tag,\n\nfür \(week.description) fehlen noch folgende Backup-Aufträge:\n\n\(names)\n\n\(reason)\n\nBitte öffne PunkteRetter und wähle „Backup jetzt erstellen“.\n\n\(late ? "Diese Warnung ist verspätet, weil PunkteRetter zum vorgesehenen Warnzeitpunkt nicht erfolgreich ausführen oder versenden konnte." : "")\n\nHinweis: Die Nachricht wurde Apple Mail zum Versand übergeben. Die tatsächliche Serverzustellung kann PunkteRetter nicht garantieren."

        do {
            try AppleMailBridge.send(accountID: mail.0, senderAddress: mail.1, to: mail.2, subject: subject, body: body)
            state.warningSentWeek = week
            state.warningQueuedWeek = nil
            try? await stateStore.save(state)
        } catch {
            state.warningQueuedWeek = week
            await SafeLog.shared.write("Warnmail konnte nicht an Apple Mail übergeben werden: \(error.localizedDescription)")
            try? await stateStore.save(state)
        }
    }

    private static func cleanup(config: AppConfiguration, state: inout RuntimeState, stateStore: AtomicJSONStore<RuntimeState>) async {
        let items = config.effectiveBackupItems
        var ownedAndValid: [BackupRecord] = []

        // Nur tatsächlich vorhandene, unveränderte und eindeutig registrierte
        // Stände zählen zur 26er-Grenze. Fremde oder beschädigte Einträge dürfen
        // weder gelöscht werden noch einen gültigen alten Stand aus der Auswahl drängen.
        for record in state.records {
            let itemID = record.itemID ?? AppConfiguration.legacyItemID
            let currentBookmark = items.first(where: { $0.id == itemID })?.destinationBookmark
            guard let bookmark = currentBookmark ?? record.destinationBookmark else { continue }
            do {
                let resolved = try Bookmarking.resolveRefreshingIfNeeded(bookmark)
                let destination = resolved.url
                let access = destination.startAccessingSecurityScopedResource()
                defer { if access { destination.stopAccessingSecurityScopedResource() } }
                let candidate = destination.appendingPathComponent(record.fileName)
                guard candidate.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == destination.resolvingSymlinksInPath().standardizedFileURL,
                      FileManager.default.fileExists(atPath: candidate.path),
                      ManagedBackupOwnership.isSafeToDelete(record: record, at: candidate) else { continue }
                ownedAndValid.append(record)
            } catch {
                await SafeLog.shared.write("Aufbewahrungsprüfung für „\(record.fileName)“ nicht möglich: \(error.localizedDescription)")
            }
        }

        let ownedIDs = Set(ownedAndValid.map(\.id))
        let toDelete = Retention.safeDeletionCandidates(state.records, keep: 26) { ownedIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        var deletedIDs = Set<UUID>()

        for record in toDelete {
            let itemID = record.itemID ?? AppConfiguration.legacyItemID
            let currentBookmark = items.first(where: { $0.id == itemID })?.destinationBookmark
            guard let destinationBookmark = currentBookmark ?? record.destinationBookmark else {
                // Bei sehr alten, inzwischen umkonfigurierten V1-Ständen lieber nichts löschen.
                continue
            }

            do {
                let dest = try Bookmarking.resolveRefreshingIfNeeded(destinationBookmark).url
                let access = dest.startAccessingSecurityScopedResource()
                defer { if access { dest.stopAccessingSecurityScopedResource() } }

                let file = dest.appendingPathComponent(record.fileName)
                guard file.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == dest.resolvingSymlinksInPath().standardizedFileURL else { continue }

                if FileManager.default.fileExists(atPath: file.path) {
                    guard ManagedBackupOwnership.isSafeToDelete(record: record, at: file) else {
                        await SafeLog.shared.write("Aufbewahrung übersprungen: Der registrierte Stand „\(record.fileName)“ ist beschädigt, verändert oder nicht eindeutig PunkteRetter zuzuordnen.")
                        continue
                    }
                    try FileManager.default.removeItem(at: file)
                    await SafeLog.shared.write("Aufbewahrung: registrierten Stand gelöscht: \(record.fileName)")
                }
                deletedIDs.insert(record.id)
            } catch {
                await SafeLog.shared.write("Aufbewahrung für \(record.fileName) übersprungen: \(error.localizedDescription)")
            }
        }

        state.records.removeAll { deletedIDs.contains($0.id) }
        try? await stateStore.save(state)
    }
}
#else
@main struct PunkteRetterAgentMain { static func main() {} }
#endif

#if os(macOS)
import SwiftUI
import AppKit
import PunkteRetterCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var config = AppConfiguration()
    @Published var state = RuntimeState()
    @Published var statusText = "Bereit"
    @Published var errorText: String? = nil
    @Published var showSetup = false
    @Published var privateTargetConfirmation = false

    private let configStore = AtomicJSONStore<AppConfiguration>(url: PunkteRetterPaths.configURL)
    private let stateStore = AtomicJSONStore<RuntimeState>(url: PunkteRetterPaths.stateURL)

    func load() async {
        do {
            config = try await configStore.load(default: AppConfiguration())
            state = try await stateStore.load(default: RuntimeState())

            var configurationChanged = try refreshStaleBookmarks()
            if config.backupItems == nil && !config.effectiveBackupItems.isEmpty {
                config.backupItems = config.effectiveBackupItems
                configurationChanged = true
            }
            if config.version < 4 {
                config.version = 4
                configurationChanged = true
            }
            if configurationChanged {
                try await configStore.save(config)
            }

            privateTargetConfirmation = config.effectiveBackupItems.first?.targetConfirmedPrivate ?? config.targetConfirmedPrivate
            reconcileCurrentWeekCompletion()
            showSetup = !config.setupCompleted
        } catch {
            errorText = "PunkteRetter konnte seine Einstellungen nicht sicher laden: \(error.localizedDescription)"
        }
    }

    func saveConfig() async {
        do { try await configStore.save(config) }
        catch { errorText = "Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)" }
    }

    func chooseSource() async {
        let panel = NSOpenPanel()
        panel.title = "Datei oder Ordner auswählen"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let sourceKind = try validateSource(url)
            let bookmark = try Bookmarking.make(for: url)
            var items = config.effectiveBackupItems

            if !items.isEmpty {
                try ensureUniqueSource(url, excluding: items[0].id)
                if config.setupCompleted { items[0].id = UUID() }
                items[0].sourceBookmark = bookmark
                items[0].sourceDisplayName = url.lastPathComponent
                items[0].sourceKind = sourceKind
                items[0].targetConfirmedPrivate = false
                try validateBackupPlan(items)
                config.backupItems = items
                state.lastSuccessfulWeek = nil
            } else {
                config.sourceBookmark = bookmark
                config.sourceDisplayName = url.lastPathComponent
                config.sourceKind = sourceKind
            }

            config.version = 4
            try await configStore.save(config)
            statusText = sourceKind == .directory ? "Ordner geprüft" : "Datei geprüft"
        } catch { errorText = error.localizedDescription }
    }

    func chooseDestination() async {
        let panel = NSOpenPanel()
        panel.title = "Privaten Backup-Ordner auswählen"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let (sourceURL, sourceKind) = try currentFirstSource()
            try validateDestination(url, forSource: sourceURL, sourceKind: sourceKind)
            let bookmark = try Bookmarking.make(for: url)
            var items = config.effectiveBackupItems

            if !items.isEmpty {
                if config.setupCompleted { items[0].id = UUID() }
                items[0].destinationBookmark = bookmark
                items[0].destinationDisplayName = url.lastPathComponent
                items[0].targetConfirmedPrivate = false
                state.lastSuccessfulWeek = nil
            } else {
                guard let sourceBookmark = config.sourceBookmark else { throw appError(30, "Bitte zuerst eine Datei oder einen Ordner auswählen.") }
                let newItem = BackupItem(
                    sourceBookmark: sourceBookmark,
                    sourceDisplayName: config.sourceDisplayName ?? sourceURL.lastPathComponent,
                    sourceKind: sourceKind,
                    destinationBookmark: bookmark,
                    destinationDisplayName: url.lastPathComponent,
                    targetConfirmedPrivate: false
                )
                items = [newItem]
            }
            try validateBackupPlan(items)
            config.backupItems = items

            config.destinationBookmark = bookmark
            config.destinationDisplayName = url.lastPathComponent
            config.targetConfirmedPrivate = false
            privateTargetConfirmation = false
            config.version = 4
            try await configStore.save(config)
            statusText = "Backup-Ziel geprüft"
        } catch { errorText = error.localizedDescription }
    }

    func addBackupSource() async {
        let sourcePanel = NSOpenPanel()
        sourcePanel.title = "Weitere Datei oder weiteren Ordner auswählen"
        sourcePanel.canChooseDirectories = true
        sourcePanel.canChooseFiles = true
        sourcePanel.allowsMultipleSelection = false
        guard sourcePanel.runModal() == .OK, let source = sourcePanel.url else { return }

        let sourceKind: BackupSourceKind
        do {
            sourceKind = try validateSource(source)
            try ensureUniqueSource(source)
        } catch {
            errorText = error.localizedDescription
            return
        }

        let targetPanel = NSOpenPanel()
        targetPanel.title = "Backup-Ordner für \(source.lastPathComponent) auswählen"
        targetPanel.canChooseDirectories = true
        targetPanel.canChooseFiles = false
        targetPanel.canCreateDirectories = true

        if let first = config.effectiveBackupItems.first,
           let (existing, stale) = try? Bookmarking.resolve(first.destinationBookmark),
           !stale {
            targetPanel.directoryURL = existing
        }

        guard targetPanel.runModal() == .OK, let target = targetPanel.url else { return }

        do {
            try validateDestination(target, forSource: source, sourceKind: sourceKind)
            guard confirmPrivateTarget(named: target.lastPathComponent) else { return }

            let item = BackupItem(
                sourceBookmark: try Bookmarking.make(for: source),
                sourceDisplayName: source.lastPathComponent,
                sourceKind: sourceKind,
                destinationBookmark: try Bookmarking.make(for: target),
                destinationDisplayName: target.lastPathComponent,
                targetConfirmedPrivate: true
            )

            var items = config.effectiveBackupItems
            items.append(item)
            try validateBackupPlan(items)
            config.backupItems = items
            config.version = 4
            state.lastSuccessfulWeek = nil

            try await configStore.save(config)
            statusText = "\(sourceKind == .directory ? "Ordner" : "Datei") „\(source.lastPathComponent)“ wurde hinzugefügt"
        } catch { errorText = error.localizedDescription }
    }

    func removeBackupItem(_ id: UUID) async {
        var items = config.effectiveBackupItems
        guard items.count > 1 else {
            errorText = "Mindestens eine Sicherungsquelle muss eingerichtet bleiben."
            return
        }
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard confirmRemoval(named: item.sourceDisplayName) else { return }

        items.removeAll { $0.id == id }
        config.backupItems = items
        reconcileCurrentWeekCompletion()

        do {
            try await configStore.save(config)
            statusText = "Sicherungsauftrag entfernt – vorhandene Backups bleiben erhalten"
        } catch { errorText = error.localizedDescription }
    }

    func changeSource(for id: UUID) async {
        guard let index = config.effectiveBackupItems.firstIndex(where: { $0.id == id }) else { return }
        let oldItem = config.effectiveBackupItems[index]

        let panel = NSOpenPanel()
        panel.title = "Datei oder Ordner ändern"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let sourceKind = try validateSource(url)
            try ensureUniqueSource(url, excluding: id)
            let (target, stale) = try Bookmarking.resolve(oldItem.destinationBookmark)
            guard !stale else { throw appError(31, "Der bisherige Backup-Ordner wurde verschoben. Bitte zuerst das Ziel neu auswählen.") }
            try validateDestination(target, forSource: url, sourceKind: sourceKind)
            guard confirmPrivateTarget(named: target.lastPathComponent) else { return }

            var items = config.effectiveBackupItems
            items[index].id = UUID()
            items[index].sourceBookmark = try Bookmarking.make(for: url)
            items[index].sourceDisplayName = url.lastPathComponent
            items[index].sourceKind = sourceKind
            items[index].targetConfirmedPrivate = true
            try validateBackupPlan(items)
            config.backupItems = items
            state.lastSuccessfulWeek = nil

            try await configStore.save(config)
            statusText = "Quelle geändert – für diese Woche ist ein neues Backup fällig"
        } catch { errorText = error.localizedDescription }
    }

    func changeDestination(for id: UUID) async {
        guard let index = config.effectiveBackupItems.firstIndex(where: { $0.id == id }) else { return }
        let item = config.effectiveBackupItems[index]

        do {
            let (source, stale) = try Bookmarking.resolve(item.sourceBookmark)
            guard !stale else { throw appError(31, "Die Quelle wurde verschoben. Bitte zuerst die Datei oder den Ordner neu auswählen.") }

            let panel = NSOpenPanel()
            panel.title = "Backup-Ordner ändern"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let target = panel.url else { return }

            try validateDestination(target, forSource: source, sourceKind: item.sourceKind)
            guard confirmPrivateTarget(named: target.lastPathComponent) else { return }

            var items = config.effectiveBackupItems
            items[index].id = UUID()
            items[index].destinationBookmark = try Bookmarking.make(for: target)
            items[index].destinationDisplayName = target.lastPathComponent
            items[index].targetConfirmedPrivate = true
            try validateBackupPlan(items)
            config.backupItems = items
            state.lastSuccessfulWeek = nil

            try await configStore.save(config)
            statusText = "Backup-Ziel geändert – für diese Woche ist ein neues Backup fällig"
        } catch { errorText = error.localizedDescription }
    }

    func completeSetup() async {
        guard !config.effectiveBackupItems.isEmpty else {
            errorText = "Bitte eine Datei oder einen Ordner und den privaten Backup-Ordner vollständig einrichten."
            return
        }
        guard privateTargetConfirmation else {
            errorText = "Bitte bestätigen, dass der Backup-Ordner privat und nicht freigegeben ist."
            return
        }
        do {
            var items = config.effectiveBackupItems
            guard !items.isEmpty else { throw appError(32, "Keine Sicherungsquelle eingerichtet.") }
            items[0].targetConfirmedPrivate = true
            guard items.allSatisfy(\.targetConfirmedPrivate) else {
                throw appError(34, "Bitte alle Backup-Ziele als privat bestätigen.")
            }
            for item in items { try verify(item: item) }
            try validateBackupPlan(items)

            config.backupItems = items
            config.targetConfirmedPrivate = true
            config.setupCompleted = true
            config.automationEnabled = true
            config.version = 4
            try HelperService.register()
            do {
                try await configStore.save(config)
            } catch {
                try? HelperService.unregister()
                config.setupCompleted = false
                config.automationEnabled = false
                throw error
            }
            if HelperService.service.status == .requiresApproval {
                statusText = "Hintergrunddienst wartet auf Freigabe in den Systemeinstellungen."
                SMAppService.openSystemSettingsLoginItems()
            } else {
                statusText = "PunkteRetter ist eingerichtet"
            }
            showSetup = false
        } catch {
            errorText = "Einrichtung konnte nicht abgeschlossen werden: \(error.localizedDescription)"
        }
    }

    func toggleAutomation(_ enabled: Bool) async {
        if enabled {
            guard !config.enabledBackupItems.isEmpty else {
                errorText = "Es ist keine Sicherungsquelle eingerichtet."
                config.automationEnabled = false
                return
            }
            guard config.enabledBackupItems.allSatisfy(\.targetConfirmedPrivate) else {
                errorText = "Bitte alle Backup-Ziele als privat bestätigen, bevor die Automatik aktiviert wird."
                config.automationEnabled = false
                return
            }
        }

        config.automationEnabled = enabled
        do {
            if enabled { try HelperService.register() }
            else { try? HelperService.unregister() }
            try await configStore.save(config)
        } catch { errorText = error.localizedDescription }
    }

    func backupNow() async {
        if weekSecured {
            errorText = "Alle eingerichteten Dateien und Ordner sind diese Kalenderwoche bereits erfolgreich gesichert. Es werden keine zusätzlichen Kopien erzeugt."
            return
        }
        guard !config.enabledBackupItems.isEmpty else {
            errorText = "Es ist keine Sicherungsquelle eingerichtet."
            return
        }

        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/PunkteRetterAgent")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            errorText = "Der Hintergrund-Helper fehlt in dieser Installation."
            return
        }

        statusText = "Fehlende Backups werden erstellt …"
        do {
            let status = try await ProcessRunner.run(executableURL: helper, arguments: ["--manual"], timeout: 30 * 60)
            guard status == 0 else {
                throw appError(40, "Der Hintergrunddienst wurde mit Fehlercode \(status) beendet.")
            }
            state = try await stateStore.load(default: RuntimeState())
            statusText = weekSecured ? "Alle Quellen diese Woche gesichert" : "\(securedCount) von \(totalEnabledCount) Backup-Aufträgen gesichert"
            if !weekSecured, let reason = state.lastFailureReason { errorText = reason }
        } catch { errorText = error.localizedDescription }
    }

    func checkAllSources() {
        do {
            for item in config.enabledBackupItems {
                let (url, stale) = try Bookmarking.resolve(item.sourceBookmark)
                guard !stale else { throw appError(21, "„\(item.sourceDisplayName)“ wurde verschoben oder umbenannt. Bitte neu auswählen.") }
                let actualKind = try validateSource(url)
                guard actualKind == item.sourceKind else {
                    throw appError(22, "Der Typ von „\(item.sourceDisplayName)“ hat sich geändert. Bitte die Quelle neu auswählen.")
                }
            }
            statusText = "Alle Dateien und Ordner sind erreichbar"
        } catch { errorText = error.localizedDescription }
    }

    func checkAllDestinations() {
        do {
            for item in config.enabledBackupItems {
                let (source, sourceStale) = try Bookmarking.resolve(item.sourceBookmark)
                let (target, targetStale) = try Bookmarking.resolve(item.destinationBookmark)
                guard !sourceStale, !targetStale else { throw appError(23, "Quelle oder Backup-Ziel wurde verschoben.") }
                try validateDestination(target, forSource: source, sourceKind: item.sourceKind)
            }
            statusText = "Alle Backup-Ziele sind erreichbar und beschreibbar"
        } catch { errorText = error.localizedDescription }
    }

    func setQuietMode(until: Date?) async {
        config.quietModeUntil = until
        await saveConfig()
    }

    func uninstall() async {
        guard let uninstallLock = ExclusiveProcessLock(url: PunkteRetterPaths.supportDirectory().appendingPathComponent("agent.lock")) else {
            errorText = "PunkteRetter führt gerade ein Backup aus. Bitte warte, bis dieser Vorgang beendet ist, und starte die Deinstallation danach erneut."
            return
        }
        defer { _ = uninstallLock }

        do {
            try HelperService.unregister()
            _ = try FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
            let support = PunkteRetterPaths.supportDirectory()
            if FileManager.default.fileExists(atPath: support.path) {
                try FileManager.default.removeItem(at: support)
            }
            NSApp.terminate(nil)
        } catch {
            errorText = "PunkteRetter konnte nicht vollständig deinstalliert werden. Es wurden keine Quelldateien und keine Backups gelöscht: \(error.localizedDescription)"
        }
    }

    var totalEnabledCount: Int { config.enabledBackupItems.count }

    var securedCount: Int {
        let week = Schedule.isoWeek(for: Date())
        return state.securedCount(itemIDs: config.enabledBackupItems.map(\.id), week: week)
    }

    var weekSecured: Bool {
        totalEnabledCount > 0 && securedCount == totalEnabledCount
    }

    var nextAttempt: Date? {
        Schedule.nextRegularSlot(
            after: Date(),
            lastSuccessfulWeek: weekSecured ? Schedule.isoWeek(for: Date()) : nil,
            automationEnabled: config.automationEnabled
        )
    }

    func isSecured(_ item: BackupItem) -> Bool {
        state.isSecured(itemID: item.id, week: Schedule.isoWeek(for: Date()))
    }

    func failureReason(for item: BackupItem) -> String? {
        state.failureReason(itemID: item.id)
    }

    private func reconcileCurrentWeekCompletion() {
        let items = config.enabledBackupItems
        let current = Schedule.isoWeek(for: Date())
        if !items.isEmpty && items.allSatisfy({ state.isSecured(itemID: $0.id, week: current) }) {
            state.lastSuccessfulWeek = current
        } else if state.lastSuccessfulWeek == current {
            state.lastSuccessfulWeek = nil
        }
    }

    private func currentFirstSource() throws -> (URL, BackupSourceKind) {
        if let first = config.effectiveBackupItems.first {
            let (url, stale) = try Bookmarking.resolve(first.sourceBookmark)
            guard !stale else { throw appError(33, "Die gewählte Datei oder der Ordner wurde verschoben. Bitte erneut auswählen.") }
            return (url, first.sourceKind)
        }
        guard let bookmark = config.sourceBookmark else { throw appError(30, "Bitte zuerst eine Datei oder einen Ordner auswählen.") }
        let (url, stale) = try Bookmarking.resolve(bookmark)
        guard !stale else { throw appError(33, "Die gewählte Datei oder der Ordner wurde verschoben. Bitte erneut auswählen.") }
        return (url, config.sourceKind ?? .file)
    }

    private func refreshStaleBookmarks() throws -> Bool {
        var items = config.effectiveBackupItems
        var changed = config.backupItems == nil && !items.isEmpty
        if items.isEmpty, config.backupItems == nil {
            if let bookmark = config.sourceBookmark {
                let source = try Bookmarking.resolveRefreshingIfNeeded(bookmark)
                if let renewed = source.refreshedBookmark {
                    config.sourceBookmark = renewed
                    config.sourceDisplayName = source.url.lastPathComponent
                    changed = true
                }
            }
            if let bookmark = config.destinationBookmark {
                let destination = try Bookmarking.resolveRefreshingIfNeeded(bookmark)
                if let renewed = destination.refreshedBookmark {
                    config.destinationBookmark = renewed
                    config.destinationDisplayName = destination.url.lastPathComponent
                    changed = true
                }
            }
        }
        for index in items.indices {
            let source = try Bookmarking.resolveRefreshingIfNeeded(items[index].sourceBookmark)
            if let bookmark = source.refreshedBookmark {
                items[index].sourceBookmark = bookmark
                items[index].sourceDisplayName = source.url.lastPathComponent
                changed = true
            }
            let destination = try Bookmarking.resolveRefreshingIfNeeded(items[index].destinationBookmark)
            if let bookmark = destination.refreshedBookmark {
                items[index].destinationBookmark = bookmark
                items[index].destinationDisplayName = destination.url.lastPathComponent
                changed = true
            }
        }
        if changed {
            config.backupItems = items
            config.version = max(config.version, 4)
            if items.count == 1, items[0].id == AppConfiguration.legacyItemID {
                config.sourceBookmark = items[0].sourceBookmark
                config.destinationBookmark = items[0].destinationBookmark
                config.sourceDisplayName = items[0].sourceDisplayName
                config.destinationDisplayName = items[0].destinationDisplayName
                config.sourceKind = items[0].sourceKind
            }
        }
        return changed
    }

    private func verify(item: BackupItem) throws {
        let (source, sourceStale) = try Bookmarking.resolve(item.sourceBookmark)
        let (target, targetStale) = try Bookmarking.resolve(item.destinationBookmark)
        guard !sourceStale, !targetStale else { throw appError(2, "Quelle oder Ziel wurde verschoben. Bitte erneut auswählen.") }
        let actualKind = try validateSource(source)
        guard actualKind == item.sourceKind else {
            throw appError(22, "Der Typ von „\(item.sourceDisplayName)“ hat sich geändert. Bitte die Quelle neu auswählen.")
        }
        try validateDestination(target, forSource: source, sourceKind: item.sourceKind)
    }

    private func validateSource(_ url: URL) throws -> BackupSourceKind {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw appError(3, "Die ausgewählte Datei oder der Ordner ist nicht erreichbar.")
        }
        guard values.isSymbolicLink != true else {
            throw appError(3, "Verknüpfungen können nicht als Sicherungsquelle verwendet werden. Bitte die echte Datei oder den echten Ordner auswählen.")
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw appError(4, "Die ausgewählte Datei oder der Ordner ist nicht lesbar.")
        }
        if values.isDirectory == true { return .directory }
        if values.isRegularFile == true {
            let name = url.lastPathComponent
            guard !name.hasPrefix("~$"), name != ".DS_Store", name != ".localized", !name.hasPrefix("._") else {
                throw appError(36, "Temporäre Office- und macOS-Metadateien können nicht als Sicherungsquelle gewählt werden.")
            }
            return .file
        }
        throw appError(3, "Die ausgewählte Quelle ist weder eine normale Datei noch ein normaler Ordner.")
    }

    private func ensureUniqueSource(_ url: URL, excluding excludedID: UUID? = nil) throws {
        let candidate = url.standardizedFileURL
        for item in config.effectiveBackupItems where item.id != excludedID {
            guard let (existing, stale) = try? Bookmarking.resolve(item.sourceBookmark), !stale else { continue }
            if existing.standardizedFileURL == candidate {
                throw appError(35, "Diese Datei oder dieser Ordner ist bereits als Sicherungsquelle eingerichtet.")
            }
        }
    }

    private func validateBackupPlan(_ items: [BackupItem]) throws {
        var locations: [BackupPlanLocation] = []
        for item in items {
            let (source, sourceStale) = try Bookmarking.resolve(item.sourceBookmark)
            let (destination, destinationStale) = try Bookmarking.resolve(item.destinationBookmark)
            guard !sourceStale, !destinationStale else {
                throw appError(37, "Mindestens eine Quelle oder ein Backup-Ziel wurde verschoben. Bitte den betroffenen Auftrag neu auswählen.")
            }
            locations.append(BackupPlanLocation(
                itemID: item.id,
                source: source,
                sourceKind: item.sourceKind,
                destination: destination
            ))
        }

        do {
            try BackupPlanSafety.validateNoDestinationInsideDirectorySource(locations)
        } catch SnapshotEngineError.destinationInsideSource {
            throw appError(38, "Ein Backup-Ziel liegt innerhalb eines eingerichteten Quellordners. Diese Kombination würde Backups in spätere Backups hinein kopieren und ist deshalb nicht erlaubt.")
        }
    }

    private func validateDestination(_ url: URL, forSource source: URL, sourceKind: BackupSourceKind) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw appError(5, "Der Backup-Ordner ist nicht erreichbar.")
        }

        do {
            try VerifiedSnapshotEngine.validateLocations(source: source, destination: url, sourceKind: sourceKind)
        } catch SnapshotEngineError.destinationInsideSource {
            let message = sourceKind == .directory
                ? "Der Backup-Ordner darf nicht im ausgewählten Quellordner oder darunter liegen."
                : "Der Backup-Ordner darf nicht in derselben Quellablage oder darunter liegen."
            throw appError(6, message)
        } catch {
            throw appError(6, error.localizedDescription)
        }

        let cloudValues = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard cloudValues?.isUbiquitousItem == true else {
            throw appError(8, "Der gewählte Backup-Ordner wird von macOS nicht als iCloud-Speicher erkannt. Bitte einen Ordner in iCloud Drive wählen.")
        }

        let test = url.appendingPathComponent(".punkteretter-write-test-\(UUID().uuidString)")
        do {
            try Data("test".utf8).write(to: test, options: .atomic)
            try FileManager.default.removeItem(at: test)
        } catch {
            throw appError(7, "In den Backup-Ordner kann nicht sicher geschrieben werden.")
        }
    }

    private func confirmPrivateTarget(named name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Privater Backup-Ordner?"
        alert.informativeText = "Bitte bestätige, dass „\(name)“ in deinem privaten iCloud Drive liegt und nicht mit anderen geteilt ist."
        alert.addButton(withTitle: "Ja, privat")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmRemoval(named name: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Sicherungsauftrag entfernen?"
        alert.informativeText = "„\(name)“ wird aus PunkteRetter entfernt. Bereits erstellte Backups werden nicht gelöscht."
        alert.addButton(withTitle: "Entfernen")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func appError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "PunkteRetter", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif

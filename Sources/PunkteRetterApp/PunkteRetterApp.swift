#if os(macOS)
import SwiftUI
import PunkteRetterCore

private enum AppVersionInfo {
    static var display: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "Version \(version) (Build \(build))"
    }
}

@main
struct PunkteRetterApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("PunkteRetter") {
            RootView().environmentObject(model).task { await model.load() }
                .frame(minWidth: 780, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        Settings { SettingsView().environmentObject(model).frame(width: 720, height: 650) }
    }
}

private struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.95, blue: 0.88).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "folder.badge.checkmark").font(.system(size: 34)).foregroundStyle(.teal)
                    VStack(alignment: .leading) {
                        Text("PunkteRetter").font(.system(size: 30, weight: .bold))
                        Text("Deine wichtigen Dateien und Ordner – ruhig im Hintergrund gesichert.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Einstellungen") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                }

                statusCard

                HStack(spacing: 16) {
                    infoCard("Letztes Backup", model.state.records.last.map { $0.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? "Noch keines", "clock.arrow.circlepath")
                    infoCard("Nächster Versuch", model.nextAttempt?.formatted(date: .abbreviated, time: .shortened) ?? "Automatik aus", "calendar.badge.clock")
                    infoCard("E-Mail", model.config.selectedMailAccountDisplayName ?? "Nicht eingerichtet", "envelope")
                }

                backupList

                Button(action: { Task { await model.backupNow() } }) {
                    Label("Fehlende Backups jetzt erstellen", systemImage: "arrow.clockwise.circle.fill")
                        .font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.89, green: 0.36, blue: 0.28))
                .disabled(model.weekSecured || model.totalEnabledCount == 0)

                HStack {
                    Text(model.statusText).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(AppVersionInfo.display).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28)
        }
        .sheet(isPresented: $model.showSetup) { SetupView().environmentObject(model).interactiveDismissDisabled() }
        .alert("PunkteRetter", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) { Button("OK") { model.errorText = nil } } message: { Text(model.errorText ?? "") }
    }

    private var statusCard: some View {
        HStack(spacing: 18) {
            Image(systemName: model.weekSecured ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 44)).foregroundStyle(model.weekSecured ? .teal : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.weekSecured ? "Alle Quellen diese Woche gesichert" : "\(model.securedCount) von \(model.totalEnabledCount) Backup-Aufträgen gesichert")
                    .font(.title2.bold())
                Text(model.config.automationEnabled ? "Die Automatik ist aktiv." : "Die Automatik ist ausgeschaltet.").foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(20).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
    }

    private var backupList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dateien und Ordner").font(.headline)
                Spacer()
                Text("\(model.totalEnabledCount) eingerichtet").font(.callout).foregroundStyle(.secondary)
            }
            if model.config.enabledBackupItems.isEmpty {
                Text("Noch keine Datei oder kein Ordner eingerichtet.").foregroundStyle(.secondary)
            } else {
                ForEach(model.config.enabledBackupItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.sourceKind == .directory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.sourceDisplayName).fontWeight(.medium).lineLimit(1)
                            Text("→ \(item.destinationDisplayName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let reason = model.failureReason(for: item) {
                                Text(reason).font(.caption).foregroundStyle(.red).lineLimit(2)
                            }
                        }
                        Spacer()
                        Image(systemName: model.isSecured(item) ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(model.isSecured(item) ? .teal : .orange)
                        Text(model.isSecured(item) ? "gesichert" : "offen").font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    }

    private func infoCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.teal)
            Text(value).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 92).background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SetupView: View {
    @EnvironmentObject var model: AppModel

    private var mailVerified: Bool {
        guard let id = model.config.selectedMailAccountID,
              let sender = model.config.selectedMailSenderAddress else { return false }
        return model.config.verifiedMailSelectionFingerprint == "\(id)|\(sender)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("PunkteRetter einrichten").font(.largeTitle.bold())
                Spacer()
                Text(AppVersionInfo.display).font(.caption).foregroundStyle(.secondary)
            }
            Text("Vier Dinge braucht PunkteRetter. Weitere Dateien und Ordner kannst du danach jederzeit hinzufügen.").foregroundStyle(.secondary)
            GroupBox("1. Benachrichtigungsadresse") {
                TextField("z. B. name@example.invalid", text: $model.config.notificationAddress).textFieldStyle(.roundedBorder).padding(.vertical, 4)
            }
            GroupBox("2. Versandkonto aus Apple Mail") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("macOS wird einmal fragen, ob PunkteRetter Apple Mail steuern darf. So muss PunkteRetter kein Mail-Passwort speichern.").font(.callout)
                    HStack {
                        Button("Apple-Mail-Konten prüfen") { model.refreshAccounts() }
                        if !model.accounts.isEmpty {
                            Picker("Versandkonto", selection: Binding(get: { ((model.config.selectedMailAccountID ?? "") + "|" + (model.config.selectedMailSenderAddress ?? "").lowercased()) }, set: { selected in if let account = model.accounts.first(where: { $0.id == selected }) { model.selectMailAccount(account) } })) {
                                ForEach(model.accounts) { account in Text("\(account.displayName) – \(account.senderAddress)").tag(account.id) }
                            }.frame(maxWidth: 380)
                        }
                        Button("Testmail senden") {
                            Task { _ = await model.testMail() }
                        }
                        .disabled(model.config.selectedMailAccountID == nil || model.mailTestInProgress)
                    }
                    if model.mailTestInProgress {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Testmail wird an Apple Mail übergeben …")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    } else if mailVerified {
                        Label("Testmail erfolgreich an Apple Mail zum Versand übergeben.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }.padding(.vertical, 4)
            }
            GroupBox("3. Erste Datei oder erster Ordner") {
                HStack {
                    if let kind = model.config.effectiveBackupItems.first?.sourceKind ?? model.config.sourceKind {
                        Image(systemName: kind == .directory ? "folder.fill" : "doc.fill").foregroundStyle(.teal)
                    }
                    Text(model.config.effectiveBackupItems.first?.sourceDisplayName ?? model.config.sourceDisplayName ?? "Noch nicht ausgewählt")
                    Spacer()
                    Button("Datei oder Ordner auswählen …") { Task { await model.chooseSource() } }
                }.padding(.vertical, 4)
            }
            GroupBox("4. Privater Backup-Ordner") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(model.config.effectiveBackupItems.first?.destinationDisplayName ?? model.config.destinationDisplayName ?? "Noch nicht ausgewählt"); Spacer(); Button("Ordner auswählen …") { Task { await model.chooseDestination() } } }
                    Toggle("Ich bestätige: Dieser Backup-Ordner ist privat und nicht mit anderen geteilt.", isOn: $model.privateTargetConfirmation)
                }.padding(.vertical, 4)
            }
            HStack {
                Button("PunkteRetter beenden") { NSApp.terminate(nil) }
                Spacer()
                Button("Einrichtung abschließen") { Task { await model.completeSetup() } }.buttonStyle(.borderedProminent).disabled(!mailVerified || model.mailTestInProgress)
            }
        }.padding(28).frame(width: 720, height: 690)
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var quietDate = Date().addingTimeInterval(7 * 86400)
    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Version", value: AppVersionInfo.display)
                LabeledContent("Diese Woche", value: model.weekSecured ? "alle gesichert" : "\(model.securedCount) von \(model.totalEnabledCount) gesichert")
                LabeledContent("Letztes Backup", value: model.state.records.last?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? "–")
                LabeledContent("Nächster Versuch", value: model.nextAttempt?.formatted(date: .abbreviated, time: .shortened) ?? "–")
            }

            Section("Dateien und Ordner") {
                ForEach(model.config.effectiveBackupItems) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: item.sourceKind == .directory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(model.isSecured(item) ? .teal : .secondary)
                            Text(item.sourceDisplayName).fontWeight(.semibold)
                            Spacer()
                            Text(model.isSecured(item) ? "diese Woche gesichert" : "noch offen").font(.caption).foregroundStyle(.secondary)
                        }
                        if let reason = model.failureReason(for: item) {
                            Text(reason).font(.caption).foregroundStyle(.red).lineLimit(3)
                        }
                        HStack {
                            Text("Ziel: \(item.destinationDisplayName)").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Quelle ändern …") { Task { await model.changeSource(for: item.id) } }
                            Button("Ziel ändern …") { Task { await model.changeDestination(for: item.id) } }
                            Button("Entfernen", role: .destructive) { Task { await model.removeBackupItem(item.id) } }
                        }
                    }.padding(.vertical, 4)
                }
                HStack {
                    Button("+ Datei oder Ordner hinzufügen") { Task { await model.addBackupSource() } }.buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Alle Quellen prüfen") { model.checkAllSources() }
                    Button("Alle Ziele prüfen") { model.checkAllDestinations() }
                }
            }

            Section("E-Mail") {
                TextField("Benachrichtigungsadresse", text: $model.config.notificationAddress)
                HStack {
                    Button("Konten laden") { model.refreshAccounts() }
                    if !model.accounts.isEmpty {
                        Picker("Versandkonto", selection: Binding(get: { ((model.config.selectedMailAccountID ?? "") + "|" + (model.config.selectedMailSenderAddress ?? "").lowercased()) }, set: { selected in if let account = model.accounts.first(where: { $0.id == selected }) { model.selectMailAccount(account) } })) {
                            ForEach(model.accounts) { account in Text("\(account.displayName) – \(account.senderAddress)").tag(account.id) }
                        }
                    }
                }
                HStack {
                    Button("Versandkonto prüfen") { model.checkMailAccount() }
                    Button("Testmail senden") { Task { _ = await model.testMail() } }
                        .disabled(model.mailTestInProgress)
                    if model.mailTestInProgress { ProgressView().controlSize(.small) }
                }
            }

            Section("Automatik") {
                Toggle("Automatik aktiv", isOn: Binding(get: { model.config.automationEnabled }, set: { value in Task { await model.toggleAutomation(value) } }))
                HStack { DatePicker("Ruhemodus bis", selection: $quietDate, displayedComponents: .date); Button("Aktivieren") { Task { await model.setQuietMode(until: quietDate) } }; Button("Beenden") { Task { await model.setQuietMode(until: nil) } } }
            }

            Section("Aktionen") {
                HStack { Button("Fehlende Backups jetzt erstellen") { Task { await model.backupNow() } }; Button("Einstellungen speichern") { Task { await model.saveConfig() } } }
                Button("PunkteRetter deinstallieren …", role: .destructive) { Task { await model.uninstall() } }
            }
        }.padding(20)
    }
}
#else
@main struct PunkteRetterApp { static func main() {} }
#endif

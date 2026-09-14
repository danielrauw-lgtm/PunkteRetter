# PunkteRetter 1.2 – technischer Prüfbericht

Stand: 2026-09-14

Version `1.2.0`, Build `123`, Paketversion `1.2.0.123`.

Build 123 wurde gegenüber Build 122 notwendig, weil zwei funktionale Korrekturen vorgenommen wurden: Der Ruhemodus pausiert nun tatsächlich automatische Backup-Versuche, und eine fällige Donnerstag-Warnung bleibt über den ISO-Wochenwechsel hinweg fällig. Zusätzlich werden App und Agent auch im ad-hoc Test-Build ausdrücklich mit Apple-Events-Entitlement und Hardened Runtime signiert und kontrolliert.

Der Stand verbleibt auf `punkte-retter-1.2-folder-snapshots`. Er wurde weder nach `main` gemergt noch getaggt oder als GitHub Release veröffentlicht.

## A. Geprüft und bestanden

- Der vollständige Quellbestand wurde auf Architektur, Datenflüsse, Fehlerbehandlung, Löschpfade, Migration, Bookmarks, Agent/App-Zusammenspiel, Wochenlogik, Mailübergabe, Build und Installer geprüft.
- Lokale statische Prüfung: 36 Repository-Dateien, Shell-Syntax, YAML, drei Plists, zwei Installer-HTML-Dateien, Dateimodi, Versionswerte sowie Suche nach Konfliktmarkern, eingebetteten Zugangsdaten, Telemetrie und Netzwerk-Uploads.
- `swift test`: 74 eindeutige Tests ohne Fehler im gültigen finalen CI-Lauf. Auf dem Apple-Silicon-Runner wird die Suite einmal direkt und ein zweites Mal im Release-Script ausgeführt; zusätzlich läuft sie nativ auf dem Intel-Runner.
- `swift build -c release`: App und Agent wurden auf Apple Silicon und nativ auf Intel kompiliert.
- `Scripts/build-release.command`: Universal-Build, App-Bundle und PKG wurden ohne übersprungene kritische Schritte erzeugt.
- App und Agent enthalten nach `lipo -info` jeweils tatsächlich `arm64` und `x86_64`.
- App und Agent bestehen die strukturelle `codesign`-Prüfung; beide enthalten im Test-Build Hardened Runtime und `com.apple.security.automation.apple-events`.
- Das PKG enthält die App direkt für `install-location="/Applications"`, Paketversion `1.2.0.123`, keine doppelte `Applications`-Ebene und die vorgesehenen Installertexte.
- Das erzeugte PKG wurde im CI tatsächlich mit `sudo installer -pkg … -target /` installiert. Danach waren `/Applications/PunkteRetter.app`, Hauptbinary, Agent und LaunchAgent am erwarteten Ort vorhanden und ausführbar.
- Version `1.2.0`, Build `123`, App-ID `de.punkteretter.app`, Package-ID `de.punkteretter.pkg`, Agent-Label und `BundleProgram` wurden am installierten Ergebnis geprüft.
- Eine vor der Installation angelegte Testdatei unter `~/Library/Application Support/PunkteRetter` blieb beim Installer-Upgrade bytegleich erhalten.
- Das veröffentlichte Actions-Artefakt wurde zusätzlich als ZIP vollständig getestet; sein lokaler SHA-256 muss mit dem von GitHub gemeldeten Artefakt-Digest übereinstimmen. Konkrete Run-ID, Commit und Prüfsumme stehen im Übergabebericht zum ausgelieferten ZIP.

Die 74 Tests decken unter anderem ab:

- einzelne Dateien sowie vollständige Ordner, Unterordner, mehrere Ebenen und leere Ordner
- während des Backups geänderte, hinzugefügte, entfernte oder ersetzte Inhalte
- direkte Einzeldatei-Änderung, Entfernung und Hash-Abweichung
- erneute Quellerfassung zwischen Kopierprüfung und Finalisierung
- Office-Lockdateien und eng definierte macOS-Metadaten-Ausschlüsse
- symbolische Links, Spezialeinträge und reservierte Manifestnamen
- temporäre Snapshots, Abbruch, aktive/alte/unklare Teilstände und Namenskollisionen
- manipulierte, beschädigte, fehlende oder nicht passende Besitzmanifeste
- Retention bei 25, 26 und 27 Ständen, getrennt pro Auftrag, ohne fremde Daten als Löschkandidaten
- mehrere unabhängige Aufträge und getrennte Wochen-/Fehlerstatus
- ISO-Wochenwechsel, Donnerstag 14:45 Uhr, Ruhemodus und nachgeholte Warnungen
- Migration alter Konfigurationen und Zustände ohne neue Felder
- Bookmark-Erneuerung ohne Klartextpfad-Fallback
- atomare JSON-Speicherung und beschädigte Zustandsdateien
- Prozesssperre und veralteten `operationInProgress`-Status
- Mail-Helper-Erfolg, Fehler, Signalabbruch und Timeout
- Ziel innerhalb einer Quelle sowie unsichere überkreuzte Auftragspläne

## B. Geprüft und fehlgeschlagen

- Ein Zwischenlauf von Build 123 (`34910343888`) fand zwei fehlschlagende Warnzeitpunkt-Regressionstests. Ursache: Die neue Nachholprüfung der Vorwoche war versehentlich auch in der alten, nur für die aktuelle Woche bestimmten Hilfsfunktion aktiv. Die Hilfsfunktion wurde wieder ausdrücklich auf die aktuelle ISO-Woche begrenzt; die separate Agent-Nachholprüfung blieb erhalten. Der nachfolgende vollständige Lauf des korrigierten Stands war grün.

Für den ausgelieferten finalen Commit sind keine verbleibenden automatisierten Testfehler bekannt. Ein nicht gestarteter Job oder fehlender Runner wäre weder als bestanden noch als Codefehler zu bewerten.

## C. Statisch geprüft

- Originalquellen werden in der Backup-Engine ausschließlich gelesen; Löschoperationen sind auf eindeutig eigene temporäre Bereiche, verifizierte registrierte Backups oder explizite App-Deinstallation begrenzt.
- Ordner-Snapshots werden vollständig inventarisiert, temporär erstellt, per SHA-256 geprüft, unmittelbar vor Abschluss erneut gegen die Quelle verglichen und erst danach atomar finalisiert.
- Retention verlangt registrierten Datensatz, Auftrag, Bookmark, direkten Zielbezug sowie byte- bzw. manifestgeprüfte Eigentümerschaft. Bei Unklarheit wird nicht gelöscht.
- Konfiguration und Runtime-State verwenden atomare Ersetzung und dateibezogene Prozesssperren; beschädigtes JSON wird nicht still durch einen leeren Zustand überschrieben.
- Security-Scoped Bookmarks werden erstellt, aufgelöst, bei sicherer stale-Auflösung erneuert und balanciert beendet. Es gibt keinen unsicheren Klartextpfad-Fallback.
- Das ausgewählte Apple-Mail-Konto wird über Account-ID und Absenderadresse gebunden; es gibt keinen stillen Konto-Fallback und keine Passwortspeicherung.
- Erfolg wird intern als „an Apple Mail übergeben“ behandelt, nicht als garantierte Serverzustellung.
- Der Ruhemodus sperrt automatische Backups und Warnungen, aber nicht „Backup jetzt erstellen“.
- Die Deinstallation erwirbt vor Änderungen dieselbe exklusive Agent-Sperre, deaktiviert den Dienst und lässt Quellen sowie Backups unangetastet.
- Keine Telemetrie, Werbung, Analytics oder externen Uploadpfade im Programmcode gefunden.

Eine statische Prüfung ersetzt keine reale TCC-, iCloud-, Apple-Mail-, Login- oder Neustartprüfung.

## D. Nicht testbar

- **NICHT GETESTET – kein eigenes physisches Apple-Silicon-Endgerät verfügbar:** frische Benutzerinstallation, reale Gatekeeper-Oberfläche, Login, Neustart und Dauerbetrieb.
- **NICHT GETESTET – keine reale Benutzerumgebung verfügbar:** iCloud-Drive-Synchronisation, nicht lokal geladene iCloud-Dateien, Security-Scoped Bookmarks über Neustarts und Jeanines konkrete Ordnerstruktur.
- **NICHT GETESTET – kein eingerichtetes reales Apple-Mail-Konto im CI:** TCC-/Apple-Events-Dialog, Kontoauswahl, echte Übergabe von Test-, Warn- und Erfolgsmail.
- **NICHT GETESTET – keine Developer-ID- und Notarisierungsdaten:** Gatekeeper-Verhalten eines signierten und notarisierten Endanwender-PKG.
- **NICHT GETESTET – CI ist nicht Jeanines Rechner:** reale Update- und Deinstallationsbedienung mit vorhandenen produktiven Daten und Backups.

## E. Externe Blocker

- Kein Developer-ID-Application-Zertifikat.
- Kein Developer-ID-Installer-Zertifikat.
- Kein Notarisierungsprofil bzw. keine Apple-Notary-Zugangsdaten.
- Kein physischer Apple-Silicon-Mac für den abschließenden manuellen Praxistest.

GitHub Actions war für den gültigen finalen Lauf verfügbar. Das ausgelieferte PKG ist dennoch ausdrücklich nur ad-hoc/unsigned und nicht notarisiert.

## F. Noch notwendige Tests vor Release

- Developer-ID-Signierung von App, Agent und Installer durchführen und verifizieren.
- PKG bei Apple notarisieren, Ticket staplen und Gatekeeper mit `spctl` prüfen.
- Auf aktueller physischer Apple-Silicon-Hardware frisch installieren und starten.
- Ersteinrichtung mit echten Security-Scoped Bookmarks und realem privaten iCloud-Ziel abschließen.
- Datei- und Ordnerbackup mit echten Office-Dateien einschließlich `.xlsm` durchführen.
- Apple-Mail-Konto auswählen und echte Test-, Warn- und Erfolgsmail an Apple Mail übergeben.
- Hintergrundagent nach Ab-/Anmeldung und Systemneustart prüfen.
- automatische Mittwoch-/Donnerstag-Ausführung und Donnerstag-Warnung praktisch beobachten.
- Ruhemodus, manuelles Backup, Retention, Update und Deinstallation interaktiv prüfen.
- Nach Update und Deinstallation bestätigen, dass Quellen und vorhandene Backups erhalten sind.
- Abschließenden Praxistest auf Jeanines Mac mit ihrer iCloud-, Mail- und Ordnerkonfiguration durchführen.

## Gesamturteil

**NICHT RELEASE-READY**

Der Stand ist ein umfassend automatisiert geprüfter Test- und Release-Kandidat. Für eine öffentliche Endanwenderfreigabe fehlen aber weiterhin Developer-ID-Signierung, Notarisierung und die oben genannten manuellen Hardware- und Praxistests. Erfolgreiche, nicht tatsächlich ausgeführte Tests werden nicht behauptet.

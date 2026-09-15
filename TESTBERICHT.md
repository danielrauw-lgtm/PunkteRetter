# PunkteRetter 1.2 – technischer Prüfbericht

Stand: 2026-09-15

Version `1.2.0`, Build `124`, Paketversion `1.2.0.124`, Konfigurationsschema `4`.

Build 124 wurde nach einem realen Test von Build 123 auf einem Benutzer-Mac notwendig. Dort wurde die Testmail nicht versandt beziehungsweise nicht als erfolgreich bestätigt. Weil Build 123 die Testmail als zwingende Voraussetzung behandelte, blieb **„Einrichtung abschließen“** gesperrt, obwohl Quelle, Ziel und Privat-Bestätigung bereits gewählt waren.

Die konkrete Ursache der fehlgeschlagenen Apple-Mail-Übergabe wurde auf dem Benutzer-Mac nicht durch Laufzeitlogs belegt und wird deshalb nicht erfunden. Der unabhängig davon eindeutige Konstruktionsfehler war die harte Kopplung der Kernfunktion an eine optionale und umgebungsabhängige Mail-Automation. Auf Entscheidung des Auftraggebers wurde die Mailfunktion in Build 124 vollständig entfernt.

Der Stand verbleibt auf `punkte-retter-1.2-folder-snapshots`. Er wird weder nach `main` gemergt noch getaggt oder als GitHub Release veröffentlicht.

## A. Geprüft und bestanden

- Quellvergleich Build 123 gegen Build 124: Mail-UI, Mail-Bridges, Testmail-Aufruf, Agent-Mailpfade und Mailzustände wurden entfernt.
- Die Einrichtung verlangt nur noch einen vollständigen Sicherungsauftrag und die Privat-Bestätigung des Zielordners.
- Die Aktivierung der Automatik hängt nicht mehr von einer Mailadresse, einem Apple-Mail-Konto oder einer Testmail ab.
- Alte Build-123-Konfigurationsfelder und alte Mail-/Warnstatusfelder werden als unbekannte JSON-Schlüssel weiterhin sicher eingelesen und beim erneuten Speichern nicht mehr ausgegeben.
- `Info.plist` enthält keine Apple-Events-Nutzungsbeschreibung mehr; die Entitlements enthalten keine Apple-Events-Automationsberechtigung.
- Installertexte beschreiben nur noch die Datei-/Ordner- und Zielauswahl.
- Lokale strukturelle Prüfung: 33 Repository-Dateien, 65 deklarierte Tests, keine Konfliktmarker, konsistente Versionswerte `1.2.0` / `124` / `1.2.0.124`.
- `zsh -n Scripts/build-release.command`: bestanden.
- XML-/Plist-Parsing von `Info.plist`, Entitlements und LaunchAgent-Plist: bestanden.
- YAML-Parsing von `.github/workflows/macos-build.yml`: bestanden.

## B. Geprüft und fehlgeschlagen

- **Build 123 auf realem Benutzer-Mac:** Testmail nicht versandt beziehungsweise nicht bestätigt; Einrichtung blieb gesperrt. Dieser Stand darf nicht weiterverwendet werden.
- `swift test` lokal: nicht gestartet, weil in der aktuellen Linux-Arbeitsumgebung kein Swift-Werkzeug installiert ist. Das ist kein fehlgeschlagener Codetest, sondern ein lokaler Umgebungsblocker.

## C. Statisch geprüft

- Originalquellen werden in der Backup-Engine ausschließlich gelesen; Löschoperationen bleiben auf eindeutig eigene temporäre Bereiche, verifizierte registrierte Backups oder die explizite App-Deinstallation begrenzt.
- Ordner-Snapshots werden vollständig inventarisiert, temporär erstellt, per SHA-256 geprüft, unmittelbar vor Abschluss erneut gegen die Quelle verglichen und erst danach atomar finalisiert.
- Retention verlangt registrierten Datensatz, Auftrag, Bookmark, direkten Zielbezug sowie byte- beziehungsweise manifestgeprüfte Eigentümerschaft. Bei Unklarheit wird nicht gelöscht.
- Konfiguration und Runtime-State verwenden atomare Ersetzung und dateibezogene Prozesssperren; beschädigtes JSON wird nicht still durch einen leeren Zustand überschrieben.
- Security-Scoped Bookmarks werden erstellt, aufgelöst, bei sicherer stale-Auflösung erneuert und balanciert beendet. Es gibt keinen unsicheren Klartextpfad-Fallback.
- Die Registrierung des Hintergrunddienstes erfolgt vor der endgültigen Speicherung einer abgeschlossenen Einrichtung. Scheitert danach das Speichern, wird der Dienst wieder abgemeldet und die Einrichtung nicht fälschlich als abgeschlossen markiert.
- Es verbleiben keine Mailquelltexte und kein `--test-mail`-Agentmodus. Die CI enthält eine Regressionprüfung gegen deren versehentliche Wiedereinführung.
- Keine Telemetrie, Werbung, Analytics oder externen Uploadpfade im Programmcode gefunden.

Eine statische Prüfung ersetzt keine reale iCloud-, Bookmark-, Login-, Neustart- oder Benutzeroberflächenprüfung.

## D. Nicht testbar

- **NOCH NICHT AUSGEFÜHRT – macOS-CI für den neuen Build 124 steht aus:** Swift-Kompilierung, 65 Tests, Universal-Build, Codesign-Struktur, PKG-Erzeugung und tatsächliche PKG-Installation.
- **NICHT GETESTET – kein eigenes physisches Apple-Silicon-Endgerät verfügbar:** frische Benutzerinstallation, reale Gatekeeper-Oberfläche, Login, Neustart und Dauerbetrieb.
- **NICHT GETESTET – keine reale Benutzerumgebung verfügbar:** iCloud-Drive-Synchronisation, nicht lokal geladene iCloud-Dateien, Security-Scoped Bookmarks über Neustarts und die konkrete produktive Ordnerstruktur.
- **NICHT GETESTET – keine Developer-ID- und Notarisierungsdaten:** Gatekeeper-Verhalten eines Developer-ID-signierten und notarisierten Endanwender-PKG.
- **NICHT GETESTET – Build 124 noch nicht auf dem betroffenen Benutzer-Mac installiert:** praktische Bestätigung, dass der verkürzte Assistent die Einrichtung abschließt und ein reales Backup startet.

## E. Externe Blocker

- Kein Swift-Compiler in der lokalen Linux-Arbeitsumgebung.
- Kein Developer-ID-Application-Zertifikat.
- Kein Developer-ID-Installer-Zertifikat.
- Kein Notarisierungsprofil beziehungsweise keine Apple-Notary-Zugangsdaten.
- Kein physischer eigener Apple-Silicon-Mac für den abschließenden manuellen Praxistest.

## F. Noch notwendige Tests vor Freigabe

- GitHub-Actions-Lauf für den exakten Build-124-Commit vollständig ausführen.
- Alle 65 Core- und Snapshot-Tests auf ARM und Intel bestehen lassen.
- Universal-Binaries für App und Agent mit `lipo` bestätigen.
- PKG-Inhalt, `/Applications`-Ziel und Paketversion prüfen.
- PKG tatsächlich installieren und Erhalt vorhandener Benutzerdaten prüfen.
- Build 124 auf dem betroffenen Benutzer-Mac über Build 123 installieren.
- Prüfen, dass der Assistent ohne Mailfelder erscheint und **„Einrichtung abschließen“** nach Quellen-, Ziel- und Privat-Auswahl aktiv wird.
- Manuelles Datei- und Ordnerbackup auf diesem Mac durchführen und den erzeugten Wochenstand öffnen.
- Hintergrundagent nach Ab-/Anmeldung und Systemneustart prüfen.
- Developer-ID-Signierung, Notarisierung, Stapling und Gatekeeper vor einem öffentlichen Endanwender-Release durchführen.

## Gesamturteil

**NICHT RELEASE-READY**

Build 124 behebt den beobachteten Einrichtungsblocker konzeptionell und entfernt die komplette Apple-Mail-Abhängigkeit. Vor Übergabe als neuer Test-Installer müssen der exakte Stand jedoch noch auf macOS gebaut, automatisiert geprüft und tatsächlich installiert werden. Erfolgreiche, noch nicht ausgeführte Tests werden nicht behauptet.

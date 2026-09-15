# PunkteRetter 1.2 – technischer Prüfbericht

Stand: 2026-09-15

Version `1.2.0`, Build `124`, Paketversion `1.2.0.124`, Konfigurationsschema `4`.

Build 124 wurde nach einem realen Test von Build 123 auf einem Benutzer-Mac notwendig. Dort wurde die Testmail nicht versandt beziehungsweise nicht als erfolgreich bestätigt. Weil Build 123 die Testmail als zwingende Voraussetzung behandelte, blieb **„Einrichtung abschließen“** gesperrt, obwohl Quelle, Ziel und Privat-Bestätigung bereits gewählt waren.

Die konkrete Ursache der fehlgeschlagenen Apple-Mail-Übergabe wurde auf dem Benutzer-Mac nicht durch Laufzeitlogs belegt und wird deshalb nicht erfunden. Der unabhängig davon eindeutige Konstruktionsfehler war die harte Kopplung der Kernfunktion an eine optionale und umgebungsabhängige Mail-Automation. Auf Entscheidung des Auftraggebers wurde die Mailfunktion in Build 124 vollständig entfernt.

Der Stand verbleibt auf `punkte-retter-1.2-folder-snapshots`. Er wird weder nach `main` gemergt noch getaggt oder als GitHub Release veröffentlicht.

## A. Geprüft und bestanden

- **GitHub Actions, Lauf 35005453166, exakter Code-Commit `39c8d625e0477440ae4015ccd1b931ac4befffff`: vollständig erfolgreich.** Beide Jobs (`build-macos` und `Native Intel-Prüfung`) wurden einem Runner zugewiesen und mit Ergebnis `success` abgeschlossen.
- Alle 65 Core-/Snapshot-Tests liefen auf dem ARM-macOS-Runner direkt sowie erneut innerhalb des Release-Scripts und zusätzlich nativ auf dem Intel-macOS-Runner: drei vollständige Testläufe, jeweils ohne Fehler.
- App und Agent wurden nativ auf Intel kompiliert. Der Universal-Build wurde mit `lipo` geprüft; beide Binärdateien enthalten tatsächlich `arm64` und `x86_64`.
- Das App-Bundle wurde auf ausführbare Haupt- und Agent-Binärdatei, LaunchAgent, Bundle-ID und die Versionswerte `1.2.0` / `124` geprüft.
- Das PKG `PunkteRetter-1.2.0.124-UNSIGNED.pkg` wurde erzeugt, vollständig expandiert und auf Paket-ID, Paketversion, Payload und den direkten Zielpfad `/Applications/PunkteRetter.app` geprüft. Eine doppelte `Applications`-Ebene wurde ausgeschlossen.
- Das erzeugte PKG wurde mit dem macOS-Systemwerkzeug `installer` tatsächlich nach `/Applications/PunkteRetter.app` installiert. App, Agent und LaunchAgent waren danach am erwarteten Ort vorhanden; eine vorher angelegte Testdatei in den Benutzerdaten blieb bytegleich erhalten.
- Die ad-hoc-Signatur von App und Agent wurde technisch geprüft. Apple-Events-Berechtigung und Apple-Events-Nutzungsbeschreibung sind nicht vorhanden.
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

- Build 124 auf dem betroffenen Benutzer-Mac über Build 123 installieren.
- Prüfen, dass der Assistent ohne Mailfelder erscheint und **„Einrichtung abschließen“** nach Quellen-, Ziel- und Privat-Auswahl aktiv wird.
- Manuelles Datei- und Ordnerbackup auf diesem Mac durchführen und den erzeugten Wochenstand öffnen.
- Hintergrundagent nach Ab-/Anmeldung und Systemneustart prüfen.
- Developer-ID-Signierung, Notarisierung, Stapling und Gatekeeper vor einem öffentlichen Endanwender-Release durchführen.

## Gesamturteil

**NICHT RELEASE-READY**

Build 124 entfernt die komplette Apple-Mail-Abhängigkeit und damit die harte Testmail-Sperre der Einrichtung. Code, Tests, Universal-Binaries und der unsigned/ad-hoc Test-Installer wurden auf GitHub-macOS-Runnern erfolgreich geprüft; das PKG wurde dort tatsächlich installiert und der Erhalt vorhandener Benutzerdaten automatisiert bestätigt. Die Einstufung bleibt dennoch **NICHT RELEASE-READY**, bis der neue Assistent und ein reales Datei-/Ordnerbackup auf dem betroffenen Benutzer-Mac geprüft sowie Developer-ID-Signierung und Notarisierung für einen öffentlichen Endanwender-Release durchgeführt wurden. Erfolgreiche, noch nicht ausgeführte Praxistests werden nicht behauptet.

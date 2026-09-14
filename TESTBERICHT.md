# PunkteRetter 1.2 – technischer Prüfstand

Stand: 2026-09-14

## Verbindlicher Status

Version `1.2.0`, Kandidaten-Build `123`, Paketversion `1.2.0.123`.

Build 123 wurde notwendig, weil nach Build 122 zwei funktionale Korrekturen vorgenommen wurden: Der Ruhemodus pausiert nun tatsächlich automatische Backup-Versuche, und ausstehende Donnerstag-Warnungen bleiben über einen ISO-Wochenwechsel hinweg fällig. Zusätzlich werden die Apple-Events-Entitlements und die Hardened Runtime des ad-hoc Test-Builds geprüft.

Der Stand ist ein **CI-Release-Candidate** und noch kein freigegebener Endanwender-Release. Er bleibt auf dem Arbeitsbranch `punkte-retter-1.2-folder-snapshots`. Es erfolgt weder ein Merge nach `main` noch ein Tag oder Release ohne ausdrückliche Freigabe.

## Geprüfte Architektur

- `AppModel`: Einrichtung, mehrere Datei-/Ordneraufträge, UI-Status und kontrollierter Start des Agenten.
- `PunkteRetterAgent`: exklusive Prozesssperre, Planung, Backup, Status, Mail und Retention.
- `VerifiedSnapshotEngine`: vollständige Inventarisierung, markierter temporärer Snapshot, SHA-256-Prüfung und atomare Übernahme.
- `RuntimeState`: Wochenstände und Fehler getrennt pro Auftrag; beschädigte JSON-Daten werden nicht stillschweigend überschrieben.
- `AtomicJSONStore`: atomare Speicherung mit dateibezogener Prozesssperre.
- Security-Scoped Bookmarks ohne Klartextpfad-Fallback; validierte stale Bookmarks werden erneuert.
- Ordner-Manifeste verknüpfen Produkt, Schema, Auftrag, Datensatz, Snapshotname und vollständige Inhaltsprüfung.
- Retention zählt und löscht nur vorhandene, unveränderte und eindeutig eigene Stände.

## Automatisierte Abdeckung

- mehrere Dateien, Unterordner und leere Verzeichnisse
- neu hinzugefügte Datei im nächsten Snapshot
- während des Backups geänderte, hinzugefügte oder entfernte Datei
- Änderung nach Prüfung der temporären Kopie
- temporäre Office- und macOS-Metadateien
- symbolische Links und Spezialeinträge
- Datei- und Ordner-Namenskollisionen
- unterbrochene, alte markierte, potenziell aktive und unklare temporäre Snapshots
- kopierte Hash-Abweichung
- fehlende, beschädigte oder inhaltlich nicht mehr passende Besitzmanifeste
- 26-Stände-Retention getrennt pro Auftrag
- beschädigter RuntimeState und atomare Update-Sicherheit
- verschobene Quelle und verschobenes Ziel
- Ziel innerhalb eines Quellordners sowie kreuzweise unsichere Auftragspläne
- gemischte Datei- und Ordneraufträge
- Prozesssperre
- Mail-Timeout, Erfolg vor der Timeout-Grenze, Signalabbruch und Fehler-Exitcode
- Warnzeitpunkt Donnerstag exakt 14:45 Uhr
- Ruhemodus pausiert automatische Versuche, lässt ein manuelles Backup aber zu
- überfällige und vorgemerkte Warnungen über einen ISO-Wochenwechsel
- direkte Einzeldatei-Änderung, Entfernung und Hash-Abweichung während des Backups
- Retention-Grenzen bei 25, 26 und 27 gültigen Ständen

## Installerprüfung in GitHub Actions

Der Workflow `.github/workflows/macos-build.yml` läuft für jeden Commit des Arbeitsbranches. Ein bestimmter Lauf wird hier bewusst nicht fest eingetragen, weil jede Aktualisierung dieses Berichts selbst einen neuen Commit und damit einen neuen Prüflauf erzeugt. Als Nachweis gilt ausschließlich ein vollständig grüner Workflow, dessen Head-SHA dem ausgelieferten Commit entspricht; Run, Commit und SHA-256 des ausgelieferten ZIP werden im Übergabebericht genannt.

Der macOS-Job hat dabei:

1. Tests und Release-Build ausgeführt.
2. App und Agent als Universal Binary geprüft.
3. den PKG-Inhalt und `install-location="/Applications"` geprüft.
4. den fertigen PKG tatsächlich mit `sudo installer -pkg … -target /` installiert.
5. anschließend App, Agent, Version 1.2.0, Build 123, LaunchAgent, Eigentümer und den Ausschluss von `/Applications/Applications` geprüft.
6. nachgewiesen, dass bestehende Daten unter `~/Library/Application Support/PunkteRetter` erhalten bleiben.

Auch Core-Tests sowie App- und Agent-Kompilierung laufen auf einem nativen Intel-Runner. Das geprüfte Artefakt heißt `PunkteRetter-1.2.0-Build123-INSTALLER-VERIFIED`. App und Agent sind darin ad-hoc mit Hardened Runtime und dem erforderlichen Apple-Events-Entitlement signiert; der PKG-Installer selbst ist nicht mit einer Developer ID signiert und nicht notarisiert.

## Nicht durch CI beweisbar

Ohne ein geeignetes reales Endgerät bleiben offen:

- interaktive TCC-/Apple-Mail-Berechtigungsdialoge
- echte iCloud-Drive- und Security-Scoped-Bookmark-Nutzung über Neustarts
- Login-Start und Neustartverhalten im Benutzerkonto
- echte Apple-Mail-Übergabe mit einem eingerichteten Konto
- Gatekeeper-Verhalten eines Developer-ID-signierten und notarisierten Installers

Der finale Status lautet deshalb bis zu diesen Prüfungen:

**CI-verifizierter Release Candidate – noch nicht interaktiv auf einem realen Endgerät geprüft.**

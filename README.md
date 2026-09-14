# PunkteRetter 1.2.0 (Build 122)

PunkteRetter ist eine native macOS-App zur wöchentlichen, verifizierten Sicherung wichtiger Dateien und kompletter Ordner in private iCloud-Drive-Ordner.

## Funktionen

- mehrere unabhängige Dateien und Ordner als Sicherungsaufträge
- vollständige Ordner-Snapshots einschließlich Unterordnern und leeren Ordnern
- neu hinzugefügte Dateien werden beim nächsten Wochen-Snapshot automatisch erfasst
- normale lesbare Einzeldateien unabhängig vom Dateityp
- Ausschluss temporärer Office-Dateien (`~$…`) sowie `.DS_Store`, `.localized` und AppleDouble-Dateien (`._…`)
- eigener Wochenstatus und eigener iCloud-Backup-Ordner pro Sicherungsauftrag
- erneuter Versuch fehlgeschlagener Aufträge ohne doppelte Kopie bereits erfolgreicher Aufträge
- Warnung am Donnerstag ab 14:45 Uhr mit den noch fehlenden Datei- und Ordneraufträgen
- eine zusammenfassende Erfolgsmail, sobald alle aktiven Aufträge der Woche gesichert sind
- Aufbewahrung von bis zu 26 eindeutig registrierten und überprüfbaren Wochenständen je Sicherungsauftrag
- klarer 45-Sekunden-Prozess-Timeout für den Testmail-Hintergrunddienst
- Übernahme bestehender Konfigurationen aus PunkteRetter 1.0 und 1.1

PunkteRetter erstellt bewusst keine ZIP-Dateien und keine inkrementellen Spezialarchive. Ein Ordner wird als normal zugänglicher, vollständiger Wochenordner gesichert. Symbolische Links und andere Spezialeinträge führen sicherheitshalber zum Fehlschlag des gesamten Ordner-Snapshots.

## Einrichtung

Nach Installation startet der Einrichtungsassistent. Er fragt nach Benachrichtigungsadresse, einem in Apple Mail eingerichteten Versandkonto, der ersten Datei oder dem ersten Ordner und dem privaten iCloud-Backup-Ordner. Weitere Dateien und Ordner lassen sich anschließend in den Einstellungen hinzufügen.

Beim ersten Zugriff auf Apple Mail kann macOS einen Sicherheitsdialog anzeigen. PunkteRetter speichert keine Mail-Passwörter und verwendet ausschließlich das ausdrücklich ausgewählte Apple-Mail-Konto.

Die automatische Sicherung läuft mittwochs und donnerstags zwischen 09:00 und 14:30 Uhr. Fehlt am Donnerstag um 14:45 Uhr noch mindestens ein aktiver Auftrag, wird eine Warnmail an Apple Mail übergeben. War der Mac ausgeschaltet oder der Versand nicht möglich, wird die Warnung beim nächsten Start als verspätet gekennzeichnet.

## Sicherheitsprinzip

1. Quelle und vollständige Ordnerstruktur werden erfasst; jede normale Datei muss lesbar und lokal aktuell verfügbar sein.
2. Pfade, Größen, Änderungszeiten und SHA-256-Werte müssen vor dem Kopieren stabil bleiben.
3. Der komplette Wochenstand entsteht zunächst in einem eindeutig markierten temporären Geschwisterordner des Ziels.
4. Ordnerstruktur, Größen und SHA-256 jeder Kopie müssen mit der stabilen Quelle übereinstimmen.
5. Unmittelbar vor Abschluss wird die Quelle erneut vollständig erfasst. Hinzugefügte, entfernte oder veränderte Dateien verwerfen den gesamten Snapshot.
6. Erst nach bestandener Gesamtprüfung wird der Wochenstand atomar auf seinen endgültigen Namen verschoben.
7. Ordner-Snapshots enthalten ein gehashtes Besitz- und Integritätsmanifest.
8. Nur eindeutig markierte temporäre Bereiche und eindeutig registrierte, unveränderte Backups dürfen bereinigt werden. Bei beschädigten oder unklaren Daten wird nichts erraten oder gelöscht.
9. Originale werden niemals verändert, gesperrt, verschoben, umbenannt oder gelöscht.
10. Ein Backup-Ziel innerhalb eines Quellordners ist ausgeschlossen – auch über mehrere konfigurierte Aufträge hinweg.

## Datenschutz

Keine Telemetrie, keine Werbung und keine externen Analysedienste. Inhalte der Sicherungsdateien und vollständige lokale Pfade werden nicht per Mail versendet. Logs sind begrenzt und enthalten keine Mailinhalte.

## Technik und Kompatibilität

- Swift 6, SwiftUI, Foundation und CryptoKit
- macOS 13 oder neuer
- Universal Binary für Apple Silicon und Intel
- `SMAppService`-LaunchAgent im App-Bundle
- dauerhafte Security-Scoped Bookmarks je Quelle und Ziel
- ISO-Kalenderwoche mit Jahr
- Apple-Mail-Auswahl über interne Account-ID plus Absenderadresse; kein stiller Fallback
- AppleScript-Timeout plus äußerer Prozess-Timeout beim Testmail-Versand

## Installer- und Release-Status

Die GitHub-Actions-Pipeline baut einen nicht relocatable PKG-Installer für `/Applications`, installiert ihn mit `installer -pkg … -target /` und prüft danach App, Agent, Version, LaunchAgent, Architektur und den Erhalt bestehender Benutzerdaten.

Ohne Apple-Developer-Zertifikate entsteht ausdrücklich ein ad-hoc signierter, **nicht notarisierter** Test-Installer. Ein öffentlicher Endanwender-Release benötigt weiterhin Developer-ID-Signierung, Notarisierung und einen manuellen Endtest auf aktueller Apple-Silicon-Hardware.

## Deinstallation

Unter **Einstellungen → PunkteRetter deinstallieren …** wird zuerst der Hintergrunddienst deaktiviert. Danach versucht die App, sich in den Papierkorb zu legen und entfernt ihre Konfigurations-/Statusdaten. Quelldateien und vorhandene Backups werden nicht gelöscht.

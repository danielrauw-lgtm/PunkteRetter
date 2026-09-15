# PunkteRetter 1.2.0 (Build 124)

PunkteRetter ist eine native macOS-App zur wöchentlichen, verifizierten Sicherung wichtiger Dateien und kompletter Ordner in einen privaten, vom Benutzer ausgewählten Backup-Ordner – typischerweise in iCloud Drive.

## Wichtige Änderung in Build 124

Build 123 konnte bei der Ersteinrichtung dauerhaft an der verpflichtenden Apple-Mail-Testnachricht hängen. Der Mailversand war für die eigentliche Sicherung nicht erforderlich, blockierte aber trotzdem die gesamte App.

Build 124 enthält deshalb bewusst **keinen E-Mail-Versand mehr**:

- keine Benachrichtigungsadresse
- keine Apple-Mail-Kontoauswahl
- keine Testmail
- keine Erfolgs- oder Warnmail
- keine Apple-Events-/Automation-Berechtigung

Der Sicherungsstatus und verständliche Fehlerhinweise bleiben direkt in PunkteRetter sichtbar. Ein Mailproblem kann die Einrichtung, automatische Backups oder ein manuelles Backup nicht mehr verhindern.

## Funktionen

- mehrere unabhängige Dateien und Ordner als Sicherungsaufträge
- vollständige Ordner-Snapshots einschließlich Unterordnern und leeren Ordnern
- automatische Erfassung später hinzugefügter Dateien und Unterordner
- normale lesbare Einzeldateien unabhängig vom Dateityp, ohne Konvertierung
- enger Ausschluss von Office-Lockdateien (`~$…`), `.DS_Store`, `.localized` und AppleDouble-Dateien (`._…`)
- eigener Wochen- und Fehlerstatus pro Sicherungsauftrag
- erneuter Versuch fehlgeschlagener Aufträge ohne doppelte Kopie bereits erfolgreicher Aufträge
- Aufbewahrung von höchstens 26 eindeutig registrierten und überprüfbaren Wochenständen je Auftrag
- Übernahme bestehender Datei-/Ordneraufträge aus PunkteRetter 1.0, 1.1 und Build 123

PunkteRetter erstellt keine ZIP-Dateien und keine proprietären oder inkrementellen Archive. Ein Ordner wird als normal zugänglicher, vollständiger Wochenordner gesichert. Symbolische Links und nicht sicher unterstützte Spezialeinträge lassen den gesamten betreffenden Snapshot kontrolliert fehlschlagen.

## Einrichtung

Nach der Installation startet ein kurzer Assistent. Er fragt nur noch nach:

1. der ersten Datei oder dem ersten Ordner,
2. dem privaten Backup-Ordner.

Weitere Dateien und Ordner lassen sich anschließend in den Einstellungen hinzufügen. Nach einem Update von Build 123 bleiben bereits ausgewählte Quellen und Ziele erhalten. Alte Mailangaben werden beim Wechsel auf Konfigurationsschema 4 nicht weiterverwendet und beim nächsten Speichern entfernt.

Die automatische Sicherung prüft mittwochs und donnerstags zwischen 09:00 und 14:30 Uhr ungefähr alle 30 Minuten, ob in der aktuellen ISO-Kalenderwoche noch Aufträge fehlen. Erfolgreiche Aufträge werden in derselben Woche nicht erneut kopiert. **„Fehlende Backups jetzt erstellen“** verwendet dieselbe geprüfte Backup-Engine und bleibt auch im Ruhemodus verfügbar.

## Sicherheitsprinzip

1. Quelle und vollständige Ordnerstruktur werden erfasst; jede normale Datei muss zuverlässig lesbar sein.
2. Relative Pfade, Typen, Größen, Änderungszeiten und SHA-256-Werte müssen vor dem Kopieren stabil bleiben.
3. Der komplette Wochenstand entsteht zunächst in einem eindeutig PunkteRetter zugeordneten temporären Geschwisterordner.
4. Ordnerstruktur, Größen und SHA-256 jeder Kopie werden gegen die erfasste Quelle geprüft.
5. Unmittelbar vor Abschluss wird die Quelle erneut vollständig erfasst. Hinzugefügte, entfernte, ersetzte oder veränderte Inhalte verwerfen den gesamten Snapshot.
6. Erst nach bestandener Gesamtprüfung wird der Wochenstand atomar finalisiert.
7. Ordner-Snapshots enthalten ein gehashtes Besitz- und Integritätsmanifest.
8. Nur eindeutig eigene temporäre Bereiche und eindeutig registrierte, unveränderte Backups dürfen bereinigt werden. Bei Unklarheit wird nichts gelöscht.
9. Originale werden niemals verändert, verschoben, umbenannt oder gelöscht.
10. Ein Backup-Ziel innerhalb eines Quellordners ist ausgeschlossen – auch über mehrere konfigurierte Aufträge hinweg.

## Datenschutz

Keine Telemetrie, keine Werbung, keine Analytics und keine Uploads an fremde Server. PunkteRetter versendet keine E-Mails und fordert keinen Zugriff auf Apple Mail an. Backup-Inhalte bleiben lokal beziehungsweise im ausdrücklich gewählten privaten Speicherziel.

## Technik und Kompatibilität

- Swift 6, SwiftUI, Foundation und CryptoKit
- macOS 13 oder neuer
- Universal-Build für `arm64` und `x86_64`
- `SMAppService`-LaunchAgent im App-Bundle
- Security-Scoped Bookmarks je Quelle und Ziel
- ISO-Kalenderwoche einschließlich Jahr
- atomare Konfigurations- und Statusspeicherung mit Prozesssperren

## Installer- und Release-Status

Die GitHub-Actions-Pipeline baut einen nicht relocatable PKG-Installer für `/Applications`, untersucht den Paketinhalt und installiert ihn mit `installer -pkg … -target /`. Danach werden App, Agent, Version, LaunchAgent, Architektur und der Erhalt einer vorhandenen Benutzerdaten-Testdatei geprüft.

Ohne Apple-Developer-Zertifikate entsteht ausdrücklich ein ad-hoc signierter, nicht notarisierter Test-Installer. Ein öffentlicher Endanwender-Release benötigt weiterhin Developer-ID-Signierung, Notarisierung und einen manuellen Endtest auf aktueller Apple-Silicon-Hardware.

## Deinstallation

Unter **Einstellungen → PunkteRetter deinstallieren …** wird zuerst der Hintergrunddienst deaktiviert. Danach versucht die App, sich in den Papierkorb zu legen und entfernt ausschließlich ihre eigenen Konfigurations- und Statusdaten. Quelldateien und vorhandene Backups werden nicht gelöscht.

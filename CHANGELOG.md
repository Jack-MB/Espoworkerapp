# Changelog — MB-Worker App

Alle nennenswerten Änderungen an der MB-Worker App werden in dieser Datei dokumentiert.
Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/).

---

## [1.3.24+50] - 2026-10-18

### Fixed & Enhanced (Live-Kopfzähler Partner vs. Intern, Vor-Ort-Mitarbeiter-Tausch & Admin-Erkennung)
- **Korrektur des Live-Kopfzählers vor Ort (`self_checkin_screen.dart`, `slot.dart`)**:
  - **Behebung der Fehlzuordnung von internen Schichten zu Partnern**: Bislang wurden alle Schichten mit vorhandener `kooperationspartnerId` als Partner gezählt. Da auch interne Schichten die MB-SCC Account-ID (`69e9f2a93910fbbbc` bzw. `6a05b9091aed30701`) führen, wurden fälschlicherweise alle Schichten als Partner (17 Partner, 0 Intern) ausgewiesen.
  - **Präzise Partner/Intern-Differenzierung (`Slot.isExternalPartner`, `Slot.isInternalEmployee`)**: Externe Partner werden nun serverseitig und clientseitig exakt abgegrenzt. Interne Schichten zählen verlässlich als „Intern“, nur echte Fremdfirmen als „Partner“.
- **Vor-Ort-Austausch bereits eingetragener Mitarbeiter (`self_checkin_screen.dart`, `Slots.php`)**:
  - **Aktivierung der Tauschen-Funktion (`canAssignEmployee`)**: Die Tauschen-Schaltfläche und das Mitarbeiterauswahlsheet sind nun für alle Administratoren, Supervisoren, Disponenten und Vor-Ort-Einsatzleiter verfügbar – selbst wenn Schichten in der Datenbank kein explizites `einsatzleiter_id`-Attribut hinterlegt haben.
  - **Interaktiver „Tauschen“-Button**: Direkter Klickbereich mit Cyan-Akzent und haptischem Feedback auf besetzten Schichtkarten.
  - **Erweitertes Firmen-Dropdown im Auswahlsheet (`_EmployeeSelectionSheet`)**:
    - MB-SCC (Intern) als Standard für interne Schichten.
    - Neue Option „🌐 Alle Firmen / Firmenübergreifend“ (`__ALL__`) für berechtigte Disponenten und Einsatzleiter.
    - Automatische Übernahme der Partnerfirma des gewählten Mitarbeiters auf die Schicht.
    - Sichere Wertauflösung (`_getEffectiveKpValue()`) zur Vermeidung von DropdownButton-Assertions.
  - **Backend-Absicherung (`Slots.php::postActionAssignEmployee`)**:
    - Übergabe von `skipUmplanungCheck => true` und automatisches Setzen von `umplanungGrund = 'Vor-Ort-Austausch (Einsatzleiter)'` verhindert HTTP 400 Bad Request bei Vor-Ort-Umbesetzungen.
    - Rückgabe von `isPartner` und `isIntern` im Response-JSON zur sofortigen reaktiven Aktualisierung des Live-Kopfzählers.
- **Admin- & Rollen-Erkennung (`api_service.dart`, `secure_storage_service.dart`)**:
  - `api_service.dart::login` prüft nun EspoCRMs natives `type == 'admin'` anstelle des nicht-existierenden User-Attributs `isAdmin`.
  - Fallback-Erkennung für Administrator-Accounts in `secure_storage_service.dart`.

---

## [1.3.22+48] - 2026-10-18

### Added & Enhanced (Tri-Parität Check-in, EL-Kopfzähler, Partner-Wechsel & WMS Signatur)
- **Check-in & Stempelmechanik Tri-Parität (Worker-App, EL vor Ort & Terminal)**:
  - **Offline Queueing mit UTC-Zeiterfassung (`CheckinStateService.dart`, `SyncQueueService.dart`)**:
    - Bei Verbindungsverlust oder Offline-Checkin wird der exakte Erfassungszeitpunkt (`stempelZeitpunktUtc`) in die Synchronisations-Queue eingereiht, sodass keine Zeitverzerrung bei nachträglicher Server-Synchronisation entsteht.
  - **Behebung des Uncheck-Bugs (`slots_screen.dart`, `self_checkin_screen.dart`, `Slots.php`)**:
    - Das Zurücksetzen eines versehentlichen Check-ins erfolgt nun über dedizierte Endpunkte bzw. den Parameter `isReset: true` / `resetCheckIn()`. Zuvor führte das Leeren des Feldes serverseitig zu einem unbeabsichtigten Neuestempeln (`nowUtc`).
  - **Dynamische Geofence-Auflösung (`self_checkin_screen.dart`, `slots_screen.dart`, `Slots.php`)**:
    - Der tatsächlich am Service-Objekt konfigurierte Radius (`so_obj.geofence_radius`) wird nun direkt im Schicht-Datensatz (`Slot.geofenceRadius`) an die App übermittelt.
    - Die statische 30m-Anzeige wurde durch dynamische Radar-Badges (`🎯 ${radius}m`) und hierarchische Auflösung (`geofenceRadius ?? rad ?? 50m`) ersetzt.
  - **Pausenerfassung beim Check-Out (`_showPauseSelectionDialog`)**:
    - Interaktiver Pausendialog beim Auschecken (0, 15, 30, 45, 60 Min oder benutzerdefinierte Eingabe).
    - Automatische ArbZG-Pausenempfehlungen (mind. 30 Min ab 6h, mind. 45 Min ab 9h Arbeitszeit).
    - Übermittlung von `pauseMinutes` und `pausenregelungIgnoriert` an das CRM-Backend.
- **Einsatzleiter vor Ort, Schichttausch & Partnerverwaltung**:
  - **Live-Kopfzähler vor Ort (`_buildLiveHeadcountBanner`)**:
    - Echtzeit-Zusammenfassung aller Vor-Ort-Schichten für Einsatzleiter und Administratoren mit Zählern für 🟢 Anwesend, ⚪ Offen, 🏁 Beendet sowie Aufteilung zwischen internen Kräften und Kooperationspartnern.
  - **Vor-Ort-Austausch besetzter Schichten (`self_checkin_screen.dart`)**:
    - Auch bereits zugewiesene Schichten (`slot.angestellteId != null`) können nun durch den Einsatzleiter vor Ort mit einem Klick auf „Tauschen“ umbesetzt werden.
  - **Kooperationspartner-Umschalter (`_EmployeeSelectionSheet`)**:
    - Firmen-Dropdown im Mitarbeiterauswahlsheet zur flexiblen Filterung und dynamischen Neuzuweisung des Kooperationspartners einer Schicht vor Ort.
  - **Direkte Telefon-Kontaktaufnahme (`angestelltePhone`)**:
    - Backend selektiert Mobiltelefonnummern (`entity_phone_number` / `angestellte.notfall_telefonnummer`) direkt an den Schicht-Slots.
    - 1-Tap Telefon-Button (`tel:<phone>`) auf offenen und besetzten Schichten.
- **WMS Ausrüstungsausgabe & Touch-Signaturpad (`depot_detail_screen.dart`)**:
  - Integration von `SfSignaturePad` (`syncfusion_flutter_signaturepad`): Ermöglicht digitale Touch-Unterschriften von Mitarbeitern direkt auf dem Display bei Ausgabe und Rücknahme von Ausrüstung im Depot.
  - Base64-Kodierung der Unterschrift und Übermittlung an das WMS-Backend mit Audit-Dokumentation im Lager-Stream.
- **Push & Sitzungshygiene (`notification_service.dart`, `dashboard_screen.dart`)**:
  - Deep-Linking: Push-Benachrichtigungen zu Schichten navigieren direkt zur jeweiligen Schicht (`SlotsScreen(highlightId: entityId)`).
  - Vollständige Sitzungsbereinigung bei Logout (`clearLocalCaches()`, `clearAll()`, `deleteAll()`) zur Verhinderung von Daten-Lecks auf Gemeinschaftsgeräten.

---

## [1.3.21+47] - 2026-10-16

### Fixed & Enhanced (Geofencing, ServiceObject-Synchronisation & Release)
- **Korrektur der Objektkoordinaten-API (`api_service.dart`)**:
  - `getObjektCoordinates()` ruft primär die korrekte EspoCRM-Entität `ServiceObject` (`/ServiceObject/$id?select=latitude,longitude,geofenceRadius,addressStreet,addressCity,addressPostalCode`) ab (zuvor fehlerhafter Endpunkt `Objekte` mit 404).
  - Automatischer Fallback auf Legacy-Objekte für Abwärtskompatibilität.
  - Sichere Extraktion von `latitude`/`latk`, `longitude`/`lonK` und `geofenceRadius`/`rad` mit dynamischer Sanitization von Tausender- und Dezimaltrennzeichen.
- **Slot-Modell (`slot.dart`)**:
  - Attribute `geofenceRadius` und `rad` hinzugefügt und in `fromJson`, `copyWith` und Konstruktor verankert.
  - Schichten führen den definierten Check-in-Radius des Service-Objekts direkt per Foreign Field mit.
- **Geofence-Prüfung (`location_service.dart`)**:
  - `checkGeofence()` nutzt primär `slot.geofenceRadius` bzw. `slot.rad` mit Default 50m.
  - Beseitigung unnötiger API-Calls bei direkt am Slot vorhandenen Geodaten.
- **Release-Build & Deployment**:
  - Kompilierung von Android Release APK (`app-worker-release.apk`) und Web-PWA.
  - Bereitstellung unter permanentem Download-Link `https://mb-scc.net/downloads/MB-Worker-latest.apk` und versioniert `MB-Worker-v1.3.21.apk`.
  - OTA-Metadaten in `AppUpdate.php` synchronisiert (Build 47, Version 1.3.21, SHA256).
  - Einbettung des permanenten Download-Links und QR-Codes in die mobile Leitstelle (`#Kommunikation`).

---

## [1.3.20+46] - 2026-10-12

### Added
- **WMS Ausrüstungsausgabe & Rücknahme vor Ort (`depot_detail_screen.dart`)**:
  - Neuer 4. Tab *Ausgabe* im Depot-Detailbereich.
  - Berechtigungsprüfung (`canManageHandover`): Zugriff für Administratoren, Disponenten, Depotverantwortliche und Objektleiter.
  - Modale Mitarbeitersuche nach Name und Personalnummer mit optischer Hervorhebung diensthabender Kollegen (`heuteImDienst`).
  - Schnellausgabe von Funkgeräten, Objektschlüsseln, Handlampen und Schutzkleidung.
  - Dialog zur Rücknahme-Quittierung mit Zustandsdokumentation (`Vollständig`, `Beschädigt`, `Verloren`).
- **Warehouse Service (`warehouse_service.dart`)**:
  - Methoden `getDepotHandoverItems()`, `issueDepotItem()`, `returnDepotItem()` und `searchEmployees()`.

### Changed
- **Navigation (`constants.dart`, `dashboard_screen.dart`)**:
  - Tab *Kollegen* aus der unteren Hauptnavigation entfernt zur Wahrung interner Zuständigkeiten und Datenschutz.
  - Index-Verwaltung der Bottom Navigation Bar entsprechend angepasst.
- **OTA Telemetrie**: Version auf 1.3.20 (Build 46) angehoben und PWA synchronisiert.

---

## [1.3.19+45] - 2026-10-11

### Added
- WMS Materialanforderungs-Workflow mit digitalem PDF-Belegabruf.
- Quittierungsfunktion für interne Mitteilungen.

### Fixed
- Performance-Optimierung bei reaktiven Dienstplan-Aktualisierungen.

# Changelog — MB-Worker App

Alle nennenswerten Änderungen an der MB-Worker App werden in dieser Datei dokumentiert.
Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/).

---

## [1.3.21+47] - 2026-10-15

### Fixed & Enhanced (Geofencing & ServiceObject-Synchronisation)
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

# MB-Worker App — Enterprise Mobile & PWA Suite

> **Offizielle mobile Einsatz- und Mitarbeiter-App von MB Security & Event Management.**  
> Nahtlos integriert in **EspoCRM 9.x Enterprise** zur mobilen Verwaltung von Schichten, WMS-Ausrüstungsausgabe, Zeiterfassung, Abwesenheiten und digitaler Einsatzdokumentation.

---

## 📌 Übersicht & Plattformen

Die **MB-Worker App** ist das zentrale mobile Arbeitswerkzeug für über 1.100 Sicherheits- und Event-Mitarbeiter im operativen Außendienst. Sie steht als native Android-App (APK) sowie als hochgradig optimierte Web-PWA (Progressive Web App für iOS & Desktop) zur Verfügung:

- 📱 **Android APK:** Direkte In-App-OTA-Aktualisierung (`https://mb-scc.net/downloads/MB-Worker-latest.apk`)
- 🌐 **Web PWA:** Lauffähig auf allen modernen Browsern und Apple iOS (`https://app.mb-scc.net`)
- 🏷️ **Aktuelle Version:** `v1.3.20+46`

---

## 🚀 Kernfunktionen & Fachmodule

### 1. WMS Ausrüstungsausgabe & Rücknahme vor Ort (`depot_detail_screen.dart`)
- **Vor-Ort Equipment-Handover:** Berechtigte Personen (Objektleiter, Depotverantwortliche, Disponenten und Administratoren) können Ausrüstung direkt vor Ort an Mitarbeiter ausgeben und zurücknehmen.
- **Intelligente Mitarbeitersuche:** Suchleiste mit Echtzeit-Vervollständigung nach Name oder Personalnummer (`pnr`). Diensthabende Mitarbeiter der aktuellen Schicht werden priorisiert hervorgehoben (`heuteImDienst = true`).
- **Kategorisierte Schnellausgabe:**
  - 📻 **Funkgeräte** (Funkrufnamen, Kanalzuweisung, Headsets)
  - 🔑 **Objektschlüssel** (Schlüsselbünde, Alarmtokens, Schließgruppen)
  - 🔦 **Handlampen** (Leuchtmittel, Akkus, Ladestationen)
  - 🦺 **Schutzkleidung & PSA** (Sicherheitsstiefel, Warnwesten nach DGUV)
- **Rücknahme-Quittierung mit Zustandsbewertung:** Rückgabe als *Vollständig*, *Beschädigt* oder *Verloren* mit automatischer Bestandsanpassung im CRM und Protokollierung im Stream.

### 2. WMS Materialanforderung & PDF-Belege
- Mitarbeiter können Material für anstehende Aufträge direkt in der App anfordern.
- Digitaler Abruf von Ausgabebelegen, Packlisten und Quittungs-PDFs.
- Lückenlose Rückverfolgbarkeit aller Materialbewegungen.

### 3. Dienstplan & Schichten (`Slots`)
- **Persönlicher Schichtkalender:** Interaktive Monats-, Wochen- und Tagesansicht aller zugewiesenen Schichten mit Uhrzeiten, Pausen, Einsatzorten und Objektanweisungen.
- **3-Stufen Schichtschutz (Eigenumplanung):**
  1. Mitarbeiter stellt Anfrage zur Schichtabgabe oder zum Schichttausch.
  2. Der angefragte Kollege bestätigt die Übernahme.
  3. Die Einsatzleitung/Disposition gibt den Tausch final frei.
- **ArbZG-Prüfung:** Automatische Berücksichtigung von gesetzlichen Höchstarbeitszeiten und Mindestruhezeiten.

### 4. GPS-validierte Stempeluhr (Check-in / Check-out)
- Standortermittlung per GPS zur Validierung der Anwesenheit am Einsatzort.
- Automatische Berücksichtigung von Rüstzeiten und Schichttoleranzen.
- Offline-Fähigkeit: Zeiterfassungsdaten werden bei Funklöchern zwischengespeichert und automatisch nachgetragen.

### 5. Abwesenheiten, Urlaub & AU-Verwaltung (`abwesenheit_screen.dart`)
- **Urlaubs-Tracker:** Transparente Anzeige des Jahresurlaubsanspruchs, bereits genehmigter Urlaubstage und verbleibender Resttage.
- **Krankmeldungen & EFZG:** Erfassung von Krankheitszeiten mit automatischer Berechnung der Entgeltfortzahlungstage.
- **AU-Upload:** Bequemes Hochladen von Arbeitsunfähigkeitsbescheinigungen per Foto oder PDF-Dokument mit integrierter Bildvorschau.

### 6. Push-Benachrichtigungen & Telemetrie
- **Native Android Push:** Firebase Cloud Messaging (FCM) für Echtzeit-Alarmierungen bei Schichtänderungen oder neuen Weisungen.
- **WebPush / VAPID:** Push-Benachrichtigungen auf iOS und Desktop-Browsern auch bei geschlossener App.
- **Bekanntmachungen & Mitteilungen:** Dringende Unternehmensinformationen mit Lesequittierung.

### 7. Biometrische Sicherheit & WebAuthn
- Schnell-Login per Face ID oder Fingerabdruck über `local_auth`.
- Verschlüsselte Sicherung von Zugangsdaten im `flutter_secure_storage`.
- WebAuthn-Schnittstelle für sichere Authentifizierung im Browser.

### 8. In-App OTA Update-Mechanismus (`AppUpdate`)
- Automatischer Versionsabgleich mit dem EspoCRM-Endpunkt `/api/v1/AppUpdate/action/check`.
- Prüfung von Mindestversion (`minRequiredVersion`), Dateigröße und SHA-256 Prüfsumme.
- Anzeige von Release Notes und ein-Klick-Download für Android-Geräte.

---

## 🛠 Technologie-Stack & Architektur

```text
espo_worker_app/
├── lib/
│   ├── core/                  # Konstanten, Farbtokens, Routen und Designsystem
│   ├── models/                # Typensichere Dart-Datenmodelle (Slot, User, WarehouseItem, etc.)
│   ├── screens/               # Screen-Komponenten (Dashboard, Depot, Abwesenheit, Login, etc.)
│   ├── services/              # Business-Services (WarehouseService, AuthService, ApiService, Push)
│   └── widgets/               # Wiederverwendbare UI-Elemente, Karten und Buttons
├── android/                   # Natives Android-Projekt mit Flavors (worker, admin)
├── web/                       # Web-PWA Assets, Service Worker (push-sw.js) und WebAuthn-Bridge
├── test/                      # 52 automatisierte Unit-, Widget- und E2E-Tests
└── pubspec.yaml               # Abhängigkeiten und Versionsnummer (1.3.20+46)
```

- **Framework:** Flutter 3.x / Dart 3.x
- **Kalender-Engine:** `syncfusion_flutter_calendar`
- **Sicherheit:** `flutter_secure_storage`, `local_auth`, `crypto`
- **Hardware-Zugriff:** `geolocator`, `image_picker`, `file_picker`
- **Netzwerk & Push:** `http`, `firebase_core`, `firebase_messaging`

---

## 📦 Build & Deployment-Befehle

### 1. Abhängigkeiten installieren
```bash
flutter pub get
```

### 2. Automatisierte Tests ausführen
```bash
flutter test
```
*(Alle 52 Tests müssen erfolgreich bestehen)*

### 3. Android Release APK bauen
```bash
flutter build apk --release
```
Die erzeugte APK liegt unter:  
`build/app/outputs/flutter-apk/app-worker-release.apk`

### 4. Web PWA bauen & deployen
```bash
# Web-Release mit Base-Href generieren
flutter build web --release --base-href /

# Auf den Webserver spiegeln
cp -r build/web/* /var/www/ios-pwa/
chown -R www-data:www-data /var/www/ios-pwa/
```

---

## 🔄 Backend-Integration (EspoCRM Endpunkte)

| Modul | Endpunkt | Funktion |
| :--- | :--- | :--- |
| **WMS Handover** | `GET /api/v1/AppWarehouse/action/depotHandoverItems` | Aktuelle Ausgaben und Bestände |
| **WMS Ausgabe** | `POST /api/v1/AppWarehouse/action/issueDepotItem` | Ausgabe vor Ort verbuchen |
| **WMS Rücknahme**| `POST /api/v1/AppWarehouse/action/returnDepotItem` | Rücknahme mit Zustand quittieren |
| **Mitarbeitersuche**| `GET /api/v1/AppWarehouse/action/searchEmployees` | Schnellsuche mit Dienststatus |
| **OTA Updates** | `GET /api/v1/AppUpdate/action/check` | Update-Prüfung & Release Notes |
| **Schichten** | `GET /api/v1/Slots` | Persönliche Schichtplanung |
| **Check-in** | `POST /api/v1/Checkin` | GPS-Zeiterfassung |
| **Abwesenheiten** | `GET /api/v1/CUrlaube`, `GET /api/v1/CKrankenscheine` | Urlaubs- & Krankmeldungsdaten |

---

## 📜 Lizenz & Urheberrecht

© 2026 MB Security & Event Management. Alle Rechte vorbehalten.  
Proprietäre Software für Mitarbeiter und autorisierte Partner.

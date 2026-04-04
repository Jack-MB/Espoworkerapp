# Espo Worker App

Eine leistungsstarke Flutter-Mobilanwendung für Außendienstmitarbeiter, nahtlos integriert in EspoCRM zur Verwaltung von Schichten, Urlaub, Krankmeldungen und Meetings.

## 🚀 Kernfunktionen

### 📅 Intelligentes Dashboard & Kalender
- **Multi-Entitäten-Ansicht**: Zentrale Anzeige von Arbeitsschichten (Slots), Urlaub, Krankheitstagen, Abwesenheiten und Meetings.
- **Echtzeit-Synchronisation**: Automatisches Abrufen aktueller Daten mit robustem Error-Handling (keine Abstürze bei fehlerhaften API-Antworten).
- **Integrierte Navigation**: Schneller Zugriff auf Schichtdetails, Meeting-Teilnehmer und Wachbücher direkt aus dem Kalender.

### 🏥 Krankmeldungen & AU-Verwaltung
- **Dokumenten-Viewer**: Hochgeladene AU-Bescheinigungen können direkt in der App als Vorschau (Bild/PDF) geöffnet werden.
- **Einfacher Upload**: Mitarbeiter können Krankmeldungen einreichen und Dokumente unkompliziert nachreichen.

### 🏢 Unternehmens-Branding & UI
- **Dynamisches Design**: Die App nutzt das Firmenlogo und Farbcodes direkt aus dem EspoCRM-Profil.
- **Server-Status-Indikator**: Sichtbare Anzeige der Server-Erreichbarkeit (Grün/Rot) direkt auf dem Login-Screen und im Dashboard.

### 🔐 Sicherheit & Komfort
- **Biometrisches Login**: Schneller Zugriff via Fingerabdruck oder Gesichtserkennung.
- **Secure Storage**: Sicherer Verschluss von Zugangsdaten im verschlüsselten Speicher des Geräts.

## 🛠 Technologie-Stack

- **Framework**: Flutter (Dart)
- **Backend**: EspoCRM API via REST (JSON)
- **Lokale Sicherheit**: `flutter_secure_storage` & `local_auth`
- **UI-Komponenten**: `syncfusion_flutter_calendar` für die komplexe Terminverwaltung.

## 📦 Installation & Build

### Voraussetzungen
- Flutter SDK (aktuelle stabile Version)
- Android Studio / VS Code mit Flutter Plugins

### Befehle
```bash
# Abhängigkeiten installieren
flutter pub get

# APK für Android generieren (Release)
flutter build apk --release --no-tree-shake-icons
```

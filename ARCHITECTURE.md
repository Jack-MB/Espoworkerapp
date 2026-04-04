# Projekt-Architektur: Espo Worker App

Diese Dokumentation beschreibt die technische Struktur und die getroffenen Design-Entscheidungen, um die Wartbarkeit und Stabilität der Anwendung zu gewährleisten.

## 🏗 Systemübersicht

Die App folgt einem modularen Aufbau, bei dem UI-Komponenten strikt von der Geschäftslogik (API-Services) getrennt sind.

### 🛠 Kernmodule

#### 📡 `api_service.dart`
- **Zuständigkeit**: Gesamte REST-Kommunikation mit EspoCRM.
- **Besonderheit**: Implementierung eines `pingServer`-Mechanismus zur Überwachung der Erreichbarkeit, ohne das System zu belasten.
- **Fehlertoleranz**: Nutzt Timeout-Mechanismen und spezifisches Exception-Handling, um UI-Einfrieren zu verhindern.

#### 🗓 `dashboard_screen.dart`
- **Zentraler Hub**: Aggregiert Daten aus fünf verschiedenen EspoCRM-Entitäten in einem einzigen Datenmodell (`ScheduledEvent`).
- **Lade-Logik**: Verwendet parallele `Future`-Abfragen mit `catchError`, damit der Ausfall eines einzelnen Moduls (z.B. Meetings-Service) nicht das gesamte Dashboard blockiert.
- **Navigation**: Integrierter `Drawer` mit optimierter Navigation, um "Black Screen"-Zustände durch Stack-Fehler zu vermeiden.

#### 🔐 `secure_storage_service.dart`
- Abstraktionslayer für `flutter_secure_storage`.
- Speichert API-Key und Server-URL verschlüsselt auf dem Gerät.

## 🔄 Datenfluss & Synchronisation

1. **Start**: Prüfung auf biometrische Authentifizierung.
2. **Login**: Falls erforderlich, Validierung gegen EspoCRM und Speicherung der Credentials.
3. **Fetching**: Paralleles Laden von:
   - Slots (Schichten)
   - Krankentagen & Urlaub
   - Meetings & Abwesenheiten
4. **Transform**: Umwandlung der rohen JSON-Daten in das einheitliche `ScheduledEvent`-Modell für den Kalender.

## ⚠️ Bekannte Verhaltensweisen & Konventionen

- **Zeitzonen-Handhabung**: Alle Zeiten vom Server werden als UTC interpretiert und via `.toLocal()` in die Benutzer-Zeit umgewandelt.
- **Kalender-Endzeiten**: EspoCRM nutzt exklusive Endzeiten (Mitternacht des Folgetages). Die App visualisiert diese korrekt durch ein einheitliches Parsing-Protokoll in den Lade-Iterationen.

## 🚀 Zukünftige Erweiterungen

- **Materialverwaltung**: Vorbereitet für die Integration, sobald das Lagersystem in EspoCRM initialisiert ist.
- **Offline-Modus**: Geplante Einführung von lokalem Caching für bereits geladene Kalenderdaten.

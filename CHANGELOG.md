# Changelog — MB-Worker App

Alle nennenswerten Änderungen an der MB-Worker App werden in dieser Datei dokumentiert.
Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/).

## [1.3.33+59] - 2026-10-24

### Added & Enhanced (DGUV V23 Alleinarbeiterschutz & Intelligentes Intervall-Tracking)
- **Zeitunabhängige Alleinarbeit & Strikte Check-In-Bedingung (`Slot.requiresAlleinarbeitConsent`)**:
  - Auf Nutzeranweisung von reinen Nachtarbeitszeiten entkoppelt: Alleinarbeitsschutz (DGUV V23) greift für **jede Schicht** (Tag, Spät oder Nacht), bei der Alleinarbeit im System aktiv ist (`isAlleinarbeit == true`).
  - Der Aufklärungs- und Zustimmungsdialog erscheint **nur und erst beim tatsächlichen Check-In**, wenn:
    1. Der Alleinarbeiterschutz für diese Schicht im System explizit aktiviert ist (`isAlleinarbeit == true`).
    2. Für diese Schicht bisher noch keine Einwilligung hinterlegt ist (`alleinarbeitConsentAt == null || empty`).
  - Schichten ohne aktivierten Alleinarbeiterschutz (`isAlleinarbeit == false`) sowie bereits quittierte Schichten bleiben zu 100% frei von Dialogen, Tracking oder Badges.
  - Angewendet in allen drei Check-In-Einstiegspunkten: `_performCheckIn` (`slots_screen.dart`), `_executeCheckIn` (`self_checkin_screen.dart`) und `_calendarCheckIn` (`dashboard_screen.dart`).
- **Keine störende Benachrichtigung in der Statusleiste**:
  - Wie vom Nutzer angewiesen, wurde jegliche dauerhafte Foreground-Service-Benachrichtigung in der Android/iOS-Statusleiste entfernt. Das punktuelle Quick-Fix-Tracking arbeitet diskret und ressourcenschonend im Hintergrund.
- **Wiederverwendbarer Einwilligungsdialog (`alleinarbeit_consent_dialog.dart`) & All-Screen Check-In**:
  - Dialog erscheint **nur und erst beim tatsächlichen Check-In** auf einer Schicht mit aktivem Alleinarbeiterschutz.
  - Vor dem Einchecken erfolgt die revisionssichere Erfassung der Einwilligung an `/AppLiveTracking/action/consent` (DGUV Vorschrift 23 § 8 & § 5 ArbSchG, DSGVO-Hinweis auf 14-Tage-Löschung).
- **Automatischer Lebenszyklus & Stopp beim Check-Out**:
  - Tracking startet erst nach erfolgter Zustimmung und erfolgreichem Check-In.
  - Beim Check-Out oder Undo-Checkin wird das Tracking sofort und unwiderruflich beendet.
- **Umfassende automatisierte Tests (`test/alleinarbeit_tracking_service_test.dart`)**:
  - 87/87 Tests erfolgreich: Erkennung von Nacht- vs. Tagschichten, strikte logische Abgrenzung (`isAlleinarbeitNachtschicht`, `requiresAlleinarbeitConsent`), flexible JSON-Typprüfung für booleans/strings/ints und sauberes Singleton-Lifecycle-Management.

---

## [1.3.32+58] - 2026-10-24

### Enhanced & Redesigned (Bereitschaftskalender: Sentinel Badge & CRM-Notizen-Anbindung)
- **Kalender-Darstellung (`dashboard_screen.dart`)**:
  - **Neues „Sentinel Badge“-Styling für Bereitschaften**: Ruf- und Büro-Bereitschaften werden im `SfCalendar` nicht mehr als massiver oranger Vollfarb-Block gerendert (Verwechslungsgefahr mit den fast 5.000 orangen Regelschichten im System), sondern als eigenständiges Sentinel-Badge mit Kontur.
  - **Struktur & Kontur**: 1.5px Kontur, semitransparenter Kern und vorangestelltes Schild-Icon (`Icons.shield`), das Bereitschaften von Schichten vor Ort visuell sofort unterscheidet.
  - **Dual-Mode Optimierung (WCAG AAA-Kontrast)**:
    - **Dark Mode**: Warmes Amber-Gold (`#F59E0B`) mit getöntem Kern und weiß-goldenem Text.
    - **Light Mode**: Sattes Bronze-Bernstein (`#B45309`) mit tiefbraunem Text (`#78350F`) auf zartem Goldgrund.
  - **Permanente Sichtbarkeit**: Büro-Bereitschaften bleiben für alle Mitarbeiter im Kalender dauerhaft aktiv und sichtbar (kein Ausblenden), da sie den verbindlichen Wochenend-Ansprechpartner des Büros für das gesamte Personal repräsentieren.
- **Detail-Modal (`dashboard_screen.dart`)**:
  - **Dynamische Desktop-Notizen**: Bei Klick auf einen Bereitschaftseintrag wird unter „Notiz“ direkt das Feld `description` aus der Desktop-Variante von EspoCRM angezeigt, sodass Anweisungen, Übergaben und Hinweise des Büros ohne Medienbruch sichtbar sind.
  - **Saubere deutsche Status-Übersetzung**: Status wird als *Geplant*, *Durchgeführt* oder *Nicht durchgeführt* dargestellt.
  - **Schild-Icon im Modal-Header**: Titel zeigt das Schild-Icon in Signal-Gold.

---

## [1.3.31+57] - 2026-10-21

### Added & Enhanced (Papier-AU & Notaufnahme-Freigabe bei Krankmeldungen)
- **Krankmeldung & Nachreichung (`krankentage_screen.dart`)**:
  - **Explizite Papier-AU-Unterstützung**: Mitarbeiter werden im Formular zur Erfassung und Nachreichung von Krankmeldungen nun direkt darüber informiert, dass Papier-Bescheinigungen (z.B. aus der Notaufnahme, dem Krankenhaus/Ambulanz oder vom Privatarzt) uneingeschränkt zulässig und erwünscht sind.
  - **Intuitiver Upload**: Die Schaltfläche wurde von „AU-Bescheinigung hochladen“ zu „Papier-AU / Notaufnahme fotografieren“ mit Kamera-Icon (`Icons.camera_alt`) aktualisiert.
  - **Hintergrund**: Nimmt Mitarbeitern nach Notfallbehandlungen die Verunsicherung bezüglich der gesetzlichen eAU und ermöglicht die sofortige Entschuldigung und Lohnfortzahlung (EFZG) ohne Verzögerung.

---

## [1.3.30+56] - 2026-10-21

### Added & Changed (Offizielle Freigabe im Apple App Store: Ungelistete App-Verteilung)
- **Offizieller Apple App Store Release (`https://apps.apple.com/us/app/espoworker/id6762371770`)**:
  - Offizielle Genehmigung und Freigabe durch Apple zur ungelisteten App-Verteilung (App-ID: `6762371770`).
  - **OTA-Update Service & Dialog (`app_update_service.dart`, `app_update_dialog.dart`)**:
    - Weiterleitung auf iOS erfolgt ab sofort primär auf den offiziellen Apple App Store Link (`appStoreUrl`), mit Rückwärtskompatibilität zu älteren Versionen.
    - Dialog-Button-Text auf iOS von „In TestFlight öffnen“ auf „Im App Store öffnen“ umgestellt.
    - Fehlertext bei Öffnen des Links angepasst.
  - **Model (`app_update_info.dart`)**:
    - Neue Property `appStoreUrl` mit automatischem Fallback auf `testFlightUrl` und `downloadUrl`.
  - **Constants (`constants.dart`)**:
    - Version auf `1.3.30` und BuildNumber auf `56` synchronisiert.
  - **Automatisierte Tests (`app_update_info_test.dart`)**:
    - 3 neue Unit-Tests für JSON-Parsing, App Store Priorisierung und Abwärtskompatibilität (75 Tests insgesamt bestanden).

### Fixed & Enhanced (Pünktlichkeitsampel Toleranz-Korrektur)
- **Check-In Pünktlichkeitsbewertung (`slots_screen.dart`)**:
  - Pünktlichkeitsampel angepasst an CRM-Backend: Stempeln vor Schichtbeginn oder pünktlich wird einheitlich als `🟢` gewertet.
  - Das Toleranzfenster (0–10 Minuten nach Schichtbeginn) wird als `🟡` ausgewiesen.
  - Erst Verspätungen von mehr als 10 Minuten nach geplantem Schichtbeginn schalten auf `🔴` um.

---

## [1.3.29+55] - 2026-10-18

### Changed & Enhanced (Check-In Terminal Parität: Freie Namen, Springer & Tausch in der Schichtenliste)
- **Check-In Terminal Parität in der Schichtenliste (`slots_screen.dart`, `slot.dart`)**:
  - **Freie Namen & Springer-Anzeige**: Manuell erfasste Springer (z. B. aus dem Vor-Ort-Formular) erscheinen in jeder Schichtkarte der Schichtenliste mit amber-farbenem `[SPRINGER]`-Badge und Bewacher-ID (`BWR: DE-BWR-...`).
  - **Schichttausch mit Alt-Mitarbeiter-Historie**: Falls ein Mitarbeiter vor Ort getauscht wurde, wird der ursprünglich eingeteilte Mitarbeiter durchgestrichen (`~Geplant: Max Mustermann~`) und darunter in Amber mit Tausch-Icon `🔄 Ersatz: Neuer Mitarbeiter [TAUSCH]` dargestellt.
  - **Mitarbeiter-Filter**: Der Personenfilter in der Schichtenansicht berücksichtigt nun auch freie Springer (`slot.effectiveEmployeeName`).
  - **Schicht-Detailansicht**: Bei Klick auf eine Schichtkarte werden ursprünglicher Mitarbeiter, Tausch-Status und Bewacher-ID sauber aufgeschlüsselt.
- **Check-In Screen Parität (`self_checkin_screen.dart`)**:
  - Kacheln zeigen bei Vor-Ort-Austausch den durchgestrichenen Vorgänger an.
  - Detail-Dialog (`_showEmployeeDetailsDialog`) führt die Zeile *Ursprünglich geplant* auf.
- **Model Parser (`slot.dart`)**:
  - `Slot.fromJson` extrahiert bei unbesetzten Slots mit `ersatzNotiz` automatisch den Namen und die Bewacher-ID.
  - Neue Getter: `originalGeplantName`, `springerName`, `springerBewacherId`, `effectiveEmployeeName`, `hasErsatzOderTausch`.
- **Unit Tests (`slot_card_layout_details_test.dart`)**:
  - 5 automatisierte Unit-Tests für Springer- und Tausch-Parsing (insgesamt 72 bestandene Tests).

---

## [1.3.28+54] - 2026-10-18

### Changed & Enhanced (Kachel-Optimierung, Positionsangabe, Tauschen-Symbol & Bewacher-Details-Popup)
- **Positionsangabe auf jeder Schichtkarte (`self_checkin_screen.dart`, `slot_card_layout_details_test.dart`)**:
  - Jede Schichtkachel zeigt nun prominent die genaue Einsatzposition (`slot.positionsname`, z. B. „Einfahrt P1“, „Einlass Nord“) als hervorgehobenes Badge (`📍 Position: ...`).
  - Falls kein expliziter Positionsname gepflegt ist, greift ein intelligenter Fallback auf die Schichtbezeichnung.
- **Entfernung fälschlicher „Einsatzleitung“-Badges (`self_checkin_screen.dart`)**:
  - Das irreführende Badge `Einsatzleitung`, das zuvor aufgrund globaler Disponenten-Berechtigungen neben jedem Mitarbeiternamen eingeblendet wurde, wurde vollständig aus der Mitarbeiterzeile entfernt.
- **Kompaktes Schichttausch-Symbol (`self_checkin_screen.dart`)**:
  - Der Tauschen-Button wurde von einer Textschaltfläche zu einem platzsparenden, modernen Icon-Button (`Icons.swap_horiz_rounded`) verschlankt. Verhindert Textüberläufe und spart wertvollen Platz.
- **Klickbares Bewacher-Details-Popup (`self_checkin_screen.dart`)**:
  - Beim Klick auf das Personen-/Avatar-Symbol links neben dem Mitarbeiternamen öffnet sich ein modales Dialog-Popup (`_showEmployeeDetailsDialog`).
  - Zeigt alle ungekürzten Mitarbeiterinformationen vollständig an: Vollständiger Name, Firma/Arbeitgeber (MB-SCC oder Kooperationspartner), Bewacher-ID (in Monospace-Schrift), Ordnernummer, Position und Schichttitel.
- **Radikal verschlanktes Kachel-Layout & Platzersparnis (`self_checkin_screen.dart`)**:
  - Zusammenfassung von Status-Badge (`🟢 Eingecheckt`), Ordner-Chip (`📁 #101`) und Schicht-Uhrzeit in **eine einzige Kopfzeile**.
  - Bereinigung von überflüssigem Innenabstand (Padding von 16 auf 12-14 gestrafft, Button-Höhen von 46 auf 40 optimiert).
- **Unit Tests (`slot_card_layout_details_test.dart`)**:
  - 3 neue automatisierte Unit-Tests für Positionsangabe, Schichtbezeichnungs-Fallback und Firmennamensauflösung (alle 68 Tests erfolgreich).

---

## [1.3.26+52] - 2026-10-18

### Fixed & Enhanced (Entfernung Telefonhörer beim Einstempeln & Multi-Word Mitarbeitersuche)
- **Entfernung des Telefonhörers (`self_checkin_screen.dart`)**:
  - Der Anrufen-Button (`Icons.phone`) neben dem Mitarbeiternamen auf den Schichtkarten im Check-in Screen wurde vollständig entfernt.
- **Intelligente Multi-Word & Debounced Server-Suche im Schichttausch (`self_checkin_screen.dart`, `slot_employee_assignment_test.dart`)**:
  - **Multi-Word Matching**: Der Suchfilter splittet Eingaben wie „Jan Philipp von Czapiewski“, „czapiewski jan“ oder „tasnim hida“ in Einzelfragmente und gleicht alle Wörter über Name, Personalnummer, Ordnernummer, Qualifikationen und Firmenname ab.
  - **Debounced Server-Abfrage**: Nach 300 ms Tipppause wird automatisch die erweiterte Backend-API aufgerufen, wodurch auch firmenübergreifende Springer (z. B. MB-SCC Personal für Subunternehmer-Schichten) nahtlos in den Treffern erscheinen.
  - **Firmen-Kennzeichnung**: Jeder Mitarbeiter in der Auswahlliste zeigt nun ein farbiges Firmen-Badge (`MB Security Concept & Consulting GmbH` bzw. Partnerfirma).
- **Unit Tests (`slot_employee_assignment_test.dart`)**:
  - Neuer Testfall für Multi-Word Search Matching inklusive invertierter Wortreihenfolge und Qualifikations-/Ordnernummernfilter (insgesamt 67 bestandene Tests).

---

## [1.3.25+51] - 2026-10-18

### Fixed & Enhanced (Chronologische Schicht-Sortierung, Strikter Kooperationspartner-Filter, Freier Springer & Primus E-Mail Parser)
- **Chronologische Schicht-Sortierung (`self_checkin_screen.dart`, `Slots.php`)**:
  - **Angleichung an Schichten-Screen**: Sowohl im Backend (`Slots.php::getActionCheckinSlots`) als auch im Frontend (`self_checkin_screen.dart`) werden alle Schichten nun strikt chronologisch nach Schichtbeginn (`COALESCE(s.beginintern, s.date_start) ASC`, lokale Beginnzeit via `espoDateToLocal`) sortiert. Das bisherige künstliche Splitten nach Status-Buckets wurde entfernt.
  - **Alphabetische Sortierung im Tauschen-Sheet**: Mitarbeiter in `_EmployeeSelectionSheet` werden automatisch alphabetisch A-Z nach Name sortiert dargestellt.
- **Strikter Filter auf Kooperationspartner (`api_service.dart`, `self_checkin_screen.dart`)**:
  - **Ausschluss von Kunden und unvollständigen Datensätzen**: `getKooperationspartner()` filtert nun strikt auf `where[type] = 'Kooperationspartner'`. Zuvor wurden Kunden mit hinterlegtem `cKrzel` fälschlicherweise in der Firmenauswahl gelistet.
  - **Strukturierte Auswahlliste**: Dropdown listet `🌐 Alle Firmen` (Filter), `🏢 MB-SCC (Intern)` an oberster Stelle sowie alle aktiven Kooperationspartner in alphabetischer Reihenfolge.
- **Freier Name & Bewacher-ID für Springer (`self_checkin_screen.dart`, `slot.dart`, `Slots.php`)**:
  - **Tab-Umschaltung im Mitarbeiterauswahlsheet**: Neues Segment `[ 👥 Aus Liste wählen ]` und `[ ✍️ Freier Name / Springer ]` ermöglicht Einsatzleitern vor Ort die Erfassung externer Sicherheitskräfte ohne hinterlegtes App-/CRM-Benutzerkonto.
  - **Springer-Formular**: Erfassung von Vor- und Nachname (Pflicht), Bewacher-ID (BWR-Nummer), Ordner-Nummer (O-NR) und Firmenzugehörigkeit (MB-SCC oder Kooperationspartner).
  - **DIN 77200 & Wachbuch-Dokumentation**: Speicherung in `slots.ersatz_notiz` im Standardformat `[Manuell erfasst] Name: ... | Bewacher-ID: ...` mit Protokollierung im Schichtverlauf.
  - **Visuelle Kennzeichnung**: Schichtkarten zeigen auffällige bernsteinfarbene `[SPRINGER]`-Badges und heben die Bewacher-ID in Monospace-Schrift hervor.
- **E-Mail Parser & Viewer analog zu Primus Tablet Suite (`email_list_screen.dart`, `email_content_helper.dart`, `email.dart`)**:
  - **Portierung des Primus Email-Modals**: Neuer 3-Wege Ansichts-Umschalter (`📄 Formatiert`, `📝 Klartext`, `💻 HTML-Code`).
  - **HTML-Sanitization & Dark-Theme-Anpassung**: `EmailContentHelper.sanitizeHtmlForTheme` bereinigt aggressive Inline-Styles, verhindert schwarze Schrift auf dunklem Grund und filtert Skripte heraus.
  - **Intelligente Signatur- & Disclaimer-Trennung**: Trennt Hauptnachricht von autorisierten Signaturen (`AUTORISIERTE SIGNATUR // MB-SCC DOKUMENTENSICHERUNG`) und lagert rechtliche Disclaimer in ein-/ausklappbare Akkordeons aus.
  - **Dateityp-Erkennung & direkter Download**: Eigene Badges für PDF, Bilder und Dokumente mit Formatierung der Dateigröße und direktem Download über `OpenFilex`.
- **Unit- & Integrationstests (`test/email_parsing_test.dart`, `test/slot_employee_assignment_test.dart`)**:
  - 8 neue Testfälle für HTML-Entity-Dekodierung, Plaintext-Konvertierung, Signatur-Splitter, Springer-Getter und alphabetische/chronologische Sortierung (insgesamt 66 bestandene Tests).

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

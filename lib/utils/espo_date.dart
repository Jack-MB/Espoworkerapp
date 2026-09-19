import 'package:intl/intl.dart';

final _espoFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

/// Parst einen EspoCRM-DateTime-String (immer UTC) in lokale Zeit.
/// EspoCRM gibt datetimes ohne Zeitzonen-Suffix zurück ("2026-07-15 06:30:00" = UTC).
/// Verwendung: espoUtcToLocal(slot.dateStart!)
DateTime espoUtcToLocal(String s) {
  try {
    if (s.contains('T')) {
      return DateTime.parse(s).toLocal();
    }
    return _espoFormat.parseUtc(s).toLocal();
  } catch (_) {
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }
}

/// Parst EspoCRM Datum – date-only ("YYYY-MM-DD") oder datetime ("YYYY-MM-DD HH:mm:ss" UTC).
/// Liefert immer das korrekte lokale Datum-Objekt.
/// Behebt den Kalender-Tages-Offset: UTC-Mitternacht "YYYY-MM-DD 22:00:00" → lokaler Folgetag.
DateTime espoDateToLocal(String s) {
  try {
    if (!s.contains(':')) {
      // Reines Datumsfeld – keine Zeitzone nötig
      return DateTime.parse(s);
    }
    if (s.contains('T')) {
      return DateTime.parse(s).toLocal();
    }
    // Datetime-Feld → UTC parsen, in Lokalzeit umwandeln
    return _espoFormat.parseUtc(s).toLocal();
  } catch (_) {
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }
}

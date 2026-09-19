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

/// Formatiert einen UTC-Datetime-String aus EspoCRM ("2026-09-19 12:34:56")
/// in die lokale Uhrzeit "HH:mm".
String? formatUtcToLocalTime(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  try {
    DateTime local;
    if (s.contains('T')) {
      local = DateTime.parse(s).toLocal();
    } else if (s.contains(' ')) {
      local = _espoFormat.parseUtc(s).toLocal();
    } else if (s.contains(':') && s.length <= 8) {
      // Bereits reines Zeitfeld HH:mm oder HH:mm:ss
      return s.substring(0, 5);
    } else {
      local = DateTime.parse(s).toLocal();
    }
    return DateFormat('HH:mm').format(local);
  } catch (_) {
    // Fallback falls Parsing scheitert
    if (s.contains(' ')) {
      final parts = s.split(' ');
      if (parts.length > 1 && parts[1].length >= 5) {
        return parts[1].substring(0, 5);
      }
    }
    return s.length >= 5 ? s.substring(0, 5) : s;
  }
}

/// Konvertiert eine lokale Uhrzeit "HH:mm" für ein gegebenes Schichtdatum
/// in einen UTC-Datetime-String "yyyy-MM-dd HH:mm:ss" für EspoCRM.
String? formatLocalToUtcDateTime({
  required String localHHmm,
  String? baseDateUtc,
}) {
  if (localHHmm.trim().isEmpty) return null;
  try {
    DateTime localDate;
    if (baseDateUtc != null && baseDateUtc.trim().isNotEmpty) {
      localDate = espoUtcToLocal(baseDateUtc);
    } else {
      localDate = DateTime.now();
    }

    final parts = localHHmm.trim().split(':');
    final hour = int.parse(parts[0]);
    final minute = parts.length > 1 ? int.parse(parts[1]) : 0;

    final localDateTime = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
      hour,
      minute,
      0,
    );

    return _espoFormat.format(localDateTime.toUtc());
  } catch (e) {
    return null;
  }
}

/// Prüft, ob ein Slot (mit UTC dateStart / dateEnd) an einem bestimmten lokalen Tag stattfindet.
/// Berücksichtigt Nachtschichten, die vor Mitternacht beginnen oder nach Mitternacht enden.
bool isSlotOnLocalDate(String? dateStartUtc, String? dateEndUtc, DateTime localTargetDate) {
  if (dateStartUtc == null || dateStartUtc.trim().isEmpty) return false;
  try {
    final startLocal = espoUtcToLocal(dateStartUtc);
    final endLocal = (dateEndUtc != null && dateEndUtc.trim().isNotEmpty)
        ? espoUtcToLocal(dateEndUtc)
        : startLocal.add(const Duration(hours: 8));

    final targetYear = localTargetDate.year;
    final targetMonth = localTargetDate.month;
    final targetDay = localTargetDate.day;

    final startDay = DateTime(startLocal.year, startLocal.month, startLocal.day);
    final endDay = DateTime(endLocal.year, endLocal.month, endLocal.day);
    final targetDayDate = DateTime(targetYear, targetMonth, targetDay);

    return (targetDayDate.isAtSameMomentAs(startDay) || targetDayDate.isAfter(startDay)) &&
           (targetDayDate.isAtSameMomentAs(endDay) || targetDayDate.isBefore(endDay));
  } catch (_) {
    return false;
  }
}

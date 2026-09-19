import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Krankentage {
  final String id;
  final String name;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final String? krankenscheinId;
  final String? krankenscheinName;
  final String? description;
  final int? berechneteTage;
  final int? werktage;
  final int? kalendertage;

  Krankentage({
    required this.id,
    required this.name,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.krankenscheinId,
    this.krankenscheinName,
    this.description,
    this.berechneteTage,
    this.werktage,
    this.kalendertage,
  });

  factory Krankentage.fromJson(Map<String, dynamic> json) {
    return Krankentage(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? 'Planned',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      krankenscheinId: json['krankenscheinId'],
      krankenscheinName: json['krankenscheinName'],
      description: json['description'],
      berechneteTage: _parseInt(json['berechneteTage']),
      werktage: _parseInt(json['werktage']),
      kalendertage: _parseInt(json['kalendertage']),
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String get formattedDateRange {
    final start = _formatDateStr(dateStart);
    final end = _formatDateStr(dateEnd);
    if (start.isEmpty && end.isEmpty) return 'Kein Zeitraum angegeben';
    if (end.isEmpty || start == end) return start;
    return '$start bis $end';
  }

  static String _formatDateStr(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    try {
      final clean = raw.trim().replaceFirst(' ', 'T');
      final dt = DateTime.parse(clean);
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) {
      return raw.split(' ')[0];
    }
  }

  String get displayStatus {
    switch (status.trim()) {
      case 'Held':
        return 'Bestätigt (AU liegt vor)';
      case 'Planned':
        return 'Gemeldet (in Prüfung)';
      case 'Not Held':
        return 'Nicht anerkannt';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status.trim()) {
      case 'Held':
        return Colors.green;
      case 'Planned':
        return Colors.orange;
      case 'Not Held':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }
}

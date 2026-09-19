import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/espo_date.dart';

class Urlaub {
  final String id;
  final String name;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final String? dateStartDate;
  final String? dateEndDate;
  final String? description;
  final String? stichwortbezeichnung;
  final String? begrndung;
  final int? werktage;
  final int? kalendertage;

  Urlaub({
    required this.id,
    required this.name,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.dateStartDate,
    this.dateEndDate,
    this.description,
    this.stichwortbezeichnung,
    this.begrndung,
    this.werktage,
    this.kalendertage,
  });

  factory Urlaub.fromJson(Map<String, dynamic> json) {
    return Urlaub(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? 'In Bearbeitung',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      dateStartDate: json['dateStartDate'],
      dateEndDate: json['dateEndDate'],
      description: json['description'],
      stichwortbezeichnung: json['stichwortbezeichnung'],
      begrndung: json['begrndung'],
      werktage: _parseInt(json['werktage']),
      kalendertage: _parseInt(json['kalendertage']),
    );
  }

  static int? _parseInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  String get formattedDateRange {
    final start = _formatDateStr(dateStart ?? dateStartDate);
    final end = _formatDateStr(dateEnd ?? dateEndDate);
    if (start.isEmpty && end.isEmpty) return 'Kein Zeitraum angegeben';
    if (end.isEmpty || start == end) return start;
    return '$start bis $end';
  }

  static String _formatDateStr(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    try {
      final dt = espoDateToLocal(raw);
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) {
      return raw.split(' ')[0];
    }
  }

  Color get statusColor {
    switch (status.trim()) {
      case 'Bestätigt':
      case 'Genehmigt':
        return Colors.green;
      case 'In Bearbeitung':
        return Colors.orange;
      case 'Abgelehnt':
        return Colors.red;
      case 'Alternativvorschlag':
        return Colors.amber.shade800;
      default:
        return Colors.blueGrey;
    }
  }
}

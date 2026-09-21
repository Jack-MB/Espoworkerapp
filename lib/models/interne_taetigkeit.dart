class InterneTaetigkeit {
  final String id;
  final String name;
  final String typ;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final bool isAllDay;
  final int pause;
  final double stunden;
  final String? ort;
  final String? beschreibung;
  final String color;
  final bool arbeitszeitkonto;
  final String? angestellteId;
  final String? angestellteName;

  InterneTaetigkeit({
    required this.id,
    required this.name,
    required this.typ,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.isAllDay = false,
    this.pause = 0,
    this.stunden = 0.0,
    this.ort,
    this.beschreibung,
    this.color = '#4f46e5',
    this.arbeitszeitkonto = true,
    this.angestellteId,
    this.angestellteName,
  });

  factory InterneTaetigkeit.fromJson(Map<String, dynamic> json) {
    return InterneTaetigkeit(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      typ: json['typ'] ?? 'Schultag',
      status: json['status'] ?? 'Geplant',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      isAllDay: json['isAllDay'] == true || json['isAllDay'] == 1,
      pause: json['pause'] is int ? json['pause'] : int.tryParse(json['pause']?.toString() ?? '0') ?? 0,
      stunden: (json['stunden'] is num)
          ? (json['stunden'] as num).toDouble()
          : double.tryParse(json['stunden']?.toString() ?? '0') ?? 0.0,
      ort: json['ort'],
      beschreibung: json['beschreibung'],
      color: json['color'] ?? ((json['typ'] ?? 'Schultag') == 'Schultag' ? '#0ea5e9' : '#6366f1'),
      arbeitszeitkonto: json['arbeitszeitkonto'] != false,
      angestellteId: json['angestellteId'],
      angestellteName: json['angestellteName'],
    );
  }
}

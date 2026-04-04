class Krankentage {
  final String id;
  final String name;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final String? krankenscheinId;
  final String? krankenscheinName;
  final int? berechneteTage;

  Krankentage({
    required this.id,
    required this.name,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.krankenscheinId,
    this.krankenscheinName,
    this.berechneteTage,
  });

  factory Krankentage.fromJson(Map<String, dynamic> json) {
    return Krankentage(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      krankenscheinId: json['krankenscheinId'],
      krankenscheinName: json['krankenscheinName'],
      berechneteTage: json['berechneteTage'],
    );
  }
}

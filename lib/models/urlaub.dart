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
  });

  factory Urlaub.fromJson(Map<String, dynamic> json) {
    return Urlaub(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      dateStartDate: json['dateStartDate'],
      dateEndDate: json['dateEndDate'],
      description: json['description'],
      stichwortbezeichnung: json['stichwortbezeichnung'],
      begrndung: json['begrndung'],
    );
  }
}

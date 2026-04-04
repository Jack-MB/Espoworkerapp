class Abwesenheit {
  final String id;
  final String name;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final String? type;
  final String? description;
  final bool isAllDay;

  Abwesenheit({
    required this.id,
    required this.name,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.type,
    this.description,
    this.isAllDay = false,
  });

  factory Abwesenheit.fromJson(Map<String, dynamic> json) {
    return Abwesenheit(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      type: json['type'],
      description: json['description'],
      isAllDay: json['isAllDay'] == true,
    );
  }
}

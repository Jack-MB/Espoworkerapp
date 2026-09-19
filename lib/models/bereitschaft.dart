class Bereitschaft {
  final String id;
  final String name;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final bool isAllDay;
  final String? description;

  Bereitschaft({
    required this.id,
    required this.name,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.isAllDay = true,
    this.description,
  });

  factory Bereitschaft.fromJson(Map<String, dynamic> json) {
    return Bereitschaft(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      isAllDay: json['isAllDay'] == true || json['isAllDay'] == 1,
      description: json['description'],
    );
  }
}

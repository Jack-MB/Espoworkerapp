class WachbuchAttachment {
  final String id;
  final String name;
  final String type;
  WachbuchAttachment({required this.id, required this.name, required this.type});
}

class Wachbuch {
  final String id;
  final String name;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final String? datumUhrzeit;
  final bool? isAllDay;
  final int? duration;
  final String? beschreibung;
  final String? description;
  final String? zustzlicheInformationen;
  final List<String>? art;
  final String? parentName;
  final String? objekteName;
  final String? assignedUserName;
  final String? createdByName;
  final String? modifiedByName;
  final String? createdAt;
  final String? modifiedAt;
  final List<WachbuchAttachment> dateinFotos;

  Wachbuch({
    required this.id,
    required this.name,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.datumUhrzeit,
    this.isAllDay,
    this.duration,
    this.beschreibung,
    this.description,
    this.zustzlicheInformationen,
    this.art,
    this.parentName,
    this.objekteName,
    this.assignedUserName,
    this.createdByName,
    this.modifiedByName,
    this.createdAt,
    this.modifiedAt,
    this.dateinFotos = const [],
  });

  factory Wachbuch.fromJson(Map<String, dynamic> json) {
    return Wachbuch(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      datumUhrzeit: json['datumUhrzeit'],
      isAllDay: json['isAllDay'],
      duration: json['duration'],
      beschreibung: json['beschreibung'],
      description: json['description'],
      zustzlicheInformationen: json['zustzlicheInformationen'],
      art: json['art'] != null ? List<String>.from(json['art']) : null,
      parentName: json['parentName'],
      objekteName: json['objekteName'],
      assignedUserName: json['assignedUserName'],
      createdByName: json['createdByName'],
      modifiedByName: json['modifiedByName'],
      createdAt: json['createdAt'],
      modifiedAt: json['modifiedAt'],
      dateinFotos: _parseAttachments(
          json['dateinFotosIds'], json['dateinFotosNames'], json['dateinFotosTypes']),
    );
  }

  static List<WachbuchAttachment> _parseAttachments(
      dynamic ids, dynamic names, dynamic types) {
    final result = <WachbuchAttachment>[];
    if (ids == null || ids is! List) return result;
    for (final id in ids) {
      result.add(WachbuchAttachment(
        id: id.toString(),
        name: names?[id] ?? id.toString(),
        type: types?[id] ?? '',
      ));
    }
    return result;
  }
}

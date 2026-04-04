class Meeting {
  final String id;
  final String name;
  final String status;
  final String? dateStart;
  final String? dateEnd;
  final int? duration;
  final String? description;
  final String? parentId;
  final String? parentType;
  final String? parentName;
  final String? assignedUserId;
  final String? assignedUserName;

  final List<Attendee>? attendees;

  Meeting({
    required this.id,
    required this.name,
    required this.status,
    this.dateStart,
    this.dateEnd,
    this.duration,
    this.description,
    this.parentId,
    this.parentType,
    this.parentName,
    this.assignedUserId,
    this.assignedUserName,
    this.attendees,
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    return Meeting(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? 'Planned',
      dateStart: json['dateStart'],
      dateEnd: json['dateEnd'],
      duration: json['duration'],
      description: json['description'],
      parentId: json['parentId'],
      parentType: json['parentType'],
      parentName: json['parentName'],
      assignedUserId: json['assignedUserId'],
      assignedUserName: json['assignedUserName'],
      attendees: json['users'] != null 
        ? (json['users'] as List).map((e) => Attendee.fromJson(e, 'User')).toList()
        : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'dateStart': dateStart,
      'dateEnd': dateEnd,
      'duration': duration,
      'description': description,
      'parentId': parentId,
      'parentType': parentType,
      'assignedUserId': assignedUserId,
    };
  }
}

class Attendee {
  final String id;
  final String name;
  final String type;
  final String? status;

  Attendee({required this.id, required this.name, required this.type, this.status});

  factory Attendee.fromJson(Map<String, dynamic> json, String type) {
    return Attendee(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: type,
      status: json['status'],
    );
  }
}

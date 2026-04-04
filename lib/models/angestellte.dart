class Angestellte {
  final String id;
  final String name;
  final String? firstName;
  final String? lastName;
  final String? emailAddress;
  final String? phoneNumber;
  final String? personalnummer;
  final String? benutzername;
  final String? qualifikation; 
  final Map<String, dynamic> rawData;

  Angestellte({
    required this.id,
    required this.name,
    this.firstName,
    this.lastName,
    this.emailAddress,
    this.phoneNumber,
    this.personalnummer,
    this.benutzername,
    this.qualifikation,
    required this.rawData,
  });

  factory Angestellte.fromJson(Map<String, dynamic> json) {
    return Angestellte(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      firstName: json['firstName'],
      lastName: json['lastName'],
      emailAddress: json['emailAddress'],
      phoneNumber: json['phoneNumber'],
      personalnummer: json['personalnummer'],
      benutzername: json['benutzername'],
      qualifikation: json['qualifikation']?.toString(), // Simple string rendering fallback
      rawData: json,
    );
  }
}

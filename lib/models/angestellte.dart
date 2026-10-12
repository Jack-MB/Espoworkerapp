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
  final int? gesamtUrlaub;
  final int? genommenUrlaub;
  final int? geplanterUrlaub;
  final int? restUrlaub;
  final int? krankentageJahr;
  final int? gesamtKrankentage;
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
    this.gesamtUrlaub,
    this.genommenUrlaub,
    this.geplanterUrlaub,
    this.restUrlaub,
    this.krankentageJahr,
    this.gesamtKrankentage,
    required this.rawData,
  });

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

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
      gesamtUrlaub: _parseInt(json['gesamtUrlaub']),
      genommenUrlaub: _parseInt(json['genommenUrlaub']),
      geplanterUrlaub: _parseInt(json['geplanterUrlaub']),
      restUrlaub: _parseInt(json['restUrlaub']),
      krankentageJahr: _parseInt(json['krankentageJahr']),
      gesamtKrankentage: _parseInt(json['gesamtKrankentage']),
      rawData: json,
    );
  }
}

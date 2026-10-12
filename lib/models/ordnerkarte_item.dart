/// Data model for Ordnerkarten & Akkreditierungen at a Depot
class OrdnerkarteItem {
  final String id;
  final String name;
  final String kartentyp; // 'Standard', 'Ostern', 'Halloween', 'Weihnachten', 'Pausenkarten', 'Sonderausweis'
  final String status; // 'Im Depot', 'Ausgegeben', 'Gesperrt', 'Verloren'
  final String warehouseId;
  final String? productName;
  final String? angestellteName;
  final String? nummernkreis;
  final int? vonNummer;
  final int? bisNummer;
  final String? einzelnummern;
  final int anzahl;
  final String? ausgegebenAm;
  final String? rueckgabeBis;
  final String? description;

  OrdnerkarteItem({
    required this.id,
    required this.name,
    required this.kartentyp,
    required this.status,
    required this.warehouseId,
    this.productName,
    this.angestellteName,
    this.nummernkreis,
    this.vonNummer,
    this.bisNummer,
    this.einzelnummern,
    this.anzahl = 1,
    this.ausgegebenAm,
    this.rueckgabeBis,
    this.description,
  });

  factory OrdnerkarteItem.fromJson(Map<String, dynamic> json) {
    return OrdnerkarteItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Ordnerkarten',
      kartentyp: json['kartentyp']?.toString() ?? 'Standard',
      status: json['status']?.toString() ?? 'Im Depot',
      warehouseId: json['warehouseId']?.toString() ?? '',
      productName: json['productName']?.toString(),
      angestellteName: json['angestellteName']?.toString(),
      nummernkreis: json['nummernkreis']?.toString(),
      vonNummer: (json['vonNummer'] as num?)?.toInt(),
      bisNummer: (json['bisNummer'] as num?)?.toInt(),
      einzelnummern: json['einzelnummern']?.toString(),
      anzahl: (json['anzahl'] as num?)?.toInt() ?? 1,
      ausgegebenAm: json['ausgegebenAm']?.toString(),
      rueckgabeBis: json['rueckgabeBis']?.toString(),
      description: json['description']?.toString(),
    );
  }

  bool get isImDepot => status == 'Im Depot';
  bool get isAusgegeben => status == 'Ausgegeben';
}

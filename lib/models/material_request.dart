/// Data models for mobile Materialanforderung
class MaterialRequestHeader {
  final String id;
  final String name; // MA-YYYY-NNNNN
  final String status; // 'Eingereicht', 'Genehmigt', 'In Kommissionierung', 'In Zustellung', 'Geliefert', 'Quittiert', 'Abgelehnt'
  final String dringlichkeit; // 'Standard', 'Hoch', 'Notfall'
  final String zielLagerId;
  final String zielLagerName;
  final String? quellLagerName;
  final String? anfordererName;
  final String? bereich;
  final String? salesOrderName;
  final String? benoetigtBis;
  final String? begruendung;
  final String? genehmigtAm;
  final String? quittiertAm;
  final int itemCount;
  final double totalMenge;
  final String createdAt;
  final List<MaterialRequestItem> items;

  MaterialRequestHeader({
    required this.id,
    required this.name,
    required this.status,
    required this.dringlichkeit,
    required this.zielLagerId,
    required this.zielLagerName,
    this.quellLagerName,
    this.anfordererName,
    this.bereich,
    this.salesOrderName,
    this.benoetigtBis,
    this.begruendung,
    this.genehmigtAm,
    this.quittiertAm,
    this.itemCount = 0,
    this.totalMenge = 0.0,
    required this.createdAt,
    this.items = const [],
  });

  factory MaterialRequestHeader.fromJson(Map<String, dynamic> json) {
    List<MaterialRequestItem> parsedItems = [];
    if (json['items'] is List) {
      parsedItems = (json['items'] as List)
          .map((item) => MaterialRequestItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return MaterialRequestHeader(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'MA-Anforderung',
      status: json['status']?.toString() ?? 'Eingereicht',
      dringlichkeit: json['dringlichkeit']?.toString() ?? 'Standard',
      zielLagerId: json['zielLagerId']?.toString() ?? '',
      zielLagerName: json['zielLagerName']?.toString() ?? 'Depot',
      quellLagerName: json['quellLagerName']?.toString(),
      anfordererName: json['anfordererName']?.toString(),
      bereich: json['bereich']?.toString(),
      salesOrderName: json['salesOrderName']?.toString(),
      benoetigtBis: json['benoetigtBis']?.toString(),
      begruendung: json['begruendung']?.toString(),
      genehmigtAm: json['genehmigtAm']?.toString(),
      quittiertAm: json['quittiertAm']?.toString(),
      itemCount: (json['itemCount'] as num?)?.toInt() ?? parsedItems.length,
      totalMenge: (json['totalMenge'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['createdAt']?.toString() ?? '',
      items: parsedItems,
    );
  }

  bool get isPendingReceipt =>
      status == 'In Zustellung' || status == 'Geliefert';
  bool get isQuittiert => status == 'Quittiert';
  bool get isEmergency => dringlichkeit == 'Notfall';
  bool get isHighPriority => dringlichkeit == 'Hoch';
}

class MaterialRequestItem {
  final String id;
  final String name;
  final String productId;
  final String productName;
  final String? partNumber;
  final double mengeBeantragt;
  final double mengeGenehmigt;
  final double mengeGeliefert;
  final double mengeQuittiert;
  final String einheit;
  final String? groesse;
  final String? ordnerkartenNummern;
  final String? bemerkung;

  MaterialRequestItem({
    required this.id,
    required this.name,
    required this.productId,
    required this.productName,
    this.partNumber,
    required this.mengeBeantragt,
    this.mengeGenehmigt = 0.0,
    this.mengeGeliefert = 0.0,
    this.mengeQuittiert = 0.0,
    this.einheit = 'Stk.',
    this.groesse,
    this.ordnerkartenNummern,
    this.bemerkung,
  });

  factory MaterialRequestItem.fromJson(Map<String, dynamic> json) {
    return MaterialRequestItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Position',
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? 'Artikel',
      partNumber: json['partNumber']?.toString(),
      mengeBeantragt: (json['mengeBeantragt'] as num?)?.toDouble() ?? 1.0,
      mengeGenehmigt: (json['mengeGenehmigt'] as num?)?.toDouble() ?? 0.0,
      mengeGeliefert: (json['mengeGeliefert'] as num?)?.toDouble() ?? 0.0,
      mengeQuittiert: (json['mengeQuittiert'] as num?)?.toDouble() ?? 0.0,
      einheit: json['einheit']?.toString() ?? 'Stk.',
      groesse: json['groesse']?.toString(),
      ordnerkartenNummern: json['ordnerkartenNummern']?.toString(),
      bemerkung: json['bemerkung']?.toString(),
    );
  }
}

class CatalogProduct {
  final String id;
  final String name;
  final String? partNumber;
  final String category;
  final bool hasSizes;
  final bool isCard;

  CatalogProduct({
    required this.id,
    required this.name,
    this.partNumber,
    required this.category,
    this.hasSizes = false,
    this.isCard = false,
  });

  factory CatalogProduct.fromJson(Map<String, dynamic> json) {
    return CatalogProduct(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      partNumber: json['partNumber']?.toString(),
      category: json['category']?.toString() ?? 'Allgemein',
      hasSizes: json['hasSizes'] == true,
      isCard: json['isCard'] == true,
    );
  }
}

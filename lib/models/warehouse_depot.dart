/// Data models for MB-SCC Lagersystem (WMS), Depots & Employee Equipment
class WarehouseDepot {
  final String id;
  final String name;
  final String lagerTyp; // 'Hauptlager', 'Objektlager', 'Mitarbeiterlager', 'Auftragslager'
  final String? qrToken;
  final String status;
  final String wartungStatus; // 'OK', 'Wäsche fällig', 'Prüfung fällig', 'Überfällig'
  final String? addressStreet;
  final String? addressCity;
  final String? letzteWaescheDatum;
  final String? naechsteWaescheDatum;
  final String? letzteMaterialPruefungDatum;
  final String? naechsteMaterialPruefungDatum;
  final String? verantwortlicherName;
  final int? stockCount;

  WarehouseDepot({
    required this.id,
    required this.name,
    required this.lagerTyp,
    this.qrToken,
    this.status = 'Active',
    this.wartungStatus = 'OK',
    this.addressStreet,
    this.addressCity,
    this.letzteWaescheDatum,
    this.naechsteWaescheDatum,
    this.letzteMaterialPruefungDatum,
    this.naechsteMaterialPruefungDatum,
    this.verantwortlicherName,
    this.stockCount,
  });

  factory WarehouseDepot.fromJson(Map<String, dynamic> json) {
    return WarehouseDepot(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unbenanntes Depot',
      lagerTyp: json['lagerTyp']?.toString() ?? 'Objektlager',
      qrToken: json['qrToken']?.toString(),
      status: json['status']?.toString() ?? 'Active',
      wartungStatus: json['wartungStatus']?.toString() ?? 'OK',
      addressStreet: json['addressStreet']?.toString(),
      addressCity: json['addressCity']?.toString(),
      letzteWaescheDatum: json['letzteWaescheDatum']?.toString(),
      naechsteWaescheDatum: json['naechsteWaescheDatum']?.toString(),
      letzteMaterialPruefungDatum: json['letzteMaterialPruefungDatum']?.toString(),
      naechsteMaterialPruefungDatum: json['naechsteMaterialPruefungDatum']?.toString(),
      verantwortlicherName: json['verantwortlicherName']?.toString(),
      stockCount: json['stockCount'] is int ? json['stockCount'] as int : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lagerTyp': lagerTyp,
    'qrToken': qrToken,
    'status': status,
    'wartungStatus': wartungStatus,
    'addressStreet': addressStreet,
    'addressCity': addressCity,
    'letzteWaescheDatum': letzteWaescheDatum,
    'naechsteWaescheDatum': naechsteWaescheDatum,
    'letzteMaterialPruefungDatum': letzteMaterialPruefungDatum,
    'naechsteMaterialPruefungDatum': naechsteMaterialPruefungDatum,
    'verantwortlicherName': verantwortlicherName,
    'stockCount': stockCount,
  };

  bool get isMaintenanceNeeded =>
      wartungStatus != 'OK' && wartungStatus.isNotEmpty;
}

class DepotStockItem {
  final String productId;
  final String productName;
  final String? partNumber;
  final String? categoryName;
  final double menge;
  final String? unit;
  final String? qrToken;
  final String? inventoryNumberId;
  final String? inventoryNumberName;
  final double? minStock;

  DepotStockItem({
    required this.productId,
    required this.productName,
    this.partNumber,
    this.categoryName,
    required this.menge,
    this.unit = 'Stk.',
    this.qrToken,
    this.inventoryNumberId,
    this.inventoryNumberName,
    this.minStock,
  });

  factory DepotStockItem.fromJson(Map<String, dynamic> json) {
    return DepotStockItem(
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? 'Artikel',
      partNumber: json['partNumber']?.toString(),
      categoryName: json['categoryName']?.toString(),
      menge: (json['menge'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit']?.toString() ?? 'Stk.',
      qrToken: json['qrToken']?.toString(),
      inventoryNumberId: json['inventoryNumberId']?.toString(),
      inventoryNumberName: json['inventoryNumberName']?.toString(),
      minStock: (json['minStock'] as num?)?.toDouble(),
    );
  }

  bool get isLowStock => minStock != null && menge <= minStock!;
}

class PersonalEquipmentItem {
  final String id;
  final String name;
  final String? category;
  final double quantity;
  final String? size;
  final String? serialNumber;
  final String? ausstellungsdatum;
  final String? rueckgabeBis;
  final String status; // 'Ausgegeben', 'Zurückgegeben', etc.
  final String? warehouseName;

  PersonalEquipmentItem({
    required this.id,
    required this.name,
    this.category,
    required this.quantity,
    this.size,
    this.serialNumber,
    this.ausstellungsdatum,
    this.rueckgabeBis,
    this.status = 'Ausgegeben',
    this.warehouseName,
  });

  factory PersonalEquipmentItem.fromJson(Map<String, dynamic> json) {
    return PersonalEquipmentItem(
      id: json['id']?.toString() ?? '',
      name: json['product_name']?.toString() ?? json['name']?.toString() ?? 'Ausrüstungsgegenstand',
      category: json['category']?.toString(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      size: json['size']?.toString() ?? json['groesse']?.toString(),
      serialNumber: json['inventory_number']?.toString() ?? json['seriennummer']?.toString(),
      ausstellungsdatum: json['ausstellungsdatum']?.toString(),
      rueckgabeBis: json['rueckgabe_bis']?.toString(),
      status: json['status']?.toString() ?? 'Ausgegeben',
      warehouseName: json['warehouse_name']?.toString(),
    );
  }
}

class WarehouseScanResult {
  final String code;
  final String match; // 'warehouse', 'product', 'inventoryNumber', 'materialZuweisung', 'unknown'
  final WarehouseDepot? warehouse;
  final DepotStockItem? product;
  final Map<String, dynamic>? rawData;

  WarehouseScanResult({
    required this.code,
    required this.match,
    this.warehouse,
    this.product,
    this.rawData,
  });

  factory WarehouseScanResult.fromJson(Map<String, dynamic> json) {
    final scan = json['scan'] is Map<String, dynamic> ? json['scan'] as Map<String, dynamic> : json;
    final matchType = scan['match']?.toString() ?? 'unknown';

    WarehouseDepot? wh;
    if (scan['warehouse'] != null && scan['warehouse'] is Map<String, dynamic>) {
      wh = WarehouseDepot.fromJson(scan['warehouse'] as Map<String, dynamic>);
    }

    DepotStockItem? prod;
    if (scan['product'] != null && scan['product'] is Map<String, dynamic>) {
      final p = scan['product'] as Map<String, dynamic>;
      prod = DepotStockItem(
        productId: p['id']?.toString() ?? '',
        productName: p['name']?.toString() ?? '',
        partNumber: p['partNumber']?.toString(),
        categoryName: p['categoryName']?.toString(),
        menge: (p['bestand'] as num?)?.toDouble() ?? 1.0,
        qrToken: p['qrToken']?.toString(),
      );
    }

    return WarehouseScanResult(
      code: scan['code']?.toString() ?? '',
      match: matchType,
      warehouse: wh,
      product: prod,
      rawData: scan,
    );
  }

  bool get isWarehouse => match == 'warehouse' && warehouse != null;
  bool get isProduct => match == 'product' && product != null;
  bool get isFound => match != 'unknown';
}

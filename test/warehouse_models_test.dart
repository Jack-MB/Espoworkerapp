import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/warehouse_depot.dart';
import 'package:espo_worker_app/models/ordnerkarte_item.dart';
import 'package:espo_worker_app/models/material_request.dart';

void main() {
  group('WarehouseDepot Model Tests', () {
    test('Parses complete warehouse depot JSON successfully', () {
      final json = {
        'id': 'wh-001',
        'name': 'Objektlager Kaue Gelsenkirchen',
        'lagerTyp': 'Objektlager',
        'status': 'Aktiv',
        'qrToken': 'WH-OBJ-KAUE',
        'verantwortlicherId': 'ang-007',
        'verantwortlicherName': 'Stefan Kirsch',
        'wartungStatus': 'Prüfung fällig',
        'wartungIntervallTage': 30,
        'letzteWartungAm': '2026-09-01',
        'naechsteWartungAm': '2026-10-01',
        'addressStreet': 'Wilhelminenstraße 174',
        'addressCity': 'Gelsenkirchen',
        'addressPostalCode': '45881',
      };

      final depot = WarehouseDepot.fromJson(json);

      expect(depot.id, 'wh-001');
      expect(depot.name, 'Objektlager Kaue Gelsenkirchen');
      expect(depot.lagerTyp, 'Objektlager');
      expect(depot.qrToken, 'WH-OBJ-KAUE');
      expect(depot.verantwortlicherName, 'Stefan Kirsch');
      expect(depot.isMaintenanceNeeded, isTrue);
      expect(depot.addressCity, 'Gelsenkirchen');
    });

    test('Handles fallback defaults for missing optional fields', () {
      final json = {
        'id': 'wh-002',
      };

      final depot = WarehouseDepot.fromJson(json);

      expect(depot.id, 'wh-002');
      expect(depot.name, 'Unbenanntes Depot');
      expect(depot.lagerTyp, 'Objektlager');
      expect(depot.status, 'Active');
      expect(depot.qrToken, isNull);
      expect(depot.isMaintenanceNeeded, isFalse);
      expect(depot.verantwortlicherName, isNull);
    });
  });

  group('DepotStockItem Model Tests', () {
    test('Correctly identifies low stock condition', () {
      final normalItem = DepotStockItem.fromJson({
        'productId': 'prod-10',
        'productName': 'Einsatzjacke MB Security Gr. L',
        'partNumber': 'CLOTH-JCK-L',
        'menge': 8.0,
        'minStock': 3.0,
        'unit': 'Stück',
        'categoryName': 'Dienstkleidung',
        'qrToken': 'PR-CLOTH-JCK-L',
      });

      final lowStockItem = DepotStockItem.fromJson({
        'productId': 'prod-11',
        'productName': 'Pfefferspray RSG-4',
        'menge': 1.0,
        'minStock': 5.0,
        'unit': 'Stück',
      });

      expect(normalItem.isLowStock, isFalse);
      expect(lowStockItem.isLowStock, isTrue);
      expect(normalItem.partNumber, 'CLOTH-JCK-L');
      expect(normalItem.qrToken, 'PR-CLOTH-JCK-L');
    });
  });

  group('PersonalEquipmentItem Model Tests', () {
    test('Parses personal equipment item with serial number and category', () {
      final json = {
        'id': 'eq-99',
        'name': 'Motorola Funkgerät DP4400e',
        'category': 'Funktechnik',
        'quantity': 1.0,
        'unit': 'Stück',
        'inventory_number': 'SN-MOT-88912',
        'size': null,
      };

      final item = PersonalEquipmentItem.fromJson(json);

      expect(item.id, 'eq-99');
      expect(item.name, 'Motorola Funkgerät DP4400e');
      expect(item.serialNumber, 'SN-MOT-88912');
      expect(item.quantity, 1.0);
      expect(item.size, isNull);
    });
  });

  group('WarehouseScanResult Model Tests', () {
    test('Parses resolved warehouse scan payload', () {
      final json = {
        'scan': {
          'status': 'success',
          'match': 'warehouse',
          'code': 'WH-OBJ-KAUE',
          'warehouse': {
            'id': 'wh-001',
            'name': 'Objektlager Kaue Gelsenkirchen',
            'lagerTyp': 'Objektlager',
            'qrToken': 'WH-OBJ-KAUE',
          },
        },
      };

      final result = WarehouseScanResult.fromJson(json);

      expect(result.isFound, isTrue);
      expect(result.isWarehouse, isTrue);
      expect(result.isProduct, isFalse);
      expect(result.warehouse?.name, 'Objektlager Kaue Gelsenkirchen');
    });

    test('Parses resolved product scan payload', () {
      final json = {
        'scan': {
          'status': 'success',
          'match': 'product',
          'code': 'PR-SHIRT-M',
          'product': {
            'id': 'prod-200',
            'name': 'Poloshirt Security Schwarz Gr. M',
            'partNumber': 'ART-SHIRT-M',
            'bestand': 12.0,
          },
        },
      };

      final result = WarehouseScanResult.fromJson(json);

      expect(result.isFound, isTrue);
      expect(result.isProduct, isTrue);
      expect(result.isWarehouse, isFalse);
      expect(result.product?.productName, 'Poloshirt Security Schwarz Gr. M');
      expect(result.product?.menge, 12.0);
    });
  });

  group('Multi-Verantwortliche & WMS Extension Tests', () {
    test('Parses multi-responsibles and counts in WarehouseDepot', () {
      final json = {
        'id': 'wh-005',
        'name': 'Arena AufSchalke Objektlager',
        'lagerTyp': 'Objektlager',
        'status': 'Aktiv',
        'verantwortlicherId': 'ang-100',
        'verantwortlicherName': 'Stefan Kirsch',
        'weitereVerantwortlicheNames': ['Max Mustermann', 'Anna Schmidt'],
        'weitereVerantwortlicheIds': ['ang-101', 'ang-102'],
        'userRole': 'Hauptverantwortlicher',
        'ordnerkartenCount': 120,
        'openMaterialRequestsCount': 3,
      };

      final depot = WarehouseDepot.fromJson(json);

      expect(depot.id, 'wh-005');
      expect(depot.verantwortlicherName, 'Stefan Kirsch');
      expect(depot.weitereVerantwortlicheNames.length, 2);
      expect(depot.weitereVerantwortlicheNames, contains('Max Mustermann'));
      expect(depot.weitereVerantwortlicheNames, contains('Anna Schmidt'));
      expect(depot.userRole, 'Hauptverantwortlicher');
      expect(depot.ordnerkartenCount, 120);
      expect(depot.openMaterialRequestsCount, 3);
    });

    test('Identifies deputy user role correctly', () {
      final json = {
        'id': 'wh-006',
        'name': 'Nordsternpark Objektlager',
        'userRole': 'Stellvertreter',
      };

      final depot = WarehouseDepot.fromJson(json);
      expect(depot.userRole, 'Stellvertreter');
    });
  });

  group('OrdnerkarteItem Model Tests', () {
    test('Parses Ordnerkarte with range and single numbers', () {
      final json = {
        'id': 'ok-001',
        'name': 'Nordtribüne Block A (001 - 050)',
        'kartentyp': 'Standard',
        'nummernkreis': '001 - 050',
        'vonNummer': 1,
        'bisNummer': 50,
        'einzelnummern': '001, 002, 003',
        'anzahl': 50,
        'status': 'Im Depot',
        'warehouseId': 'wh-005',
        'description': 'Ausgabe an Gate 1',
      };

      final item = OrdnerkarteItem.fromJson(json);

      expect(item.id, 'ok-001');
      expect(item.name, 'Nordtribüne Block A (001 - 050)');
      expect(item.kartentyp, 'Standard');
      expect(item.nummernkreis, '001 - 050');
      expect(item.vonNummer, 1);
      expect(item.bisNummer, 50);
      expect(item.anzahl, 50);
      expect(item.status, 'Im Depot');
      expect(item.isImDepot, isTrue);
      expect(item.description, 'Ausgabe an Gate 1');
      expect(item.warehouseId, 'wh-005');
    });

    test('Parses personal Ordnerkarte assigned to employee', () {
      final json = {
        'id': 'ok-002',
        'name': 'Pausenkarte Jan von Czapiewski',
        'kartentyp': 'Pausenkarten',
        'nummernkreis': 'PK-42',
        'anzahl': 1,
        'status': 'Ausgegeben',
        'warehouseId': 'wh-005',
        'angestellteName': 'Jan von Czapiewski',
      };

      final item = OrdnerkarteItem.fromJson(json);

      expect(item.id, 'ok-002');
      expect(item.kartentyp, 'Pausenkarten');
      expect(item.angestellteName, 'Jan von Czapiewski');
      expect(item.anzahl, 1);
      expect(item.isAusgegeben, isTrue);
    });
  });

  group('MaterialRequest Models Tests', () {
    test('Parses CatalogProduct and handles clothing detection', () {
      final jsonClothing = {
        'id': 'prod-001',
        'name': 'Einsatzjacke Security',
        'category': 'PSA / Bekleidung',
        'hasSizes': true,
        'isCard': false,
      };

      final prod = CatalogProduct.fromJson(jsonClothing);

      expect(prod.id, 'prod-001');
      expect(prod.name, 'Einsatzjacke Security');
      expect(prod.hasSizes, isTrue);
      expect(prod.isCard, isFalse);
    });

    test('Serializes and deserializes MaterialRequestItem', () {
      final itemJson = {
        'id': 'item-001',
        'name': 'Handfunkgerät Kenwood TK-3501',
        'productId': 'prod-002',
        'productName': 'Handfunkgerät Kenwood TK-3501',
        'mengeBeantragt': 4.0,
        'einheit': 'Stück',
        'groesse': null,
        'ordnerkartenNummern': null,
        'bemerkung': 'Inklusive 4x Akku',
      };

      final fromJson = MaterialRequestItem.fromJson(itemJson);
      expect(fromJson.productName, 'Handfunkgerät Kenwood TK-3501');
      expect(fromJson.mengeBeantragt, 4.0);
      expect(fromJson.bemerkung, 'Inklusive 4x Akku');
    });

    test('Parses MaterialRequestHeader and checks delivery status', () {
      final json = {
        'id': 'req-999',
        'name': 'MA-2026-00001',
        'status': 'In Zustellung',
        'dringlichkeit': 'Hoch',
        'benoetigtBis': '2026-10-12 18:00',
        'bereich': 'VIP Eingang',
        'zielLagerId': 'wh-005',
        'zielLagerName': 'Arena AufSchalke Objektlager',
        'itemCount': 1,
        'totalMenge': 10.0,
        'createdAt': '2026-10-12 09:00:00',
        'items': [
          {
            'id': 'item-10',
            'name': 'Absperrgitter Mannesmann',
            'productId': 'prod-10',
            'productName': 'Absperrgitter Mannesmann',
            'mengeBeantragt': 10.0,
            'einheit': 'Stück',
          }
        ],
      };

      final req = MaterialRequestHeader.fromJson(json);

      expect(req.id, 'req-999');
      expect(req.name, 'MA-2026-00001');
      expect(req.isPendingReceipt, isTrue);
      expect(req.isHighPriority, isTrue);
      expect(req.items.length, 1);
      expect(req.items.first.productName, 'Absperrgitter Mannesmann');
    });
  });
}

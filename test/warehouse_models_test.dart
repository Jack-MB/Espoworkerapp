import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/warehouse_depot.dart';

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
}

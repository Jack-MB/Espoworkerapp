import 'package:flutter_test/flutter_test.dart';
import 'package:espo_worker_app/models/app_update_info.dart';

void main() {
  group('AppUpdateInfo Model Tests', () {
    test('parses JSON with explicit appStoreUrl', () {
      final json = {
        'status': 'success',
        'isUpdateAvailable': true,
        'isForceUpdate': false,
        'latestVersion': '1.3.30',
        'latestBuild': 56,
        'clientVersion': '1.3.29',
        'clientBuild': 55,
        'releaseNotes': 'Offizieller Apple App Store Release',
        'downloadUrl': 'https://apps.apple.com/us/app/espoworker/id6762371770',
        'appStoreUrl': 'https://apps.apple.com/us/app/espoworker/id6762371770',
        'testFlightUrl': 'https://apps.apple.com/us/app/espoworker/id6762371770',
        'fileSizeBytes': 10485760, // 10 MB
        'sha256': 'abc123hash',
      };

      final info = AppUpdateInfo.fromJson(json);

      expect(info.latestVersion, equals('1.3.30'));
      expect(info.latestBuild, equals(56));
      expect(info.clientVersion, equals('1.3.29'));
      expect(info.clientBuild, equals(55));
      expect(info.isUpdateAvailable, isTrue);
      expect(info.isForceUpdate, isFalse);
      expect(info.appStoreUrl, equals('https://apps.apple.com/us/app/espoworker/id6762371770'));
      expect(info.testFlightUrl, equals('https://apps.apple.com/us/app/espoworker/id6762371770'));
      expect(info.formattedFileSize, equals('10.0 MB'));
    });

    test('falls back to testFlightUrl if appStoreUrl is absent (backward compatibility)', () {
      final json = {
        'latestVersion': '1.3.29',
        'latestBuild': 55,
        'clientVersion': '1.3.28',
        'clientBuild': 54,
        'isUpdateAvailable': true,
        'isForceUpdate': false,
        'releaseNotes': 'TestFlight Update',
        'downloadUrl': 'https://testflight.apple.com/join/legacy',
        'testFlightUrl': 'https://testflight.apple.com/join/legacy',
        'fileSizeBytes': 0,
        'sha256': '',
      };

      final info = AppUpdateInfo.fromJson(json);

      expect(info.appStoreUrl, equals('https://testflight.apple.com/join/legacy'));
      expect(info.testFlightUrl, equals('https://testflight.apple.com/join/legacy'));
      expect(info.formattedFileSize, isEmpty);
    });

    test('handles missing or malformed fields gracefully', () {
      final json = <String, dynamic>{};
      final info = AppUpdateInfo.fromJson(json);

      expect(info.latestVersion, equals('0.0.0'));
      expect(info.latestBuild, equals(0));
      expect(info.clientVersion, equals('0.0.0'));
      expect(info.clientBuild, equals(0));
      expect(info.isUpdateAvailable, isFalse);
      expect(info.isForceUpdate, isFalse);
      expect(info.appStoreUrl, isNull);
      expect(info.testFlightUrl, isNull);
    });
  });
}

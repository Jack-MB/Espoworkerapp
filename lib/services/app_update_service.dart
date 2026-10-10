import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/server_config.dart';
import '../models/app_update_info.dart';
import '../widgets/app_update_dialog.dart';
import 'secure_storage_service.dart';

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  final SecureStorageService _storage = SecureStorageService();
  bool _isChecking = false;
  DateTime? _lastPromptTime;

  /// Ermittelt die aktuell installierte Version der App
  Future<Map<String, dynamic>> getCurrentAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return {
        'version': info.version.isNotEmpty ? info.version : AppConstants.appVersion,
        'build': int.tryParse(info.buildNumber) ?? AppConstants.appBuildNumber,
      };
    } catch (_) {
      return {
        'version': AppConstants.appVersion,
        'build': AppConstants.appBuildNumber,
      };
    }
  }

  /// Prüft gegen EspoCRM, ob ein Update für diese Plattform vorliegt
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (_isChecking) return null;
    _isChecking = true;

    try {
      final current = await getCurrentAppVersion();
      final String version = current['version'].toString();
      final int build = current['build'] as int;

      String platform = 'android';
      if (kIsWeb) {
        platform = 'web';
      } else if (Platform.isIOS) {
        platform = 'ios';
      }

      final uri = Uri.parse(
        '${ServerConfig().apiUrl}/AppUpdate/check'
        '?app=worker&platform=$platform&version=$version&build=$build',
      );

      final headers = <String, String>{
        'Accept': 'application/json',
      };

      // Authentifizierungstoken mitsenden, falls eingeloggt (für Geräte-Telemetrie)
      final token = await _storage.getToken();
      if (token != null && token.isNotEmpty) {
        if (token.startsWith('ApiKey ')) {
          headers['X-Api-Key'] = token.substring(7);
        } else if (token.startsWith('Basic ')) {
          headers['Authorization'] = token;
        } else {
          headers['X-Api-Key'] = token;
        }
      }

      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['status'] == 'success') {
          return AppUpdateInfo.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[AppUpdateService] Fehler bei Update-Prüfung: $e');
      return null;
    } finally {
      _isChecking = false;
    }
  }

  /// Prüft automatisch und zeigt den Update-Dialog, falls verfügbar.
  Future<void> checkAndPrompt(BuildContext context, {bool autoPrompt = true}) async {
    // Bei automatischem Check nur alle 15 Minuten erneut prüfen (außer bei manuellem Check)
    if (autoPrompt && _lastPromptTime != null) {
      final diff = DateTime.now().difference(_lastPromptTime!);
      if (diff.inMinutes < 15) return;
    }

    final updateInfo = await checkForUpdate();
    if (updateInfo == null || !updateInfo.isUpdateAvailable) {
      if (!autoPrompt && context.mounted) {
        final current = await getCurrentAppVersion();
        final currentVer = current['version']?.toString() ?? AppConstants.appVersion;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb 
                ? 'Ihre Web-App ist auf dem neuesten Stand (v$currentVer)!'
                : 'Ihre App ist auf dem neuesten Stand (v$currentVer)!',
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    _lastPromptTime = DateTime.now();

    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: !updateInfo.isForceUpdate,
      builder: (ctx) => AppUpdateDialog(updateInfo: updateInfo),
    );
  }

  /// Lädt das Release-APK herunter und startet den nativen Android Package-Installer
  Future<void> downloadAndInstallApk(
    AppUpdateInfo info, {
    required void Function(double progress, int received, int total) onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download fehlgeschlagen: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? info.fileSizeBytes;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/mb_scc_worker_update.apk');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          onProgress(progress, receivedBytes, totalBytes);
        }
      }

      await sink.flush();
      await sink.close();

      // Native Installation über Android Intent starten
      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        debugPrint('[AppUpdateService] OpenFilex Ergebnis: ${result.message}');
      }
    } finally {
      client.close();
    }
  }

  /// Öffnet den TestFlight Public Link oder Store auf iOS
  Future<bool> openTestFlightOrStore(AppUpdateInfo info) async {
    final targetUrl = info.testFlightUrl?.isNotEmpty == true 
        ? info.testFlightUrl! 
        : info.downloadUrl;

    final uri = Uri.parse(targetUrl);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Führt einen Cache-Bust und Reload der Web-PWA durch
  Future<void> reloadPwa() async {
    if (!kIsWeb) return;
    try {
      final uri = Uri.parse('/update.html');
      await launchUrl(uri, webOnlyWindowName: '_self');
    } catch (e) {
      debugPrint('[AppUpdateService] PWA Reload Fehler: $e');
    }
  }
}

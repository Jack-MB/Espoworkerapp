import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../services/secure_storage_service.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../services/web_push_service.dart';

class PushSettingsSheet extends StatefulWidget {
  final VoidCallback? onTokenSynced;

  const PushSettingsSheet({Key? key, this.onTokenSynced}) : super(key: key);

  static void show(BuildContext context, {VoidCallback? onTokenSynced}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PushSettingsSheet(onTokenSynced: onTokenSynced),
    );
  }

  @override
  State<PushSettingsSheet> createState() => _PushSettingsSheetState();
}

class _PushSettingsSheetState extends State<PushSettingsSheet> {
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isTesting = false;

  bool _systemPermissionGranted = false;
  String? _fcmToken;
  String? _statusMessage;
  bool _statusIsSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);

    bool granted = false;
    String? token;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      granted = await NotificationService().areNotificationsEnabled();
      token = await FirebaseService().getStoredOrCurrentToken();
    } else if (kIsWeb) {
      final perm = WebPushService().getNotificationPermission();
      granted = perm == 'granted';
      token = await SecureStorageService().read('fcm_token');
    } else {
      granted = true;
      token = await SecureStorageService().read('fcm_token');
    }

    if (mounted) {
      setState(() {
        _systemPermissionGranted = granted;
        _fcmToken = token;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSyncToken() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = null;
    });

    try {
      String? token;
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        token = await FirebaseService().requestPermissionAndSyncToken();
      } else if (kIsWeb) {
        await WebPushService().initWebPush();
        token = await SecureStorageService().read('fcm_token');
        if (token == null || token.isEmpty) {
          throw Exception('WebPush konnte keinen Token anfordern.');
        }
      }

      await _loadStatus();

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _statusIsSuccess = true;
          _statusMessage = '✅ Token erfolgreich mit EspoCRM synchronisiert!';
        });
        widget.onTokenSynced?.call();
      }
    } catch (e) {
      debugPrint('Sync token error: $e');
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _statusIsSuccess = false;
          final cleanErr = e.toString().replaceFirst('Exception: ', '');
          _statusMessage = '⚠️ $cleanErr';
        });
      }
    }
  }

  Future<void> _handleSendTestPush() async {
    setState(() {
      _isTesting = true;
      _statusMessage = null;
    });

    try {
      final success = await ApiService().sendTestPush();
      if (mounted) {
        setState(() {
          _isTesting = false;
          if (success) {
            _statusIsSuccess = true;
            _statusMessage = '🎉 Test-Push versendet! Bitte Benachrichtigungsleiste prüfen.';
          } else {
            _statusIsSuccess = false;
            _statusMessage = '❌ Senden fehlgeschlagen. Bitte erst Token synchronisieren.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _statusIsSuccess = false;
          _statusMessage = 'Fehler beim Senden: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = theme.primaryColor;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? Colors.white12 : Colors.black.withOpacity(0.08);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 25, offset: Offset(0, -5)),
        ],
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Header Row
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, primaryColor.withOpacity(0.75)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.notifications_active, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Push-Benachrichtigungen',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Status & Geräte-Synchronisation',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                // Status Box 1: Android System Permission
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _systemPermissionGranted
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.red.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _systemPermissionGranted ? Icons.check : Icons.warning_amber_rounded,
                              color: _systemPermissionGranted ? Colors.green : Colors.red,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Smartphone-Systemberechtigung',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _systemPermissionGranted
                                      ? (!kIsWeb && Platform.isIOS
                                          ? 'In iOS-Mitteilungen erlaubt'
                                          : 'In Android-Einstellungen erlaubt')
                                      : (!kIsWeb && Platform.isIOS
                                          ? 'In iOS noch nicht erlaubt / blockiert'
                                          : 'In Android noch nicht erlaubt / blockiert'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _systemPermissionGranted ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (!_systemPermissionGranted && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              if (Platform.isIOS) {
                                await FirebaseService().requestPermissionAndSyncToken();
                              } else {
                                await NotificationService().requestPermission();
                              }
                              await _loadStatus();
                            },
                            icon: const Icon(Icons.notifications_active_outlined, size: 16),
                            label: const Text('Berechtigung jetzt anfragen', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Status Box 2: Firebase Token
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (_fcmToken != null && _fcmToken!.isNotEmpty)
                              ? Colors.green.withOpacity(0.15)
                              : Colors.orange.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (_fcmToken != null && _fcmToken!.isNotEmpty)
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                          color: (_fcmToken != null && _fcmToken!.isNotEmpty)
                              ? Colors.green
                              : Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EspoCRM Push-Registrierung',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (_fcmToken != null && _fcmToken!.isNotEmpty)
                                  ? 'FCM-Token registriert & aktiv'
                                  : 'Noch kein Token auf dem Server hinterlegt',
                              style: TextStyle(
                                fontSize: 12,
                                color: (_fcmToken != null && _fcmToken!.isNotEmpty)
                                    ? Colors.green
                                    : Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_fcmToken != null && _fcmToken!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Token: ${_fcmToken!.substring(0, _fcmToken!.length > 16 ? 16 : _fcmToken!.length)}...',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Status Message Feedback Banner
                if (_statusMessage != null) ...[
                  const SizedBox(height: 14),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _statusMessage!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Meldung in die Zwischenablage kopiert'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _statusIsSuccess
                              ? Colors.green.withOpacity(0.15)
                              : Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _statusIsSuccess ? Colors.green.shade400 : Colors.orange.shade400,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _statusIsSuccess ? Icons.check_circle : Icons.info_outline,
                              color: _statusIsSuccess ? Colors.green : Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _statusIsSuccess ? Colors.green : Colors.orange,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: (_statusIsSuccess ? Colors.green : Colors.orange).withOpacity(0.6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Action Button 1: Token synchronisieren
                ElevatedButton.icon(
                  onPressed: (_isSyncing || _isTesting) ? null : _handleSyncToken,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.sync, size: 20),
                  label: Text(
                    _isSyncing ? 'Wird synchronisiert...' : 'Token jetzt synchronisieren',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                ),

                const SizedBox(height: 10),

                // Action Button 2: Test-Push senden
                OutlinedButton.icon(
                  onPressed: (_isSyncing || _isTesting) ? null : _handleSendTestPush,
                  icon: _isTesting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isDark ? Colors.white : primaryColor,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _isTesting ? 'Sende Test-Push...' : 'Test-Push an dieses Gerät senden',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : primaryColor,
                    side: BorderSide(color: primaryColor.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                // Help Box if Permission Denied
                if (!_systemPermissionGranted && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            Text(
                              Platform.isIOS
                                  ? 'So aktivierst du Mitteilungen auf dem iPhone:'
                                  : 'So aktivierst du Benachrichtigungen in Android:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Platform.isIOS
                              ? '1. Öffne die iPhone-Einstellungen.\n'
                                '2. Scrolle zu "MB-Security" (oder "Mitteilungen").\n'
                                '3. Tippe auf "Mitteilungen" und aktiviere "Mitteilungen erlauben".\n'
                                '4. Kehre zur App zurück und tippe oben auf "Token jetzt synchronisieren".'
                              : '1. Öffne die Android-Einstellungen deines Handys.\n'
                                '2. Gehe zu Apps ➔ "MB-Worker".\n'
                                '3. Wähle "Benachrichtigungen" und schalte "Alle Benachrichtigungen zulassen" auf AN.\n'
                                '4. Kehre zur App zurück und tippe oben auf "Token jetzt synchronisieren".',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

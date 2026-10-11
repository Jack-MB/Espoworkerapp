import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../providers/theme_provider.dart';
import '../services/app_update_service.dart';
import '../widgets/push_settings_sheet.dart';
import 'change_password_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isCheckingUpdate = false;
  String _appVersion = AppConstants.appVersion;
  int _appBuild = AppConstants.appBuildNumber;

  @override
  void initState() {
    super.initState();
    _initVersionInfo();
  }

  Future<void> _initVersionInfo() async {
    final info = await AppUpdateService().getCurrentAppVersion();
    if (mounted) {
      setState(() {
        _appVersion = info['version']?.toString() ?? AppConstants.appVersion;
        _appBuild = int.tryParse(info['build']?.toString() ?? '') ?? AppConstants.appBuildNumber;
      });
    }
  }

  void _triggerUpdateCheck() async {
    setState(() => _isCheckingUpdate = true);
    try {
      await AppUpdateService().checkAndPrompt(context, autoPrompt: false);
      await _initVersionInfo();
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentThemeKey = themeProvider.selectedThemeName;
    final activeThemeColors = AppConstants.themes[currentThemeKey] ?? AppConstants.themes['Espo']!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // ── 1. ERSCHEINUNGSBILD (FARBSCHEMA & DARK MODE) ──
          _buildSectionHeader(context, 'Erscheinungsbild', Icons.palette_outlined),
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.color_lens, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Farbschema',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const Spacer(),
                      Text(
                        currentThemeKey,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: AppConstants.themes.keys.map((themeName) {
                      final themeColors = AppConstants.themes[themeName]!;
                      final primary = themeColors['primary']!;
                      final isSelected = currentThemeKey == themeName;

                      return Tooltip(
                        message: themeName,
                        child: GestureDetector(
                          onTap: () => themeProvider.setColorTheme(themeName),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.white24,
                                width: isSelected ? 3.5 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: primary.withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const Divider(height: 28),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      color: isDark ? Colors.amberAccent : Colors.orange,
                    ),
                    title: const Text('Dunkles Design (Dark Mode)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    subtitle: Text(
                      isDark ? 'Schont den Akku und die Augen' : 'Helles Standard-Design aktiv',
                      style: const TextStyle(fontSize: 12),
                    ),
                    activeColor: activeThemeColors['secondary'],
                    value: themeProvider.themeMode == ThemeMode.dark,
                    onChanged: (value) {
                      themeProvider.setMode(value ? ThemeMode.dark : ThemeMode.light);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── 2. MITTEILUNGEN & BENACHRICHTIGUNGEN ──
          _buildSectionHeader(context, 'Benachrichtigungen', Icons.notifications_active_outlined),
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_active, color: Colors.blueAccent),
              ),
              title: const Text('Push-Benachrichtigungen', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Schichtänderungen, Erinnerungen & Updates verwalten', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                PushSettingsSheet.show(context);
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── 3. KONTO & SICHERHEIT ──
          _buildSectionHeader(context, 'Konto & Sicherheit', Icons.security_outlined),
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock_rounded, color: Colors.green),
              ),
              title: const Text('Passwort ändern', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Aktualisieren Sie Ihr persönliches Zugangspasswort', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── 4. APP & SYSTEM ──
          _buildSectionHeader(context, 'App & System', Icons.info_outline),
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isCheckingUpdate
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple),
                          )
                        : const Icon(Icons.system_update_rounded, color: Colors.purple),
                  ),
                  title: const Text('Auf Updates prüfen', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Installierte Version: v$_appVersion+$_appBuild', style: const TextStyle(fontSize: 12)),
                  trailing: ElevatedButton(
                    onPressed: _isCheckingUpdate ? null : _triggerUpdateCheck,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Prüfen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.verified_outlined, color: Colors.orange),
                  ),
                  title: const Text('Build & Umgebung', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    kIsWeb ? 'PWA Web-Client (Build $_appBuild) • iOS / Android / Desktop' : 'Android Native APK (Build $_appBuild) • MB-SCC Security',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Footer
          Center(
            child: Column(
              children: [
                Text(
                  'MB-SCC GmbH • Sicherheitsdienst & Facility',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mitarbeiter-Portal v$_appVersion+$_appBuild',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

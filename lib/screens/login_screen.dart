import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../services/web_biometric_service.dart';
import '../core/constants.dart';
import '../core/server_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/acl_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController = TextEditingController();
  final _apiService = ApiService();
  final _secureStorage = SecureStorageService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  bool _isLoading = false;
  String? _errorMessage;
  bool _canCheckBiometrics = false;       // native (local_auth)
  bool _canCheckWebBiometrics = false;    // web (WebAuthn)
  bool _webBiometricEnabled = false;      // WebAuthn bereits registriert
  bool _hasSavedCredentials = false;
  bool? _serverOnline;
  bool _isRooted = false;
  final _webBiometric = WebBiometricService();

  /// Whether the user needs to configure a server URL (first launch or manual change)
  bool _showServerUrlField = false;
  /// Whether a valid server URL is already saved
  bool _hasServerUrl = false;
  /// Whether the server URL is currently being validated
  bool _isValidatingUrl = false;
  /// Whether the entered URL has been validated successfully
  bool _urlValidated = false;

  @override
  void initState() {
    super.initState();
    _checkSecurity();
    _checkBiometricAvailability();
    _checkSavedCredentials();
    _checkServerUrl();
    if (kIsWeb) _checkWebBiometricAvailability();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _checkForNativeUpdate();
      }
    });
  }

  Future<void> _checkForNativeUpdate() async {
    if (kIsWeb) return; // In der Webversion niemals einen Download oder Update-Popup anbieten
    try {
      final response = await http.get(Uri.parse('https://app.mb-scc.net/download/version.json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestBuild = data['buildNumber'] as int?;
        if (latestBuild != null && latestBuild > AppConstants.appBuildNumber) {
          _showUpdatePopup(data['version'], data['url']);
        }
      }
    } catch (_) {
      // Silently fail if offline or unavailable
    }
  }

  void _showUpdatePopup(String? latestVersion, String? downloadUrl) {
    if (kIsWeb) return; // Kein Download-Link im Web
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Update verfügbar!'),
        content: Text('Eine neue Version der MB-SCC App ($latestVersion) ist verfügbar. Bitte aktualisieren Sie die App, um die neuesten Funktionen zu nutzen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Später'),
          ),
          ElevatedButton(
            onPressed: () {
              if (downloadUrl != null) {
                launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Jetzt herunterladen'),
          ),
        ],
      ),
    );
  }


  Future<void> _checkServerUrl() async {
    setState(() {
      _hasServerUrl = true;
      _showServerUrlField = false;
    });
    _checkServerStatus();
  }

  Future<void> _checkSecurity() async {
    if (kIsWeb) return; // Not supported on Web
  }

  Future<void> _checkServerStatus() async {
    if (!ServerConfig().isConfigured) return;
    final status = await _apiService.pingServer();
    if (mounted) setState(() => _serverOnline = status);
  }

  Future<void> _checkBiometricAvailability() async {
    if (kIsWeb) return; // Web uses WebAuthn instead
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('mobile_biometric_enabled') ?? false;
      if (mounted) {
        setState(() {
          _canCheckBiometrics = canCheck || isDeviceSupported;
        });
      }
      if ((canCheck || isDeviceSupported) && isEnabled && _hasSavedCredentials && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        _authenticateWithBiometrics();
      }
    } on PlatformException catch (_) {
      // Ignore
    }
  }

  /// Prüft WebAuthn-Verfügbarkeit (nur Web/PWA)
  Future<void> _checkWebBiometricAvailability() async {
    final available = await _webBiometric.isPlatformAvailable();
    final enabled = _webBiometric.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _canCheckWebBiometrics = available;
        _webBiometricEnabled = enabled;
      });
    }
    // Wenn Biometrie aktiviert und Credentials vorhanden: direkt anbieten
    if (available && enabled && _hasSavedCredentials && mounted) {
      // Kurze Verzögerung damit die UI fertig gebaut ist
      await Future.delayed(const Duration(milliseconds: 500));
      _authenticateWithWebBiometrics();
    }
  }

  Future<void> _checkSavedCredentials() async {
    final username = await _secureStorage.getUsername();
    final password = await _secureStorage.getPassword();
    
    if (username != null && username.isNotEmpty) {
      _usernameController.text = username;
    }
    
    if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
      if (mounted) {
        setState(() => _hasSavedCredentials = true);
      }
    }
  }

  /// Validates the server URL by pinging the EspoCRM API
  Future<void> _validateServerUrl() async {
    final url = _serverUrlController.text.trim();
    
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Bitte geben Sie die Server-URL ein.');
      return;
    }

    // Basic URL validation
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _errorMessage = 'Die URL muss mit https:// oder http:// beginnen.');
      return;
    }

    setState(() {
      _isValidatingUrl = true;
      _errorMessage = null;
    });

    final isValid = await ApiService.pingCustomUrl(url);

    if (!mounted) return;

    if (isValid) {
      // Save the URL and activate it
      await ServerConfig().saveAndSetBaseUrl(url);
      
      setState(() {
        _isValidatingUrl = false;
        _urlValidated = true;
        _hasServerUrl = true;
        _showServerUrlField = false;
        _errorMessage = null;
      });

      // Now check server status with the new URL
      _checkServerStatus();
    } else {
      setState(() {
        _isValidatingUrl = false;
        _urlValidated = false;
        _errorMessage = 'Server nicht erreichbar oder kein gültiges EspoCRM.\nBitte überprüfen Sie die URL.';
      });
    }
  }

  Future<void> _login() async {
    if (_isRooted) {
      setState(() => _errorMessage = 'Sicherheitsfehler: System-Manipulation erkannt (Root/Jailbreak). Login blockiert.');
      return;
    }

    if (!ServerConfig().isConfigured) {
      setState(() => _errorMessage = 'Bitte zuerst die Server-URL konfigurieren.');
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Bitte Benutzernamen und Passwort eingeben.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await _apiService.login(username, password);

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (success) {
      // Refresh ACL status after successful login
      final acl = AclService();
      await acl.refresh();
      
      // Security check: If this is the admin app, user MUST be admin
      if (!acl.isAuthorized) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Zugriff verweigert: Diese App-Version ist nur für Administratoren zulässig.';
          });
        }
        return;
      }

      await _secureStorage.savePassword(password);
      
      // Notify the system that autofill was successful (saves password to iCloud/Google)
      TextInput.finishAutofillContext();

      // ── Biometrie-Aktivierung anbieten ─────────────────────────────
      if (kIsWeb && _canCheckWebBiometrics && !_webBiometricEnabled && mounted) {
        final offer = await _showBiometricSetupDialog();
        if (offer == true && mounted) {
          final credId = await _webBiometric.register(username, username);
          if (credId != null && mounted) {
            setState(() => _webBiometricEnabled = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Biometrische Anmeldung aktiviert!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else if (!kIsWeb && _canCheckBiometrics && mounted) {
        final prefs = await SharedPreferences.getInstance();
        final mobileBiometricOffered = prefs.getBool('mobile_biometric_offered') ?? false;
        if (!mobileBiometricOffered) {
          await prefs.setBool('mobile_biometric_offered', true);
          final offer = await _showBiometricSetupDialog();
          if (offer == true && mounted) {
            await prefs.setBool('mobile_biometric_enabled', true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Biometrische Anmeldung aktiviert!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
      // ────────────────────────────────────────────────────────────────
      
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = 'Login fehlgeschlagen. Bitte überprüfen Sie Ihre Eingaben.';
        });
      }
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    if (kIsWeb) return; // Web uses _authenticateWithWebBiometrics instead
    
    if (_isRooted) {
      setState(() => _errorMessage = 'Sicherheitsfehler: System-Manipulation erkannt (Root/Jailbreak). Login blockiert.');
      return;
    }

    if (!_hasSavedCredentials) {
      setState(() => _errorMessage = 'Keine gespeicherten Anmeldedaten für Biometrie gefunden. Bitte einmal manuell anmelden.');
      return;
    }

    if (!ServerConfig().isConfigured) {
      setState(() => _errorMessage = 'Bitte zuerst die Server-URL konfigurieren.');
      return;
    }

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Bitte authentifizieren Sie sich, um sich anzumelden.',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated) {
        final username = await _secureStorage.getUsername();
        final password = await _secureStorage.getPassword();
        
        if (username != null && password != null) {
          _usernameController.text = username;
          _passwordController.text = password;
          await _login();
        }
      }
    } on PlatformException catch (e) {
      setState(() => _errorMessage = 'Biometrie-Fehler: ${e.message}');
    }
  }

  /// Biometrische Anmeldung über WebAuthn (nur PWA/Browser)
  Future<void> _authenticateWithWebBiometrics() async {
    if (!kIsWeb || !_webBiometricEnabled) return;

    if (!_hasSavedCredentials) {
      setState(() => _errorMessage =
          'Keine gespeicherten Zugangsdaten. Bitte einmal manuell anmelden.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authenticated = await _webBiometric.authenticate();
      if (authenticated) {
        // Credentials aus SecureStorage laden und einloggen
        final username = await _secureStorage.getUsername();
        final password = await _secureStorage.getPassword();
        if (username != null && password != null) {
          _usernameController.text = username;
          _passwordController.text = password;
          await _login();
          return;
        }
      } else {
        if (mounted) setState(() => _errorMessage = 'Biometrie-Authentifizierung fehlgeschlagen oder abgebrochen.');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Biometrie-Fehler: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Zeigt den Dialog zur Aktivierung der biometrischen Anmeldung.
  Future<bool?> _showBiometricSetupDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fingerprint, color: Colors.blue, size: 28),
            SizedBox(width: 12),
            Text('Biometrische Anmeldung'),
          ],
        ),
        content: const Text(
          'Möchten Sie sich zukünftig mit Fingerabdruck, Face ID oder Windows Hello anmelden?\n\n'
          'Ihre Zugangsdaten werden sicher auf diesem Gerät gespeichert und nur nach erfolgreicher Biometrie freigegeben.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nein, danke'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.fingerprint),
            label: const Text('Aktivieren'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F17) : null,
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.85 : 0.4,
              child: Image.asset(
                'assets/images/bg_pattern.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Firmenlogo
                  GestureDetector(
                    onDoubleTap: () => Navigator.of(context).pushNamed('/adminlogin'),
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.45),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo_cyan.png',
                          width: 104,
                          height: 104,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Image.asset(
                            'assets/images/logo.png',
                            width: 104,
                            height: 104,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.shield,
                              size: 80,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'MB SECURITY',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                      const SizedBox(width: 10),
                      if (_serverOnline != null)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _serverOnline! ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_serverOnline! ? Colors.green : Colors.red).withOpacity(0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              )
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Concept & Consulting GmbH',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black54,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 24),

              // ─── SERVER URL SECTION ─────────────────────────────
              if (_showServerUrlField) ...[
                // Server URL configuration
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.blue.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns, size: 20, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Server-Konfiguration',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bitte geben Sie die URL Ihres EspoCRM-Servers ein:',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _serverUrlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Server-URL',
                          hintText: 'https://crm.beispiel.de',
                          prefixIcon: const Icon(Icons.link),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: _isValidatingUrl
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : _urlValidated
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _isValidatingUrl ? null : _validateServerUrl,
                          icon: const Icon(Icons.verified_user, size: 18),
                          label: Text(_isValidatingUrl ? 'Prüfe...' : 'Verbindung prüfen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      if (_hasServerUrl) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: () => setState(() {
                              _showServerUrlField = false;
                              _errorMessage = null;
                            }),
                            child: const Text('Abbrechen'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (_hasServerUrl) ...[
                // Compact server indicator with change option
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.dns, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          ServerConfig().baseUrl,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ─── ERROR MESSAGE ──────────────────────────────────
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: AppConstants.errorColor),
                    textAlign: TextAlign.center,
                  ),
                ),

              // ─── LOGIN FIELDS ───────────────────────────────────
              // Only show login fields when server is configured
              if (_hasServerUrl && !_showServerUrlField) ...[
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        controller: _usernameController,
                        autofillHints: const [AutofillHints.username],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Benutzername',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        keyboardType: TextInputType.visiblePassword,
                        onSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Passwort',
                          prefixIcon: const Icon(Icons.lock),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Anmelden',
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                // ─── Biometrie-Button (Native App) ──────────────────
                if (_canCheckBiometrics)
                  TextButton.icon(
                    onPressed: _isLoading ? null : _authenticateWithBiometrics,
                    style: TextButton.styleFrom(
                      foregroundColor: isDark 
                          ? Colors.lightBlueAccent 
                          : Theme.of(context).primaryColor,
                    ),
                    icon: const Icon(Icons.fingerprint, size: 28),
                    label: const Text(
                      'Mit Biometrie anmelden',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),

                // ─── Biometrie-Button (PWA / Web) ──────────────────
                if (_canCheckWebBiometrics && _webBiometricEnabled) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _authenticateWithWebBiometrics,
                      icon: const Icon(Icons.fingerprint, size: 26),
                      label: const Text(
                        'Mit Biometrie anmelden',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.lightBlueAccent : Colors.blue.shade700,
                        side: BorderSide(
                          color: isDark ? Colors.lightBlueAccent : Colors.blue.shade400,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        _webBiometric.clear();
                        setState(() => _webBiometricEnabled = false);
                      },
                      child: Text(
                        'Biometrie deaktivieren',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                ] else if (_canCheckWebBiometrics && !_webBiometricEnabled) ...[
                  // Hinweis: Biometrie verfügbar, aber noch nicht aktiviert
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '🔐 Biometrische Anmeldung verfügbar – nach dem Login aktivieren',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
}

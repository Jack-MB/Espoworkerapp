import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../core/constants.dart';
import '../core/server_config.dart';
import '../services/acl_service.dart';
import 'dashboard_screen.dart';
import 'package:safe_device/safe_device.dart';

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
  bool _canCheckBiometrics = false;
  bool _hasSavedCredentials = false;
  bool? _serverOnline;
  bool _isRooted = false;

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
  }

  Future<void> _checkServerUrl() async {
    final savedUrl = await _secureStorage.getServerUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      setState(() {
        _hasServerUrl = true;
        _showServerUrlField = false;
        _serverUrlController.text = savedUrl;
      });
      _checkServerStatus();
    } else {
      setState(() {
        _hasServerUrl = false;
        _showServerUrlField = true;
      });
    }
  }

  Future<void> _checkSecurity() async {
    try {
      final isRooted = await SafeDevice.isJailBroken;
      if (isRooted && mounted) {
        setState(() => _isRooted = true);
      }
    } catch (_) {}
  }

  Future<void> _checkServerStatus() async {
    if (!ServerConfig().isConfigured) return;
    final status = await _apiService.pingServer();
    if (mounted) setState(() => _serverOnline = status);
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(() {
          _canCheckBiometrics = canCheck || isDeviceSupported;
        });
      }
    } on PlatformException catch (_) {
      // Ignore
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
      await AclService().refresh();
      await _secureStorage.savePassword(password);
      
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

  void _showChangeServerDialog() {
    setState(() {
      _showServerUrlField = true;
      _urlValidated = false;
      _serverOnline = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo — only show if server is configured
              if (_hasServerUrl && ServerConfig().isConfigured)
                Image.network(
                  '${ServerConfig().baseUrl}/?entryPoint=LogoImage&id=65831620982c96e7c',
                  height: 80,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.business,
                    size: 80,
                    color: Theme.of(context).primaryColor,
                  ),
                )
              else
                Icon(
                  Icons.dns_rounded,
                  size: 80,
                  color: Theme.of(context).primaryColor,
                ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'MB-SCC',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
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
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _showChangeServerDialog,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.edit, size: 14, color: Theme.of(context).primaryColor),
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
                TextField(
                  controller: _usernameController,
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
                  decoration: InputDecoration(
                    labelText: 'Passwort',
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}

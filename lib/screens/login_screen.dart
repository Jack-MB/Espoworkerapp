import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../core/constants.dart';
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
  final _apiService = ApiService();
  final _secureStorage = SecureStorageService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  bool _isLoading = false;
  String? _errorMessage;
  bool _canCheckBiometrics = false;
  bool _hasSavedCredentials = false;
  bool? _serverOnline;
  bool _isRooted = false;

  @override
  void initState() {
    super.initState();
    _checkSecurity();
    _checkBiometricAvailability();
    _checkSavedCredentials();
    _checkServerStatus();
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

  Future<void> _login() async {
    if (_isRooted) {
      setState(() => _errorMessage = 'Sicherheitsfehler: System-Manipulation erkannt (Root/Jailbreak). Login blockiert.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.network(
                '${AppConstants.baseUrl}/?entryPoint=LogoImage&id=65831620982c96e7c',
                height: 80,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.business,
                  size: 80,
                  color: Theme.of(context).primaryColor,
                ),
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
              const SizedBox(height: 32),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: AppConstants.errorColor),
                    textAlign: TextAlign.center,
                  ),
                ),
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
                    foregroundColor: Theme.of(context).brightness == Brightness.dark 
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
          ),
        ),
      ),
    );
  }
}

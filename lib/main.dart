import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/self_checkin_screen.dart';
import 'providers/theme_provider.dart';
import 'core/app_theme.dart';
import 'services/acl_service.dart';
import 'core/server_config.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';
import 'services/polling_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load dynamic server URL from secure storage
  await ServerConfig().init();
  
  if (!kIsWeb) {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Initialize Firebase core FIRST with explicit options
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('Firebase Core initialized successfully');
      }
    } catch (e) {
      debugPrint('Firebase Core init error: $e');
    }

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Initialize Firebase messaging listeners & handlers
        await FirebaseService().init();
        
        // Initialize local notifications
        await NotificationService().initialize();
      }

      if (Platform.isAndroid) {
        // Initialize background worker (Android only)
        await PollingService().initialize();
        // Start polling every 15 minutes (Android minimum)
        await PollingService().schedulePolling(const Duration(minutes: 15));
      }
    } catch (e) {
      debugPrint('Native services init error: $e');
    }
  }

  // Initialize ACL service on all platforms (Web, iOS, Android)
  try {
    await AclService().init();
  } catch (e) {
    debugPrint('AclService init error: $e');
  }

  runApp(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: const EspoWorkerApp(),
    ),
  );
}

class EspoWorkerApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const EspoWorkerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      navigatorKey: EspoWorkerApp.navigatorKey,
      title: 'MB-Security',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de', 'DE'),
        Locale('en', 'US'),
      ],
      theme: AppTheme.getTheme(themeProvider.selectedThemeName, false),
      darkTheme: AppTheme.getTheme(themeProvider.selectedThemeName, true),
      themeMode: themeProvider.themeMode,
      home: const LoginScreen(),
      routes: {
        '/adminlogin': (context) => const AdminLoginScreen(),
        '/selfcheckin': (context) => const SelfCheckinScreen(),
      },
    );
  }
}

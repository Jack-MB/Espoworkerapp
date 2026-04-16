import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login_screen.dart';
import 'services/polling_service.dart';
import 'services/notification_service.dart';
import 'providers/theme_provider.dart';
import 'core/app_theme.dart';
import 'services/acl_service.dart';

import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb) {
    try {
      // Initialize Firebase via custom service
      await FirebaseService().init();
      
      // Initialize local notifications
      await NotificationService().initialize();
      // Initialize background worker
      await PollingService().initialize();
      // Start polling every 15 minutes (Android minimum)
      await PollingService().schedulePolling(const Duration(minutes: 15));
      // Initialize ACL service
      await AclService().init();
    } catch (e) {
      debugPrint('Init error: $e');
    }
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
    );
  }
}

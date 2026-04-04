import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  static const String baseUrl = kIsWeb ? 'http://localhost:8080' : 'https://crm.mb-scc.de';
  static const String apiUrl = '$baseUrl/api/v1';

  // EspoCRM primary color hints (Slate / Dark Blue)
  static const Color primaryColor = Color(0xFF173D5D); // Espresso Dark Blue / Slate
  static const Color secondaryColor = Color(0xFF2FA2D1); // Light blue accents
  static const Color backgroundColor = Color(0xFFF2F4F8); // Light greyish blue
  static const Color surfaceColor = Colors.white;
  static const Color errorColor = Color(0xFFD32F2F);

  // Additional Themes
  static const Map<String, Map<String, Color>> themes = {
    'Espo': {
      'primary': Color(0xFF173D5D),
      'secondary': Color(0xFF2FA2D1),
    },
    'Violet': {
      'primary': Color(0xFF673AB7),
      'secondary': Color(0xFF9575CD),
    },
    'Sakura': {
      'primary': Color(0xFFD16B95),
      'secondary': Color(0xFFF48FB1),
    },
    'Hazyblue': {
      'primary': Color(0xFF5B8BA3),
      'secondary': Color(0xFF81ABC0),
    },
  };

  // Identity / Legal
  static const String firmBewacherId = '14818';
}

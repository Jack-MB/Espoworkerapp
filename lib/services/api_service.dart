import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/server_config.dart';
import 'secure_storage_service.dart';
import '../models/wachbuch.dart';
import '../models/slot.dart';
import '../models/note.dart';
import '../models/urlaub.dart';
import '../models/krankentage.dart';
import '../models/bereitschaft.dart';
import '../models/angestellte.dart';
import '../models/document.dart';
import '../models/document_folder.dart';
import '../models/notification.dart';
import '../models/abwesenheit.dart';
import '../models/meeting.dart';
import '../models/email.dart';
import '../models/email_template.dart';
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import '../models/arbeitszeitkonto.dart';


class _HttpWithTimeout {
  static const Duration _timeout = Duration(seconds: 15);

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      http.get(url, headers: headers).timeout(_timeout);

  static Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      http.post(url, headers: headers, body: body, encoding: encoding).timeout(_timeout);

  static Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      http.put(url, headers: headers, body: body, encoding: encoding).timeout(_timeout);

  static Future<http.Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      http.patch(url, headers: headers, body: body, encoding: encoding).timeout(_timeout);
}

class ApiService {
  final SecureStorageService _storageService = SecureStorageService();
  static const String _cachedSlotsKey = 'cached_slots_payload_v1';
  static const String _cachedSlotsMasterKey = 'cached_slots_master_map_v1';
  static const String _cachedWachbuchsKey = 'cached_wachbuchs_payload_v1';
  static const String _cachedUrlaubKey = 'cached_urlaub_payload_v1';
  static const String _cachedKrankKey = 'cached_krank_payload_v1';
  static const String _cachedBereitschaftKey = 'cached_bereitschaft_payload_v1';
  static const String _cachedAbwesenheitKey = 'cached_abwesenheit_payload_v1';
  static const String _cachedMeetingsKey = 'cached_meetings_payload_v1';
  bool _isLastSlotsFromCache = false;
  bool get isLastSlotsFromCache => _isLastSlotsFromCache;

  Future<bool> pingServer() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/App/user');
      final response = await _HttpWithTimeout.get(url).timeout(const Duration(seconds: 5));
      // 200, 401, 403 all mean "server reachable"
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Validates that the given [baseUrl] points to a reachable EspoCRM instance.
  /// Returns true if the server responds (even with 401).
  static Future<bool> pingCustomUrl(String baseUrl) async {
    try {
      final normalized = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final url = Uri.parse('$normalized/api/v1/App/user');
      final response = await _HttpWithTimeout.get(url).timeout(const Duration(seconds: 8));
      // 200, 401, 403 all mean "server is there and running EspoCRM"
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<bool> login(String rawUsername, String rawPassword) async {
    final String username = rawUsername.trim();
    final String password = rawPassword.trim();
    
    debugPrint('Attempting login for: $username to ${ServerConfig().apiUrl}/App/user');

    final bool isApiKey = password.length > 20 && !password.contains(' ');

    if (isApiKey) {
      final url = Uri.parse('${ServerConfig().apiUrl}/App/user');
      final headers = {
        'Accept': 'application/json',
        'X-Api-Key': password
      };
      try {
        final response = await _HttpWithTimeout.get(url, headers: headers);
        if (response.statusCode == 200) {
          await _storageService.saveToken('ApiKey $password');
          await _storageService.saveUsername(username);
          return true;
        }
      } catch (e) {
        debugPrint('API Key Login error: $e');
      }
      return false;
    }

    // Standard User Login via Basic Auth GET App/user
    final url = Uri.parse('${ServerConfig().apiUrl}/App/user');
    final String basicAuth = 'Basic ' + base64Encode(utf8.encode('$username:$password'));
    
    try {
      final response = await _HttpWithTimeout.get(
        url,
        headers: {
          'Authorization': basicAuth,
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        debugPrint('App/user returned 200 SUCCESS!');
        
        final data = json.decode(response.body);
        String? angestelltexId = data['user'] != null 
            ? (data['user']['angestelltexId'] ?? data['user']['angestellte2Id']) 
            : null;

        final String? userId = data['user'] != null ? data['user']['id'] : null;
        String? angestellteName = data['user'] != null 
            ? (data['user']['angestelltexName'] ?? data['user']['angestellte2Name']) 
            : null;

        // Fallback: If not directly attached to User, query Angestellte entity
        if (angestelltexId == null && userId != null) {
          try {
            final qUrl = Uri.parse('${ServerConfig().apiUrl}/Angestellte?maxSize=1&where[0][type]=equals&where[0][attribute]=assignedUserId&where[0][value]=$userId');
            final qRes = await _HttpWithTimeout.get(qUrl, headers: {'Authorization': basicAuth, 'Accept': 'application/json'});
            if (qRes.statusCode == 200) {
              final qData = json.decode(qRes.body);
              if (qData['list'] != null && qData['list'].isNotEmpty) {
                angestelltexId = qData['list'][0]['id'];
                angestellteName = qData['list'][0]['name'];
              }
            }
          } catch (e) {
            debugPrint('Fallback Angestellte query failed: $e');
          }
          
          // Second fallback for KP Users
          if (angestelltexId == null) {
            try {
              final qUrl2 = Uri.parse('${ServerConfig().apiUrl}/Angestellte?maxSize=1&where[0][type]=equals&where[0][attribute]=kpUserId&where[0][value]=$userId');
              final qRes2 = await _HttpWithTimeout.get(qUrl2, headers: {'Authorization': basicAuth, 'Accept': 'application/json'});
              if (qRes2.statusCode == 200) {
                final qData2 = json.decode(qRes2.body);
                if (qData2['list'] != null && qData2['list'].isNotEmpty) {
                  angestelltexId = qData2['list'][0]['id'];
                  angestellteName = qData2['list'][0]['name'];
                }
              }
            } catch (_) {}
          }
        }

        await _storageService.saveToken(basicAuth);
        await _storageService.saveUsername(username);
        
        if (angestelltexId != null) {
          await _storageService.saveAngestellteId(angestelltexId);
        }
        if (userId != null) {
          await _storageService.saveAssignedUserId(userId);
        }
        if (angestellteName != null) {
          await _storageService.saveAngestellteName(angestellteName);
        }

        // Save Admin status
        final bool isAdmin = data['user'] != null ? (data['user']['isAdmin'] ?? false) : false;
        await _storageService.saveIsAdmin(isAdmin);
        
        // Save App Manager status (from full User record)
        bool isAppManager = false;
        if (userId != null) {
          try {
             final userUrl = Uri.parse('${ServerConfig().apiUrl}/User/$userId');
             final userResp = await _HttpWithTimeout.get(userUrl, headers: {
                'Authorization': basicAuth,
                'Accept': 'application/json',
             });
             if (userResp.statusCode == 200) {
               final uData = json.decode(userResp.body);
               isAppManager = uData['isAppManager'] ?? false;
             }
          } catch (e) {
             debugPrint('Failed to fetch user record for AppManager check: $e');
          }
        }
        await _storageService.saveIsAppManager(isAppManager);

        // Save ACL from response metadata
        if (data['acl'] != null) {
          await _storageService.saveAcl(data['acl']);
        }

        // Upload FCM Token to EspoCRM
        if (userId != null) {
          await syncFcmToken();
        }


        return true;
      }
      debugPrint('App/user returned ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Standard Login error: $e');
      return false;
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _storageService.getToken();
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    
    if (token != null) {
      if (token.startsWith('Basic ')) {
        headers['Authorization'] = token;
      } else if (token.startsWith('ApiKey ')) {
        headers['X-Api-Key'] = token.replaceAll('ApiKey ', '');
      } else {
        headers['X-Auth-Token'] = token; // Legacy fallback
      }
    }
    
    return headers;
  }

  Future<Map<String, dynamic>?> getObjektCoordinates(String id) async {
    final cacheKey = 'cached_objekt_coords_$id';
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/Objekte/$id?select=latk,lonK,rad');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latVal = data['latk'];
        final lonVal = data['lonK'];
        final radVal = data['rad'];
        
        if (latVal != null && lonVal != null) {
          final lat = double.tryParse(latVal.toString().replaceAll(',', ''));
          final lon = double.tryParse(lonVal.toString().replaceAll(',', ''));
          
          int parsedRad = 30;
          if (radVal != null) {
            // Robust parsing of integer with possible thousands separators (.)
            final sanitizedRad = radVal.toString().replaceAll('.', '').replaceAll(',', '');
            parsedRad = int.tryParse(sanitizedRad) ?? 30;
          }

          if (lat != null && lon != null) {
            final result = {
              'latk': lat, 
              'lonK': lon,
              'rad': parsedRad,
            };
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(cacheKey, json.encode(result));
            } catch (_) {}
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('getObjektCoordinates error: $e, checking offline cache');
    }

    // Offline cache fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString(cacheKey);
      if (cachedStr != null && cachedStr.isNotEmpty) {
        return Map<String, dynamic>.from(json.decode(cachedStr));
      }
    } catch (_) {}
    return null;
  }

  Future<Slot?> getSlotById(String id) async {
    final url = Uri.parse(
        '${ServerConfig().apiUrl}/Slots/$id'
        '?select=id,name,status,dateStart,dateEnd,schichtbezeichnung,objekteId,objekteName,angestellteId,angestellteName,accountId,accountName,salesOrderName,positionsname,firmaFarbcode,color,kooperationspartnerName,stundenanzahl,checkin,checkout,neueobjektstrasse,neueobjektplz,neueobjektort,firmastrasse,firmaplz,firmaort,latk,lonK,bewacherID,personalausweisnummer,kleidung,kleidungAnmerkungen,neueobjektkleidung,neueobjektkleidunganmerkung,annahmeStatus');
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Slot.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<dynamic> getMetadata() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Metadata');
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load metadata');
  }

  Future<bool> patchSlot(String slotId, Map<String, dynamic> data) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Slots/$slotId');
    final response = await _HttpWithTimeout.patch(
      url,
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    debugPrint('PATCH Slots $slotId: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw Exception('Server-Fehler: ${response.statusCode}');
    }
    return true;
  }

  /// Check-in für eine Schicht über dedizierte Server-Action mit Ampel-Berechnung
  Future<bool> checkInSlot(String slotId, {String? checkInTime}) async {
    final primaryUrl = Uri.parse('${ServerConfig().apiUrl}/Slots/action/checkin');
    try {
      final headers = await _getHeaders();
      final body = json.encode({
        'slotId': slotId,
        if (checkInTime != null) 'checkin': checkInTime,
      });
      final response = await _HttpWithTimeout.post(primaryUrl, headers: headers, body: body);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return true;
        throw Exception(data['message'] ?? 'Check-in fehlgeschlagen');
      }
      if (response.statusCode == 403) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Keine Berechtigung zum Einchecken');
      }
    } catch (e) {
      if (e.toString().contains('Berechtigung') || e.toString().contains('deaktiviert')) {
        rethrow;
      }
      debugPrint('checkInSlot action endpoint failed: $e, trying fallback');
    }

    // Fallback: direct patchSlot (Admin / Legacy)
    final checkinVal = checkInTime ?? DateTime.now().toUtc().toString().split('.')[0];
    return patchSlot(slotId, {
      'checkin': checkinVal,
      'cI': '🟢',
      'status': 'Durchgeführt',
    });
  }

  /// Check-out für eine Schicht über dedizierte Server-Action
  Future<bool> checkOutSlot(String slotId, {String? checkOutTime}) async {
    final primaryUrl = Uri.parse('${ServerConfig().apiUrl}/Slots/action/checkout');
    try {
      final headers = await _getHeaders();
      final body = json.encode({
        'slotId': slotId,
        if (checkOutTime != null) 'checkout': checkOutTime,
      });
      final response = await _HttpWithTimeout.post(primaryUrl, headers: headers, body: body);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return true;
        throw Exception(data['message'] ?? 'Check-out fehlgeschlagen');
      }
      if (response.statusCode == 403) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Keine Berechtigung zum Auschecken');
      }
    } catch (e) {
      if (e.toString().contains('Berechtigung') || e.toString().contains('deaktiviert')) {
        rethrow;
      }
      debugPrint('checkOutSlot action endpoint failed: $e, trying fallback');
    }

    // Fallback: direct patchSlot (Admin / Legacy)
    final checkoutVal = checkOutTime ?? DateTime.now().toUtc().toString().split('.')[0];
    return patchSlot(slotId, {'checkout': checkoutVal});
  }

  /// Nimmt eine Schicht an — nutzt Custom Server Action mit Validierung.
  Future<bool> annehmeSchicht(String slotId) async {
    // 1. Primärer Endpunkt: SchichtAnnahme Controller
    final primaryUrl = Uri.parse('${ServerConfig().apiUrl}/SchichtAnnahme/action/annehmen');
    try {
      final headers = await _getHeaders();
      final body = json.encode({'slotId': slotId});
      final response = await _HttpWithTimeout.post(primaryUrl, headers: headers, body: body);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return true;
        throw Exception(data['message'] ?? 'Unbekannter Fehler');
      }
      if (response.statusCode == 403) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Keine Berechtigung oder Zeitkonflikt');
      }
    } catch (e) {
      if (e.toString().contains('Zeitkonflikt') || e.toString().contains('Berechtigung')) {
        rethrow;
      }
      debugPrint('annehmeSchicht primary endpoint failed: $e, trying fallback');
    }

    // 2. Fallback-Endpunkt: Slots Controller
    final fallbackUrl = Uri.parse('${ServerConfig().apiUrl}/Slots/$slotId/action/annehmen');
    try {
      final response = await _HttpWithTimeout.post(fallbackUrl, headers: await _getHeaders(), body: '{}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return true;
        throw Exception(data['message'] ?? 'Unbekannter Fehler');
      }
      if (response.statusCode == 403) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Keine Berechtigung oder Zeitkonflikt');
      }
      throw Exception('Server-Fehler: ${response.statusCode} – ${response.body}');
    } catch (e) {
      debugPrint('annehmeSchicht fallback failed: $e');
      rethrow;
    }
  }

  /// Lehnt eine Schicht ab — nutzt Custom Server Action.
  Future<bool> ablehneSchicht(String slotId, {String? grund, String? kommentar}) async {
    final finalGrund = grund ?? kommentar ?? '';

    // 1. Primärer Endpunkt: SchichtAnnahme Controller
    final primaryUrl = Uri.parse('${ServerConfig().apiUrl}/SchichtAnnahme/action/ablehnen');
    try {
      final headers = await _getHeaders();
      final body = json.encode({'slotId': slotId, 'kommentar': finalGrund});
      final response = await _HttpWithTimeout.post(primaryUrl, headers: headers, body: body);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return true;
        throw Exception(data['message'] ?? 'Unbekannter Fehler');
      }
      if (response.statusCode == 403) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Keine Berechtigung zum Ablehnen');
      }
    } catch (e) {
      if (e.toString().contains('interne') || e.toString().contains('Berechtigung')) {
        rethrow;
      }
      debugPrint('ablehneSchicht primary endpoint failed: $e, trying fallback');
    }

    // 2. Fallback-Endpunkt: Slots Controller
    final fallbackUrl = Uri.parse('${ServerConfig().apiUrl}/Slots/$slotId/action/ablehnen');
    try {
      final body = json.encode(finalGrund.isNotEmpty ? {'grund': finalGrund} : {});
      final response = await _HttpWithTimeout.post(fallbackUrl, headers: await _getHeaders(), body: body);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return true;
        throw Exception(data['message'] ?? 'Unbekannter Fehler');
      }
      if (response.statusCode == 403) {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Keine Berechtigung');
      }
      throw Exception('Server-Fehler: ${response.statusCode} – ${response.body}');
    } catch (e) {
      debugPrint('ablehneSchicht fallback failed: $e');
      rethrow;
    }
  }

  /// Delta-Sync: Gibt nur Schichten zurück die seit [since] geändert wurden.
  /// Verwendet /api/v1/Slots/action/delta?since=... (Custom Action).
  /// Fallback: voller Reload via getSlots().
  Future<List<Slot>> getDeltaSlots(DateTime since) async {
    final sinceStr =
        '${since.year.toString().padLeft(4, '0')}-'
        '${since.month.toString().padLeft(2, '0')}-'
        '${since.day.toString().padLeft(2, '0')} '
        '${since.hour.toString().padLeft(2, '0')}:'
        '${since.minute.toString().padLeft(2, '0')}:'
        '${since.second.toString().padLeft(2, '0')}';

    final url = Uri.parse('${ServerConfig().apiUrl}/Slots/action/delta?since=${Uri.encodeComponent(sinceStr)}');
    try {
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Slot.fromJson(e)).toList();
        }
      }
      if (response.statusCode == 404) {
        // Delta-Action noch nicht deployed — kein Fallback nötig, Caller macht vollen Load
        debugPrint('getDeltaSlots: Custom Action nicht verfügbar');
        return [];
      }
    } catch (e) {
      debugPrint('getDeltaSlots error: $e');
    }
    return [];
  }

  /// AZK-Saldo: Holt den Arbeitszeitkonto-Stand für den eingeloggten Mitarbeiter.
  Future<Map<String, dynamic>?> getAzkSaldo() async {
    final angestellteId = await _storageService.getAngestellteId();
    if (angestellteId == null) return null;

    // Versuche Custom Action
    final actionUrl = Uri.parse('${ServerConfig().apiUrl}/Angestellte/$angestellteId/action/azkSaldo');
    try {
      final response = await _HttpWithTimeout.get(actionUrl, headers: await _getHeaders());
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (_) {}

    // Fallback: Direkte Berechnung aus Schichten (letzte 90 Tage)
    try {
      final slots = await getSlots(
        startDate: DateTime.now().subtract(const Duration(days: 90)),
        endDate: DateTime.now(),
      );
      double sollStunden = 0;
      double istStunden  = 0;
      for (final s in slots) {
        if (s.stundenanzahl != null) sollStunden += s.stundenanzahl!;
        if (s.checkin != null && s.checkout != null) {
          istStunden += s.stundenanzahl ?? 0;
        }
      }
      return {
        'sollStunden': sollStunden,
        'istStunden':  istStunden,
        'differenz':   istStunden - sollStunden,
        'berechnetLokal': true,
      };
    } catch (e) {
      debugPrint('getAzkSaldo fallback error: $e');
      return null;
    }
  }

  Future<List<Wachbuch>> getWachbuchs() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CWachbuch?maxSize=50&orderBy=createdAt&order=desc');
    try {
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      debugPrint('getWachbuchs status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cachedWachbuchsKey, response.body);
          } catch (_) {}
          final result = <Wachbuch>[];
          for (var e in data['list']) {
            try {
              result.add(Wachbuch.fromJson(e));
            } catch (err, stack) {
              debugPrint('Error parsing Wachbuch $err\n$stack\nJSON: $e');
            }
          }
          return result;
        }
      } else {
        debugPrint('getWachbuchs error body: ${response.body}');
      }
    } catch (e) {
      debugPrint('Network error in getWachbuchs: $e. Falling back to offline cache.');
    }

    // Offline cache fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cachedWachbuchsKey);
      if (cached != null && cached.isNotEmpty) {
        final data = json.decode(cached);
        if (data['list'] != null) {
          final result = <Wachbuch>[];
          for (var e in data['list']) {
            try {
              result.add(Wachbuch.fromJson(e));
            } catch (_) {}
          }
          return result;
        }
      }
    } catch (_) {}

    return [];
  }

  /// Fetches a single Wachbuch record by ID (includes dateinFotos* fields).
  Future<Wachbuch?> getWachbuchById(String id) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CWachbuch/$id');
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Wachbuch.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<Map<String, dynamic>?> getSelfUser() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/App/user');
    final headers = await _getHeaders();
    try {
      final response = await _HttpWithTimeout.get(url, headers: headers);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('getSelfUser error: $e');
    }
    return null;
  }

  Future<List<Slot>> getSlots({DateTime? startDate, DateTime? endDate}) async {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 60));
    final end = endDate ?? DateTime.now().add(const Duration(days: 180));
    
    // Format to EspoCRM string (YYYY-MM-DD without time)
    final startStr = '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    
    // Add 1 day to end date to ensure the full final day is included 
    // (EspoCRM's lessThanOrEquals with date-only value is effectively 'until midnight of that day')
    final endPlusOne = end.add(const Duration(days: 1));
    final endStr = '${endPlusOne.year.toString().padLeft(4, '0')}-${endPlusOne.month.toString().padLeft(2, '0')}-${endPlusOne.day.toString().padLeft(2, '0')}';

    final baseUri = Uri.parse(ServerConfig().apiUrl);
    final url = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '${baseUri.path}/Slots',
      queryParameters: {
        'maxSize': '2000',
        'where[0][type]': 'greaterThanOrEquals',
        'where[0][attribute]': 'dateStart',
        'where[0][value]': startStr,
        'where[1][type]': 'lessThanOrEquals',
        'where[1][attribute]': 'dateStart',
        'where[1][value]': endStr,
        'orderBy': 'dateStart',
        'order': 'asc',
      },
    );

    try {
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          _isLastSlotsFromCache = false;
          try {
            final prefs = await SharedPreferences.getInstance();
            // 1. Update legacy single-request cache
            await prefs.setString(_cachedSlotsKey, response.body);
            await prefs.setString('${_cachedSlotsKey}_time', DateTime.now().toIso8601String());

            // 2. Merge into master slot map (prevents narrow date queries from wiping out cache)
            final String? masterJson = prefs.getString(_cachedSlotsMasterKey);
            Map<String, dynamic> masterMap = {};
            if (masterJson != null && masterJson.isNotEmpty) {
              try {
                masterMap = Map<String, dynamic>.from(json.decode(masterJson));
              } catch (_) {}
            }
            for (var item in data['list']) {
              if (item is Map && item['id'] != null) {
                masterMap[item['id'].toString()] = item;
              }
            }
            await prefs.setString(_cachedSlotsMasterKey, json.encode(masterMap));
          } catch (e) {
            debugPrint('Error saving slots master cache: $e');
          }
          return (data['list'] as List).map((e) => Slot.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('Network error in getSlots: $e. Falling back to offline cache.');
    }

    // Offline cache fallback using master map
    try {
      final prefs = await SharedPreferences.getInstance();
      final masterJson = prefs.getString(_cachedSlotsMasterKey);
      List<Slot> allCached = [];

      if (masterJson != null && masterJson.isNotEmpty) {
        final Map<String, dynamic> masterMap = json.decode(masterJson);
        allCached = masterMap.values.map((e) => Slot.fromJson(e as Map<String, dynamic>)).toList();
      }

      // If master map was empty, check legacy cache key
      if (allCached.isEmpty) {
        final cachedJson = prefs.getString(_cachedSlotsKey);
        if (cachedJson != null && cachedJson.isNotEmpty) {
          final data = json.decode(cachedJson);
          if (data['list'] != null) {
            allCached = (data['list'] as List).map((e) => Slot.fromJson(e)).toList();
          }
        }
      }

      if (allCached.isNotEmpty) {
        _isLastSlotsFromCache = true;
        // If specific start & end dates were requested, filter cached results
        if (startDate != null || endDate != null) {
          final filtered = allCached.where((s) {
            if (s.dateStart == null) return false;
            try {
              final sDate = DateTime.parse(s.dateStart!.contains(' ') ? s.dateStart!.split(' ')[0] : s.dateStart!);
              if (startDate != null && sDate.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) {
                return false;
              }
              if (endDate != null && sDate.isAfter(DateTime(endDate.year, endDate.month, endDate.day))) {
                return false;
              }
              return true;
            } catch (_) {
              return true;
            }
          }).toList();

          if (filtered.isNotEmpty) {
            debugPrint('Serving ${filtered.length} filtered slots from offline cache');
            return filtered;
          }
        }
        // Fallback: Return all cached slots so user is never left with an empty screen offline
        debugPrint('Serving ${allCached.length} total slots from offline master cache');
        return allCached;
      }
    } catch (cacheErr) {
      debugPrint('Error reading slots cache: $cacheErr');
    }

    return <Slot>[];
  }

  /// Returns all cached slots regardless of filter, useful for offline views
  Future<List<Slot>> getAllCachedSlots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final masterJson = prefs.getString(_cachedSlotsMasterKey);
      if (masterJson != null && masterJson.isNotEmpty) {
        final Map<String, dynamic> masterMap = json.decode(masterJson);
        return masterMap.values.map((e) => Slot.fromJson(e as Map<String, dynamic>)).toList();
      }
      final cachedJson = prefs.getString(_cachedSlotsKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final data = json.decode(cachedJson);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Slot.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return <Slot>[];
  }

  Future<List<Note>> getWachbuchNotes(String wachbuchId) async {
    // Use Uri constructor to avoid double-encoding of bracket characters
    final baseUri = Uri.parse(ServerConfig().apiUrl);
    final url = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '${baseUri.path}/Note',
      queryParameters: {
        'maxSize': '100',
        'where[0][type]': 'equals',
        'where[0][attribute]': 'parentType',
        'where[0][value]': 'CWachbuch',
        'where[1][type]': 'equals',
        'where[1][attribute]': 'parentId',
        'where[1][value]': wachbuchId,
        'orderBy': 'createdAt',
        'order': 'desc',
        'select': 'id,post,type,createdAt,createdById,createdByName,parentType,parentId,attachmentsIds,attachmentsNames',
      },
    );
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Note.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<bool> createWachbuchNote(String wachbuchId, String text) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Note');
    final headers = await _getHeaders();
    final body = json.encode({
      'post': text,
      'type': 'Post',
      'parentType': 'CWachbuch',
      'parentId': wachbuchId,
    });
    final response = await _HttpWithTimeout.post(url, headers: headers, body: body);
    return response.statusCode == 200 || response.statusCode == 201;
  }

  /// Uploads a file as an Attachment. Returns the attachment ID or null on failure.
  Future<String?> uploadAttachment({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    String parentType = 'Note',
    String field = 'attachments',
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Attachment');
    final headers = await _getHeaders();
    final base64Data = base64Encode(bytes);
    final dataUri = 'data:$mimeType;base64,$base64Data';
    final body = json.encode({
      'name': fileName,
      'type': mimeType,
      'role': 'Attachment',
      'parentType': parentType,
      'field': field,
      'file': dataUri,
    });
    final response = await _HttpWithTimeout.post(url, headers: headers, body: body);
    debugPrint('uploadAttachment status: ${response.statusCode}');
    debugPrint('uploadAttachment body: ${response.body}');
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(response.body);
      return data['id'] as String?;
    }
    return null;
  }

  /// Creates a Note with optional attachment IDs already uploaded.
  Future<bool> createNoteWithAttachments(
    String wachbuchId,
    String text,
    List<String> attachmentIds,
  ) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Note');
    final headers = await _getHeaders();
    final body = json.encode({
      'post': text,
      'type': 'Post',
      'parentType': 'CWachbuch',
      'parentId': wachbuchId,
      if (attachmentIds.isNotEmpty) 'attachmentsIds': attachmentIds,
    });
    final response = await _HttpWithTimeout.post(url, headers: headers, body: body);
    debugPrint('createNote status: ${response.statusCode}');
    debugPrint('createNote body: ${response.body}');
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<void> triggerWachbuchUpdate(String id) async {
    final token = await _storageService.getToken();
    if (token == null) return;
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/CWachbuch/$id');
      await _HttpWithTimeout.put(
        url,
        headers: {'Authorization': token, 'Content-Type': 'application/json'},
        body: json.encode({'modifiedAt': DateTime.now().toUtc().toIso8601String()}),
      );
    } catch (_) {}
  }

  Future<List<Urlaub>> getUrlaubs() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/CUrlaube?maxSize=100&orderBy=createdAt&order=desc');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cachedUrlaubKey, response.body);
          } catch (_) {}
          return (data['list'] as List).map((e) => Urlaub.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('getUrlaubs error: $e, falling back to cache');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cachedUrlaubKey);
      if (cached != null && cached.isNotEmpty) {
        final data = json.decode(cached);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Urlaub.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return <Urlaub>[];
  }

  Future<List<Krankentage>> getKrankentage() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/CKrankenscheine?maxSize=100&orderBy=createdAt&order=desc');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cachedKrankKey, response.body);
          } catch (_) {}
          return (data['list'] as List).map((e) => Krankentage.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('getKrankentage error: $e, falling back to cache');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cachedKrankKey);
      if (cached != null && cached.isNotEmpty) {
        final data = json.decode(cached);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Krankentage.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return <Krankentage>[];
  }

  Future<List<Bereitschaft>> getBereitschaften() async {
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
      final to = now.add(const Duration(days: 180));
      final fromStr = '${from.year.toString().padLeft(4, '0')}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
      final toStr = '${to.year.toString().padLeft(4, '0')}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
      final url = Uri.parse(
        '${ServerConfig().apiUrl}/CBereitschaft?maxSize=200'
        '&where%5B0%5D%5Btype%5D=greaterThanOrEquals&where%5B0%5D%5Battribute%5D=dateStart&where%5B0%5D%5Bvalue%5D=$fromStr'
        '&where%5B1%5D%5Btype%5D=lessThanOrEquals&where%5B1%5D%5Battribute%5D=dateStart&where%5B1%5D%5Bvalue%5D=$toStr'
        '&orderBy=dateStart&order=asc',
      );
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cachedBereitschaftKey, response.body);
          } catch (_) {}
          return (data['list'] as List).map((e) => Bereitschaft.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('getBereitschaften error: $e, falling back to cache');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cachedBereitschaftKey);
      if (cached != null && cached.isNotEmpty) {
        final data = json.decode(cached);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Bereitschaft.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return <Bereitschaft>[];
  }

  /// Resolves and caches the Angestellte record linked to the current user
  Future<bool> resolveCurrentUserAngestellte() async {
    try {
      final headers = await _getHeaders();
      final userId = await _storageService.getAssignedUserId();
      final username = await _storageService.getUsername();

      String? targetUserId = userId;
      if (targetUserId == null && username != null && username.isNotEmpty) {
        final uUrl = Uri.parse('${ServerConfig().apiUrl}/User?where[0][type]=equals&where[0][attribute]=userName&where[0][value]=${Uri.encodeComponent(username)}');
        final uRes = await _HttpWithTimeout.get(uUrl, headers: headers);
        if (uRes.statusCode == 200) {
          final uData = json.decode(uRes.body);
          if (uData['list'] != null && (uData['list'] as List).isNotEmpty) {
            targetUserId = uData['list'][0]['id'];
            if (targetUserId != null) {
              await _storageService.saveAssignedUserId(targetUserId);
            }
          }
        }
      }

      if (targetUserId == null) return false;

      // Query Angestellte by assignedUserId
      final qUrl = Uri.parse('${ServerConfig().apiUrl}/Angestellte?maxSize=1&where[0][type]=equals&where[0][attribute]=assignedUserId&where[0][value]=$targetUserId');
      final qRes = await _HttpWithTimeout.get(qUrl, headers: headers);
      if (qRes.statusCode == 200) {
        final qData = json.decode(qRes.body);
        if (qData['list'] != null && (qData['list'] as List).isNotEmpty) {
          final ang = qData['list'][0];
          await _storageService.saveAngestellteId(ang['id']);
          if (ang['name'] != null) {
            await _storageService.saveAngestellteName(ang['name']);
          }
          return true;
        }
      }

      // Second fallback: kpUserId
      final qUrl2 = Uri.parse('${ServerConfig().apiUrl}/Angestellte?maxSize=1&where[0][type]=equals&where[0][attribute]=kpUserId&where[0][value]=$targetUserId');
      final qRes2 = await _HttpWithTimeout.get(qUrl2, headers: headers);
      if (qRes2.statusCode == 200) {
        final qData2 = json.decode(qRes2.body);
        if (qData2['list'] != null && (qData2['list'] as List).isNotEmpty) {
          final ang2 = qData2['list'][0];
          await _storageService.saveAngestellteId(ang2['id']);
          if (ang2['name'] != null) {
            await _storageService.saveAngestellteName(ang2['name']);
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('resolveCurrentUserAngestellte error: $e');
    }
    return false;
  }

  Future<bool> createUrlaub({
    required String dateStart,
    required String dateEnd,
    required String description,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CUrlaube');
    final headers = await _getHeaders();
    String? angestellteId = await _storageService.getAngestellteId();
    String? assignedUserId = await _storageService.getAssignedUserId();
    String? angestellteName = await _storageService.getAngestellteName();

    if (angestellteId == null || angestellteId.isEmpty) {
      await resolveCurrentUserAngestellte();
      angestellteId = await _storageService.getAngestellteId();
      assignedUserId = await _storageService.getAssignedUserId();
      angestellteName = await _storageService.getAngestellteName();
    }

    if (angestellteId == null || angestellteId.isEmpty) {
      debugPrint('createUrlaub error: Keine verknüpfte Angestellte-Entität gefunden.');
      return false;
    }

    final name = (angestellteName != null && angestellteName.isNotEmpty)
        ? 'Urlaub $angestellteName'
        : 'Urlaubsantrag';

    final body = json.encode({
      'name': name.trim(),
      'status': 'In Bearbeitung',
      'dateStart': dateStart, // e.g. "2026-03-20 00:00:00"
      'dateEnd': dateEnd,   // e.g. "2026-03-20 23:59:59"
      'description': description,
      'isAllDay': true, // Standard for vacation
      'parentId': angestellteId,
      'parentType': 'Angestellte',
      if (assignedUserId != null && assignedUserId.isNotEmpty) 'assignedUserId': assignedUserId,
    });

    final response = await _HttpWithTimeout.post(url, headers: headers, body: body);
    debugPrint('createUrlaub response: ${response.statusCode} - ${response.body}');
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> createKrankentage({
    required String dateStart,
    required String dateEnd,
    required String description,
    String? krankenscheinId,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CKrankenscheine');
    final headers = await _getHeaders();
    String? angestellteId = await _storageService.getAngestellteId();
    String? assignedUserId = await _storageService.getAssignedUserId();
    String? angestellteName = await _storageService.getAngestellteName();

    if (angestellteId == null || angestellteId.isEmpty) {
      await resolveCurrentUserAngestellte();
      angestellteId = await _storageService.getAngestellteId();
      assignedUserId = await _storageService.getAssignedUserId();
      angestellteName = await _storageService.getAngestellteName();
    }

    if (angestellteId == null || angestellteId.isEmpty) {
      debugPrint('createKrankentage error: Keine verknüpfte Angestellte-Entität gefunden.');
      return false;
    }

    final name = (angestellteName != null && angestellteName.isNotEmpty)
        ? 'Krank $angestellteName'
        : 'Krankmeldung';

    final body = json.encode({
      'name': name.trim(),
      'status': 'Planned', // Default typically used for illness in Espo
      'dateStart': dateStart,
      'dateEnd': dateEnd,
      'description': description,
      'isAllDay': true,
      if (krankenscheinId != null && krankenscheinId.isNotEmpty) 'krankenscheinId': krankenscheinId,
      'parentId': angestellteId,
      'parentType': 'Angestellte',
      if (assignedUserId != null && assignedUserId.isNotEmpty) 'assignedUserId': assignedUserId,
    });

    final response = await _HttpWithTimeout.post(url, headers: headers, body: body);
    debugPrint('createKrankentage response: ${response.statusCode} - ${response.body}');
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> updateKrankentage(String id, String krankenscheinId) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CKrankenscheine/$id');
    final headers = await _getHeaders();
    final body = json.encode({
      'krankenscheinId': krankenscheinId,
    });
    final patchResponse = await _HttpWithTimeout.patch(url, headers: headers, body: body);
    if (patchResponse.statusCode == 200) return true;
    final putResponse = await _HttpWithTimeout.put(url, headers: headers, body: body);
    return putResponse.statusCode == 200;
  }

  Future<List<Angestellte>> getAngestellte() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte?maxSize=100&orderBy=name&order=asc');
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Angestellte.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<Angestellte?> getAngestellteById(String id) async {
    final cacheKey = 'cached_angestellte_$id';
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte/$id');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(cacheKey, response.body);
        } catch (_) {}
        return Angestellte.fromJson(data);
      }
    } catch (e) {
      debugPrint('getAngestellteById error: $e, falling back to offline cache');
    }

    // Offline cache fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        debugPrint('Serving Angestellte $id from offline cache');
        return Angestellte.fromJson(json.decode(cachedJson));
      }
    } catch (cacheErr) {
      debugPrint('Error reading Angestellte cache: $cacheErr');
    }
    return null;
  }

  Future<bool> updateAngestellte(String id, Map<String, dynamic> updates) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte/$id');
    final headers = await _getHeaders();
    final body = json.encode(updates);
    final response = await _HttpWithTimeout.put(url, headers: headers, body: body);
    return response.statusCode == 200;
  }

  Future<List<DocumentFolder>> getDocumentFolders() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/DocumentFolder?maxSize=100&orderBy=name&order=asc');
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => DocumentFolder.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<List<EspoDocument>> getDocuments({String? folderId}) async {
    String urlStr = '${ServerConfig().apiUrl}/Document?maxSize=50&orderBy=createdAt&order=desc&select=id,name,status,type,fileId,fileName,createdAt';
    if (folderId != null) {
      urlStr += '&where[0][type]=equals&where[0][attribute]=folderId&where[0][value]=$folderId';
    }
    final url = Uri.parse(urlStr);
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => EspoDocument.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<List<EspoNotification>> getNotifications() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Notification?maxSize=50&orderBy=createdAt&order=desc');
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => EspoNotification.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<int> getUnreadNotificationCount() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/Notification/action/notReadCount');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        return int.tryParse(response.body.trim()) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<bool> markAllNotificationsRead() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/Notification/action/markAllRead');
      final headers = await _getHeaders();
      final response = await _HttpWithTimeout.post(url, headers: headers, body: '{}');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markNotificationRead(String id) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Notification/$id');
    final headers = await _getHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await _HttpWithTimeout.put(url, headers: headers, body: json.encode({'read': true}));
    return response.statusCode == 200;
  }

  Future<List<Abwesenheit>> getAbwesenheiten() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/CAbwesenheitsnotizen?maxSize=100&orderBy=dateStart&order=desc');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cachedAbwesenheitKey, response.body);
          } catch (_) {}
          return (data['list'] as List).map((e) => Abwesenheit.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('getAbwesenheiten error: $e, falling back to cache');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cachedAbwesenheitKey);
      if (cached != null && cached.isNotEmpty) {
        final data = json.decode(cached);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Abwesenheit.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return <Abwesenheit>[];
  }

  Future<bool> createAbwesenheit({
    required String dateStart,
    required String dateEnd,
    required String name,
    required String description,
    bool isAllDay = false,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CAbwesenheitsnotizen');
    final headers = await _getHeaders();
    final angestellteId = await _storageService.getAngestellteId();
    final assignedUserId = await _storageService.getAssignedUserId();
    
    final body = json.encode({
      'name': name,
      'status': 'Planned',
      'dateStart': dateStart, // Format: "YYYY-MM-DD HH:mm:ss"
      'dateEnd': dateEnd,     // Format: "YYYY-MM-DD HH:mm:ss"
      'description': description,
      'isAllDay': isAllDay,
      'parentType': 'Angestellte',
      if (angestellteId != null) 'parentId': angestellteId, // Use as 'parentId' for "Bezieht sich auf"
      if (angestellteId != null) 'angestellteId': angestellteId, // Legacy direct link
      if (assignedUserId != null) 'assignedUserId': assignedUserId,
    });
    
    final response = await _HttpWithTimeout.post(url, headers: headers, body: body);
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<List<Meeting>> getMeetings() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/Meeting?maxSize=50&orderBy=dateStart&order=desc');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cachedMeetingsKey, response.body);
          } catch (_) {}
          return (data['list'] as List).map((e) => Meeting.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('getMeetings error: $e, falling back to cache');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cachedMeetingsKey);
      if (cached != null && cached.isNotEmpty) {
        final data = json.decode(cached);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Meeting.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return <Meeting>[];
  }

  Future<Meeting?> getMeetingById(String id) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Meeting/$id');
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Meeting.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<bool> updateMeetingStatus(String id, String status) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Meeting/$id');
    final headers = await _getHeaders();
    final body = json.encode({'status': status});
    final response = await _HttpWithTimeout.put(url, headers: headers, body: body);
    return response.statusCode == 200;
  }

  Future<bool> createMeeting({
    required String name,
    required String dateStart,
    required String dateEnd,
    String? description,
    String? parentId,
    String? parentType,
    List<String>? usersIds,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Meeting');
    final headers = await _getHeaders();
    final selfUserId = await _storageService.getAssignedUserId();
    
    // Ensure self is in the list of participants if not provided
    final List<String> participants = usersIds ?? [];
    if (selfUserId != null && !participants.contains(selfUserId)) {
      participants.add(selfUserId);
    }

    final body = json.encode({
      'name': name,
      'status': 'Planned',
      'dateStart': dateStart, // ISO string YYYY-MM-DD HH:mm:ss
      'dateEnd': dateEnd,
      if (description != null) 'description': description,
      if (parentId != null) 'parentId': parentId,
      if (parentType != null) 'parentType': parentType,
      'usersIds': participants,
      if (selfUserId != null) 'assignedUserId': selfUserId,
    });
    
    final response = await _HttpWithTimeout.post(url, headers: headers, body: body);
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<List<Map<String, dynamic>>> searchEntities(String entityType, String query) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/$entityType?maxSize=20&where[0][type]=contains&where[0][attribute]=name&where[0][value]=$query');
    final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).cast<Map<String, dynamic>>();
      }
    }
    return [];
  }

  Future<bool> isUserBusy(String userId, String start, String end) async {
    final headers = await _getHeaders();
    
    // Check Meetings
    final meetUrl = Uri.parse('${ServerConfig().apiUrl}/Meeting?maxSize=1'
      '&where[0][type]=isParticipant&where[0][value]=$userId'
      '&where[1][type]=between&where[1][attribute]=dateStart&where[1][value]=$start&where[1][value]=$end');
    // Note: EspoCRM 'between' date filters usually check if start is in range. 
    // For true overlap we'd need more logic, but this is a good first step.
    
    final meetResp = await _HttpWithTimeout.get(meetUrl, headers: headers);
    if (meetResp.statusCode == 200) {
      final jsonMeet = json.decode(meetResp.body);
      if (jsonMeet['total'] != null && jsonMeet['total'] > 0) return true;
    }

    // Check Slots (Shifts)
    final slotUrl = Uri.parse('${ServerConfig().apiUrl}/Slots?maxSize=1'
      '&where[0][type]=equals&where[0][attribute]=assignedUserId&where[0][value]=$userId'
      '&where[1][type]=between&where[1][attribute]=dateStart&where[1][value]=$start&where[1][value]=$end');
    
    final slotResp = await _HttpWithTimeout.get(slotUrl, headers: headers);
    if (slotResp.statusCode == 200) {
      final jsonSlot = json.decode(slotResp.body);
      if (jsonSlot['total'] != null && jsonSlot['total'] > 0) return true;
    }

    return false;
  }

  Future<String> syncFcmToken([String? directToken]) async {
    final fcmToken = directToken ?? await _storageService.read('fcm_token');
    
    if (fcmToken == null || fcmToken.isEmpty) {
      return 'Fehler: Kein Token lokal gefunden (null/empty).';
    }

    String tokenPreview = fcmToken.length > 8 ? fcmToken.substring(0, 8) + "..." : fcmToken;
    final headers = await _getHeaders();
    final payload = json.encode({
      'fcmToken': fcmToken,
      'cFcmToken': fcmToken,
      'token': fcmToken,
    });

    String result = "Token ($tokenPreview) ";

    // 1. Primärer, sicherer Sync via dedizierte Controller-Action
    try {
      final actionUrl = Uri.parse('${ServerConfig().apiUrl}/User/action/syncFcmToken');
      debugPrint('Syncing FCM Token via action to $actionUrl');
      final actResp = await _HttpWithTimeout.post(actionUrl, headers: headers, body: payload);
      if (actResp.statusCode == 200) {
        final data = json.decode(actResp.body);
        if (data['success'] == true) {
          result += "Action: OK. ";
          return result;
        }
      }
    } catch (e) {
      debugPrint('Action syncFcmToken failed: $e');
    }

    // 2. Fallback: Direkter User-Patch
    final userId = await _storageService.getAssignedUserId();
    if (userId != null) {
      try {
        final url = Uri.parse('${ServerConfig().apiUrl}/User/$userId');
        final response = await _HttpWithTimeout.patch(url, headers: headers, body: payload);
        if (response.statusCode == 200) {
          result += "User: OK. ";
        }
      } catch (_) {}
    }

    // 3. Fallback: Angestellte-Patch
    final angId = await _storageService.getAngestellteId();
    if (angId != null) {
      try {
        final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte/$angId');
        await _HttpWithTimeout.patch(url, headers: headers, body: payload);
      } catch (_) {}
    }

    return result;
  }

  Future<bool> sendTestPush() async {
    final headers = await _getHeaders();

    // 1. Wenn im Browser (Chrome/Web): WebPush-Endpoint aufrufen
    if (kIsWeb) {
      try {
        final webUrl = Uri.parse('${ServerConfig().apiUrl}/PushSubscription/action/testPush');
        final resp = await _HttpWithTimeout.post(webUrl, headers: headers);
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          if (data['success'] == true) return true;
        }
      } catch (e) {
        debugPrint('Web sendTestPush error: $e');
      }
    }

    // 2. Nativer Android/FCM Push-Endpoint
    final url = Uri.parse('${ServerConfig().apiUrl}/User/action/testPush');
    try {
      final resp = await _HttpWithTimeout.post(url, headers: headers);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        return data['success'] == true;
      }
    } catch (e) {
      debugPrint('sendTestPush error: $e');
    }
    return false;
  }

  // --- Email Endpoints --- //

  Future<List<Map<String, dynamic>>> getEmailFolders() async {
    final token = await _storageService.getToken();
    if (token == null) return [];
    
    // Custom folders
    final url = Uri.parse('${ServerConfig().apiUrl}/EmailFolder');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['list']);
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> getInboundEmails() async {
    final token = await _storageService.getToken();
    if (token == null) return [];
    
    // Group inboxes
    final url = Uri.parse('${ServerConfig().apiUrl}/InboundEmail');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['list']);
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> getGroupEmailFolders() async {
    final token = await _storageService.getToken();
    if (token == null) return [];
    
    final url = Uri.parse('${ServerConfig().apiUrl}/GroupEmailFolder');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['list']);
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> getEmailAccounts() async {
    final token = await _storageService.getToken();
    if (token == null) return [];
    
    // Email Accounts (Personal/Shared IMAP Accounts)
    final url = Uri.parse('${ServerConfig().apiUrl}/EmailAccount');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['list']);
      }
    } catch (_) {}
    return [];
  }

  Future<List<Email>> getEmails({String? folderId, String? inboundEmailId, String? groupFolderId, String? status}) async {
    final token = await _storageService.getToken();
    if (token == null) return [];

    String url = '${ServerConfig().apiUrl}/Email?maxSize=50&orderBy=createdAt&order=desc';
    
    if (folderId != null && folderId != 'all') {
      url += '&where[0][type]=equals&where[0][attribute]=folderId&where[0][value]=$folderId';
    } else if (inboundEmailId != null) {
       url += '&where[0][type]=equals&where[0][attribute]=inboundEmailId&where[0][value]=$inboundEmailId';
    } else if (groupFolderId != null) {
       url += '&where[0][type]=equals&where[0][attribute]=groupFolderId&where[0][value]=$groupFolderId';
    } else if (status != null) {
      url += '&where[0][type]=equals&where[0][attribute]=status&where[0][value]=$status';
    }

    try {
      final response = await _HttpWithTimeout.get(Uri.parse(url), headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = data['list'] as List;
        return list.map((e) => Email.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Email?> getEmailDetails(String id) async {
    final token = await _storageService.getToken();
    if (token == null) return null;
    final url = Uri.parse('${ServerConfig().apiUrl}/Email/$id');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        return Email.fromJson(json.decode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<List<EmailTemplate>> getEmailTemplates() async {
    final token = await _storageService.getToken();
    if (token == null) return [];

    // max 100 templates
    final url = Uri.parse('${ServerConfig().apiUrl}/EmailTemplate?maxSize=100&orderBy=name&order=asc');
    
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = data['list'] as List;
        return list.map((e) => EmailTemplate.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }
  
  // Lädt die verfügbaren Absenderadressen für den aktuellen User
  Future<List<String>> getAvailableFromAddresses() async {
    final token = await _storageService.getToken();
    if (token == null) return [];

    // Der Standardweg in EspoCRM, um From-Adressen zu bekommen (kann Inbounds & Personal Accounts umfassen)
    final url = Uri.parse('${ServerConfig().apiUrl}/Email/action/getComposerData');
    
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.containsKey('fromEmailAddresses') && data['fromEmailAddresses'] is List) {
          return List<String>.from(data['fromEmailAddresses']);
        }
      }
    } catch (_) {}
    
    // Fallback: Benutzer-E-Mail, falls getComposerData fehlschlägt
    try {
       final user = await getSelfUser();
       if (user != null && user['user'] != null) {
         final email = user['user']['emailAddress'];
         if (email != null) return [email.toString()];
       }
    } catch (_) {}
    return [];
  }

  Future<bool> sendEmail(Map<String, dynamic> emailData) async {
    final token = await _storageService.getToken();
    if (token == null) return false;

    // Send immediately via Email entity creation with status "Sending" or action "send"
    final url = Uri.parse('${ServerConfig().apiUrl}/Email');
    
    try {
      final response = await _HttpWithTimeout.post(
        url,
        headers: {
          'Authorization': token, 
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: json.encode(emailData),
      );
      
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Error sending email: $e');
      return false;
    }
  }

  // --- Chat Endpoints --- //

  Future<List<ChatRoom>> getMyChatRooms() async {
    final token = await _storageService.getToken();
    if (token == null) return [];
    
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/getMyRooms');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return data.map((e) => ChatRoom.fromJson(e)).toList();
        } else if (data['list'] is List) {
          return (data['list'] as List).map((e) => ChatRoom.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> getChatUsersFiltered() async {
    final token = await _storageService.getToken();
    if (token == null) return {};
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/getChatUsersFiltered');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return {};
  }

  Future<String?> createDirectChat(String userId) async {
    final token = await _storageService.getToken();
    if (token == null) return null;
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/createDirectChat');
    try {
      final response = await _HttpWithTimeout.post(
        url, 
        headers: {'Authorization': token, 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'userId': userId})
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['chatRoomId'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<List<ChatMessage>> getChatMessages(String roomId, {int offset = 0, String? after}) async {
    final token = await _storageService.getToken();
    if (token == null) return [];
    
    final afterQuery = after != null ? '&after=${Uri.encodeComponent(after)}' : '';
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/getMessages?chatRoomId=$roomId&offset=$offset$afterQuery');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return data.map((e) => ChatMessage.fromJson(e)).toList();
        } else if (data['list'] is List) {
          return (data['list'] as List).map((e) => ChatMessage.fromJson(e)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<ChatMessage?> sendChatMessage(String roomId, String text, {String? attachmentId}) async {
    final token = await _storageService.getToken();
    if (token == null) return null;
    
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/sendMessage');
    try {
      final bodyMap = <String, dynamic>{'chatRoomId': roomId, 'body': text};
      if (attachmentId != null) {
        bodyMap['attachmentId'] = attachmentId;
      }
      
      final response = await _HttpWithTimeout.post(
        url, 
        headers: {'Authorization': token, 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(bodyMap)
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ChatMessage.fromJson(data);
      } else {
        debugPrint('sendChatMessage failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('sendChatMessage exception: $e');
    }
    return null;
  }

  Future<void> markChatRoomRead(String roomId) async {
    final token = await _storageService.getToken();
    if (token == null) return;
    
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/markReadReceipt');
    try {
      await _HttpWithTimeout.post(
        url, 
        headers: {'Authorization': token, 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'chatRoomId': roomId})
      );
    } catch (_) {}
  }

  Future<bool> deleteChatMessage(String messageId) async {
    final token = await _storageService.getToken();
    if (token == null) return false;

    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/deleteMessage');
    try {
      final response = await _HttpWithTimeout.post(
        url,
        headers: {'Authorization': token, 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'messageId': messageId}),
      );
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }

  Future<List<ChatReaction>?> toggleChatReaction(String messageId, String emoji) async {
    final token = await _storageService.getToken();
    if (token == null) return null;

    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/toggleReaction');
    try {
      final response = await _HttpWithTimeout.post(
        url,
        headers: {'Authorization': token, 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'messageId': messageId, 'emoji': emoji}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['reactions'] is List) {
          return (data['reactions'] as List)
              .whereType<Map<String, dynamic>>()
              .map((r) => ChatReaction.fromJson(r))
              .toList();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> setChatTyping(String roomId) async {
    final token = await _storageService.getToken();
    if (token == null) return;

    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/setTyping');
    try {
      await _HttpWithTimeout.post(
        url,
        headers: {'Authorization': token, 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'chatRoomId': roomId}),
      );
    } catch (_) {}
  }

  Future<List<String>> getChatTyping(String roomId) async {
    final token = await _storageService.getToken();
    if (token == null) return [];

    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/getTyping?chatRoomId=${Uri.encodeComponent(roomId)}');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['typing'] is List) {
          return (data['typing'] as List)
              .map((e) => (e['name'] ?? '').toString())
              .where((name) => name.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<int> getChatUnreadCount() async {
    final token = await _storageService.getToken();
    if (token == null) return 0;
    
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/getUnreadCount');
    try {
      final response = await _HttpWithTimeout.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['total'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }


  // ── Admin Login (Switch User) ─────────────────────────────────────────────
  Future<bool> adminLogin(String adminUser, String adminPass, String targetUser) async {
    final ok = await login(adminUser, adminPass);
    if (!ok) return false;
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/User?where[0][type]=equals&where[0][attribute]=userName&where[0][value]=${Uri.encodeComponent(targetUser)}');
      final resp = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['list'] != null && (data['list'] as List).isNotEmpty) {
          final user = (data['list'] as List).first;
          final targetUserId = user['id'] as String;
          await _storageService.saveUserId(targetUserId);
          if (user['name'] != null) {
            await _storageService.saveAngestellteName(user['name']);
          }
          final angUrl = Uri.parse('${ServerConfig().apiUrl}/Angestellte?where[0][type]=equals&where[0][attribute]=assignedUserId&where[0][value]=$targetUserId');
          final angResp = await _HttpWithTimeout.get(angUrl, headers: await _getHeaders());
          if (angResp.statusCode == 200) {
            final angData = json.decode(angResp.body);
            if (angData['list'] != null && (angData['list'] as List).isNotEmpty) {
              final ang = (angData['list'] as List).first;
              await _storageService.saveAngestellteId(ang['id']);
              if (ang['name'] != null) {
                await _storageService.saveAngestellteName(ang['name']);
              }
            }
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // ── Arbeitszeitkonten ──────────────────────────────────────────────────────
  Future<List<Arbeitszeitkonto>> getArbeitszeitkonten({String? angestellteId, int limit = 500}) async {
    final where = <Map<String, dynamic>>[];
    if (angestellteId != null) {
      where.add({'type': 'equals', 'attribute': 'angestellteId', 'value': angestellteId});
    }
    final url = Uri.parse('${ServerConfig().apiUrl}/Arbeitszeitkonto?maxSize=$limit&orderBy=jahr&order=desc${where.isNotEmpty ? '&where=${Uri.encodeComponent(json.encode(where))}' : ''}');
    try {
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Arbeitszeitkonto.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('getArbeitszeitkonten error: $e');
    }
    return [];
  }

  // ── Change Password ────────────────────────────────────────────────────────
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    final self = await getSelfUser();
    final userId = self?['user']?['id'];
    if (userId == null) return false;
    final url = Uri.parse('${ServerConfig().apiUrl}/User/$userId/password');
    try {
      final response = await _HttpWithTimeout.put(
        url,
        headers: await _getHeaders(),
        body: json.encode({
          'currentPassword': currentPassword,
          'password': newPassword,
          'confirmPassword': newPassword,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Active Banner ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getActiveBanner() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/CAppBanner?where[0][type]=isTrue&where[0][attribute]=aktiv&maxSize=1');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null && (data['list'] as List).isNotEmpty) {
          return (data['list'] as List).first as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return null;
  }

  // ── System Checkin Config ──────────────────────────────────────────────────
  Future<bool> getCheckinConfig() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/Slots/action/getCheckinConfig');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['checkinCheckoutEnabled'] == true;
      }
    } catch (_) {}
    return true;
  }

  // ── Stored Employee Name ───────────────────────────────────────────────────
  Future<String?> getStoredAngestellteName() async {
    return await _storageService.getAngestellteName();
  }

  // ── Create Wachbuch ────────────────────────────────────────────────────────
  Future<String?> createWachbuch(String name, String? objId) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'status': 'Active',
        if (objId != null) ...{
          'serviceObjectId': objId,
          'objekteId': objId,
        },
      };
      final url = Uri.parse('${ServerConfig().apiUrl}/CWachbuch');
      final response = await _HttpWithTimeout.post(
        url,
        headers: await _getHeaders(),
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // ── Active Shift Info ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getAktiveSchichtInfo() async {
    try {
      final now = DateTime.now();
      final slots = await getSlots(
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );
      Slot? activeSlot;
      for (final s in slots) {
        if (s.checkin != null && s.checkout == null) {
          activeSlot = s;
          break;
        }
      }
      if (activeSlot == null) {
        for (final s in slots) {
          if (s.dateStart != null && s.dateEnd != null) {
            try {
              final start = DateTime.parse(s.dateStart!);
              final end = DateTime.parse(s.dateEnd!);
              if (now.isAfter(start) && now.isBefore(end)) {
                activeSlot = s;
                break;
              }
            } catch (_) {}
          }
        }
      }
      if (activeSlot == null && slots.isNotEmpty) {
        activeSlot = slots.first;
      }
      if (activeSlot == null) return null;

      Wachbuch? matchingWb;
      final books = await getWachbuchs();
      for (final wb in books) {
        // 1. Exact foreign key match by serviceObjectId
        if (activeSlot.objekteId != null &&
            wb.serviceObjectId != null &&
            activeSlot.objekteId == wb.serviceObjectId) {
          matchingWb = wb;
          break;
        }
        // 2. Exact name match
        final activeName = (activeSlot.objekteName ?? activeSlot.name).trim().toLowerCase();
        final wbName = wb.name.trim().toLowerCase();
        if (activeName.isNotEmpty && wbName == activeName) {
          matchingWb = wb;
          break;
        }
        // 3. Substring match
        if (activeName.isNotEmpty && (wbName.contains(activeName) || activeName.contains(wbName))) {
          matchingWb = wb;
          break;
        }
      }

      return {
        'slot': activeSlot,
        'wachbuch': matchingWb,
      };
    } catch (_) {
      return null;
    }
  }

  // ── Dienstanweisungen ──────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getDienstanweisungen() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/Dienstanweisung?maxSize=100&orderBy=createdAt&order=desc');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          return List<Map<String, dynamic>>.from(data['list']);
        }
      }
    } catch (e) {
      debugPrint('getDienstanweisungen error: $e');
    }
    return [];
  }

  // ── Delta-Sync: Slots ───────────────────────────────────────────────────────
  Future<List<Slot>> getSlotsDelta({required DateTime since}) async {
    try {
      final sinceUtc = since.toUtc();
      final sinceStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(sinceUtc);
      final baseUri = Uri.parse(ServerConfig().apiUrl);
      final url = Uri(
        scheme: baseUri.scheme,
        host: baseUri.host,
        port: baseUri.hasPort ? baseUri.port : null,
        path: '${baseUri.path}/Slots',
        queryParameters: {
          'maxSize': '500',
          'where[0][type]': 'greaterThanOrEquals',
          'where[0][attribute]': 'modifiedAt',
          'where[0][value]': sinceStr,
          'orderBy': 'modifiedAt',
          'order': 'asc',
        },
      );

      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          return (data['list'] as List).map((e) => Slot.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('getSlotsDelta error: $e');
    }
    return [];
  }

  // ── Upcoming Birthdays ─────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getUpcomingBirthdays() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte?select=id,name,firstName,lastName,geburtsdatum&maxSize=500&where[0][type]=isNotNull&where[0][attribute]=geburtsdatum');
      final response = await _HttpWithTimeout.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['list'] != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final List<Map<String, dynamic>> upcoming = [];
          for (final item in data['list']) {
            final bdateStr = item['geburtsdatum'] as String?;
            if (bdateStr == null || bdateStr.length < 10) continue;
            try {
              final bDate = DateTime.parse(bdateStr);
              var nextBday = DateTime(now.year, bDate.month, bDate.day);
              if (nextBday.isBefore(today)) {
                nextBday = DateTime(now.year + 1, bDate.month, bDate.day);
              }
              final diffDays = nextBday.difference(today).inDays;
              if (diffDays >= 0 && diffDays <= 7) {
                final copy = Map<String, dynamic>.from(item);
                copy['daysUntil'] = diffDays;
                copy['age'] = nextBday.year - bDate.year;
                upcoming.add(copy);
              }
            } catch (_) {}
          }
          upcoming.sort((a, b) => (a['daysUntil'] as int).compareTo(b['daysUntil'] as int));
          return upcoming;
        }
      }
    } catch (e) {
      debugPrint('getUpcomingBirthdays error: $e');
    }
    return [];
  }
}

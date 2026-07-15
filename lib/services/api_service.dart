import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
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

class ApiService {
  final SecureStorageService _storageService = SecureStorageService();

  Future<bool> pingServer() async {
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/App/user');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
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
      final response = await http.get(url).timeout(const Duration(seconds: 8));
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
        final response = await http.get(url, headers: headers);
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
      final response = await http.get(
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
            final qRes = await http.get(qUrl, headers: {'Authorization': basicAuth, 'Accept': 'application/json'});
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
              final qRes2 = await http.get(qUrl2, headers: {'Authorization': basicAuth, 'Accept': 'application/json'});
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
             final userResp = await http.get(userUrl, headers: {
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
    final url = Uri.parse('${ServerConfig().apiUrl}/Objekte/$id?select=latk,lonK,rad');
    final response = await http.get(url, headers: await _getHeaders());
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
          return {
            'latk': lat, 
            'lonK': lon,
            'rad': parsedRad,
          };
        }
      }
    }
    return null;
  }

  Future<Slot?> getSlotById(String id) async {
    final url = Uri.parse(
        '${ServerConfig().apiUrl}/Slots/$id'
        '?select=id,name,status,dateStart,dateEnd,schichtbezeichnung,objekteId,objekteName,angestellteId,angestellteName,accountId,accountName,salesOrderName,positionsname,firmaFarbcode,color,kooperationspartnerName,stundenanzahl,checkin,checkout,neueobjektstrasse,neueobjektplz,neueobjektort,firmastrasse,firmaplz,firmaort,latk,lonK,bewacherID,personalausweisnummer,kleidung,kleidungAnmerkungen,neueobjektkleidung,neueobjektkleidunganmerkung,annahmeStatus');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Slot.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<dynamic> getMetadata() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Metadata');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load metadata');
  }

  Future<bool> patchSlot(String slotId, Map<String, dynamic> data) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Slots/$slotId');
    final response = await http.patch(
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

  /// Nimmt eine Schicht an — nutzt Custom Server Action mit Validierung.
  /// Fällt bei älteren Server-Versionen auf einfaches PATCH zurück.
  Future<bool> annehmeSchicht(String slotId) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Slots/$slotId/action/annehmen');
    try {
      final response = await http.post(url, headers: await _getHeaders(), body: '{}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return true;
        throw Exception(data['message'] ?? 'Unbekannter Fehler');
      }
      if (response.statusCode == 404) {
        // Custom Action noch nicht deployed — Fallback auf PATCH
        debugPrint('annehmeSchicht: Custom Action nicht verfügbar, Fallback auf PATCH');
        return patchSlot(slotId, {'annahmeStatus': 'Angenommen'});
      }
      throw Exception('Server-Fehler: ${response.statusCode} – ${response.body}');
    } catch (e) {
      // Netzwerkfehler — Fallback auf PATCH
      debugPrint('annehmeSchicht action failed: $e, falling back to PATCH');
      return patchSlot(slotId, {'annahmeStatus': 'Angenommen'});
    }
  }

  /// Lehnt eine Schicht ab — nutzt Custom Server Action.
  Future<bool> ablehneSchicht(String slotId, {String? grund}) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Slots/$slotId/action/ablehnen');
    try {
      final body = json.encode(grund != null ? {'grund': grund} : {});
      final response = await http.post(url, headers: await _getHeaders(), body: body);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) return true;
        throw Exception(data['message'] ?? 'Unbekannter Fehler');
      }
      if (response.statusCode == 404) {
        debugPrint('ablehneSchicht: Custom Action nicht verfügbar, Fallback auf PATCH');
        return patchSlot(slotId, {'annahmeStatus': 'Abgelehnt'});
      }
      throw Exception('Server-Fehler: ${response.statusCode} – ${response.body}');
    } catch (e) {
      debugPrint('ablehneSchicht action failed: $e, falling back to PATCH');
      return patchSlot(slotId, {'annahmeStatus': 'Abgelehnt'});
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
      final response = await http.get(url, headers: await _getHeaders());
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
      final response = await http.get(actionUrl, headers: await _getHeaders());
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
          try {
            final fmt = 'yyyy-MM-dd HH:mm:ss';
            // Simplified: count only slots with both timestamps
            istStunden += s.stundenanzahl ?? 0;
          } catch (_) {}
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
    final response = await http.get(url, headers: await _getHeaders());
    debugPrint('getWachbuchs status: ${response.statusCode}');
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
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
    return [];
  }

  /// Fetches a single Wachbuch record by ID (includes dateinFotos* fields).
  Future<Wachbuch?> getWachbuchById(String id) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CWachbuch/$id');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Wachbuch.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<Map<String, dynamic>?> getSelfUser() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/App/user');
    final headers = await _getHeaders();
    try {
      final response = await http.get(url, headers: headers);
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

    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Slot.fromJson(e)).toList();
      }
    }
    return [];
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
    final response = await http.get(url, headers: await _getHeaders());
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
    final response = await http.post(url, headers: headers, body: body);
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
    final response = await http.post(url, headers: headers, body: body);
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
    final response = await http.post(url, headers: headers, body: body);
    debugPrint('createNote status: ${response.statusCode}');
    debugPrint('createNote body: ${response.body}');
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<void> triggerWachbuchUpdate(String id) async {
    final token = await _storageService.getToken();
    if (token == null) return;
    try {
      final url = Uri.parse('${ServerConfig().apiUrl}/CWachbuch/$id');
      await http.put(
        url,
        headers: {'Authorization': token, 'Content-Type': 'application/json'},
        body: json.encode({'modifiedAt': DateTime.now().toUtc().toIso8601String()}),
      );
    } catch (_) {}
  }

  Future<List<Urlaub>> getUrlaubs() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CUrlaube?maxSize=100&orderBy=createdAt&order=desc');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Urlaub.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<List<Krankentage>> getKrankentage() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CKrankenscheine?maxSize=100&orderBy=createdAt&order=desc');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Krankentage.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<List<Bereitschaft>> getBereitschaften() async {
    // Bereitschaften der letzten 30 Tage bis zu den nächsten 180 Tagen laden
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
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Bereitschaft.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<bool> createUrlaub({
    required String dateStart,
    required String dateEnd,
    required String description,
  }) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CUrlaube');
    final headers = await _getHeaders();
    final angestellteId = await _storageService.getAngestellteId();
    final assignedUserId = await _storageService.getAssignedUserId();
    final angestellteName = await _storageService.getAngestellteName() ?? '';
    
    final body = json.encode({
      'name': 'Urlaub $angestellteName'.trim(),
      'status': 'In Bearbeitung',
      'dateStart': dateStart, // e.g. "2026-03-20 00:00:00"
      'dateEnd': dateEnd,   // e.g. "2026-03-20 23:59:59"
      'description': description,
      'isAllDay': true, // Standard for vacation
      if (angestellteId != null) 'parentId': angestellteId,
      if (angestellteId != null) 'parentType': 'Angestellte',
      if (assignedUserId != null) 'assignedUserId': assignedUserId,
    });
    
    final response = await http.post(url, headers: headers, body: body);
    debugPrint('createUrlaub response: ${response.statusCode}');
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
    final angestellteId = await _storageService.getAngestellteId();
    final assignedUserId = await _storageService.getAssignedUserId();
    final angestellteName = await _storageService.getAngestellteName() ?? '';
    
    final body = json.encode({
      'name': 'Krank $angestellteName'.trim(),
      'status': 'Planned', // Default typically used for illness in Espo
      'dateStart': dateStart,
      'dateEnd': dateEnd,
      'description': description,
      'isAllDay': true,
      if (krankenscheinId != null) 'krankenscheinId': krankenscheinId,
      if (angestellteId != null) 'parentId': angestellteId,
      if (angestellteId != null) 'parentType': 'Angestellte',
      if (assignedUserId != null) 'assignedUserId': assignedUserId,
    });
    
    final response = await http.post(url, headers: headers, body: body);
    debugPrint('createKrankentage response: ${response.statusCode}');
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> updateKrankentage(String id, String krankenscheinId) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CKrankenscheine/$id');
    final headers = await _getHeaders();
    final body = json.encode({
      'krankenscheinId': krankenscheinId,
    });
    final response = await http.put(url, headers: headers, body: body);
    return response.statusCode == 200;
  }

  Future<List<Angestellte>> getAngestellte() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte?maxSize=100&orderBy=name&order=asc');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Angestellte.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<Angestellte?> getAngestellteById(String id) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte/$id');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Angestellte.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<bool> updateAngestellte(String id, Map<String, dynamic> updates) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte/$id');
    final headers = await _getHeaders();
    final body = json.encode(updates);
    final response = await http.put(url, headers: headers, body: body);
    return response.statusCode == 200;
  }

  Future<List<DocumentFolder>> getDocumentFolders() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/DocumentFolder?maxSize=100&orderBy=name&order=asc');
    final response = await http.get(url, headers: await _getHeaders());
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
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => EspoDocument.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<List<EspoNotification>> getNotifications() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Notification?maxSize=20');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => EspoNotification.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<bool> markNotificationRead(String id) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Notification/$id');
    final headers = await _getHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await http.put(url, headers: headers, body: json.encode({'read': true}));
    return response.statusCode == 200;
  }

  Future<List<Abwesenheit>> getAbwesenheiten() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/CAbwesenheitsnotizen?maxSize=100&orderBy=dateStart&order=desc');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Abwesenheit.fromJson(e)).toList();
      }
    }
    return [];
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
    
    final response = await http.post(url, headers: headers, body: body);
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<List<Meeting>> getMeetings() async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Meeting?maxSize=50&orderBy=dateStart&order=desc');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Meeting.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<Meeting?> getMeetingById(String id) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Meeting/$id');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Meeting.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<bool> updateMeetingStatus(String id, String status) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/Meeting/$id');
    final headers = await _getHeaders();
    final body = json.encode({'status': status});
    final response = await http.put(url, headers: headers, body: body);
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
    
    final response = await http.post(url, headers: headers, body: body);
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<List<Map<String, dynamic>>> searchEntities(String entityType, String query) async {
    final url = Uri.parse('${ServerConfig().apiUrl}/$entityType?maxSize=20&where[0][type]=contains&where[0][attribute]=name&where[0][value]=$query');
    final response = await http.get(url, headers: await _getHeaders());
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
    
    final meetResp = await http.get(meetUrl, headers: headers);
    if (meetResp.statusCode == 200) {
      final jsonMeet = json.decode(meetResp.body);
      if (jsonMeet['total'] != null && jsonMeet['total'] > 0) return true;
    }

    // Check Slots (Shifts)
    final slotUrl = Uri.parse('${ServerConfig().apiUrl}/Slots?maxSize=1'
      '&where[0][type]=equals&where[0][attribute]=assignedUserId&where[0][value]=$userId'
      '&where[1][type]=between&where[1][attribute]=dateStart&where[1][value]=$start&where[1][value]=$end');
    
    final slotResp = await http.get(slotUrl, headers: headers);
    if (slotResp.statusCode == 200) {
      final jsonSlot = json.decode(slotResp.body);
      if (jsonSlot['total'] != null && jsonSlot['total'] > 0) return true;
    }

    return false;
  }

  Future<String> syncFcmToken() async {
    final userId = await _storageService.getAssignedUserId();
    final angId = await _storageService.getAngestellteId();
    final fcmToken = await _storageService.read('fcm_token');
    
    if (fcmToken == null || fcmToken.isEmpty) {
      return 'Fehler: Kein Token lokal gefunden (null/empty).';
    }

    String tokenPreview = fcmToken.length > 8 ? fcmToken.substring(0, 8) + "..." : fcmToken;

    if (userId == null && angId == null) {
      return 'Abgebrochen: Keine UserID/AngestellteID gefunden.';
    }

    String result = "Token ($tokenPreview) ";
    final headers = await _getHeaders();
    final payload = json.encode({
      'cFcmToken': fcmToken,
      'fcmToken': fcmToken,
    });

    // 1. Update User
    if (userId != null) {
      try {
        final url = Uri.parse('${ServerConfig().apiUrl}/User/$userId');
        debugPrint('Syncing User FCM Token to $url');
        final response = await http.patch(url, headers: headers, body: payload);

        if (response.statusCode == 200) {
          result += "User: OK. ";
        } else if (response.statusCode == 405) {
          final putResp = await http.put(url, headers: headers, body: payload);
          result += "User: ${putResp.statusCode == 200 ? 'OK (PUT)' : 'Fehler ${putResp.statusCode}'}. ";
        } else {
          result += "User: Fehler ${response.statusCode}. ";
          debugPrint('FCM Sync User failed: ${response.body}');
        }
      } catch (e) {
        result += "User: Exception. ";
      }
    }

    // 2. Update Angestellte (Employee) - redundant safe bet
    if (angId != null) {
      try {
        final url = Uri.parse('${ServerConfig().apiUrl}/Angestellte/$angId');
        debugPrint('Syncing Angestellte FCM Token to $url');
        final response = await http.patch(url, headers: headers, body: payload);
        if (response.statusCode == 200) {
          result += "Angestellte: OK. ";
        } else {
          // Failure here is often expected if field doesn't exist, so we don't treat it as critical
          debugPrint('FCM Sync Angestellte failed: ${response.statusCode}');
        }
      } catch (_) {}
    }

    return result.isEmpty ? "Kein Sync durchgeführt." : result;
  }

  // --- Email Endpoints --- //

  Future<List<Map<String, dynamic>>> getEmailFolders() async {
    final token = await _storageService.getToken();
    if (token == null) return [];
    
    // Custom folders
    final url = Uri.parse('${ServerConfig().apiUrl}/EmailFolder');
    try {
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.get(Uri.parse(url), headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.post(
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
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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
      final response = await http.post(
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

  Future<List<ChatMessage>> getChatMessages(String roomId, {int offset = 0}) async {
    final token = await _storageService.getToken();
    if (token == null) return [];
    
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/getMessages?chatRoomId=$roomId&offset=$offset');
    try {
      final response = await http.get(url, headers: {'Authorization': token, 'Accept': 'application/json'});
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

  Future<bool> sendChatMessage(String roomId, String text, {String? attachmentId}) async {
    final token = await _storageService.getToken();
    if (token == null) return false;
    
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/sendMessage');
    try {
      final bodyMap = <String, dynamic>{'chatRoomId': roomId, 'body': text};
      if (attachmentId != null) {
        bodyMap['attachmentId'] = attachmentId;
      }
      
      final response = await http.post(
        url, 
        headers: {'Authorization': token, 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(bodyMap)
      );
      if (response.statusCode != 200) {
        debugPrint('sendChatMessage failed: ${response.statusCode} - ${response.body}');
      }
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('sendChatMessage exception: $e');
    }
    return false;
  }

  Future<void> markChatRoomRead(String roomId) async {
    final token = await _storageService.getToken();
    if (token == null) return;
    
    final url = Uri.parse('${ServerConfig().apiUrl}/ChatMessage/action/markRead');
    try {
      await http.post(
        url, 
        headers: {'Authorization': token, 'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'chatRoomId': roomId})
      );
    } catch (_) {}
  }

}

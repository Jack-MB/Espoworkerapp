import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import '../core/constants.dart';
import 'secure_storage_service.dart';
import '../models/wachbuch.dart';
import '../models/slot.dart';
import '../models/note.dart';
import '../models/urlaub.dart';
import '../models/krankentage.dart';
import '../models/angestellte.dart';
import '../models/document.dart';
import '../models/notification.dart';
import '../models/abwesenheit.dart';
import '../models/meeting.dart';

class ApiService {
  final SecureStorageService _storageService = SecureStorageService();

  Future<bool> pingServer() async {
    try {
      final url = Uri.parse('${AppConstants.apiUrl}/App/user');
      // Just a HEAD or quick GET, without auth if we just want reachability
      // but App/user might return 401, which is enough to know it's there.
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      return true; // We got a response, even if 401
    } catch (_) {
      return false;
    }
  }

  Future<bool> login(String rawUsername, String rawPassword) async {
    final String username = rawUsername.trim();
    final String password = rawPassword.trim();
    
    debugPrint('Attempting login for: $username to \${AppConstants.apiUrl}/App/user');

    final bool isApiKey = password.length > 20 && !password.contains(' ');

    if (isApiKey) {
      final url = Uri.parse('${AppConstants.apiUrl}/App/user');
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
    final url = Uri.parse('${AppConstants.apiUrl}/App/user');
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
        final String? angestelltexId = data['user'] != null 
            ? (data['user']['angestelltexId'] ?? data['user']['angestellte2Id']) 
            : null;

        final String? userId = data['user'] != null ? data['user']['id'] : null;
        final String? angestellteName = data['user'] != null 
            ? (data['user']['angestelltexName'] ?? data['user']['angestellte2Name']) 
            : null;

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
      debugPrint('App/user returned \${response.statusCode} - \${response.body}');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Objekte/$id?select=latk,lonK,rad');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Slots/$id');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Slot.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<dynamic> getMetadata() async {
    final url = Uri.parse('${AppConstants.apiUrl}/Metadata');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to load metadata');
  }

  Future<bool> patchSlot(String slotId, Map<String, dynamic> data) async {
    final url = Uri.parse('${AppConstants.apiUrl}/Slots/$slotId');
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

  Future<List<Wachbuch>> getWachbuchs() async {
    final url = Uri.parse('${AppConstants.apiUrl}/CWachbuch?maxSize=50&orderBy=createdAt&order=desc');
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
    final url = Uri.parse('${AppConstants.apiUrl}/CWachbuch/$id');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Wachbuch.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<Map<String, dynamic>?> getSelfUser() async {
    final url = Uri.parse('${AppConstants.apiUrl}/App/user');
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

    final baseUri = Uri.parse(AppConstants.apiUrl);
    final url = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '${baseUri.path}/Slots',
      queryParameters: {
        'maxSize': '500',
        'where[0][type]': 'greaterThanOrEquals',
        'where[0][attribute]': 'dateStart',
        'where[0][value]': startStr,
        'where[1][type]': 'lessThanOrEquals',
        'where[1][attribute]': 'dateStart',
        'where[1][value]': endStr,
        'orderBy': 'dateStart',
        'order': 'asc',
        'select': 'id,name,status,dateStart,dateEnd,schichtbezeichnung,objekteId,objekteName,angestellteId,angestellteName,accountId,accountName,salesOrderName,positionsname,firmaFarbcode,kooperationspartnerName,stundenanzahl,checkin,checkout,neueobjektstrasse,neueobjektplz,neueobjektort,firmastrasse,firmaplz,firmaort,latk,lonK,bewacherID,personalausweisnummer',
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
    final baseUri = Uri.parse(AppConstants.apiUrl);
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
        'select': 'id,post,type,createdAt,createdById,createdByName,parentType,parentId,attachmentsIds,attachmentsNames,attachmentsTypes',
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
    final url = Uri.parse('${AppConstants.apiUrl}/Note');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Attachment');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Note');
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

  Future<List<Urlaub>> getUrlaubs() async {
    final url = Uri.parse('${AppConstants.apiUrl}/Urlaub?maxSize=100&orderBy=createdAt&order=desc');
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
    final url = Uri.parse('${AppConstants.apiUrl}/CKrankentage?maxSize=100&orderBy=createdAt&order=desc');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['list'] != null) {
        return (data['list'] as List).map((e) => Krankentage.fromJson(e)).toList();
      }
    }
    return [];
  }

  Future<bool> createUrlaub({
    required String dateStart,
    required String dateEnd,
    required String description,
  }) async {
    final url = Uri.parse('${AppConstants.apiUrl}/Urlaub');
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
      if (angestellteId != null) 'angestellteId': angestellteId,
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
    final url = Uri.parse('${AppConstants.apiUrl}/CKrankentage');
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
      if (angestellteId != null) 'angestellteId': angestellteId,
      if (assignedUserId != null) 'assignedUserId': assignedUserId,
    });
    
    final response = await http.post(url, headers: headers, body: body);
    debugPrint('createKrankentage response: ${response.statusCode}');
    return response.statusCode == 200 || response.statusCode == 201;
  }

  Future<bool> updateKrankentage(String id, String krankenscheinId) async {
    final url = Uri.parse('${AppConstants.apiUrl}/CKrankentage/$id');
    final headers = await _getHeaders();
    final body = json.encode({
      'krankenscheinId': krankenscheinId,
    });
    final response = await http.put(url, headers: headers, body: body);
    return response.statusCode == 200;
  }

  Future<List<Angestellte>> getAngestellte() async {
    final url = Uri.parse('${AppConstants.apiUrl}/Angestellte?maxSize=100&orderBy=name&order=asc');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Angestellte/$id');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Angestellte.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<bool> updateAngestellte(String id, Map<String, dynamic> updates) async {
    final url = Uri.parse('${AppConstants.apiUrl}/Angestellte/$id');
    final headers = await _getHeaders();
    final body = json.encode(updates);
    final response = await http.put(url, headers: headers, body: body);
    return response.statusCode == 200;
  }

  Future<List<EspoDocument>> getDocuments() async {
    final url = Uri.parse('${AppConstants.apiUrl}/Document?maxSize=50&orderBy=createdAt&order=desc');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Notification?maxSize=20');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Notification/$id');
    final headers = await _getHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await http.put(url, headers: headers, body: json.encode({'read': true}));
    return response.statusCode == 200;
  }

  Future<List<Abwesenheit>> getAbwesenheiten() async {
    final url = Uri.parse('${AppConstants.apiUrl}/CAbwesenheitsnotiz?maxSize=100&orderBy=dateStart&order=desc');
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
    final url = Uri.parse('${AppConstants.apiUrl}/CAbwesenheitsnotiz');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Meeting?maxSize=50&orderBy=dateStart&order=desc');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Meeting/$id');
    final response = await http.get(url, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return Meeting.fromJson(json.decode(response.body));
    }
    return null;
  }

  Future<bool> updateMeetingStatus(String id, String status) async {
    final url = Uri.parse('${AppConstants.apiUrl}/Meeting/$id');
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
    final url = Uri.parse('${AppConstants.apiUrl}/Meeting');
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
    final url = Uri.parse('${AppConstants.apiUrl}/$entityType?maxSize=20&where[0][type]=contains&where[0][attribute]=name&where[0][value]=$query');
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
    final meetUrl = Uri.parse('${AppConstants.apiUrl}/Meeting?maxSize=1'
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
    final slotUrl = Uri.parse('${AppConstants.apiUrl}/Slot?maxSize=1'
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
        final url = Uri.parse('${AppConstants.apiUrl}/User/$userId');
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
        final url = Uri.parse('${AppConstants.apiUrl}/Angestellte/$angId');
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
}

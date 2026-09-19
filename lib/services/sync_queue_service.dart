import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// A persistent sync queue that stores pending check-in/check-out updates
/// locally and retries them when the network is available.
class SyncQueueService extends ChangeNotifier {
  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;
  SyncQueueService._internal() {
    _initPendingCount();
  }

  static const String _storageKey = 'pending_sync_queue';
  final ApiService _apiService = ApiService();
  Timer? _retryTimer;
  bool _isSyncing = false;
  int _pendingCount = 0;

  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;

  Future<void> _initPendingCount() async {
    final queue = await _loadQueue();
    _pendingCount = queue.length;
    notifyListeners();
  }

  // Callback to notify the UI about sync state changes (backward compatibility)
  void Function(int pendingCount)? onSyncStateChanged;

  /// Add a pending sync item to the queue.
  Future<void> enqueue({
    required String slotId,
    required Map<String, dynamic> data,
    required String description,
  }) async {
    final item = {
      'slotId': slotId,
      'data': data,
      'description': description,
      'createdAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
    };

    final queue = await _loadQueue();
    // Remove any existing entry for the same slotId+field combo to avoid duplicates
    queue.removeWhere((q) => q['slotId'] == slotId && _sameFields(q['data'], data));
    queue.add(item);
    await _saveQueue(queue);

    debugPrint('SyncQueue: Enqueued for $slotId ($description). Queue size: ${queue.length}');
    onSyncStateChanged?.call(queue.length);

    // Try to sync immediately
    processQueue();
  }

  /// Add a pending Wachbuch note to the queue (offline support).
  Future<void> enqueueWachbuchNote({
    required String wachbuchId,
    required String text,
    List<String> attachmentIds = const [],
    required String description,
  }) async {
    final item = {
      'type': 'wachbuch_note',
      'wachbuchId': wachbuchId,
      'text': text,
      'attachmentIds': attachmentIds,
      'description': description,
      'createdAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
    };

    final queue = await _loadQueue();
    queue.add(item);
    await _saveQueue(queue);

    debugPrint('SyncQueue: Enqueued Wachbuch note for $wachbuchId ($description). Queue size: ${queue.length}');
    onSyncStateChanged?.call(queue.length);

    // Try to sync immediately
    processQueue();
  }

  /// Check if two data maps update the same fields
  bool _sameFields(dynamic a, Map<String, dynamic> b) {
    if (a is! Map) return false;
    final aKeys = a.keys.toSet();
    final bKeys = b.keys.toSet();
    return aKeys.intersection(bKeys).isNotEmpty;
  }

  /// Start periodic retry timer (call once on app start)
  void startPeriodicSync({Duration interval = const Duration(seconds: 30)}) {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(interval, (_) => processQueue());
    debugPrint('SyncQueue: Periodic sync started (every ${interval.inSeconds}s)');
  }

  /// Stop the periodic retry timer
  void stopPeriodicSync() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Process all pending items in the queue
  Future<void> processQueue() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final queue = await _loadQueue();
      if (queue.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint('SyncQueue: Processing ${queue.length} pending items...');
      final List<Map<String, dynamic>> remainingQueue = [];
      int successCount = 0;

      for (final item in queue) {
        final itemType = item['type'] as String?;
        final retryCount = (item['retryCount'] as int?) ?? 0;

        try {
          bool success = false;
          if (itemType == 'wachbuch_note') {
            final wbId = item['wachbuchId'] as String;
            final text = item['text'] as String;
            final attIds = List<String>.from(item['attachmentIds'] ?? []);
            success = await _apiService.createNoteWithAttachments(wbId, text, attIds);
          } else {
            final slotId = item['slotId'] as String;
            final data = Map<String, dynamic>.from(item['data'] as Map);
            if (data.containsKey('checkin')) {
              success = await _apiService.checkInSlot(slotId, checkInTime: data['checkin']);
            } else if (data.containsKey('checkout')) {
              success = await _apiService.checkOutSlot(slotId, checkOutTime: data['checkout']);
            } else {
              success = await _apiService.patchSlot(slotId, data);
            }
          }

          if (success) {
            successCount++;
            debugPrint('SyncQueue: ✅ Synced item successfully');
          } else {
            item['retryCount'] = retryCount + 1;
            if (retryCount < 10) {
              remainingQueue.add(item);
            } else {
              debugPrint('SyncQueue: ❌ Dropped item after $retryCount retries');
            }
          }
        } catch (e) {
          final desc = item['description'] ?? item['slotId'] ?? 'item';
          debugPrint('SyncQueue: ⚠️ Error syncing $desc: $e');
          final errStr = e.toString();
          // Unrecoverable authorization error -> drop immediately
          if (errStr.contains('Berechtigung') || errStr.contains('403') || errStr.contains('deaktiviert')) {
            debugPrint('SyncQueue: ❌ Dropped $desc due to permission or disabled feature: $e');
            continue;
          }
          item['retryCount'] = retryCount + 1;
          if (retryCount < 10) {
            remainingQueue.add(item);
          } else {
            debugPrint('SyncQueue: ❌ Dropped $desc after $retryCount retries');
          }
        }
      }

      await _saveQueue(remainingQueue);
      debugPrint('SyncQueue: $successCount synced, ${remainingQueue.length} remaining');
      onSyncStateChanged?.call(remainingQueue.length);
    } finally {
      _isSyncing = false;
    }
  }

  /// Get the current number of pending items
  Future<int> getPendingCount() async {
    final queue = await _loadQueue();
    return queue.length;
  }

  /// Get a human-readable summary of pending items
  Future<List<String>> getPendingSummary() async {
    final queue = await _loadQueue();
    return queue.map((item) => '${item['description']} (Versuch ${item['retryCount']})').toList();
  }

  /// Clear all pending items (use with caution)
  Future<void> clearQueue() async {
    await _saveQueue([]);
    onSyncStateChanged?.call(0);
  }

  /// Get all pending queue items with full metadata
  Future<List<Map<String, dynamic>>> getPendingItems() async {
    return await _loadQueue();
  }

  Future<List<Map<String, dynamic>>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_storageKey);
    if (rawJson == null || rawJson.isEmpty) return [];
    try {
      final List<dynamic> decoded = json.decode(rawJson);
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('SyncQueue: Error loading queue: $e');
      return [];
    }
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, json.encode(queue));
    _pendingCount = queue.length;
    notifyListeners();
  }
}

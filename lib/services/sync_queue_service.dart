import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// A persistent sync queue that stores pending check-in/check-out updates
/// locally and retries them when the network is available.
class SyncQueueService {
  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;
  SyncQueueService._internal();

  static const String _storageKey = 'pending_sync_queue';
  final ApiService _apiService = ApiService();
  Timer? _retryTimer;
  bool _isSyncing = false;

  // Callback to notify the UI about sync state changes
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

  /// Check if two data maps update the same fields
  bool _sameFields(dynamic a, Map<String, dynamic> b) {
    if (a is! Map) return false;
    final aKeys = (a as Map).keys.toSet();
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
        final slotId = item['slotId'] as String;
        final data = Map<String, dynamic>.from(item['data'] as Map);
        final retryCount = (item['retryCount'] as int?) ?? 0;

        try {
          final success = await _apiService.patchSlot(slotId, data);
          if (success) {
            successCount++;
            debugPrint('SyncQueue: ✅ Synced $slotId successfully');
          } else {
            // Server returned non-200 but no exception
            item['retryCount'] = retryCount + 1;
            if (retryCount < 50) { // Max 50 retries (~25 min at 30s interval)
              remainingQueue.add(item);
            } else {
              debugPrint('SyncQueue: ❌ Dropped $slotId after $retryCount retries');
            }
          }
        } catch (e) {
          debugPrint('SyncQueue: ⚠️ Error syncing $slotId: $e');
          item['retryCount'] = retryCount + 1;
          if (retryCount < 50) {
            remainingQueue.add(item);
          } else {
            debugPrint('SyncQueue: ❌ Dropped $slotId after $retryCount retries');
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
  }
}

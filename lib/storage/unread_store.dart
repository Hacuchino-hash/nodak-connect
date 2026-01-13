import 'dart:async';
import 'dart:convert';

import 'prefs_manager.dart';

/// Storage for unread message tracking with debounced writes to reduce I/O.
class UnreadStore {
  static const String _contactLastReadKey = 'contact_last_read';
  static const String _channelLastReadKey = 'channel_last_read';

  // Debounce timers to batch rapid writes
  Timer? _contactSaveTimer;
  Timer? _channelSaveTimer;
  static const Duration _saveDebounceDuration = Duration(milliseconds: 500);

  // Pending write data
  Map<String, int>? _pendingContactLastRead;
  Map<int, int>? _pendingChannelLastRead;

  /// Dispose timers when no longer needed
  void dispose() {
    _contactSaveTimer?.cancel();
    _channelSaveTimer?.cancel();
  }

  Future<Map<String, int>> loadContactLastRead() async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_contactLastReadKey);
    if (jsonStr == null) return {};

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json.map((key, value) => MapEntry(key, value as int));
    } catch (_) {
      return {};
    }
  }

  /// Save contact last read timestamps with debouncing.
  /// Writes are delayed by 500ms and batched to reduce I/O operations.
  void saveContactLastRead(Map<String, int> lastReadMs) {
    _pendingContactLastRead = lastReadMs;

    // Cancel existing timer
    _contactSaveTimer?.cancel();

    // Schedule new write
    _contactSaveTimer = Timer(_saveDebounceDuration, () async {
      if (_pendingContactLastRead != null) {
        await _flushContactLastRead();
      }
    });
  }

  Future<Map<int, int>> loadChannelLastRead() async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_channelLastReadKey);
    if (jsonStr == null) return {};

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json.map((key, value) => MapEntry(int.parse(key), value as int));
    } catch (_) {
      return {};
    }
  }

  /// Save channel last read timestamps with debouncing.
  /// Writes are delayed by 500ms and batched to reduce I/O operations.
  void saveChannelLastRead(Map<int, int> lastReadMs) {
    _pendingChannelLastRead = lastReadMs;

    _channelSaveTimer?.cancel();

    _channelSaveTimer = Timer(_saveDebounceDuration, () async {
      if (_pendingChannelLastRead != null) {
        await _flushChannelLastRead();
      }
    });
  }

  Future<void> _flushContactLastRead() async {
    if (_pendingContactLastRead == null) return;

    final prefs = PrefsManager.instance;
    final jsonStr = jsonEncode(_pendingContactLastRead);
    await prefs.setString(_contactLastReadKey, jsonStr);
    _pendingContactLastRead = null;
  }

  Future<void> _flushChannelLastRead() async {
    if (_pendingChannelLastRead == null) return;

    final prefs = PrefsManager.instance;
    final asString =
        _pendingChannelLastRead!.map((key, value) => MapEntry(key.toString(), value));
    final jsonStr = jsonEncode(asString);
    await prefs.setString(_channelLastReadKey, jsonStr);
    _pendingChannelLastRead = null;
  }

  /// Immediately flush pending writes (call before app termination or disposal)
  Future<void> flush() async {
    _contactSaveTimer?.cancel();
    _channelSaveTimer?.cancel();

    await Future.wait([
      _flushContactLastRead(),
      _flushChannelLastRead(),
    ]);
  }
}

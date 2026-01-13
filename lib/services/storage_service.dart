import 'dart:convert';
import '../models/path_history.dart';
import '../storage/prefs_manager.dart';

class StorageService {
  static const String _pathHistoryPrefix = 'path_history_';
  static const String _pendingMessagesKey = 'pending_messages';
  static const String _repeaterPasswordsKey = 'repeater_passwords';
  static const String _repeaterAutoLoginKey = 'repeater_auto_login';

  Future<void> savePathHistory(
      String contactPubKeyHex, ContactPathHistory history) async {
    final prefs = PrefsManager.instance;
    final key = '$_pathHistoryPrefix$contactPubKeyHex';
    final jsonStr = jsonEncode(history.toJson());
    await prefs.setString(key, jsonStr);
  }

  Future<ContactPathHistory?> loadPathHistory(String contactPubKeyHex) async {
    final prefs = PrefsManager.instance;
    final key = '$_pathHistoryPrefix$contactPubKeyHex';
    final jsonStr = prefs.getString(key);

    if (jsonStr == null) return null;

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ContactPathHistory.fromJson(contactPubKeyHex, json);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearPathHistory(String contactPubKeyHex) async {
    final prefs = PrefsManager.instance;
    final key = '$_pathHistoryPrefix$contactPubKeyHex';
    await prefs.remove(key);
  }

  Future<void> clearAllPathHistories() async {
    final prefs = PrefsManager.instance;
    final keys = prefs.getKeys();
    final pathHistoryKeys =
        keys.where((key) => key.startsWith(_pathHistoryPrefix));

    for (final key in pathHistoryKeys) {
      await prefs.remove(key);
    }
  }

  Future<Map<String, String>> loadPendingMessages() async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_pendingMessagesKey);

    if (jsonStr == null) return {};

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json.map((key, value) => MapEntry(key, value as String));
    } catch (e) {
      return {};
    }
  }

  Future<void> savePendingMessages(Map<String, String> pending) async {
    final prefs = PrefsManager.instance;
    final jsonStr = jsonEncode(pending);
    await prefs.setString(_pendingMessagesKey, jsonStr);
  }

  Future<void> clearPendingMessages() async {
    final prefs = PrefsManager.instance;
    await prefs.remove(_pendingMessagesKey);
  }

  /// Save a repeater password by public key hex
  Future<void> saveRepeaterPassword(
      String repeaterPubKeyHex, String password) async {
    final prefs = PrefsManager.instance;
    final passwords = await loadRepeaterPasswords();
    passwords[repeaterPubKeyHex] = password;
    final jsonStr = jsonEncode(passwords);
    await prefs.setString(_repeaterPasswordsKey, jsonStr);
  }

  /// Load all saved repeater passwords (map of pubKeyHex -> password)
  Future<Map<String, String>> loadRepeaterPasswords() async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_repeaterPasswordsKey);

    if (jsonStr == null) return {};

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json.map((key, value) => MapEntry(key, value as String));
    } catch (e) {
      return {};
    }
  }

  /// Get a specific repeater's saved password
  Future<String?> getRepeaterPassword(String repeaterPubKeyHex) async {
    final passwords = await loadRepeaterPasswords();
    return passwords[repeaterPubKeyHex];
  }

  /// Remove a saved repeater password
  Future<void> removeRepeaterPassword(String repeaterPubKeyHex) async {
    final prefs = PrefsManager.instance;
    final passwords = await loadRepeaterPasswords();
    passwords.remove(repeaterPubKeyHex);
    final jsonStr = jsonEncode(passwords);
    await prefs.setString(_repeaterPasswordsKey, jsonStr);
  }

  /// Clear all saved repeater passwords
  Future<void> clearAllRepeaterPasswords() async {
    final prefs = PrefsManager.instance;
    await prefs.remove(_repeaterPasswordsKey);
  }

  /// Check if a specific repeater has auto-login enabled
  Future<bool> isRepeaterAutoLoginEnabled(String repeaterPubKeyHex) async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_repeaterAutoLoginKey);

    if (jsonStr == null) return false;

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return json[repeaterPubKeyHex] == true;
    } catch (e) {
      return false;
    }
  }

  /// Set auto-login enabled/disabled for a specific repeater
  Future<void> setRepeaterAutoLogin(
      String repeaterPubKeyHex, bool enabled) async {
    final prefs = PrefsManager.instance;
    final jsonStr = prefs.getString(_repeaterAutoLoginKey);
    Map<String, dynamic> settings = {};

    if (jsonStr != null) {
      try {
        settings = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (e) {
        // ignore parse errors
      }
    }

    if (enabled) {
      settings[repeaterPubKeyHex] = true;
    } else {
      settings.remove(repeaterPubKeyHex);
    }

    await prefs.setString(_repeaterAutoLoginKey, jsonEncode(settings));
  }
}

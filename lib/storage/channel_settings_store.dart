import 'prefs_manager.dart';

class ChannelSettingsStore {
  static const String _smazKeyPrefix = 'channel_smaz_';
  static const String _mutedKeyPrefix = 'channel_muted_';

  Future<bool> loadSmazEnabled(int channelIndex) async {
    final prefs = PrefsManager.instance;
    final key = '$_smazKeyPrefix$channelIndex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveSmazEnabled(int channelIndex, bool enabled) async {
    final prefs = PrefsManager.instance;
    final key = '$_smazKeyPrefix$channelIndex';
    await prefs.setBool(key, enabled);
  }

  Future<bool> loadMuted(int channelIndex) async {
    final prefs = PrefsManager.instance;
    final key = '$_mutedKeyPrefix$channelIndex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveMuted(int channelIndex, bool muted) async {
    final prefs = PrefsManager.instance;
    final key = '$_mutedKeyPrefix$channelIndex';
    await prefs.setBool(key, muted);
  }
}

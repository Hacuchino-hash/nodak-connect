import 'package:shared_preferences/shared_preferences.dart';

class WardriveSettingsStore {
  static const _channelNameKey = 'wardrive_channel_name';
  static const _apiEndpointKey = 'wardrive_api_endpoint';
  static const _autoIntervalKey = 'wardrive_auto_interval';
  static const _ignoredRepeaterIdsKey = 'wardrive_ignored_repeaters';
  static const _sendToChannelKey = 'wardrive_send_to_channel';
  static const _sendToApiKey = 'wardrive_send_to_api';

  static const String defaultChannelName = '#wardrive';
  static const String defaultApiEndpoint = 'https://coverage.ndme.sh/put-sample';
  static const int defaultAutoInterval = 30; // seconds

  Future<String> getChannelName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_channelNameKey) ?? defaultChannelName;
  }

  Future<void> setChannelName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_channelNameKey, name);
  }

  Future<String> getApiEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiEndpointKey) ?? defaultApiEndpoint;
  }

  Future<void> setApiEndpoint(String endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiEndpointKey, endpoint);
  }

  Future<int> getAutoInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoIntervalKey) ?? defaultAutoInterval;
  }

  Future<void> setAutoInterval(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoIntervalKey, seconds);
  }

  Future<List<String>> getIgnoredRepeaterIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_ignoredRepeaterIdsKey) ?? [];
  }

  Future<void> setIgnoredRepeaterIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_ignoredRepeaterIdsKey, ids);
  }

  Future<bool> getSendToChannel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sendToChannelKey) ?? true;
  }

  Future<void> setSendToChannel(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sendToChannelKey, value);
  }

  Future<bool> getSendToApi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sendToApiKey) ?? true;
  }

  Future<void> setSendToApi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sendToApiKey, value);
  }
}

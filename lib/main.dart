import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'connector/meshcore_connector.dart';
import 'screens/scanner_screen.dart';
import 'services/storage_service.dart';
import 'services/message_retry_service.dart';
import 'services/path_history_service.dart';
import 'services/app_settings_service.dart';
import 'services/notification_service.dart';
import 'services/ble_debug_log_service.dart';
import 'services/app_debug_log_service.dart';
import 'services/background_service.dart';
import 'services/map_tile_cache_service.dart';
import 'services/wardrive_service.dart';
import 'storage/prefs_manager.dart';
import 'utils/app_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SharedPreferences cache
  await PrefsManager.initialize();

  // Initialize services
  final storage = StorageService();
  final connector = MeshCoreConnector();
  final pathHistoryService = PathHistoryService(storage);
  final retryService = MessageRetryService(storage);
  final appSettingsService = AppSettingsService();
  final bleDebugLogService = BleDebugLogService();
  final appDebugLogService = AppDebugLogService();
  final backgroundService = BackgroundService();
  final mapTileCacheService = MapTileCacheService();
  final wardriveService = WardriveService();

  // Load settings
  await appSettingsService.loadSettings();

  // Initialize app logger
  appLogger.initialize(
    appDebugLogService,
    enabled: appSettingsService.settings.appDebugLogEnabled,
  );

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();
  await backgroundService.initialize();

  // Wire up connector with services
  connector.initialize(
    retryService: retryService,
    pathHistoryService: pathHistoryService,
    appSettingsService: appSettingsService,
    bleDebugLogService: bleDebugLogService,
    appDebugLogService: appDebugLogService,
    backgroundService: backgroundService,
  );

  await connector.loadContactCache();
  await connector.loadChannelSettings();

  // Load persisted channel messages
  await connector.loadAllChannelMessages();
  await connector.loadUnreadState();

  runApp(MeshCoreApp(
    connector: connector,
    retryService: retryService,
    pathHistoryService: pathHistoryService,
    storage: storage,
    appSettingsService: appSettingsService,
    bleDebugLogService: bleDebugLogService,
    appDebugLogService: appDebugLogService,
    mapTileCacheService: mapTileCacheService,
    wardriveService: wardriveService,
  ));
}

class MeshCoreApp extends StatelessWidget {
  final MeshCoreConnector connector;
  final MessageRetryService retryService;
  final PathHistoryService pathHistoryService;
  final StorageService storage;
  final AppSettingsService appSettingsService;
  final BleDebugLogService bleDebugLogService;
  final AppDebugLogService appDebugLogService;
  final MapTileCacheService mapTileCacheService;
  final WardriveService wardriveService;

  const MeshCoreApp({
    super.key,
    required this.connector,
    required this.retryService,
    required this.pathHistoryService,
    required this.storage,
    required this.appSettingsService,
    required this.bleDebugLogService,
    required this.appDebugLogService,
    required this.mapTileCacheService,
    required this.wardriveService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: connector),
        ChangeNotifierProvider.value(value: retryService),
        ChangeNotifierProvider.value(value: pathHistoryService),
        ChangeNotifierProvider.value(value: appSettingsService),
        ChangeNotifierProvider.value(value: bleDebugLogService),
        ChangeNotifierProvider.value(value: appDebugLogService),
        ChangeNotifierProvider.value(value: wardriveService),
        Provider.value(value: storage),
        Provider.value(value: mapTileCacheService),
      ],
      child: Consumer<AppSettingsService>(
        builder: (context, settingsService, child) {
          // NodakMesh brand colors
          const ndmcEmerald = Color(0xFF10B981);
          const ndmcBgPrimary = Color(0xFF0A0A0A);
          const ndmcBgSecondary = Color(0xFF111111);
          const ndmcBgTertiary = Color(0xFF1A1A1A);

          return MaterialApp(
            title: 'Nodak Mesh Connect',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: ndmcEmerald,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: ndmcEmerald,
                brightness: Brightness.dark,
                surface: ndmcBgSecondary,
                // Remove custom override - let Material handle it
              ),
              scaffoldBackgroundColor: ndmcBgPrimary,
              cardColor: ndmcBgTertiary,
              appBarTheme: const AppBarTheme(
                backgroundColor: ndmcBgSecondary,
                surfaceTintColor: Colors.transparent,
              ),
              useMaterial3: true,
            ),
            themeMode: _themeModeFromSetting(settingsService.settings.themeMode),
            home: const ScannerScreen(),
          );
        },
      ),
    );
  }

  ThemeMode _themeModeFromSetting(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

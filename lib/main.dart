import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:decvault/features/auth/screens/auth_screen.dart';
import 'package:decvault/features/auth/screens/desktop_auth_screen.dart';
import 'package:decvault/features/decentralized/screens/export_device_pairing_screen.dart';
import 'package:decvault/features/decentralized/screens/import_device_pairing_screen.dart';
import 'package:decvault/features/decentralized/screens/node_setup_screen.dart';
import 'package:decvault/features/decentralized/screens/seed_phrase_screen.dart';
import 'package:decvault/features/decentralized/services/decentralized_service.dart';
import 'package:decvault/features/home/screens/home_screen.dart';
import 'package:decvault/features/home/screens/desktop_home_screen.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/features/backup/screens/backups_screen.dart';
import 'package:decvault/features/backup/screens/desktop_backups_screen.dart';
import 'package:decvault/features/backup/backup_service.dart';
import 'package:decvault/features/password/screens/password_generator_screen.dart';
import 'package:decvault/features/password/screens/desktop_password_generator_screen.dart';
import 'package:decvault/features/password/screens/breach_monitoring_screen.dart';
import 'package:decvault/features/password/screens/desktop_breach_monitoring_screen.dart';
import 'package:decvault/features/password/screens/add_password_screen.dart';
import 'package:decvault/features/password/screens/desktop_add_password_screen.dart';
import 'package:decvault/features/settings/screens/settings_screen.dart';
import 'package:decvault/features/settings/screens/desktop_settings_screen.dart';
import 'package:decvault/features/sia/screens/sia_settings_screen.dart';
import 'package:decvault/features/sia/screens/sia_password_required_screen.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/vault/models/file_model.dart';
import 'package:decvault/features/vault/repositories/file_repository.dart';
import 'package:decvault/features/vault/screens/vault_screen.dart';
import 'package:decvault/features/vault/screens/desktop_vault_screen.dart';
import 'package:decvault/features/vault/services/renterd_uploader.dart';
import 'package:decvault/features/vault/services/encryption_service.dart';
import 'package:decvault/features/settings/services/settings_service.dart';
import 'package:decvault/features/sia/services/sia_service.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/common/widgets/app_lifecycle_wrapper.dart';
import 'package:decvault/features/subscription/screens/subscription_screen.dart';
import 'package:decvault/features/subscription/screens/desktop_subscription_screen.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:decvault/features/subscription/services/storage_service.dart';
import 'package:decvault/features/about/screens/about_screen.dart';
import 'package:decvault/features/about/screens/desktop_about_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/core/network/authenticated_client.dart';

// Helper function to determine if running on desktop
bool get isDesktop {
  if (kIsWeb) return false;
  try {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  } catch (e) {
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Initialize Hive
    await Hive.initFlutter();
    Hive.registerAdapter(PasswordModelAdapter());
    Hive.registerAdapter(FileModelAdapter());
    await Hive.openBox<FileModel>('files');

    // ── DecentralizedService MUST be first: every downstream service calls
    //    isDecentralized (SiaService, EncryptionService, RevenueCatService…)
    final decentralizedService = DecentralizedService();
    await decentralizedService.init();
    Get.put(decentralizedService);

    // ── AuthService MUST be initialized before route determination.
    //    init() calls clearDemoData() which can invalidate the session.
    //    Reading is_logged_in from raw prefs before this runs gives a stale
    //    answer and can open /home with no valid session.
    final authService = AuthService();
    await authService.init();
    Get.put(authService);

    // Global JWT 401 interceptor — must be registered before any service that
    // makes authenticated HTTP calls.
    Get.put(AuthenticatedClient(), permanent: true);

    // Determine initial route using the authoritative post-init login state.
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    final appMode = prefs.getString('app_mode') ?? 'managed';
    final isLoggedIn = await authService.checkLoginStatus();

    String initialRoute;
    if (!onboardingComplete) {
      // Path choice is embedded in both auth screens (desktop and mobile).
      initialRoute = '/auth';
    } else if (isLoggedIn && appMode == 'decentralized') {
      initialRoute = '/home';
    } else {
      initialRoute = '/auth';
    }

    // Initialize PasswordRepository
    final privateKey = isLoggedIn ? await authService.getPrivateKey() : null;
    final passwordRepo = PasswordRepository(privateKey ?? '');
    await passwordRepo.init();
    Get.put(passwordRepo);

    // Initialize SettingsService (required by RenterdUploader and BackupService)
    final settingsService = SettingsService();
    Get.put(settingsService);

    // Initialize EncryptionService (required by BackupService and RenterdUploader)
    final encryptionService = EncryptionService(authService);
    Get.put(encryptionService);

    // Initialize SiaService (makes HTTP calls — isolate failures so a network
    // error at startup does not prevent the app from opening)
    final siaService = SiaService();
    try {
      await siaService.init();
    } catch (e) {
      // ignore
    }
    Get.put(siaService);

    // Initialize BackupService (depends on SettingsService and EncryptionService)
    final backupService = BackupService();
    try {
      await backupService.init();
    } catch (e) {
      // ignore
    }
    Get.put(backupService);

    // Initialize RenterdUploader (depends on SettingsService and EncryptionService)
    final renterdUploader = RenterdUploader(settingsService, encryptionService);
    Get.put(renterdUploader);

    // Initialize FileRepository (depends on RenterdUploader)
    final fileRepo = FileRepository(renterdUploader);
    Get.put(fileRepo);

    // Initialize SecurityService (for PIN and biometric authentication)
    try {
      final securityService = SecurityService();
      await securityService.onInit();
      Get.put(securityService);
    } catch (e) {
      // ignore
    }

    // Register subscription services
    Get.put(RevenueCatService(), permanent: true);
    Get.put(StorageService(), permanent: true);

    runApp(SecureSphereApp(initialRoute: initialRoute));
  } catch (e) {
    runApp(const _StartupErrorApp());
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                SizedBox(height: 16),
                Text(
                  'Failed to start',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'A critical error occurred during startup.\nPlease restart the app.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SecureSphereApp extends StatelessWidget {
  final String initialRoute;
  const SecureSphereApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return AppLifecycleWrapper(
      child: GetMaterialApp(
      title: 'DecVault',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1E8E3E), // Green primary color
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF1E8E3E),
          secondary: const Color(0xFF34A853),
          surface: const Color(0xFF121212),
          error: Colors.redAccent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E),
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E8E3E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF34A853),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3C4043)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF34A853), width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFF2C2C2C),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF34A853);
            }
            return Colors.grey;
          }),
          trackColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF1E8E3E).withOpacity(0.5);
            }
            return Colors.grey.withOpacity(0.5);
          }),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF34A853);
            }
            return Colors.grey;
          }),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF34A853),
          thumbColor: const Color(0xFF1E8E3E),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1E8E3E), // Green primary color
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF1E8E3E),
          secondary: const Color(0xFF34A853),
          surface: const Color(0xFF121212),
          error: Colors.redAccent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E),
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E8E3E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF34A853),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3C4043)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF34A853), width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFF2C2C2C),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF34A853);
            }
            return Colors.grey;
          }),
          trackColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF1E8E3E).withOpacity(0.5);
            }
            return Colors.grey.withOpacity(0.5);
          }),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF34A853);
            }
            return Colors.grey;
          }),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF34A853),
          thumbColor: const Color(0xFF1E8E3E),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      themeMode: ThemeMode.dark, // Force dark mode
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      getPages: [
        GetPage(name: '/decentralized-node-setup', page: () => const NodeSetupScreen()),
        GetPage(name: '/decentralized-seed-phrase', page: () => const DecentralizedSeedPhraseScreen()),
        GetPage(name: '/device-pairing-export', page: () => const ExportDevicePairingScreen()),
        GetPage(name: '/device-pairing-import', page: () => const ImportDevicePairingScreen()),
        GetPage(name: '/auth', page: () => isDesktop ? const DesktopAuthScreen() : const AuthScreen()),
        GetPage(name: '/home', page: () => isDesktop ? const DesktopHomeScreen() : const HomeScreen()),
        GetPage(name: '/backups', page: () => isDesktop ? const DesktopBackupsScreen() : const BackupsScreen()),
        GetPage(name: '/password-generator', page: () => isDesktop ? const DesktopPasswordGeneratorScreen() : const PasswordGeneratorScreen()),
        GetPage(name: '/settings', page: () => isDesktop ? const DesktopSettingsScreen() : const SettingsScreen()),
        GetPage(name: '/sia-settings', page: () => const SiaSettingsScreen()),
        GetPage(name: '/sia-password-required', page: () => const SiaPasswordRequiredScreen()),
        GetPage(name: '/breach-monitoring', page: () => isDesktop ? const DesktopBreachMonitoringScreen() : const BreachMonitoringScreen()),
        GetPage(name: '/vault', page: () => isDesktop ? const DesktopVaultScreen() : const VaultScreen()),
        GetPage(name: '/add-password', page: () => isDesktop ? const DesktopAddPasswordScreen() : const AddPasswordScreen()),
        GetPage(name: '/subscription', page: () => isDesktop ? const DesktopSubscriptionScreen() : const SubscriptionScreen()),
        GetPage(name: '/about', page: () => isDesktop ? const DesktopAboutScreen() : const AboutScreen()),
      ],
      ),
    );
  }
}
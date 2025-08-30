import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:securesphere/features/auth/screens/auth_screen.dart';
import 'package:securesphere/features/auth/screens/desktop_auth_screen.dart';
import 'package:securesphere/features/home/screens/home_screen.dart';
import 'package:securesphere/features/home/screens/desktop_home_screen.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:securesphere/features/backup/screens/backups_screen.dart';
import 'package:securesphere/features/backup/screens/desktop_backups_screen.dart';
import 'package:securesphere/features/backup/backup_service.dart';
import 'package:securesphere/features/password/screens/password_generator_screen.dart';
import 'package:securesphere/features/password/screens/desktop_password_generator_screen.dart';
import 'package:securesphere/features/password/screens/breach_monitoring_screen.dart';
import 'package:securesphere/features/password/screens/desktop_breach_monitoring_screen.dart';
import 'package:securesphere/features/password/screens/add_password_screen.dart';
import 'package:securesphere/features/password/screens/desktop_add_password_screen.dart';
import 'package:securesphere/features/settings/screens/settings_screen.dart';
import 'package:securesphere/features/settings/screens/desktop_settings_screen.dart';
import 'package:securesphere/features/sia/screens/sia_settings_screen.dart';
import 'package:securesphere/features/sia/screens/sia_password_required_screen.dart';
import 'package:securesphere/features/auth/services/auth_service.dart';
import 'package:securesphere/features/vault/models/file_model.dart';
import 'package:securesphere/features/vault/repositories/file_repository.dart';
import 'package:securesphere/features/vault/screens/vault_screen.dart';
import 'package:securesphere/features/vault/screens/desktop_vault_screen.dart';
import 'package:securesphere/features/vault/services/renterd_uploader.dart';
import 'package:securesphere/features/vault/services/encryption_service.dart';
import 'package:securesphere/features/settings/services/settings_service.dart';
import 'package:securesphere/features/sia/services/sia_service.dart';
import 'package:securesphere/features/auth/services/security_service.dart';
import 'package:securesphere/common/widgets/app_lifecycle_wrapper.dart';

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
    
    // Register the PasswordModel adapter
    Hive.registerAdapter(PasswordModelAdapter());
    
    // Register the FileModel adapter
    Hive.registerAdapter(FileModelAdapter());
    
    // Open the files box for FileRepository
    await Hive.openBox<FileModel>('files');
    
    // Initialize and register AuthService first
    final authService = AuthService();
    await authService.init();
    Get.put(authService);
    
    final isLoggedIn = await authService.checkLoginStatus();
    
    // Initialize PasswordRepository 
    final privateKey = isLoggedIn ? await authService.getPrivateKey() : null;
    final passwordRepo = PasswordRepository(privateKey ?? ''); 
    await passwordRepo.init();
    Get.put(passwordRepo);
    
    // Initialize SettingsService first (required by other services)
    final settingsService = SettingsService();
    Get.put(settingsService);
    
    // Initialize EncryptionService (required by BackupService)
    final encryptionService = EncryptionService(authService);
    Get.put(encryptionService);
    
    // Initialize SiaService
    final siaService = SiaService();
    await siaService.init();
    Get.put(siaService);
    
    // Initialize BackupService (depends on SettingsService and EncryptionService)
    final backupService = BackupService();
    try {
      await backupService.init();
      Get.put(backupService);
    } catch (e) {
      // Register it anyway to avoid GetX errors, but mark as failed
      Get.put(backupService);
    }
    
    // Initialize RenterdUploader
    final renterdUploader = RenterdUploader(settingsService, encryptionService);
    Get.put(renterdUploader);
    
    // Initialize FileRepository with RenterdUploader
    final fileRepo = FileRepository(renterdUploader);
    Get.put(fileRepo);
    
    // Initialize SecurityService (for PIN and biometric authentication)
    try {
      final securityService = SecurityService();
      await securityService.onInit();
      Get.put(securityService);
    } catch (e) {
      // Continue without SecurityService - app will work but without PIN/biometric features
    }
    
    runApp(const SecureSphereApp());
  } catch (e) {
    rethrow;
  }
}

class SecureSphereApp extends StatelessWidget {
  const SecureSphereApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLifecycleWrapper(
      child: GetMaterialApp(
      title: 'SecureSphere',
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
      initialRoute: '/auth',
      getPages: [
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
        // Security settings are now integrated into the main settings screen
      ],
      ),
    );
  }
}
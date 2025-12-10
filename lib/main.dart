import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:decvault/features/auth/screens/auth_screen.dart';
import 'package:decvault/features/auth/screens/desktop_auth_screen.dart';
import 'package:decvault/features/home/screens/home_screen.dart';
import 'package:decvault/features/home/screens/desktop_home_screen.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/features/backup/screens/backups_screen.dart';
import 'package:decvault/features/backup/screens/desktop_backups_screen.dart';
import 'package:decvault/features/backup/backup_service.dart';
import 'package:decvault/features/password/screens/password_generator_screen.dart';
import 'package:decvault/features/password/screens/desktop_password_generator_screen.dart';
import 'package:decvault/features/password/screens/breach_monitoring_screen_gated.dart';
import 'package:decvault/features/password/screens/desktop_breach_monitoring_screen_gated.dart';
import 'package:decvault/features/password/screens/add_password_screen.dart';
import 'package:decvault/features/password/screens/desktop_add_password_screen.dart';
import 'package:decvault/features/settings/screens/settings_screen.dart';
import 'package:decvault/features/settings/screens/desktop_settings_screen.dart';
import 'package:decvault/features/sia/screens/sia_settings_screen.dart';
import 'package:decvault/features/sia/screens/sia_password_required_screen.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/auth/services/qr_login_service.dart';
import 'package:decvault/features/vault/models/file_model.dart';
import 'package:decvault/features/vault/repositories/file_repository.dart';
import 'package:decvault/features/vault/screens/vault_screen.dart';
import 'package:decvault/features/vault/screens/desktop_vault_screen.dart';
import 'package:decvault/features/vault/services/renterd_uploader.dart';
import 'package:decvault/features/vault/services/encryption_service.dart';
import 'package:decvault/features/settings/services/settings_service.dart';
import 'package:decvault/features/sia/services/sia_service.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:decvault/features/subscription/services/storage_service.dart';
import 'package:decvault/features/subscription/screens/subscription_screen.dart';
import 'package:decvault/features/subscription/screens/desktop_subscription_screen.dart';
import 'package:decvault/common/widgets/app_lifecycle_wrapper.dart';
import 'package:decvault/services/notification_service.dart';
import 'package:decvault/features/auth/screens/pin_unlock_screen.dart';
import 'package:decvault/features/about/screens/about_screen.dart';
import 'package:decvault/features/about/screens/desktop_about_screen.dart';

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
  
  // Initialize window manager for desktop
  if (isDesktop) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Color(0xFF121212),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // Hide default title bar
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  try {
    // Initialize Hive
    await Hive.initFlutter();
    
    // Register the PasswordModel adapter
    Hive.registerAdapter(PasswordModelAdapter());
    
    // Register the FileModel adapter
    Hive.registerAdapter(FileModelAdapter());
    
    // Open the files box for FileRepository
    await Hive.openBox<FileModel>('files');
    
    // Initialize NotificationService for download notifications
    await NotificationService().initialize();
    
    // Initialize and register AuthService first
    final authService = AuthService();
    await authService.init();
    Get.put(authService);
    
    // Initialize QrLoginService (depends on AuthService)
    try {
      final qrLoginService = QrLoginService();
      Get.put(qrLoginService);
    } catch (e) {
      // Continue without QrLoginService - QR pairing feature will not work
    }
    
    // Check if user is logged in
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
    
    // Initialize RevenueCat (for subscriptions)
    try {
      final revenueCatService = RevenueCatService();
      await revenueCatService.onInit();
      Get.put(revenueCatService);
      
      // Login user to RevenueCat and check backend Pro status
      if (isLoggedIn) {
        final userId = await authService.getUserId();
        if (userId != null) {
          try {
            await revenueCatService.loginUser(userId);
          } catch (e) {
          }
        }
      }
    } catch (e) {
      // Continue without RevenueCat - app will work but without subscription features
    }
    
    // Initialize StorageService (for tracking file vault usage)
    try {
      final storageService = StorageService();
      await storageService.onInit();
      Get.put(storageService);
      
      // Set user ID and sync if user is logged in
      if (isLoggedIn) {
        final userId = await authService.getUserId();
        if (userId != null) {
          storageService.setUserId(userId);
          try {
            await storageService.syncWithBackend();
          } catch (e) {
          }
        }
      }
    } catch (e) {
      // Continue without StorageService - app will work but without storage tracking
    }
    
    runApp(const DecVaultApp());
  } catch (e) {
    rethrow;
  }
}

class DecVaultApp extends StatefulWidget {
  const DecVaultApp({super.key});

  @override
  State<DecVaultApp> createState() => _DecVaultAppState();
}

class _DecVaultAppState extends State<DecVaultApp> with WindowListener {
  String? _initialRoute;
  bool _isInitialized = false;
  DateTime? _lastFocusLostTime;
  DateTime? _lastFocusGainedTime;
  static const Duration _focusDebounce = Duration(milliseconds: 500);
  
  SecurityService? get _securityService {
    try {
      return Get.find<SecurityService>();
    } catch (e) {
      return null;
    }
  }
  
  @override
  void initState() {
    super.initState();
    _determineInitialRoute();
    
    // Add window listener for desktop
    if (isDesktop) {
      windowManager.addListener(this);
    }
  }
  
  @override
  void dispose() {
    if (isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }
  
  // WindowListener callbacks for desktop
  @override
  void onWindowFocus() {
    // Window gained focus - check if we need to unlock
    _onWindowFocusGained();
  }
  
  @override
  void onWindowBlur() {
    // Window lost focus - lock the app if PIN is enabled
    _onWindowFocusLost();
  }
  
  @override
  void onWindowMinimize() {
    // Window minimized - lock the app
    _onWindowFocusLost();
  }
  
  @override
  void onWindowRestore() {
    // Window restored from minimize - show unlock if needed
    _onWindowFocusGained();
  }
  
  @override
  void onWindowClose() async {
    // Window is closing
  }
  
  @override
  void onWindowMaximize() {
    // Window maximized - no action needed
  }
  
  @override
  void onWindowUnmaximize() {
    // Window unmaximized - no action needed
  }
  
  @override
  void onWindowResize() {
    // Window resized - no action needed
  }
  
  @override
  void onWindowMove() {
    // Window moved - no action needed
  }
  
  @override
  void onWindowEnterFullScreen() {
    // Entered fullscreen - no action needed
  }
  
  @override
  void onWindowLeaveFullScreen() {
    // Left fullscreen - no action needed
  }
  
  Future<void> _onWindowFocusLost() async {
    _lastFocusLostTime = DateTime.now();
    
    final service = _securityService;
    if (service == null) return;
    
    // Lock the app if security is enabled and lockOnAppClose is true
    if (service.hasSecurityEnabled && service.securitySettings.lockOnAppClose) {
      await service.lockApp();
    }
  }
  
  Future<void> _onWindowFocusGained() async {
    _lastFocusGainedTime = DateTime.now();
    
    final service = _securityService;
    if (service == null) return;
    
    // Check if this was a very quick focus change (debounce)
    if (_lastFocusLostTime != null) {
      final timeSinceBlur = DateTime.now().difference(_lastFocusLostTime!);
      if (timeSinceBlur < _focusDebounce) {
        // Too quick, likely just a system dialog or quick alt-tab
        return;
      }
    }
    
    // Small delay to ensure window is fully visible
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Check if we need to show PIN unlock
    if (service.hasSecurityEnabled && service.isAppLocked) {
      // Make sure we're not on the auth screen
      if (Get.currentRoute != '/auth' && !Get.isDialogOpen!) {
        Get.dialog(
          const PinUnlockScreen(),
          barrierDismissible: false,
          barrierColor: Colors.black87,
        );
      }
    }
  }
  
  Future<void> _determineInitialRoute() async {
    try {
      final authService = Get.find<AuthService>();
      final isLoggedIn = await authService.checkLoginStatus();
      
      if (isLoggedIn) {
        // User is logged in, go to home
        // The AppLifecycleWrapper will show the PIN unlock screen if needed
        setState(() {
          _initialRoute = '/home';
          _isInitialized = true;
        });
      } else {
        // Not logged in, show auth screen
        setState(() {
          _initialRoute = '/auth';
          _isInitialized = true;
        });
      }
    } catch (e) {
      // Error checking login status, default to auth screen
      setState(() {
        _initialRoute = '/auth';
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen until initial route is determined
    if (!_isInitialized || _initialRoute == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo or app name
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E8E3E).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: Color(0xFF34A853),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'DecVault',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 48),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
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
      initialRoute: _initialRoute,
      getPages: [
        GetPage(name: '/auth', page: () => isDesktop ? const DesktopAuthScreen() : const AuthScreen()),
        GetPage(name: '/home', page: () => isDesktop ? const DesktopHomeScreen() : const HomeScreen()),
        GetPage(name: '/backups', page: () => isDesktop ? const DesktopBackupsScreen() : const BackupsScreen()),
        GetPage(name: '/password-generator', page: () => isDesktop ? const DesktopPasswordGeneratorScreen() : const PasswordGeneratorScreen()),
        GetPage(name: '/settings', page: () => isDesktop ? const DesktopSettingsScreen() : const SettingsScreen()),
        GetPage(name: '/sia-settings', page: () => const SiaSettingsScreen()),
        GetPage(name: '/sia-password-required', page: () => const SiaPasswordRequiredScreen()),
        GetPage(name: '/breach-monitoring', page: () => isDesktop ? const DesktopBreachMonitoringScreenGated() : const BreachMonitoringScreenGated()),
        GetPage(name: '/vault', page: () => isDesktop ? const DesktopVaultScreen() : const VaultScreen()),
        GetPage(name: '/add-password', page: () => isDesktop ? const DesktopAddPasswordScreen() : const AddPasswordScreen()),
        GetPage(name: '/subscription', page: () => isDesktop ? const DesktopSubscriptionScreen() : const SubscriptionScreen()),
        GetPage(name: '/about', page: () => isDesktop ? const DesktopAboutScreen() : const AboutScreen()),
        // Security settings are now integrated into the main settings screen
      ],
      ),
    );
  }
}

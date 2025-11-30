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
  
  if (isDesktop) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Color(0xFF121212),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  try {
    await Hive.initFlutter();
    Hive.registerAdapter(PasswordModelAdapter());
    Hive.registerAdapter(FileModelAdapter());
    await Hive.openBox<FileModel>('files');
    await NotificationService().initialize();
    
    final authService = AuthService();
    await authService.init();
    Get.put(authService);
    
    try {
      final qrLoginService = QrLoginService();
      Get.put(qrLoginService);
    } catch (e) {
      // QR login unavailable
    }
    
    final isLoggedIn = await authService.checkLoginStatus();
    final privateKey = isLoggedIn ? await authService.getPrivateKey() : null;
    final passwordRepo = PasswordRepository(privateKey ?? ''); 
    await passwordRepo.init();
    Get.put(passwordRepo);
    
    final settingsService = SettingsService();
    Get.put(settingsService);
    
    final encryptionService = EncryptionService(authService);
    Get.put(encryptionService);
    
    final siaService = SiaService();
    await siaService.init();
    Get.put(siaService);
    
    final backupService = BackupService();
    try {
      await backupService.init();
      Get.put(backupService);
    } catch (e) {
      Get.put(backupService);
    }
    
    final renterdUploader = RenterdUploader(settingsService, encryptionService);
    Get.put(renterdUploader);
    
    final fileRepo = FileRepository(renterdUploader);
    Get.put(fileRepo);
    
    try {
      final securityService = SecurityService();
      await securityService.onInit();
      Get.put(securityService);
    } catch (e) {
      // Security features unavailable
    }
    
    try {
      final revenueCatService = RevenueCatService();
      await revenueCatService.onInit();
      Get.put(revenueCatService);
      
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
      // Subscription features unavailable
    }
    
    try {
      final storageService = StorageService();
      await storageService.onInit();
      Get.put(storageService);
      
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
      // Storage tracking unavailable
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
  
  @override
  void onWindowFocus() {
    _onWindowFocusGained();
  }
  
  @override
  void onWindowBlur() {
    _onWindowFocusLost();
  }
  
  @override
  void onWindowMinimize() {
    _onWindowFocusLost();
  }
  
  @override
  void onWindowRestore() {
    _onWindowFocusGained();
  }
  
  @override
  void onWindowClose() async {
  }
  
  @override
  void onWindowMaximize() {
  }
  
  @override
  void onWindowUnmaximize() {
  }
  
  @override
  void onWindowResize() {
  }
  
  @override
  void onWindowMove() {
  }
  
  @override
  void onWindowEnterFullScreen() {
  }
  
  @override
  void onWindowLeaveFullScreen() {
  }
  
  Future<void> _onWindowFocusLost() async {
    _lastFocusLostTime = DateTime.now();
    
    final service = _securityService;
    if (service == null) return;
    
    if (service.hasSecurityEnabled && service.securitySettings.lockOnAppClose) {
      await service.lockApp();
    }
  }
  
  Future<void> _onWindowFocusGained() async {
    _lastFocusGainedTime = DateTime.now();
    
    final service = _securityService;
    if (service == null) return;
    
    if (_lastFocusLostTime != null) {
      final timeSinceBlur = DateTime.now().difference(_lastFocusLostTime!);
      if (timeSinceBlur < _focusDebounce) {
        return;
      }
    }
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (service.hasSecurityEnabled && service.isAppLocked) {
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
      
      setState(() {
        _initialRoute = isLoggedIn ? '/home' : '/auth';
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _initialRoute = '/auth';
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _initialRoute == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
      ],
      ),
    );
  }
}

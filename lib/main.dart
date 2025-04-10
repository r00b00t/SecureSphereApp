import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:securesphere/features/auth/screens/auth_screen.dart';
import 'package:securesphere/features/home/screens/home_screen.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:securesphere/features/backup/screens/backups_screen.dart';
import 'package:securesphere/features/backup/backup_service.dart';
import 'package:securesphere/features/password/screens/password_generator_screen.dart';
import 'package:securesphere/features/settings/screens/settings_screen.dart';
import 'package:securesphere/features/auth/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Initialize Hive
    await Hive.initFlutter();
    
    // Register the PasswordModel adapter
    Hive.registerAdapter(PasswordModelAdapter());
    
    // Initialize and register AuthService first
    final authService = AuthService();
    await authService.init();
    Get.put(authService);
    
    // Check if user is logged in
    final isLoggedIn = await authService.checkLoginStatus();
    
    // Initialize PasswordRepository with null private key if user is not logged in
    final privateKey = isLoggedIn ? await authService.getPrivateKey() : null;
    final passwordRepo = PasswordRepository(privateKey ?? ''); // Provide empty string as fallback
    await passwordRepo.init();
    Get.put(passwordRepo);
    
    if (!isLoggedIn) {
      print('No user logged in, initialized PasswordRepository with null private key');
    }
    
    final backupService = BackupService();
    await backupService.init();
    Get.put(backupService);
    
    runApp(const SecureSphereApp());
  } catch (e) {
    print('Failed to initialize app: $e');
    rethrow;
  }
}

class SecureSphereApp extends StatelessWidget {
  const SecureSphereApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
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
        cardTheme: const CardTheme(
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
        cardTheme: const CardTheme(
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
        GetPage(name: '/auth', page: () => const AuthScreen()),
        GetPage(name: '/home', page: () => const HomeScreen()),
        GetPage(name: '/backups', page: () => const BackupsScreen()),
        GetPage(name: '/password-generator', page: () => const PasswordGeneratorScreen()),
        GetPage(name: '/settings', page: () => const SettingsScreen()),
        // Security settings are now integrated into the main settings screen
      ],
    );
  }
}
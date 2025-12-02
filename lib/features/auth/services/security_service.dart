import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/security_settings.dart';
import 'auth_service.dart';

class SecurityService extends GetxService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  static const _pinKey = 'user_pin';
  static const _initialSetupKey = 'initial_setup_complete';
  
  // Storage wrapper methods with fallback to SharedPreferences for macOS development
  Future<void> _secureWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('secure_$key', value);
    }
  }

  Future<String?> _secureRead(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) {
        return value;
      }
    } catch (e) {
    }
    
    // Fallback to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('secure_$key');
  }

  Future<void> _secureDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
    }
    
    // Also delete from SharedPreferences fallback
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('secure_$key');
  }
  
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  // Reactive security settings
  final Rx<SecuritySettings> _securitySettings = SecuritySettings().obs;
  SecuritySettings get securitySettings => _securitySettings.value;
  
  // App lock state
  final RxBool _isAppLocked = false.obs;
  bool get isAppLocked => _isAppLocked.value;
  
  // Initial setup state - prevents locking during first signup
  final RxBool _isInitialSetupComplete = false.obs;
  bool get isInitialSetupComplete => _isInitialSetupComplete.value;
  
  // Biometric availability
  final RxBool _biometricsAvailable = false.obs;
  bool get biometricsAvailable => _biometricsAvailable.value;
  
  // Grace period after successful unlock to prevent immediate re-locking
  DateTime? _lastUnlockTime;
  static const Duration _unlockGracePeriod = Duration(seconds: 30); // Increased from 10
  
  // Track when app was last paused to detect short pauses (system dialogs, etc)
  DateTime? _lastPauseTime;
  static const Duration _shortPauseTolerance = Duration(seconds: 30); // Increased from 5

  @override
  Future<void> onInit() async {
    super.onInit();
    await _initialize();
  }

  Future<void> _initialize() async {
    
    // Check initial setup status
    final setupComplete = await _secureRead(_initialSetupKey);
    _isInitialSetupComplete.value = setupComplete == 'true';
    
    // Load security settings
    final settings = await SecuritySettings.load();
    _securitySettings.value = settings;
    
    // Check biometric availability
    await _checkBiometricAvailability();
    
    // Only check should lock if initial setup is complete
    if (_isInitialSetupComplete.value) {
      await _checkShouldLock();
    } else {
      _isAppLocked.value = false;
    }
    
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      if (kIsWeb) {
        _biometricsAvailable.value = false;
        return;
      }
      
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      _biometricsAvailable.value = canCheck && isDeviceSupported;
      
    } catch (e) {
      _biometricsAvailable.value = false;
    }
  }

  Future<void> _checkShouldLock() async {
    final settings = _securitySettings.value;
    
    // Don't lock during initial setup
    if (!_isInitialSetupComplete.value) {
      _isAppLocked.value = false;
      return;
    }
    
    // If no security is enabled (neither PIN nor biometric), don't lock
    if (!settings.hasPinEnabled && !settings.biometricEnabled) {
      _isAppLocked.value = false;
      return;
    }
    
    // CRITICAL: Always require authentication on fresh app startup when security is enabled
    // This ensures security even when app is completely killed and restarted
    _isAppLocked.value = true;
    
    // Additional checks for auto-lock due to inactivity
    if (settings.shouldAutoLock()) {
    }
    
    // Log the reason for locking
    if (settings.lockOnAppClose) {
    }
  }

  // PIN Methods
  Future<bool> hasPinSet() async {
    final pin = await _secureRead(_pinKey);
    return pin != null && pin.isNotEmpty;
  }

  Future<bool> setPinCode(String pin) async {
    try {
      if (pin.length != 6) {
        throw Exception('PIN must be exactly 6 digits');
      }
      
      // Validate that PIN contains only numbers
      if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
        throw Exception('PIN must contain only numbers');
      }
      
      await _secureWrite(_pinKey, pin);
      
      // Update security settings
      final settings = _securitySettings.value.copyWith(hasPinEnabled: true);
      _securitySettings.value = settings;
      await settings.save();
      
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyPinCode(String pin) async {
    try {
      final storedPin = await _secureRead(_pinKey);
      return storedPin == pin;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removePinCode(String currentPin) async {
    try {
      // Verify current PIN first
      if (!await verifyPinCode(currentPin)) {
        throw Exception('Current PIN is incorrect');
      }
      
      await _secureDelete(_pinKey);
      
      // Update security settings
      final settings = _securitySettings.value.copyWith(hasPinEnabled: false);
      _securitySettings.value = settings;
      await settings.save();
      
      // Unlock app since PIN is removed
      _isAppLocked.value = false;
      
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> changePinCode(String currentPin, String newPin) async {
    try {
      // Verify current PIN first
      if (!await verifyPinCode(currentPin)) {
        throw Exception('Current PIN is incorrect');
      }
      
      if (newPin.length != 6) {
        throw Exception('New PIN must be exactly 6 digits');
      }
      
      return await setPinCode(newPin);
    } catch (e) {
      return false;
    }
  }

  Future<bool> resetPinWithSeedPhrase(String seedPhrase) async {
    try {
      // Import AuthService to verify seed phrase
      final authService = Get.find<AuthService>();
      
      // Verify the seed phrase
      final isValidSeedPhrase = await authService.verifySeedPhrase(seedPhrase);
      if (!isValidSeedPhrase) {
        throw Exception('Invalid seed phrase');
      }
      
      
      // Clear the existing PIN using the secure delete wrapper
      // This has fallback logic for macOS/iOS keychain issues
      try {
        await _secureDelete(_pinKey);
      } catch (deleteError) {
        // Continue anyway - PIN might not have been set
      }
      
      // Update security settings to disable PIN
      final settings = _securitySettings.value.copyWith(hasPinEnabled: false);
      _securitySettings.value = settings;
      await settings.save();
      
      // Unlock app since PIN is being reset
      _isAppLocked.value = false;
      
      return true;
    } catch (e) {
      // If it's a PlatformException related to keychain (-34018), provide more context
      if (e.toString().contains('-34018') || e.toString().contains('security result code')) {
        
        // Try to at least update the settings even if secure storage fails
        try {
          final settings = _securitySettings.value.copyWith(hasPinEnabled: false);
          _securitySettings.value = settings;
          await settings.save();
          _isAppLocked.value = false;
          return true;
        } catch (settingsError) {
          return false;
        }
      }
      return false;
    }
  }

  // Biometric Methods
  Future<bool> enableBiometrics() async {
    try {
      if (!_biometricsAvailable.value) {
        throw Exception('Biometrics not available on this device');
      }
      
      // Test biometric authentication
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to enable biometric login',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      
      if (authenticated) {
        final settings = _securitySettings.value.copyWith(biometricEnabled: true);
        _securitySettings.value = settings;
        await settings.save();
        
        return true;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> disableBiometrics() async {
    try {
      final settings = _securitySettings.value.copyWith(biometricEnabled: false);
      _securitySettings.value = settings;
      await settings.save();
      
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      if (!_securitySettings.value.biometricEnabled || !_biometricsAvailable.value) {
        return false;
      }
      
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock the app',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      
      if (authenticated) {
        await _updateLastActiveTime();
      }
      
      return authenticated;
    } catch (e) {
      return false;
    }
  }

  // Auto-lock Methods
  Future<void> setAutoLockTime(int seconds) async {
    try {
      final settings = _securitySettings.value.copyWith(autoLockTimeSeconds: seconds);
      _securitySettings.value = settings;
      await settings.save();
      
    } catch (e) {
    }
  }

  Future<void> setLockOnAppClose(bool enabled) async {
    try {
      final settings = _securitySettings.value.copyWith(lockOnAppClose: enabled);
      _securitySettings.value = settings;
      await settings.save();
      
    } catch (e) {
    }
  }

  // App lock state management
  Future<void> lockApp() async {
    _isAppLocked.value = true;
    await _updateLastActiveTime();
  }

  Future<void> unlockApp() async {
    _isAppLocked.value = false;
    _lastUnlockTime = DateTime.now(); // Track when app was unlocked
    await _updateLastActiveTime();
  }

  Future<bool> unlockWithPin(String pin) async {
    if (await verifyPinCode(pin)) {
      await unlockApp();
      return true;
    }
    return false;
  }

  Future<bool> unlockWithBiometrics() async {
    if (await authenticateWithBiometrics()) {
      await unlockApp();
      return true;
    }
    return false;
  }

  // Activity tracking
  Future<void> _updateLastActiveTime() async {
    final settings = _securitySettings.value.copyWith(lastActiveTime: DateTime.now());
    _securitySettings.value = settings;
    await settings.save();
  }

  Future<void> updateActivity() async {
    await _updateLastActiveTime();
    
    // If app is unlocked and should auto-lock, lock it
    if (!_isAppLocked.value && _securitySettings.value.shouldAutoLock()) {
      await lockApp();
    }
  }

  /// Mark user as actively using the app to prevent auto-lock during operations
  Future<void> markUserActive() async {
    await _updateLastActiveTime();
    _lastUnlockTime = DateTime.now(); // Reset unlock time to extend grace period
  }
  
  // Clear lock state (used during logout)
  void clearLockState() {
    _isAppLocked.value = false;
    _lastUnlockTime = null;
    _lastPauseTime = null;
  }

  // App lifecycle methods
  Future<void> onAppResumed() async {
    
    // Don't lock during initial setup
    if (!_isInitialSetupComplete.value) {
      return;
    }
    
    // Check if app was recently unlocked (grace period)
    if (_lastUnlockTime != null) {
      final timeSinceUnlock = DateTime.now().difference(_lastUnlockTime!);
      if (timeSinceUnlock < _unlockGracePeriod) {
        // Update last active time to prevent unwanted auto-lock
        await _updateLastActiveTime();
        return;
      }
    }
    
    // Check if this was a short pause (likely system dialog or quick app switch)
    if (_lastPauseTime != null) {
      final pauseDuration = DateTime.now().difference(_lastPauseTime!);
      if (pauseDuration < _shortPauseTolerance) {
        // Update last active time since user is still using the app
        await _updateLastActiveTime();
        return;
      }
    }
    
    final settings = _securitySettings.value;
    
    // Only lock if security is enabled and enough time has passed
    if (settings.hasPinEnabled || settings.biometricEnabled) {
      // Check if should auto-lock due to inactivity (respects auto-lock timeout setting)
      if (settings.shouldAutoLock()) {
        _isAppLocked.value = true;
      } else {
        // Update last active time since user is returning to app
        await _updateLastActiveTime();
      }
    }
  }

  Future<void> onAppPaused() async {
    _lastPauseTime = DateTime.now();
    await _updateLastActiveTime();
  }

  // Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      if (!_biometricsAvailable.value) return [];
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  // Mark initial setup as complete (call this after successful registration)
  Future<void> markInitialSetupComplete() async {
    await _secureWrite(_initialSetupKey, 'true');
    _isInitialSetupComplete.value = true;
    
    // Now apply security settings if any security is enabled
    if (hasSecurityEnabled) {
      await _checkShouldLock();
    }
  }

  // Helper method to check if any security is enabled
  bool get hasSecurityEnabled => 
    _isInitialSetupComplete.value && 
    (_securitySettings.value.hasPinEnabled || _securitySettings.value.biometricEnabled);
  
  // Helper method to get human-readable auto-lock time
  String get autoLockTimeString {
    final seconds = _securitySettings.value.autoLockTimeSeconds;
    if (seconds == 0) return 'Disabled';
    if (seconds < 60) return '$seconds seconds';
    final minutes = seconds ~/ 60;
    if (minutes == 1) return '1 minute';
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    if (hours == 1) return '1 hour';
    return '$hours hours';
  }
}

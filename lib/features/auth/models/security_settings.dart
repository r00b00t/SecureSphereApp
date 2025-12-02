import 'package:shared_preferences/shared_preferences.dart';

class SecuritySettings {
  final bool hasPinEnabled;
  final bool biometricEnabled;
  final int autoLockTimeSeconds; // 0 means disabled, default 60 seconds (1 minute)
  final bool lockOnAppClose;
  final DateTime? lastActiveTime;

  SecuritySettings({
    this.hasPinEnabled = false,
    this.biometricEnabled = false,
    this.autoLockTimeSeconds = 60, // Default 60 seconds (1 minute)
    this.lockOnAppClose = true,
    this.lastActiveTime,
  });

  // Copy with method for easy updates
  SecuritySettings copyWith({
    bool? hasPinEnabled,
    bool? biometricEnabled,
    int? autoLockTimeSeconds,
    bool? lockOnAppClose,
    DateTime? lastActiveTime,
  }) {
    return SecuritySettings(
      hasPinEnabled: hasPinEnabled ?? this.hasPinEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockTimeSeconds: autoLockTimeSeconds ?? this.autoLockTimeSeconds,
      lockOnAppClose: lockOnAppClose ?? this.lockOnAppClose,
      lastActiveTime: lastActiveTime ?? this.lastActiveTime,
    );
  }

  // Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'hasPinEnabled': hasPinEnabled,
      'biometricEnabled': biometricEnabled,
      'autoLockTimeSeconds': autoLockTimeSeconds,
      'lockOnAppClose': lockOnAppClose,
      'lastActiveTime': lastActiveTime?.millisecondsSinceEpoch,
    };
  }

  // Create from map
  factory SecuritySettings.fromMap(Map<String, dynamic> map) {
    // Migration: convert old autoLockTimeMinutes to seconds if present
    int autoLockSeconds = 60; // Default value
    
    if (map['autoLockTimeSeconds'] != null) {
      autoLockSeconds = map['autoLockTimeSeconds'] as int;
    } else if (map['autoLockTimeMinutes'] != null) {
      autoLockSeconds = (map['autoLockTimeMinutes'] as int) * 60;
    }
    
    return SecuritySettings(
      hasPinEnabled: map['hasPinEnabled'] ?? false,
      biometricEnabled: map['biometricEnabled'] ?? false,
      autoLockTimeSeconds: autoLockSeconds,
      lockOnAppClose: map['lockOnAppClose'] ?? true,
      lastActiveTime: map['lastActiveTime'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['lastActiveTime'])
          : null,
    );
  }

  // Load from SharedPreferences
  static Future<SecuritySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString('security_settings');
    
    if (settingsJson != null) {
      try {
        final map = Map<String, dynamic>.from(
          prefs.getString('security_settings') != null 
            ? {} // Would need JSON parsing here, but keeping simple with individual keys
            : {}
        );
        return SecuritySettings.fromMap(map);
      } catch (e) {
      }
    }
    
    // Load individual settings for backward compatibility
    // Migration: convert old minutes setting to seconds if present
    int autoLockSeconds = 60; // Default value
    
    final storedSeconds = prefs.getInt('auto_lock_seconds');
    final storedMinutes = prefs.getInt('auto_lock_minutes');
    
    if (storedSeconds != null) {
      autoLockSeconds = storedSeconds;
    } else if (storedMinutes != null) {
      autoLockSeconds = storedMinutes * 60;
    }
    
    return SecuritySettings(
      hasPinEnabled: prefs.getString('pin') != null && prefs.getString('pin')!.isNotEmpty,
      biometricEnabled: prefs.getBool('use_biometrics') ?? false,
      autoLockTimeSeconds: autoLockSeconds,
      lockOnAppClose: prefs.getBool('lock_on_app_close') ?? true,
      lastActiveTime: prefs.getInt('last_active_time') != null 
          ? DateTime.fromMillisecondsSinceEpoch(prefs.getInt('last_active_time')!)
          : null,
    );
  }

  // Save to SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Save individual settings for compatibility with existing code
    await prefs.setBool('use_biometrics', biometricEnabled);
    await prefs.setInt('auto_lock_seconds', autoLockTimeSeconds);
    await prefs.setBool('lock_on_app_close', lockOnAppClose);
    
    if (lastActiveTime != null) {
      await prefs.setInt('last_active_time', lastActiveTime!.millisecondsSinceEpoch);
    }
  }

  bool get isAutoLockEnabled => autoLockTimeSeconds > 0;
  
  bool shouldAutoLock() {
    if (!isAutoLockEnabled || lastActiveTime == null) return false;
    
    final now = DateTime.now();
    final timeDifference = now.difference(lastActiveTime!);
    return timeDifference.inSeconds >= autoLockTimeSeconds;
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/sia/services/sia_service.dart';

/// SIA Configuration model
class SiaConfig {
  final String ip;
  final String port;
  final String password;

  SiaConfig({
    required this.ip,
    required this.port,
    required this.password,
  });

  String get renterdUrl => 'http://$ip:$port';

  String get apiPassword => password;

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'password': password,
  };

  /// Create from JSON
  factory SiaConfig.fromJson(Map<String, dynamic> json) => SiaConfig(
    ip: json['ip'] as String,
    port: json['port'] as String,
    password: json['password'] as String,
  );
}

class SettingsService {
  static const String _siaConfigKey = 'sia_config';
  static const String _siaVerifiedKey = 'sia_verified';
  static const String _backupOptionKey = 'backupOption';
  static const String _useBiometricsKey = 'use_biometrics';
  static const String _pinKey = 'pin';

  /// Get SIA configuration
  Future<SiaConfig?> getSiaConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // First try the old legacy format
      final configJson = prefs.getString(_siaConfigKey);
      if (configJson != null) {
        final config = jsonDecode(configJson) as Map<String, dynamic>;
        return SiaConfig.fromJson(config);
      }
      
      // Then try the new local config format
      final localConfigJson = prefs.getString('local_sia_config');
      if (localConfigJson != null) {
        final localConfig = jsonDecode(localConfigJson) as Map<String, dynamic>;
        
        try {
          final siaService = Get.find<SiaService>();
          final password = await siaService.getStoredPassword();
          
          if (password != null && password.isNotEmpty) {
            return SiaConfig(
              ip: localConfig['host'] as String,
              port: localConfig['port'].toString(),
              password: password,
            );
          } else {
          }
        } catch (e) {
        }
      }
      
      // If no local configs found, check SiaService for current configuration
      try {
        final siaService = Get.find<SiaService>();
        final currentConfig = siaService.currentConfig;
        
        if (currentConfig != null) {
          return SiaConfig(
            ip: currentConfig.host,
            port: currentConfig.port.toString(),
            password: currentConfig.password,
          );
        } else {
        }
      } catch (e) {
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Save SIA configuration
  Future<void> saveSiaConfig(SiaConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = jsonEncode(config.toJson());
      await prefs.setString(_siaConfigKey, configJson);
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> isSiaVerified() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_siaVerifiedKey) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Set SIA verification status
  Future<void> setSiaVerified(bool verified) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_siaVerifiedKey, verified);
    } catch (e) {
    }
  }

  /// Get backup option
  Future<String> getBackupOption() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_backupOptionKey) ?? 'SecureSphere Decentralized Server';
    } catch (e) {
      return 'SecureSphere Decentralized Server';
    }
  }

  /// Save backup option
  Future<void> saveBackupOption(String option) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_backupOptionKey, option);
    } catch (e) {
    }
  }

  /// Get biometrics setting
  Future<bool> getUseBiometrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_useBiometricsKey) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Save biometrics setting
  Future<void> saveUseBiometrics(bool useBiometrics) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_useBiometricsKey, useBiometrics);
    } catch (e) {
    }
  }

  /// Get PIN
  Future<String?> getPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_pinKey);
    } catch (e) {
      return null;
    }
  }

  /// Save PIN
  Future<void> savePin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinKey, pin);
    } catch (e) {
    }
  }

  /// Clear SIA configuration
  Future<void> clearSiaConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_siaConfigKey);
      await prefs.remove(_siaVerifiedKey);
    } catch (e) {
    }
  }
} 
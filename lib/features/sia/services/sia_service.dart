import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:decvault/config/api_config.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/sia/models/sia_node_config.dart';
import 'package:decvault/features/sia/screens/sia_password_required_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class SiaService extends GetxService {
  static const String _siaPasswordKey = 'sia_password';
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
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
  
  SiaNodeConfig? _currentConfig;
  SiaNodeConfig? get currentConfig => _currentConfig;

  // Secure storage with fallback to SharedPreferences on macOS
  Future<void> _secureWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fallback_$key', value);
    }
  }

  Future<String?> _secureRead(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) return value;
    } catch (e) {
    }
    
    // Try fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('fallback_$key');
    } catch (e) {
      return null;
    }
  }

  Future<void> _secureDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fallback_$key');
    } catch (e) {
    }
  }

  Future<SiaService> init() async {
    await loadSiaConfiguration();
    return this;
  }

  /// Load SIA configuration based on user's backup option
  Future<void> loadSiaConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get user's current preference (respects their choice)
    final backupOption = prefs.getString('backupOption') ?? 'DecVault';
    
    // Check if user has existing config in backend (for information only)
    final hasBackendConfig = await _checkIfUserHasBackendConfig();
    
    if (backupOption == 'DecVault') {
      _currentConfig = SiaNodeConfig(
        host: ApiConfig.psqlBaseUrl,
        port: '',
        password: '',
        isDecVaultManagedNode: true,
      );
    } else if (backupOption == 'Self-Hosted SIA Node') {
      // Load self-hosted config from backend
      await _loadCustomConfigFromBackend();
    } else {
      // Handle legacy or unknown preferences
      if (hasBackendConfig) {
        // Migrate to self-hosted only if no explicit preference
        await prefs.setString('backupOption', 'Self-Hosted SIA Node');
        await _loadCustomConfigFromBackend();
      } else {
        await prefs.setString('backupOption', 'DecVault');
        _currentConfig = SiaNodeConfig(
          host: ApiConfig.psqlBaseUrl,
          port: '',
          password: '',
          isDecVaultManagedNode: true,
        );
      }
    }
  }

  /// Check if user has existing SIA config in backend
  Future<bool> _checkIfUserHasBackendConfig() async {
    try {
      final authService = Get.find<AuthService>();
      final userId = await authService.getUserId();
      
      if (userId == null) {
        return false;
      }

      final url = Uri.parse(ApiConfig.getSiaNodeEndpoint(userId));
      final headers = {
        'Content-Type': 'application/json',
        'api-key': ApiConfig.psqlApiKey,
        'user-id': userId,
      };

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return true;
      } else if (response.statusCode == 404) {
        return false;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Load custom config from backend
  Future<void> _loadCustomConfigFromBackend() async {
    try {
      final authService = Get.find<AuthService>();
      final userId = await authService.getUserId();
      
      if (userId == null) {
        _currentConfig = null;
        return;
      }

      final url = Uri.parse(ApiConfig.getSiaNodeEndpoint(userId));
      final headers = {
        'Content-Type': 'application/json',
        'api-key': ApiConfig.psqlApiKey,
        'user-id': userId,
      };


      final response = await http.get(url, headers: headers);


      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Backend returns: {"success": true, "node": {"host": "...", "port": "..."}}
        final nodeData = data['node'] as Map<String, dynamic>;
        
        // Get stored password locally (decrypted)
        final storedPassword = await getStoredPassword();
        
        // Handle both String and int types for port from backend
        final hostStr = nodeData['host'] as String;
        final portRaw = nodeData['port'];
        final portStr = portRaw?.toString(); // Convert to string regardless of original type
        
        
        _currentConfig = SiaNodeConfig(
          host: hostStr,
          port: portStr ?? '',
          password: storedPassword ?? '', // Use stored password or empty
          isDecVaultManagedNode: false,
        );
        
        // If password is missing, trigger the password required screen
        if (_currentConfig?.password.isEmpty == true) {
          Future.delayed(const Duration(milliseconds: 1000), () async {
            try {
              await _triggerPasswordCheckViaAuth();
            } catch (e) {
            }
          });
        }
      } else if (response.statusCode == 404) {
        // No custom config found in backend, check local storage
        final localConfig = await _loadLocalSiaConfig();
        if (localConfig != null) {
          _currentConfig = localConfig;
        } else {
          _currentConfig = null;
        }
      } else {
        _currentConfig = null;
      }
    } catch (e) {
      
      // Backend connection failed, try local storage as fallback
      final localConfig = await _loadLocalSiaConfig();
      if (localConfig != null) {
        _currentConfig = localConfig;
      } else {
        _currentConfig = null;
      }
    }
  }

  /// Save SIA config to backend (for self-hosted)
  Future<bool> saveSiaConfigToBackend(String host, String port, String password) async {
    try {
      final authService = Get.find<AuthService>();
      final userId = await authService.getUserId();
      
      if (userId == null) {
        return false;
      }

      // Production mode - use real user ID from authentication

      // Prepare request data
      final url = Uri.parse(ApiConfig.siaNodeEndpoint);
      final headers = {
        'Content-Type': 'application/json',
        'api-key': ApiConfig.psqlApiKey,
        'user-id': userId, // ✅ REQUIRED by backend
      };
      final payload = {
        'uuid': userId,  // Backend expects lowercase 'uuid'
        'host': host,
        'port': port,
      };
      final body = jsonEncode(payload);

      // Debug logging

      // Save host and port to backend
      final response = await http.post(
        url,
        headers: headers,
        body: body,
      );


      if (response.statusCode == 200 || response.statusCode == 201) {
        
        // Save password locally (encrypted)
        final passwordSaved = await _savePasswordLocally(password);
        if (!passwordSaved) {
          return false;
        }
        
        // Update current config
        _currentConfig = SiaNodeConfig(
          host: host,
          port: port,
          password: password,
          isDecVaultManagedNode: false,
        );
        
        return true;
      } else {
        return false;
      }
    } catch (e) {
      if (e is http.ClientException) {
      }
      return false;
    }
  }

  /// Save password locally with encryption (public method for settings screen)
  Future<bool> savePasswordLocally(String password) async {
    return await _savePasswordLocally(password);
  }

  /// Clear stored password
  Future<bool> clearStoredPassword() async {
    try {
      await _secureDelete(_siaPasswordKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Save password locally (encrypted)
  Future<bool> _savePasswordLocally(String password) async {
    try {
      
      if (password.isEmpty) {
        return false;
      }
      
      // Create encryption key from user's data
      final authService = Get.find<AuthService>();
      final userId = await authService.getUserId();
      if (userId == null) {
        return false;
      }
      
      
      final keyBytes = sha256.convert(utf8.encode(userId)).bytes.take(32).toList();
      final key = encrypt.Key(Uint8List.fromList(keyBytes));
      final iv = encrypt.IV.fromSecureRandom(16);
      
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encrypt(password, iv: iv);
      
      // Store both encrypted password and IV
      final encryptedData = {
        'encrypted': encrypted.base64,
        'iv': iv.base64,
      };
      
      final jsonData = jsonEncode(encryptedData);
      
      await _secureWrite(_siaPasswordKey, jsonData);
      
      // Verify the stored data can be read back
      final verifyData = await _secureRead(_siaPasswordKey);
      if (verifyData == null) {
        return false;
      }
      
      try {
        final verifyParsed = jsonDecode(verifyData);
        if (verifyParsed is! Map<String, dynamic> || 
            !verifyParsed.containsKey('encrypted') || 
            !verifyParsed.containsKey('iv')) {
          await _secureDelete(_siaPasswordKey);
          return false;
        }
      } catch (e) {
        await _secureDelete(_siaPasswordKey);
        return false;
      }
      
      return true;
    } catch (e) {
      // Clean up any partial data
      await _secureDelete(_siaPasswordKey);
      return false;
    }
  }

  /// Get decrypted password
  Future<String?> getStoredPassword() async {
    try {
      final encryptedDataStr = await _secureRead(_siaPasswordKey);
      if (encryptedDataStr == null) return null;
      
      
      // Validate that the stored data is a valid JSON string
      dynamic encryptedData;
      try {
        encryptedData = jsonDecode(encryptedDataStr);
      } catch (jsonError) {
        // Clear corrupted data
        await _secureDelete(_siaPasswordKey);
        return null;
      }
      
      // Validate that the decrypted data has the expected structure
      if (encryptedData is! Map<String, dynamic>) {
        // Clear invalid data
        await _secureDelete(_siaPasswordKey);
        return null;
      }
      
      if (!encryptedData.containsKey('encrypted') || !encryptedData.containsKey('iv')) {
        // Clear incomplete data
        await _secureDelete(_siaPasswordKey);
        return null;
      }
      
      final authService = Get.find<AuthService>();
      final userId = await authService.getUserId();
      if (userId == null) {
        return null;
      }
      
      final keyBytes = sha256.convert(utf8.encode(userId)).bytes.take(32).toList();
      final key = encrypt.Key(Uint8List.fromList(keyBytes));
      
      try {
        final iv = encrypt.IV.fromBase64(encryptedData['iv']);
        final encrypter = encrypt.Encrypter(encrypt.AES(key));
        final encrypted = encrypt.Encrypted.fromBase64(encryptedData['encrypted']);
        
        final decryptedPassword = encrypter.decrypt(encrypted, iv: iv);
        return decryptedPassword;
      } catch (cryptoError) {
        // Clear data that can't be decrypted
        await _secureDelete(_siaPasswordKey);
        return null;
      }
      
    } catch (e) {
      // Clear any problematic data
      await _secureDelete(_siaPasswordKey);
      return null;
    }
  }

  /// Check if password is missing for self-hosted config
  Future<bool> isPasswordMissing() async {
    final prefs = await SharedPreferences.getInstance();
    final backupOption = prefs.getString('backupOption') ?? 'DecVault';
    
    
    if (backupOption == 'DecVault') {
      return false; // DecVault has built-in password
    }
    
    if (_currentConfig == null) {
      return false; // No config means no password needed
    }
    
    final storedPassword = await getStoredPassword();
    final passwordMissing = storedPassword == null || storedPassword.isEmpty;
    return passwordMissing;
  }

  /// Setup default for new user (DecVault)
  Future<void> setupDefaultForNewUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backupOption', 'DecVault');
    await loadSiaConfiguration();
  }

  /// Clear all SIA data on logout
  Future<void> onUserLogout() async {
    
    // Clear stored password
    await _secureDelete(_siaPasswordKey);
    
    // Clear current config
    _currentConfig = null;
    
    // Clear preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('backupOption');
    
    // Also delete any other SIA-related keys that might exist
    await _secureDelete('sia_host');
    await _secureDelete('sia_port');
    await _secureDelete('sia_config');
    
  }

  /// Force clear all SIA password data (for debugging)
  Future<void> clearAllPasswordData() async {
    await _secureDelete(_siaPasswordKey);
    
    // If current config exists and it's self-hosted, clear its password
    if (_currentConfig != null && !_currentConfig!.isDecVaultManagedNode) {
      _currentConfig = SiaNodeConfig(
        host: _currentConfig!.host,
        port: _currentConfig!.port,
        password: '', // Clear password
        isDecVaultManagedNode: false,
      );
    }
    
  }

  /// Update password for current config
  Future<void> updatePassword(String password) async {
    if (_currentConfig != null && !_currentConfig!.isDecVaultManagedNode) {
      await _savePasswordLocally(password);
      _currentConfig = SiaNodeConfig(
        host: _currentConfig!.host,
        port: _currentConfig!.port,
        password: password,
        isDecVaultManagedNode: false,
      );
    }
  }

  /// Get current SIA config (DecVault or self-hosted)
  Map<String, String> getCurrentSiaConfig() {
    
    if (_currentConfig != null) {
      
      return {
        'host': _currentConfig!.host,
        'port': _currentConfig!.port,
        'password': _currentConfig!.password,
      };
    }
    
    // Fallback to DecVault
    
    return {
      'host': ApiConfig.SSip,
      'port': ApiConfig.SSport,
      'password': ApiConfig.SSpass,
    };
  }

  /// Trigger password check via AuthService
  Future<void> _triggerPasswordCheckViaAuth() async {
    try {
      
      // Wait a bit to ensure context is available
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Check if we have a valid context before navigating
      if (Get.context != null) {
        try {
          // Use direct widget navigation to avoid route issues
          Get.to(() => const SiaPasswordRequiredScreen());
        } catch (e) {
          // This is the last resort - if this fails, there's a deeper issue
        }
      } else {
      }
    } catch (e) {
    }
  }

  /// Load SIA config from local storage (fallback when backend is unavailable)
  Future<SiaNodeConfig?> _loadLocalSiaConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString('local_sia_config');
      
      if (configJson == null) {
        return null;
      }
      
      final configData = jsonDecode(configJson) as Map<String, dynamic>;
      
      // Get stored password locally (decrypted)
      final storedPassword = await getStoredPassword();
      
      final config = SiaNodeConfig(
        host: configData['host'] as String,
        port: configData['port'].toString(),
        password: storedPassword ?? '',
        isDecVaultManagedNode: configData['isDecVaultManagedNode'] as bool? ?? false,
      );
      
      return config;
    } catch (e) {
      return null;
    }
  }
}

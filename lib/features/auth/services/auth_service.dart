import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:hex/hex.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/user.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/config/api_config.dart';

import 'package:decvault/features/sia/services/sia_service.dart';
import 'package:decvault/features/sia/screens/sia_password_required_screen.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/subscription/services/storage_service.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class AuthService extends GetxService {
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
  static const _seedPhraseKey = 'seed_phrase';
  static const _userIdKey = 'user_id';
  static const _pinKey = 'user_pin';
  
  // Current authenticated user
  User? currentUser;
  

  static final AuthService _instance = AuthService._internal();
  
  factory AuthService() {
    return _instance;
  }
  
  AuthService._internal();
  
  // Initialize the service
  Future<AuthService> init() async {
    
    // Check if we have a stored private key or seed phrase
    final hasPrivateKey = await _secureContainsKey('private_key');
    final hasSeedPhrase = await this.hasSeedPhrase();
    
    if (!hasPrivateKey && !hasSeedPhrase) {
   }
    
    // Additional check for SIA password after initialization
    _checkExistingSessionForSiaPassword();
    
    return this;
  }

  // Check existing session for SIA password requirement
  void _checkExistingSessionForSiaPassword() {
    Future.delayed(const Duration(milliseconds: 3000), () async {
      
      try {
        final storedUserId = await _secureRead(_userIdKey);
        
        if (storedUserId != null) {
          
          final needsPassword = await _checkIfSiaPasswordNeeded();
          
          if (needsPassword) {
            try {
              await Future.delayed(const Duration(milliseconds: 500)); // Short delay for context
              Get.offAllNamed('/sia-password-required');
            } catch (e) {
              try {
                // Fallback to direct navigation
                Get.off(() => const SiaPasswordRequiredScreen());
              } catch (e2) {
              }
            }
          } else {
          }
        } else {
        }
      } catch (e) {
      }
    });
  }

  Future<void> clearPasswordStorage() async {
    try {
      final passwordRepo = Get.find<PasswordRepository>();
      await passwordRepo.clearAllPasswords();
    } catch (e) {
    }
  }

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

  Future<bool> _secureContainsKey(String key) async {
    try {
      final hasKey = await _storage.containsKey(key: key);
      if (hasKey) return true;
    } catch (e) {
    }
    
    // Fallback to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('secure_$key');
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

  Future<String?> generateAndStoreSeedPhrase() async {
    final seedPhrase = bip39.generateMnemonic();
    await _secureWrite(_seedPhraseKey, seedPhrase);
    return seedPhrase;
  }

  Future<bool> verifySeedPhrase(String inputPhrase) async {
    final storedPhrase = await _secureRead(_seedPhraseKey);
    if (storedPhrase == null) return false;
    
    // Normalize both for comparison
    final normalizedInput = _normalizeSeedPhrase(inputPhrase);
    final normalizedStored = _normalizeSeedPhrase(storedPhrase);
    
    return normalizedStored == normalizedInput && bip39.validateMnemonic(normalizedInput);
  }

  Future<bool> hasSeedPhrase() async {
    return await _secureContainsKey(_seedPhraseKey);
  }

  Future<void> clearSeedPhrase() async {
    await _secureDelete(_seedPhraseKey);
  }
  
  // Register a new user with seed phrase (or login if user already exists)
  Future<bool> registerUser(String seedPhrase) async {
    try {
      await clearPasswordStorage();
      
      // Generate seed phrase if none provided, otherwise normalize the provided one
      final phraseToUse = seedPhrase.isEmpty 
          ? bip39.generateMnemonic() 
          : _normalizeSeedPhrase(seedPhrase);
      
      
      // Derive keys from seed phrase
      final keys = deriveKeysFromSeedPhrase(phraseToUse);
      
      // Try to register with server FIRST before storing anything
      bool registrationSuccess = await _registerWithServer(keys['publicKey']!);
        if (!registrationSuccess) {
        // If registration fails, try to login (user might already exist)
        return await loginUser(phraseToUse);
      }
      
      
      // Only store seed phrase and keys AFTER successful registration
      await _secureWrite(_seedPhraseKey, phraseToUse);
      await _secureWrite('private_key', keys['privateKey']!);
      
      // Store login state in shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      
      // Initialize storage tracking with user ID
      try {
        final userId = await getUserId();
        if (userId != null) {
          final storageService = Get.find<StorageService>();
          storageService.setUserId(userId);
          await storageService.syncWithBackend();
        }
      } catch (e) {
      }
      
      // Mark initial setup as complete after successful registration
      try {
        final securityService = Get.find<SecurityService>();
        await securityService.markInitialSetupComplete();
      } catch (e) {
      }
      
      // Setup default SIA configuration for new user (DecVault)
      final siaService = Get.find<SiaService>();
      await siaService.setupDefaultForNewUser();
      
      return true;
    } catch (e) {
        return false;
    }
  }
  
  Future<bool> _registerWithServer(String publicKey) async {
    try {
      final url = Uri.parse(ApiConfig.registerEndpoint);
      final payload = jsonEncode({
        'public_key': publicKey
      });

      final headers = {
        'Content-Type': 'application/json',
        'api-key': ApiConfig.psqlApiKey, // Use API key from config
      };
      
      // Try registration with retry logic
      http.Response? response;
      Exception? lastError;
      
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          response = await http.Client().post(
            url,
            headers: headers, // Use defined headers map
            body: payload,
          ).timeout(const Duration(seconds: 30));
          
          if (response.statusCode == 201) {
            break; // Success, exit retry loop
          }
          
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
      
      if (response == null) {
        throw lastError is Exception ? lastError : Exception('Failed to get response after 3 attempts');
      }
  
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Parse the uuid from the response
        final responseData = jsonDecode(response.body);
        
        // Handle both String and int types for user ID from backend
        final userIdRaw = responseData['uuid'] ?? responseData['userId'];
        final uuid = userIdRaw?.toString(); // Convert to string regardless of original type

        if (uuid == null || uuid.isEmpty) {
          return false;
        }
        // Store the received uuid in secure storage
        await _secureWrite(_userIdKey, uuid);
        return true;
      } else if (response.statusCode == 409) {
        // User already exists - this is expected for existing users
        return false; // Return false so registerUser method tries login
      } else {
        return false;
      }
    } catch (e) {
      // Include more detailed error information
      if (e is http.ClientException) {
      }
      return false;
    }
  }
  
  // Login a user with seed phrase
  Future<bool> loginUser(String seedPhrase) async {
    try {
      // Normalize the seed phrase for consistent formatting across platforms
      final normalizedPhrase = _normalizeSeedPhrase(seedPhrase);
      
      // Verify the seed phrase
      final isValid = bip39.validateMnemonic(normalizedPhrase);
      if (!isValid) {
        return false;
      }
      
      // Production mode - no demo seed phrase check
      
      // Derive public key from seed phrase
      final keys = deriveKeysFromSeedPhrase(normalizedPhrase);
      final publicKey = keys['publicKey'];
      if (publicKey == null || publicKey.isEmpty) {
        return false;
      }
      
      // Production mode only - no demo mode fallback
      
      // Send public key to login API
      final url = Uri.parse(ApiConfig.loginEndpoint);
      final payload = jsonEncode({'public_key': publicKey});
      final headers = {
        'Content-Type': 'application/json',
        'api-key': ApiConfig.psqlApiKey,
      };
      http.Response? response;
      Exception? lastError;
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          response = await http.Client().post(
            url,
            headers: headers,
            body: payload,
          ).timeout(const Duration(seconds: 30));
          if (response.statusCode == 200 || response.statusCode == 201) {
            break;
          }
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
        }
      }
      if (response == null) {
        if (lastError != null) print('AUTH_SERVICE: Last error: $lastError');
        // Production mode - no demo fallback
        return false;
      }
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        
        // Handle both String and int types for user ID from backend
        final userIdRaw = data['uuid'] ?? data['userId'];
        final userId = userIdRaw?.toString(); // Convert to string regardless of original type
        
        if (userId == null || userId.isEmpty) {
          return false;
        }
        
        // Store all credentials after successful login (use normalized phrase)
        await _secureWrite(_seedPhraseKey, normalizedPhrase);
        await _secureWrite(_userIdKey, userId);
        await _secureWrite('private_key', keys['privateKey']!);
        
        // Set login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        
        
        // Initialize storage tracking with user ID
        try {
          final storageService = Get.find<StorageService>();
          storageService.setUserId(userId);
          await storageService.syncWithBackend();
        } catch (e) {
        }
        
        // Mark initial setup as complete after successful login
        try {
          final securityService = Get.find<SecurityService>();
          await securityService.markInitialSetupComplete();
        } catch (e) {
        }
        
        // Check if SIA password is needed and navigate accordingly
        try {
          final needsPassword = await _checkIfSiaPasswordNeeded();
          
          if (needsPassword) {
            try {
              await Future.delayed(const Duration(milliseconds: 500)); // Short delay for context
              
              // Try offAllNamed first
              Get.offAllNamed('/sia-password-required');
            } catch (e) {
              try {
                // Fallback to direct navigation
                Get.off(() => const SiaPasswordRequiredScreen());
              } catch (e2) {
                // Last resort - go to home screen
                Get.offAllNamed('/home');
              }
            }
          } else {
            Get.offAllNamed('/home');
          }
          
        } catch (e) {
          // On error, go to home screen as fallback
          Get.offAllNamed('/home');
        }
        
        return true;
      } else {
        // Production mode - no demo fallback
        return false;
      }
    } catch (e) {
      if (e is http.ClientException) {
      }
      // Production mode - no demo fallback
      return false;
    }
  }
  
  // Logout the current user
  Future<void> logoutUser() async {
    try {

      // Clear security lock state FIRST before clearing credentials
      try {
        final securityService = Get.find<SecurityService>();
        securityService.clearLockState(); // Unlock and clear lock state
      } catch (e) {
      }

      await clearSeedPhrase();
      await _secureDelete(_userIdKey);
      await _secureDelete(_pinKey);
      
      // Clear all SIA-related data (both auth service and SIA service)
      await _secureDelete('sia_password');
      
      // Clear SIA data through SiaService
      try {
        final siaService = Get.find<SiaService>();
        await siaService.onUserLogout();
      } catch (e) {
      }
      
      // Update shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', false);
      await prefs.remove('user_seed_phrase');
      await prefs.remove('user_pin');
      await prefs.remove('secure_user_pin'); // Remove fallback storage
      await prefs.remove('secure_seed_phrase'); // Remove fallback storage
      await prefs.remove('secure_user_id'); // Remove fallback storage
      
      // Clear manual SIA connection flag on logout
      await prefs.setBool('sia_manually_connected', false);
      

      
      Get.offAllNamed('/auth');
    } catch (e) {
      // Show error safely
      if (Get.context != null) {
        try {
          SnackbarUtils.showError(
        title: 'Logout Failed',
        message: 'Could not complete logout: $e',
      );
        } catch (snackbarError) {
        }
      }
    }
  }
  
  // Delete user account from backend and clear all local data
  Future<bool> deleteAccount() async {
    try {
      // Get public key for the delete request
      final publicKey = await getPublicKey();
      if (publicKey == null || publicKey.isEmpty) {
        throw Exception('Could not retrieve public key');
      }
      
      // Call DELETE API endpoint - try /account first, then /api/account as fallback
      final urls = [
        Uri.parse('${ApiConfig.psqlBaseUrl}/account'),
        Uri.parse('${ApiConfig.psqlBaseUrl}/api/account'),
      ];
      
      final headers = {
        'Content-Type': 'application/json',
      };
      final payload = jsonEncode({
        'public_key': publicKey,
      });
      
      // Debug logging
      print('🗑️ DELETE ACCOUNT DEBUG:');
      print('  Base URL: ${ApiConfig.psqlBaseUrl}');
      print('  Public Key (first 20 chars): ${publicKey.substring(0, publicKey.length > 20 ? 20 : publicKey.length)}...');
      print('  Request Payload: $payload');
      
      http.Response? response;
      Exception? lastError;
      
      // Try both endpoint paths
      for (int i = 0; i < urls.length; i++) {
        final url = urls[i];
        try {
          print('  Attempting URL ${i + 1}: $url');
          
          // Create a DELETE request with body (http.delete doesn't support body)
          final request = http.Request('DELETE', url);
          request.headers.addAll(headers);
          request.body = payload;
          
          print('  Request Method: ${request.method}');
          print('  Request Headers: ${request.headers}');
          
          final client = http.Client();
          final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));
          response = await http.Response.fromStream(streamedResponse);
          
          // Debug logging for response
          print('  Response Status Code: ${response.statusCode}');
          print('  Response Headers: ${response.headers}');
          print('  Response Body Length: ${response.body.length}');
          print('  Response Body (first 500 chars): ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
          
          // Check if response is HTML (likely a 404 page or error page)
          final contentType = response.headers['content-type'] ?? '';
          final isHtml = contentType.contains('text/html') || 
                         response.body.trim().startsWith('<!DOCTYPE') ||
                         response.body.trim().startsWith('<html');
          
          print('  Is HTML Response: $isHtml');
          
          if (isHtml) {
            // This endpoint returned HTML, try the next one
            print('  ⚠️ Got HTML response, trying next URL...');
            continue;
          }
          
          // If we got a valid response (not HTML), break and use it
          if (response.statusCode == 200 || response.statusCode == 204 || 
              (response.statusCode >= 400 && response.statusCode < 500 && !isHtml)) {
            print('  ✅ Got valid response, using this URL');
            break;
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          print('  ❌ Error with URL $url: $e');
          continue;
        }
      }
      
      if (response == null) {
        print('  ❌ No valid response received from any URL');
        throw lastError ?? Exception('Failed to connect to server. Please check your internet connection.');
      }
      
      // Check if final response is HTML
      final contentType = response.headers['content-type'] ?? '';
      final isHtml = contentType.contains('text/html') || 
                     response.body.trim().startsWith('<!DOCTYPE') ||
                     response.body.trim().startsWith('<html');
      
      print('  Final Response Analysis:');
      print('    Status Code: ${response.statusCode}');
      print('    Content Type: $contentType');
      print('    Is HTML: $isHtml');
      print('    Full Response Body: ${response.body}');
      
      if (isHtml) {
        // Backend returned HTML, likely endpoint doesn't exist
        throw Exception('Account deletion endpoint not found on server. The backend API endpoint DELETE /account needs to be implemented.');
      }
      
      if (response.statusCode == 200 || response.statusCode == 204) {
        print('  ✅ Account deletion successful! Status: ${response.statusCode}');
        print('  🧹 Starting local data cleanup...');
        
        // Account deleted successfully, clear all local data
        try {
          // Clear security lock state FIRST before clearing credentials
          try {
            final securityService = Get.find<SecurityService>();
            securityService.clearLockState();
            print('  ✓ Security lock state cleared');
          } catch (e) {
            print('  ⚠️ Error clearing security lock: $e');
          }

          await clearSeedPhrase();
          print('  ✓ Seed phrase cleared');
          
          await _secureDelete(_userIdKey);
          print('  ✓ User ID cleared');
          
          await _secureDelete(_pinKey);
          print('  ✓ PIN cleared');
          
          await _secureDelete('private_key');
          print('  ✓ Private key cleared');
          
          // Clear all SIA-related data
          await _secureDelete('sia_password');
          print('  ✓ SIA password cleared');
          
          try {
            final siaService = Get.find<SiaService>();
            await siaService.onUserLogout();
            print('  ✓ SIA service data cleared');
          } catch (e) {
            print('  ⚠️ Error clearing SIA service: $e');
          }
          
          // Update shared preferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', false);
          await prefs.remove('user_seed_phrase');
          await prefs.remove('user_pin');
          await prefs.remove('secure_user_pin');
          await prefs.remove('secure_seed_phrase');
          await prefs.remove('secure_user_id');
          await prefs.setBool('sia_manually_connected', false);
          print('  ✓ Shared preferences cleared');
          
          print('  ✅ All local data cleared successfully');
          print('  🚪 Navigating to auth screen...');
          
          // Navigate to auth screen
          Get.offAllNamed('/auth');
          
          return true;
        } catch (e) {
          print('  ⚠️ Error during local cleanup: $e');
          // Even if clearing local data fails, account is deleted on backend
          Get.offAllNamed('/auth');
          return true;
        }
      } else {
        // Account deletion failed on backend
        String errorMessage = 'Failed to delete account (${response.statusCode})';
        
        if (response.body.isNotEmpty) {
          try {
            final responseData = jsonDecode(response.body);
            errorMessage = responseData['error'] ?? responseData['message'] ?? errorMessage;
          } catch (e) {
            // If response is not JSON, use the status code message
            if (response.statusCode == 404) {
              errorMessage = 'Account deletion endpoint not found. Please contact support.';
            } else if (response.statusCode == 401 || response.statusCode == 403) {
              errorMessage = 'Unauthorized. Please log in and try again.';
            } else {
              errorMessage = 'Server error (${response.statusCode}). Please try again later.';
            }
          }
        }
        
        throw Exception(errorMessage);
      }
    } catch (e) {
      rethrow;
    }
  }
  
  // Check if user is logged in
  bool isLoggedIn() {
    // Use a cached value to prevent infinite rebuilds
    return false; // Default to false to prevent rebuild loops
  }
  
  // Async version for checking login status
  Future<bool> checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('is_logged_in') ?? false;
    } catch (e) {
      return false;
    }
  }
  
  // Get the seed from mnemonic
  Uint8List _getSeedFromMnemonic(String mnemonic) {
    return bip39.mnemonicToSeed(mnemonic);
  }
  
  // Normalize seed phrase to ensure consistent format across platforms
  String _normalizeSeedPhrase(String seedPhrase) {
    // 1. Trim outer whitespace
    // 2. Convert to lowercase (BIP39 words are case-insensitive)
    // 3. Replace multiple spaces/newlines with single space
    // 4. Trim again to be safe
    return seedPhrase
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Derive HD wallet keys from seed phrase
  Map<String, String> deriveKeysFromSeedPhrase(String seedPhrase) {
    try {
      // Normalize the seed phrase first for consistent formatting
      final normalizedPhrase = _normalizeSeedPhrase(seedPhrase);
      
      // Validate the seed phrase
      if (!bip39.validateMnemonic(normalizedPhrase)) {
        throw Exception('Invalid seed phrase');
      }
      
      // Convert mnemonic to seed
      final seed = _getSeedFromMnemonic(normalizedPhrase);
      
      // Create a BIP32 node from the seed
      final node = bip32.BIP32.fromSeed(seed);
      
      final child = node.derivePath("m/44'/0'/0'/0/0");
      
      // Get private key (as hex string)
      final privateKey = HEX.encode(child.privateKey!);
      
      // Get public key (as hex string)
      final publicKey = HEX.encode(child.publicKey);
      
      return {
        'privateKey': privateKey,
        'publicKey': publicKey,
      };
    } catch (e) {
      return {
        'privateKey': 'Error: $e',
        'publicKey': 'Error: $e',
      };
    }
  }
  
  // Get keys from stored seed phrase
  Future<Map<String, String>> getKeysFromStoredSeedPhrase() async {
    try {
      final storedPhrase = await _storage.read(key: _seedPhraseKey);
      if (storedPhrase == null) {
        return {
          'privateKey': 'No seed phrase stored',
          'publicKey': 'No seed phrase stored',
        };
      }
      
      return deriveKeysFromSeedPhrase(storedPhrase);
    } catch (e) {
      return {
        'privateKey': 'Error: $e',
        'publicKey': 'Error: $e',
      };
    }
  }
  
  // Get the user ID from secure storage
  Future<String?> getUserId() async {
    try {
      final userId = await _secureRead(_userIdKey); // Use secure read with fallback
      
      
      return userId;
    } catch (e) {
      return null;
    }
  }
  
  Future<String?> getPrivateKey() async {
    try {
      // First try to get directly stored private key using secure read
      final storedPrivateKey = await _secureRead('private_key');
      if (storedPrivateKey != null) {
        return storedPrivateKey;
      }
      
      // Fallback to derivation from seed phrase if no stored key
      if (!await hasSeedPhrase()) {
        return null;
      }
      
      // Get the stored seed phrase
      final seedPhrase = await _storage.read(key: _seedPhraseKey);
      if (seedPhrase == null) {
        return null;
      }
      
      // Derive keys from seed phrase
      final keys = deriveKeysFromSeedPhrase(seedPhrase);
      
      if (keys['privateKey'] == null || keys['privateKey']!.isEmpty) {
        return null;
      }
      
      // Store the derived key for future use
      await _storage.write(key: 'private_key', value: keys['privateKey']);
      return keys['privateKey'];
    } catch (e) {
      return null;
    }
  }
  
  // Get the stored seed phrase for display in settings
  Future<String?> getStoredSeedPhrase() async {
    try {
      return await _secureRead(_seedPhraseKey);
    } catch (e) {
      return null;
    }
  }
  
  // Get the public key from stored seed phrase
  Future<String?> getPublicKey() async {
    try {
      final keys = await getKeysFromStoredSeedPhrase();
      final publicKey = keys['publicKey'];
      if (publicKey == null || publicKey.isEmpty || publicKey.startsWith('Error:') || publicKey == 'No seed phrase stored') {
        return null;
      }
      return publicKey;
    } catch (e) {
      return null;
    }
  }

  // DEPRECATED: Use SecurityService for PIN management instead
  @Deprecated('Use SecurityService.setPinCode() instead')
  Future<void> storePin(String pin) async {
    try {
      if (pin.length != 6) {
        throw Exception('PIN must be exactly 6 digits');
      }
      
      final userId = await getUserId();
      if (userId == null) {
        throw Exception('No user ID found');
      }
      
      // Store PIN with user ID prefix for additional security
      await _storage.write(key: _pinKey, value: '$userId:$pin');
    } catch (e) {
      rethrow;
    }
  }
  
  // DEPRECATED: Use SecurityService for PIN verification instead
  @Deprecated('Use SecurityService.verifyPinCode() instead')
  Future<bool> verifyPin(String inputPin) async {
    try {
      if (inputPin.length != 6) {
        return false;
      }
      
      final userId = await getUserId();
      if (userId == null) {
        return false;
      }
      
      final storedPin = await _storage.read(key: _pinKey);
      if (storedPin == null) {
        return false;
      }
      
      // Check if stored PIN matches input with user ID
      return storedPin == '$userId:$inputPin';
    } catch (e) {
      return false;
    }
  }
  
  // Check if PIN is stored
  Future<bool> hasPin() async {
    return await _storage.containsKey(key: _pinKey);
  }
  
  // Check existing session for SIA password requirements
  Future<void> checkExistingSession() async {
    try {
      
      // Get current stored user ID
      final storedUserId = await _secureRead(_userIdKey);
      
      // If we have a valid user ID, check if SIA password is needed
      if (storedUserId != null) {
        
        // Check if user manually connected and is still connected
        final prefs = await SharedPreferences.getInstance();
        final manuallyConnected = prefs.getBool('sia_manually_connected') ?? false;
        
        
        if (!manuallyConnected) {
          // Only clear SIA password if user hasn't manually connected successfully
          await _storage.delete(key: 'sia_password');
          
          // Also clear SIA service password data
          try {
            final siaService = Get.find<SiaService>();
            await siaService.clearAllPasswordData();
          } catch (e) {
          }
        } else {
        }
        
        // Small delay to let other services initialize
        Future.delayed(const Duration(milliseconds: 2000), () async {
          final needsPassword = await _checkIfSiaPasswordNeeded();
          if (needsPassword) {
            try {
              await Future.delayed(const Duration(milliseconds: 500)); // Short delay for context
              Get.offAllNamed('/sia-password-required');
            } catch (e) {
              try {
                // Fallback to direct navigation
                Get.off(() => const SiaPasswordRequiredScreen());
              } catch (e2) {
              }
            }
          }
        });
      }
      
    } catch (e) {
    }
  }
  
  // Check if SIA password is needed after login
  Future<bool> _checkIfSiaPasswordNeeded() async {
    try {
      
      final siaService = Get.find<SiaService>();
      
      await siaService.loadSiaConfiguration();
      
      final isPasswordMissing = await siaService.isPasswordMissing();
      
      final currentConfig = siaService.currentConfig;
      
      if (currentConfig != null) {
      }
      
      // Return true if password is missing and we have a self-hosted config
      final needsPassword = isPasswordMissing && currentConfig != null && !currentConfig.isDecVaultManagedNode;
      
      if (needsPassword) {
      } else {
        if (!isPasswordMissing) {
        }
        if (currentConfig == null) {
        }
        if (currentConfig?.isDecVaultManagedNode == true) {
        }
      }
      
      return needsPassword;
    } catch (e) {
      return false; // Default to false on error
    }
  }

  // Manual trigger for SIA password check (can be called from anywhere)
  static Future<void> triggerSiaPasswordCheckIfNeeded() async {
    try {
      final authService = Get.find<AuthService>();
      
      final needsPassword = await authService._checkIfSiaPasswordNeeded();
      
      if (needsPassword) {
        Get.offAllNamed('/sia-password-required');
      } else {
      }
    } catch (e) {
    }
  }

}

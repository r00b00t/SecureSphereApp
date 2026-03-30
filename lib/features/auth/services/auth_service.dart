import 'package:flutter/material.dart' show Color, Colors;
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

import 'package:decvault/features/decentralized/services/decentralized_service.dart';
import 'package:decvault/features/sia/services/sia_service.dart';
import 'package:decvault/features/sia/screens/sia_password_required_screen.dart';
import 'package:decvault/features/auth/services/security_service.dart';

class AuthService extends GetxService {
  static const _storage = FlutterSecureStorage();
  static const _seedPhraseKey = 'seed_phrase';
  static const _userIdKey = 'user_id';
  static const _pinKey = 'user_pin';
  static const _jwtTokenKey = 'jwt_token';

  // Current authenticated user
  User? currentUser;
  

  static final AuthService _instance = AuthService._internal();
  
  factory AuthService() {
    return _instance;
  }
  
  AuthService._internal();
  
  Future<AuthService> init() async {
    await clearDemoData();
    
    final hasPrivateKey = await _storage.containsKey(key: 'private_key');
    final hasSeedPhrase = await this.hasSeedPhrase();
    
    if (!hasPrivateKey && !hasSeedPhrase) {
   }
    
    _checkExistingSessionForSiaPassword();
    
    return this;
  }

  void _checkExistingSessionForSiaPassword() {
    Future.delayed(const Duration(milliseconds: 3000), () async {
      try {
        final storedUserId = await _storage.read(key: _userIdKey);
        
        if (storedUserId != null) {
          final needsPassword = await _checkIfSiaPasswordNeeded();
          
          if (needsPassword) {
            try {
              await Future.delayed(const Duration(milliseconds: 500));
              Get.offAllNamed('/sia-password-required');
            } catch (e) {
              try {
                Get.off(() => const SiaPasswordRequiredScreen());
              } catch (e2) {
                // Navigation failed
              }
            }
          }
        }
      } catch (e) {
        // Error in session check
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

  Future<String?> generateAndStoreSeedPhrase() async {
    final seedPhrase = bip39.generateMnemonic();
    await _storage.write(key: _seedPhraseKey, value: seedPhrase);
    return seedPhrase;
  }

  Future<bool> verifySeedPhrase(String inputPhrase) async {

    final storedPhrase = await _storage.read(key: _seedPhraseKey);
    return storedPhrase == inputPhrase && bip39.validateMnemonic(inputPhrase);
  }

  Future<bool> hasSeedPhrase() async {

    return await _storage.containsKey(key: _seedPhraseKey);
  }

  Future<void> clearSeedPhrase() async {
    await _storage.delete(key: _seedPhraseKey);
  }
  

  
  // Register a new user with seed phrase (or login if user already exists)
  Future<bool> registerUser(String seedPhrase) async {
    try {
      await clearPasswordStorage();
      
      // Generate seed phrase if none provided
      final phraseToUse = seedPhrase.isEmpty ? await generateAndStoreSeedPhrase() : seedPhrase;
      

      
      // Store seed phrase in secure storage
      await _storage.write(key: _seedPhraseKey, value: phraseToUse);
      
      // Derive keys from seed phrase
      final keys = deriveKeysFromSeedPhrase(phraseToUse!);
      
      // Store private key in secure storage for later retrieval
      await _storage.write(key: 'private_key', value: keys['privateKey']);
      
                  // Try to register with server

      bool registrationSuccess = await _registerWithServer(keys['publicKey']!);
        if (!registrationSuccess) {
        // If registration fails, try to login (user might already exist)

        return await loginUser(phraseToUse);
      }
      

      
      // Store login state in shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      
      // Mark initial setup as complete after successful registration
      try {
        final securityService = Get.find<SecurityService>();
        await securityService.markInitialSetupComplete();

      } catch (e) {

      }
      
      // Setup default SIA configuration for new user (SecureSphere)
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

      final headers = await getAuthHeaders();
      
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
        await _storage.write(key: _userIdKey, value: uuid);
        await _fetchAndStoreToken(publicKey);

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
      // Verify the seed phrase
      final isValid = bip39.validateMnemonic(seedPhrase);
      if (!isValid) {
        return false;
      }
      
      
      // Derive public key from seed phrase
      final keys = deriveKeysFromSeedPhrase(seedPhrase);
      final publicKey = keys['publicKey'];
      if (publicKey == null || publicKey.isEmpty) {
        return false;
      }
      
      
      // Send public key to login API
      final url = Uri.parse(ApiConfig.loginEndpoint);
      final payload = jsonEncode({'public_key': publicKey});
      final headers = await getAuthHeaders();
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
        
        await _storage.write(key: _userIdKey, value: userId);
        await _storage.write(key: 'private_key', value: keys['privateKey']);

        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          await _storage.write(key: _jwtTokenKey, value: token);
        }

        // Set login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);

        // Reload SIA config now that the user ID is known (ensures the correct
        // bucket name and host are picked up before the vault opens).
        try {
          final siaService = Get.find<SiaService>();
          await siaService.loadSiaConfiguration();
        } catch (_) {}

        // Mark initial setup as complete after successful login
        try {
          final securityService = Get.find<SecurityService>();
          await securityService.markInitialSetupComplete();
        } catch (e) {
        }

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
        return false;
      }
    } catch (e) {
      if (e is http.ClientException) {
      }
      return false;
    }
  }
  
  // Logout the current user
  Future<void> logoutUser() async {
    try {
      // Read mode BEFORE clearing prefs so we know where to route after logout.
      final prefs = await SharedPreferences.getInstance();
      final isDecentralized =
          (prefs.getString('app_mode') ?? '') == 'decentralized';

      await clearSeedPhrase();
      await _storage.delete(key: _userIdKey);
      await _storage.delete(key: _pinKey);
      await _storage.delete(key: _jwtTokenKey);

      // Clear all SIA-related data
      await _storage.delete(key: 'sia_password');
      try {
        final siaService = Get.find<SiaService>();
        await siaService.onUserLogout();
      } catch (_) {}

      if (isDecentralized) {
        // Clear all decentralized keys (node config, seed phrase, private key,
        // user ID) and reset app_mode so the user can re-onboard.
        try {
          final decSvc = Get.find<DecentralizedService>();
          await decSvc.clearAll();
        } catch (_) {
          // Fallback: delete keys directly if service is unavailable.
          await _storage.delete(key: 'decentralized_private_key');
          await _storage.delete(key: 'decentralized_user_id');
          await _storage.delete(key: 'decentralized_seed_phrase');
          await _storage.delete(key: 'node_host');
          await _storage.delete(key: 'node_port');
          await _storage.delete(key: 'node_password');
        }
      }

      // Always clear onboarding_complete, app_mode, and backupOption so the
      // auth screen shows path choice on next launch for all users.
      await prefs.remove('onboarding_complete');
      await prefs.remove('app_mode');
      await prefs.remove('backupOption');

      await prefs.setBool('is_logged_in', false);
      await prefs.remove('user_seed_phrase');
      await prefs.remove('user_pin');
      await prefs.setBool('sia_manually_connected', false);

      // Both modes return to /auth where path choice is embedded.
      Get.offAllNamed('/auth');
    } catch (e) {
      Get.snackbar('Logout Failed', 'Could not complete logout: $e');
    }
  }
  
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

  /// Returns Authorization + Content-Type headers using the stored JWT.
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await _storage.read(key: _jwtTokenKey);
    return {
      'Authorization': 'Bearer ${token ?? ''}',
      'Content-Type': 'application/json',
    };
  }

  /// Call when any API returns 401. Clears the session and navigates to /auth.
  /// Safe to call from services — guards against being called before the
  /// widget tree exists (e.g., during startup init).
  Future<void> handleUnauthorized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      if (!isLoggedIn) return; // Not logged in yet — ignore spurious 401
      await prefs.setBool('is_logged_in', false);
      await _storage.delete(key: _jwtTokenKey);
    } catch (_) {}
    final ctx = Get.context;
    if (ctx == null) return; // Widget tree not ready yet — skip nav
    Get.snackbar(
      'Session Expired',
      'Please sign in again.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xFF323232),
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
    Get.offAllNamed('/auth');
  }

  /// Calls /login and stores the returned JWT. Used after /signup, which does
  /// not issue a token itself.
  Future<void> _fetchAndStoreToken(String publicKey) async {
    try {
      final url = Uri.parse(ApiConfig.loginEndpoint);
      final response = await http.Client().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'public_key': publicKey}),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          await _storage.write(key: _jwtTokenKey, value: token);
        }
      }
    } catch (_) {}
  }

  Uint8List _getSeedFromMnemonic(String mnemonic) {
    return bip39.mnemonicToSeed(mnemonic);
  }
  
  // Derive HD wallet keys from seed phrase
  Map<String, String> deriveKeysFromSeedPhrase(String seedPhrase) {
    try {
      // Validate the seed phrase
      if (!bip39.validateMnemonic(seedPhrase)) {
        throw Exception('Invalid seed phrase');
      }
      
      // Convert mnemonic to seed
      final seed = _getSeedFromMnemonic(seedPhrase);
      
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
  
  Future<String?> getUserId() async {
    try {
      // Path A (decentralized): return the locally derived user ID.
      final decentralizedId = await _storage.read(key: 'decentralized_user_id');
      if (decentralizedId != null && decentralizedId.isNotEmpty) {
        return decentralizedId;
      }
      // Path B (managed): return the backend-issued UUID.
      final userId = await _storage.read(key: _userIdKey);
      return userId;
    } catch (e) {
      return null;
    }
  }
  
  Future<String?> getPrivateKey() async {
    try {
      // Path A (decentralized): private key stored under a separate key.
      final decentralizedKey = await _storage.read(key: 'decentralized_private_key');
      if (decentralizedKey != null && decentralizedKey.isNotEmpty) {
        return decentralizedKey;
      }
      // Path B (managed): directly stored private key.
      final storedPrivateKey = await _storage.read(key: 'private_key');
      if (storedPrivateKey != null) {
        return storedPrivateKey;
      }
      
      // Fallback to derivation from seed phrase if no stored key
      if (!await hasSeedPhrase()) {
        return null;
      }
      
      final seedPhrase = await _storage.read(key: _seedPhraseKey);
      if (seedPhrase == null) {
        return null;
      }
      
      // Derive keys from seed phrase
      final keys = deriveKeysFromSeedPhrase(seedPhrase);
      
      if (keys['privateKey'] == null || keys['privateKey']!.isEmpty) {
        return null;
      }
      
      await _storage.write(key: 'private_key', value: keys['privateKey']);
      return keys['privateKey'];
    } catch (e) {
      return null;
    }
  }
  
  Future<String?> getStoredSeedPhrase() async {
    try {
      return await _storage.read(key: _seedPhraseKey);
    } catch (e) {
      return null;
    }
  }
  

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
      
      return storedPin == '$userId:$inputPin';
    } catch (e) {
      return false;
    }
  }
  
  Future<bool> hasPin() async {
    return await _storage.containsKey(key: _pinKey);
  }
  
  // Clear any demo-related data for production mode
  Future<void> clearDemoData() async {
    try {
      
      // Debug: show current stored user ID
      final storedUserId = await _storage.read(key: _userIdKey);
      
      // If we have a valid user ID, check if SIA password is needed
      if (storedUserId != null) {
        
        final prefs = await SharedPreferences.getInstance();
        final manuallyConnected = prefs.getBool('sia_manually_connected') ?? false;
        
        
        if (!manuallyConnected) {
          // Skip entirely for Path A — password lives in node_password, not sia_password
          try {
            final decSvc = Get.find<DecentralizedService>();
            if (decSvc.isDecentralized) return;
          } catch (_) {}

          // Only clear SIA password if user hasn't manually connected successfully
          await _storage.delete(key: 'sia_password');

          // Clear SIA service password data, then reload for managed users
          try {
            final siaService = Get.find<SiaService>();
            await siaService.clearAllPasswordData();
            await siaService.loadSiaConfiguration();
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
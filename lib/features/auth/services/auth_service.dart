import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:hex/hex.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../../../config/api_config.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';

class AuthService extends GetxService {
  static const _storage = FlutterSecureStorage();
  static const _seedPhraseKey = 'seed_phrase';
  static const _userIdKey = 'user_id';
  
  // Current authenticated user
  User? currentUser;
  
  // Make AuthService a singleton
  static final AuthService _instance = AuthService._internal();
  
  factory AuthService() {
    return _instance;
  }
  
  AuthService._internal();
  
  // Initialize the service
  Future<AuthService> init() async {
    print('AUTH_SERVICE: Initializing AuthService');
    
    // Check if we have a stored private key or seed phrase
    final hasPrivateKey = await _storage.containsKey(key: 'private_key');
    final hasSeedPhrase = await this.hasSeedPhrase();
    
    if (!hasPrivateKey && !hasSeedPhrase) {
      print('AUTH_SERVICE: No private key or seed phrase found during initialization');
      // This is normal for first-time users, they will need to register
    }
    
    return this;
  }

  Future<void> clearPasswordStorage() async {
    try {
      final passwordRepo = Get.find<PasswordRepository>();
      await passwordRepo.clearAllPasswords();
    } catch (e) {
      debugPrint('Error clearing password storage: $e');
    }
  }

  Future<String?> generateAndStoreSeedPhrase() async {
    final seedPhrase = bip39.generateMnemonic();
    await _storage.write(key: _seedPhraseKey, value: seedPhrase);
    return seedPhrase;
  }

  Future<bool> verifySeedPhrase(String inputPhrase) async {
    // Verify with local storage
    final storedPhrase = await _storage.read(key: _seedPhraseKey);
    return storedPhrase == inputPhrase && bip39.validateMnemonic(inputPhrase);
  }

  Future<bool> hasSeedPhrase() async {
    // Check in local storage
    return await _storage.containsKey(key: _seedPhraseKey);
  }

  Future<void> clearSeedPhrase() async {
    await _storage.delete(key: _seedPhraseKey);
  }
  
  // Register a new user with seed phrase
  Future<bool> registerUser(String seedPhrase) async {
    try {
      print('AUTH_SERVICE: Starting user registration process');
      
      // Clear any existing passwords before registering
      await clearPasswordStorage();
      
      // Generate seed phrase if none provided
      final phraseToUse = seedPhrase.isEmpty ? await generateAndStoreSeedPhrase() : seedPhrase;
      
      // Store seed phrase in secure storage
      await _storage.write(key: _seedPhraseKey, value: phraseToUse);
      
      // Derive keys from seed phrase
      final keys = deriveKeysFromSeedPhrase(phraseToUse!);
      print('AUTH_SERVICE: Keys derived successfully');
      
      // Store private key in secure storage for later retrieval
      await _storage.write(key: 'private_key', value: keys['privateKey']);
      
      // Register public key with server
      final registrationSuccess = await _registerWithServer(keys['publicKey']!, keys['privateKey']!);
      if (!registrationSuccess) {
        throw Exception('Failed to register with server');
      }
      
      // Store login state in shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      
      print('AUTH_SERVICE: Registration completed successfully');
      return true;
    } catch (e) {
      print('AUTH_SERVICE: Registration error: $e');
      return false;
    } finally {
      // Ensure any resources are properly released
      print('AUTH_SERVICE: Registration process finalized');
    }
  }
  
  Future<bool> _registerWithServer(String publicKey, String uuid) async {
    try {
      // Generate a unique UUID if not provided
      final userId = uuid.isEmpty ? const Uuid().v4() : uuid;
      
      final url = Uri.parse(ApiConfig.registerEndpoint);
      final payload = jsonEncode({
        'userId': userId,
        'publicKey': publicKey
      });
      
      print('AUTH_SERVICE: Sending registration request to $url');
      print('AUTH_SERVICE: Request payload: $payload');
      
      // Try registration with retry logic
      http.Response? response;
      Exception? lastError;
      
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          response = await http.Client().post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: payload,
          ).timeout(const Duration(seconds: 30));
          
          if (response.statusCode == 200) {
            break; // Success, exit retry loop
          }
          
          print('AUTH_SERVICE: Registration attempt $attempt failed with status ${response.statusCode}');
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          print('AUTH_SERVICE: Registration attempt $attempt failed with error: $e');
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
      
      if (response == null) {
        throw lastError is Exception ? lastError : Exception('Failed to get response after 3 attempts');
      }
      
      print('AUTH_SERVICE: Server response status: ${response.statusCode}');
      print('AUTH_SERVICE: Server response body: ${response.body}');
      
      if (response.statusCode == 200) {
        // Store the generated userId in secure storage
        await _storage.write(key: _userIdKey, value: userId);
        print('AUTH_SERVICE: Successfully registered with server. User ID: $userId');
        return true;
      } else {
        final errorResponse = jsonDecode(response.body);
        print('AUTH_SERVICE: Server registration failed with status ${response.statusCode}');
        print('AUTH_SERVICE: Error details: ${errorResponse['error'] ?? response.body}');
        return false;
      }
    } catch (e) {
      print('AUTH_SERVICE: Server registration error: $e');
      // Include more detailed error information
      if (e is http.ClientException) {
        print('AUTH_SERVICE: Connection error details: ${e.message}');
        print('AUTH_SERVICE: URI attempted: ${e.uri}');
      }
      return false;
    }
  }
  
  // Login a user with seed phrase
  Future<bool> loginUser(String seedPhrase) async {
    try {
      print('AUTH_SERVICE: Starting user login process');
      // Verify the seed phrase
      final isValid = await verifySeedPhrase(seedPhrase);
      
      if (isValid) {
        // Set login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        print('AUTH_SERVICE: Login successful');
        return true;
      }
      
      print('AUTH_SERVICE: Login failed - invalid seed phrase');
      return false;
    } catch (e) {
      print('AUTH_SERVICE: Login error: $e');
      return false;
    }
  }
  
  // Logout the current user
  Future<void> logoutUser() async {
    try {
      print('AUTH_SERVICE: Starting user logout process');
      // Clear seed phrase from secure storage
      await clearSeedPhrase();
      
      // Clear user ID from secure storage
      await _storage.delete(key: _userIdKey);
      print('AUTH_SERVICE: User ID cleared from secure storage');
      
      // Update shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', false);
      await prefs.remove('user_seed_phrase');
      await prefs.remove('user_pin');
      
      print('AUTH_SERVICE: Logout completed successfully');
      Get.offAllNamed('/auth');
    } catch (e) {
      print('AUTH_SERVICE: Logout error: $e');
      Get.snackbar('Logout Failed', 'Could not complete logout: $e');
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
      print('AUTH_SERVICE: Error checking login status: $e');
      return false;
    }
  }
  
  // Get the seed from mnemonic
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
      
      // Create a BIP32 node from the seed
      final node = bip32.BIP32.fromSeed(seed);
      
      // Derive the first account (m/44'/0'/0'/0/0 path for BIP44)
      // This is a standard derivation path for Bitcoin, but can be adjusted for other chains
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
      print('AUTH_SERVICE: Error deriving keys: $e');
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
      print('AUTH_SERVICE: Error getting keys: $e');
      return {
        'privateKey': 'Error: $e',
        'publicKey': 'Error: $e',
      };
    }
  }
  
  // Get the user ID from secure storage
  Future<String?> getUserId() async {
    try {
      final userId = await _storage.read(key: _userIdKey);
      print('AUTH_SERVICE: Retrieved user ID from storage: $userId');
      return userId;
    } catch (e) {
      print('AUTH_SERVICE: Error retrieving user ID: $e');
      return null;
    }
  }
  
  Future<String?> getPrivateKey() async {
    try {
      // First try to get directly stored private key
      final storedPrivateKey = await _storage.read(key: 'private_key');
      if (storedPrivateKey != null) {
        print('AUTH_SERVICE: Retrieved stored private key');
        return storedPrivateKey;
      }
      
      // Fallback to derivation from seed phrase if no stored key
      if (!await hasSeedPhrase()) {
        print('AUTH_SERVICE: No seed phrase available for private key derivation');
        return null;
      }
      
      // Get the stored seed phrase
      final seedPhrase = await _storage.read(key: _seedPhraseKey);
      if (seedPhrase == null) {
        print('AUTH_SERVICE: Seed phrase read returned null');
        return null;
      }
      
      // Derive keys from seed phrase
      final keys = deriveKeysFromSeedPhrase(seedPhrase);
      
      if (keys['privateKey'] == null || keys['privateKey']!.isEmpty) {
        print('AUTH_SERVICE: Derived private key is null or empty');
        return null;
      }
      
      // Store the derived key for future use
      await _storage.write(key: 'private_key', value: keys['privateKey']);
      print('AUTH_SERVICE: Successfully derived and stored private key');
      return keys['privateKey'];
    } catch (e) {
      print('AUTH_SERVICE: Error getting private key: $e');
      return null;
    }
  }
  

}
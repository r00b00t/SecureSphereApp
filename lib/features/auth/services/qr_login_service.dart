import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/config/api_config.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/core/network/authenticated_client.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class QrLoginService extends GetxService {
  AuthService get _authService => Get.find<AuthService>();
  
  // QR session state
  String? _currentSessionId;
  Timer? _sessionTimer;
  final _sessionTimeout = const Duration(minutes: 5);
  
  // Observable state for UI
  final isSessionActive = false.obs;
  final sessionStatus = Rx<QrSessionStatus>(QrSessionStatus.idle);

  @override
  void onClose() {
    _cancelSession();
    super.onClose();
  }

  /// Generate a new QR code session for desktop login
  Future<String?> generateQrSession() async {
    try {
      // Generate unique session ID
      final sessionId = _generateSessionId();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Create QR payload
      final qrData = jsonEncode({
        'session_id': sessionId,
        'timestamp': timestamp,
        'type': 'qr_login',
        'app': 'securesphere',
      });
      
      // Register session with backend
      final registered = await _registerQrSession(sessionId);
      if (!registered) {
        return null;
      }
      
      _currentSessionId = sessionId;
      isSessionActive.value = true;
      sessionStatus.value = QrSessionStatus.waitingForScan;
      
      // Start polling for authentication
      _startPolling();
      
      // Auto-cancel after timeout
      _sessionTimer = Timer(_sessionTimeout, () {
        _cancelSession();
      });
      
      return qrData;
    } catch (e) {
      return null;
    }
  }

  /// Mobile scans QR and validates with backend
  Future<bool> scanAndValidateQr(String qrData) async {
    try {
      final data = jsonDecode(qrData) as Map<String, dynamic>;
      final sessionId = data['session_id'] as String?;
      final timestamp = data['timestamp'] as int?;
      final type = data['type'] as String?;
      
      // Validate QR data
      if (sessionId == null || timestamp == null || type != 'qr_login') {
        return false;
      }
      
      // Check if QR is not expired (5 minutes)
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > 5 * 60 * 1000) {
        return false;
      }
      
      // Get user's public key for authentication
      final userId = await _authService.getUserId();
      if (userId == null) {
        return false;
      }
      
      // Try to get seed phrase or derive public key
      
      // Try getPrivateKey first - it handles fallbacks internally
      final privateKey = await _authService.getPrivateKey();
      if (privateKey == null || privateKey.isEmpty) {
        return false;
      }
      
      // Get the seed phrase to derive public key (private key exists means seed phrase should too)
      final seedPhrase = await _authService.getStoredSeedPhrase();
      if (seedPhrase == null || seedPhrase.isEmpty) {
        return false;
      }
      
      // Derive public key from seed phrase
      final keys = _authService.deriveKeysFromSeedPhrase(seedPhrase);
      final publicKey = keys['publicKey'];
      
      if (publicKey == null || publicKey.isEmpty) {
        return false;
      }
      
      
      // Authenticate the QR session with mobile device
      // Include seed phrase so desktop can decrypt backups
      final authenticated = await _authenticateQrSession(
        sessionId,
        userId,
        publicKey,
        seedPhrase,
      );
      
      // Don't show snackbar here - let the UI handle it
      
      return authenticated;
    } catch (e) {
      // Don't show snackbar here - let the UI handle error display
      return false;
    }
  }

  /// Register QR session with backend
  Future<bool> _registerQrSession(String sessionId) async {
    try {
      final url = Uri.parse('${ApiConfig.psqlBaseUrl}/qr-auth/create-session');
      final headers = await _authService.getAuthHeaders();
      final response = await Get.find<AuthenticatedClient>()
          .post(url, headers: headers, body: jsonEncode({
            'session_id': sessionId,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }))
          .timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  /// Authenticate QR session from mobile device
  Future<bool> _authenticateQrSession(
    String sessionId,
    String userId,
    String publicKey,
    String seedPhrase,
  ) async {
    try {
      final url = Uri.parse('${ApiConfig.psqlBaseUrl}/qr-auth/authenticate');
      final headers = await _authService.getAuthHeaders();
      final response = await Get.find<AuthenticatedClient>()
          .post(url, headers: headers, body: jsonEncode({
            'session_id': sessionId,
            'user_id': userId,
            'public_key': publicKey,
            'seed_phrase': seedPhrase,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }))
          .timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  /// Poll backend for authentication status (desktop)
  void _startPolling() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!isSessionActive.value || _currentSessionId == null) {
        timer.cancel();
        return;
      }
      
      _checkAuthenticationStatus();
    });
  }

  /// Check if mobile has authenticated the session
  Future<void> _checkAuthenticationStatus() async {
    if (_currentSessionId == null) return;
    
    try {
      final url = Uri.parse(
        '${ApiConfig.psqlBaseUrl}/qr-auth/check-status/$_currentSessionId',
      );
      final headers = await _authService.getAuthHeaders();
      final response = await Get.find<AuthenticatedClient>()
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['status'] as String?;
        final userId = data['user_id'] as String?;
        final publicKey = data['public_key'] as String?;
        final seedPhrase = data['seed_phrase'] as String?;
        
        if (status == 'authenticated' && userId != null && publicKey != null && seedPhrase != null) {
          sessionStatus.value = QrSessionStatus.authenticated;
          
          // Login the desktop user with seed phrase
          await _loginDesktopUser(userId, publicKey, seedPhrase);
          
          _cancelSession();
        } else if (status == 'authenticated') {
        }
      }
    } catch (e) {
    }
  }

  /// Complete desktop login after mobile authentication
  Future<void> _loginDesktopUser(String userId, String publicKey, String seedPhrase) async {
    try {
      sessionStatus.value = QrSessionStatus.loggingIn;
      
      // Store user credentials using secure storage
      final storage = const FlutterSecureStorage(
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
      await storage.write(key: 'user_id', value: userId);
      await storage.write(key: 'seed_phrase', value: seedPhrase); // Store seed phrase for backup decryption
      
      // Also derive and store the private key
      final keys = _authService.deriveKeysFromSeedPhrase(seedPhrase);
      final privateKey = keys['privateKey'];
      if (privateKey != null) {
        await storage.write(key: 'private_key', value: privateKey);
      }
      
      // Mark as logged in using shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      
      
      // Navigate to home
      Get.offAllNamed('/home');
      
      // Show success message safely after navigation
      Future.delayed(const Duration(milliseconds: 500), () {
        if (Get.context != null) {
          try {
            SnackbarUtils.showSuccess(
              title: 'Success',
              message: 'Logged in successfully via QR code!',
            );
          } catch (e) {
          }
        }
      });
    } catch (e) {
      sessionStatus.value = QrSessionStatus.error;
      // Don't show snackbar here - let the UI observe sessionStatus and display error
    }
  }

  /// Cancel current QR session
  void _cancelSession() {
    _sessionTimer?.cancel();
    _currentSessionId = null;
    isSessionActive.value = false;
    sessionStatus.value = QrSessionStatus.idle;
  }

  /// Generate unique session ID
  String _generateSessionId() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return sha256.convert(values).toString().substring(0, 16);
  }
}

enum QrSessionStatus {
  idle,
  waitingForScan,
  authenticated,
  loggingIn,
  error,
} 

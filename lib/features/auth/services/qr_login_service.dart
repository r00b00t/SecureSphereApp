import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:securesphere/config/api_config.dart';
import 'package:securesphere/features/auth/services/auth_service.dart';

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
        print('QR_LOGIN: Failed to register session with backend');
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
      
      print('QR_LOGIN: Generated session: $sessionId');
      return qrData;
    } catch (e) {
      print('QR_LOGIN: Error generating QR session: $e');
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
        print('QR_LOGIN: Invalid QR data format');
        return false;
      }
      
      // Check if QR is not expired (5 minutes)
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > 5 * 60 * 1000) {
        print('QR_LOGIN: QR code expired');
        return false;
      }
      
      // Get user's public key for authentication
      final userId = await _authService.getUserId();
      if (userId == null) {
        print('QR_LOGIN: User not logged in on mobile');
        return false;
      }
      
      // Try to get seed phrase or derive public key
      print('QR_LOGIN: Attempting to retrieve authentication keys for user $userId');
      
      // Try getPrivateKey first - it handles fallbacks internally
      final privateKey = await _authService.getPrivateKey();
      if (privateKey == null || privateKey.isEmpty) {
        print('QR_LOGIN: Cannot retrieve keys - please log in again with your seed phrase');
        return false;
      }
      
      // Get the seed phrase to derive public key (private key exists means seed phrase should too)
      final seedPhrase = await _authService.getStoredSeedPhrase();
      if (seedPhrase == null || seedPhrase.isEmpty) {
        print('QR_LOGIN: Cannot retrieve seed phrase - please log in again');
        return false;
      }
      
      // Derive public key from seed phrase
      final keys = _authService.deriveKeysFromSeedPhrase(seedPhrase);
      final publicKey = keys['publicKey'];
      
      if (publicKey == null || publicKey.isEmpty) {
        print('QR_LOGIN: Failed to derive public key');
        return false;
      }
      
      print('QR_LOGIN: Successfully retrieved keys for authentication');
      
      // Authenticate the QR session with mobile device
      final authenticated = await _authenticateQrSession(
        sessionId,
        userId,
        publicKey,
      );
      
      // Don't show snackbar here - let the UI handle it
      print('QR_LOGIN: Authentication ${authenticated ? "successful" : "failed"}');
      
      return authenticated;
    } catch (e) {
      print('QR_LOGIN: Error validating QR: $e');
      Get.snackbar('Error', 'Failed to validate QR code: $e');
      return false;
    }
  }

  /// Register QR session with backend
  Future<bool> _registerQrSession(String sessionId) async {
    try {
      final url = Uri.parse('${ApiConfig.psqlBaseUrl}/qr-auth/create-session');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'api-key': ApiConfig.psqlApiKey,
        },
        body: jsonEncode({
          'session_id': sessionId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(const Duration(seconds: 10));
      
      print('QR_LOGIN: Register session response: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('QR_LOGIN: Error registering session: $e');
      return false;
    }
  }

  /// Authenticate QR session from mobile device
  Future<bool> _authenticateQrSession(
    String sessionId,
    String userId,
    String publicKey,
  ) async {
    try {
      final url = Uri.parse('${ApiConfig.psqlBaseUrl}/qr-auth/authenticate');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'api-key': ApiConfig.psqlApiKey,
        },
        body: jsonEncode({
          'session_id': sessionId,
          'user_id': userId,
          'public_key': publicKey,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(const Duration(seconds: 10));
      
      print('QR_LOGIN: Authenticate response: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('QR_LOGIN: Error authenticating session: $e');
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
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'api-key': ApiConfig.psqlApiKey,
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['status'] as String?;
        final userId = data['user_id'] as String?;
        final publicKey = data['public_key'] as String?;
        
        if (status == 'authenticated' && userId != null && publicKey != null) {
          print('QR_LOGIN: Session authenticated! User: $userId');
          sessionStatus.value = QrSessionStatus.authenticated;
          
          // Login the desktop user
          await _loginDesktopUser(userId, publicKey);
          
          _cancelSession();
        }
      }
    } catch (e) {
      print('QR_LOGIN: Error checking status: $e');
    }
  }

  /// Complete desktop login after mobile authentication
  Future<void> _loginDesktopUser(String userId, String publicKey) async {
    try {
      sessionStatus.value = QrSessionStatus.loggingIn;
      
      // Store user credentials using secure storage
      final storage = const FlutterSecureStorage();
      await storage.write(key: 'user_id', value: userId);
      
      // Mark as logged in using shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      
      print('QR_LOGIN: Desktop user logged in via QR');
      
      // Navigate to home
      Get.offAllNamed('/home');
      Get.snackbar(
        'Success',
        'Logged in successfully via QR code!',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      print('QR_LOGIN: Error logging in desktop user: $e');
      sessionStatus.value = QrSessionStatus.error;
      Get.snackbar('Error', 'Failed to complete login: $e');
    }
  }

  /// Cancel current QR session
  void _cancelSession() {
    _sessionTimer?.cancel();
    _currentSessionId = null;
    isSessionActive.value = false;
    sessionStatus.value = QrSessionStatus.idle;
    print('QR_LOGIN: Session cancelled');
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
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DecentralizedService extends GetxService {
  static const _storage = FlutterSecureStorage();

  static const String nodeHostKey = 'node_host';
  static const String nodePortKey = 'node_port';
  static const String nodePasswordKey = 'node_password';
  static const String privateKeyKey = 'decentralized_private_key';
  static const String seedPhraseKey = 'decentralized_seed_phrase';
  static const String userIdKey = 'decentralized_user_id';
  static const String appModeKey = 'app_mode';

  bool _isDecentralized = false;
  bool get isDecentralized => _isDecentralized;

  Future<DecentralizedService> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isDecentralized = (prefs.getString(appModeKey) ?? '') == 'decentralized';
    return this;
  }

  /// Re-read mode from prefs (call after onboarding completes in the same session).
  Future<void> refreshMode() async {
    final prefs = await SharedPreferences.getInstance();
    _isDecentralized = (prefs.getString(appModeKey) ?? '') == 'decentralized';
  }

  Future<Map<String, String>?> getNodeConfig() async {
    final host = await _storage.read(key: nodeHostKey);
    final port = await _storage.read(key: nodePortKey);
    final password = await _storage.read(key: nodePasswordKey);
    if (host == null || port == null || password == null) return null;
    return {'host': host, 'port': port, 'password': password};
  }

  Future<void> saveNodeConfig(String host, String port, String password) async {
    await _storage.write(key: nodeHostKey, value: host);
    await _storage.write(key: nodePortKey, value: port);
    await _storage.write(key: nodePasswordKey, value: password);
  }

  Future<String?> getPrivateKey() async {
    return _storage.read(key: privateKeyKey);
  }

  Future<String?> getSeedPhrase() async {
    return _storage.read(key: seedPhraseKey);
  }

  Future<void> saveKeys(String seedPhrase, String privateKey) async {
    await _storage.write(key: seedPhraseKey, value: seedPhrase);
    await _storage.write(key: privateKeyKey, value: privateKey);
  }

  Future<String?> getUserId() async {
    return _storage.read(key: userIdKey);
  }

  /// Derives a stable 32-char hex identifier from the public key and stores it.
  /// Uses SHA-256 of the public-key bytes; takes the first 32 hex characters.
  Future<String> deriveAndStoreUserId(String publicKeyHex) async {
    final keyBytes = _hexDecode(publicKeyHex);
    final hash = sha256.convert(keyBytes).toString(); // 64 hex chars
    final userId = hash.substring(0, 32);
    await _storage.write(key: userIdKey, value: userId);
    return userId;
  }

  /// Persists all onboarding decisions and marks the session as decentralized.
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(appModeKey, 'decentralized');
    await prefs.setBool('is_logged_in', true);
    await prefs.setBool('onboarding_complete', true);
    // Path A is always self-hosted from the SIA service perspective
    await prefs.setString('backupOption', 'Self-Hosted SIA Node');
    _isDecentralized = true;
  }

  Future<void> importFromPairing({
    required String seedPhrase,
    required String privateKey,
    required String publicKey,
    required String host,
    required String port,
    required String password,
  }) async {
    await saveKeys(seedPhrase, privateKey);
    await saveNodeConfig(host, port, password);
    await deriveAndStoreUserId(publicKey);
    await completeOnboarding();
  }

  Future<void> clearAll() async {
    await _storage.delete(key: nodeHostKey);
    await _storage.delete(key: nodePortKey);
    await _storage.delete(key: nodePasswordKey);
    await _storage.delete(key: privateKeyKey);
    await _storage.delete(key: seedPhraseKey);
    await _storage.delete(key: userIdKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(appModeKey);
    _isDecentralized = false;
  }

  static Uint8List _hexDecode(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length - 1; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }
}

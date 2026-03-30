import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/decentralized/services/decentralized_service.dart';
import 'package:decvault/features/sia/services/sia_service.dart';

class ImportDevicePairingScreen extends StatefulWidget {
  const ImportDevicePairingScreen({super.key});

  @override
  State<ImportDevicePairingScreen> createState() =>
      _ImportDevicePairingScreenState();
}

class _ImportDevicePairingScreenState
    extends State<ImportDevicePairingScreen> {
  static const int _pbkdf2Iterations = 100000;

  _ImportMode _mode = _ImportMode.choosing;

  // QR / paste path
  String? _scannedPayload; // raw base64 string
  final _pasteController = TextEditingController();
  final _qrPinController = TextEditingController();
  bool _qrPinVisible = false;
  String? _qrError;
  bool _qrDecrypting = false;
  MobileScannerController? _scannerController;

  // Manual path
  final _seedController = TextEditingController();
  final _manualHostController = TextEditingController();
  final _manualPortController = TextEditingController(text: '9980');
  final _manualPasswordController = TextEditingController();
  final _manualFormKey = GlobalKey<FormState>();
  bool _manualPasswordVisible = false;
  bool _manualTesting = false;
  bool _manualConnectionOk = false;
  String? _manualConnectionMessage;
  bool _manualSaving = false;
  bool _isOnboarding = true;

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
  }

  Future<void> _loadOnboardingState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isOnboarding = !(prefs.getBool('onboarding_complete') ?? false);
    });
  }

  void _handleBack() {
    if (_isOnboarding) {
      Get.offAllNamed('/auth');
    } else {
      Get.back();
    }
  }

  @override
  void dispose() {
    _pasteController.dispose();
    _qrPinController.dispose();
    _seedController.dispose();
    _manualHostController.dispose();
    _manualPortController.dispose();
    _manualPasswordController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  static Uint8List _pbkdf2(
      String password, Uint8List salt, int iterations, int dkLen) {
    final passwordBytes = utf8.encode(password);
    final mac = Hmac(sha256, passwordBytes);
    const hLen = 32;
    final blockCount = (dkLen / hLen).ceil();
    final dk = <int>[];

    for (var i = 1; i <= blockCount; i++) {
      final iBytes = ByteData(4)..setUint32(0, i, Endian.big);
      var u = mac.convert([...salt, ...iBytes.buffer.asUint8List()]).bytes;
      final t = List<int>.from(u);
      for (var j = 1; j < iterations; j++) {
        u = mac.convert(u).bytes;
        for (var k = 0; k < hLen; k++) {
          t[k] ^= u[k];
        }
      }
      dk.addAll(t);
    }
    return Uint8List.fromList(dk.sublist(0, dkLen));
  }

  Map<String, String> _deriveKeys(String seedPhrase) {
    final seed = bip39.mnemonicToSeed(seedPhrase);
    final node = bip32.BIP32.fromSeed(seed);
    final child = node.derivePath("m/44'/0'/0'/0/0");
    return {
      'privateKey': HEX.encode(child.privateKey!),
      'publicKey': HEX.encode(child.publicKey),
    };
  }

  Future<void> _decryptAndImport(String base64Payload, String pin) async {
    setState(() {
      _qrDecrypting = true;
      _qrError = null;
    });

    try {
      // 1. Base64-decode outer JSON
      late Map<String, dynamic> outer;
      try {
        outer = jsonDecode(utf8.decode(base64Decode(base64Payload)))
            as Map<String, dynamic>;
      } catch (_) {
        throw const FormatException('Invalid QR code format');
      }

      final saltB64 = outer['salt'] as String?;
      final ivB64 = outer['iv'] as String?;
      final ciphertextB64 = outer['ciphertext'] as String?;

      if (saltB64 == null || ivB64 == null || ciphertextB64 == null) {
        throw const FormatException('Incomplete QR payload');
      }

      final salt = base64Decode(saltB64);
      final ivBytes = base64Decode(ivB64);

      // 2. Derive key using PBKDF2
      final aesKey = await Future(
          () => _pbkdf2(pin, Uint8List.fromList(salt), _pbkdf2Iterations, 32));

      // 3. Decrypt
      late String innerJson;
      try {
        final key = enc.Key(aesKey);
        final iv = enc.IV(Uint8List.fromList(ivBytes));
        final encrypter = enc.Encrypter(enc.AES(key));
        final encrypted = enc.Encrypted.fromBase64(ciphertextB64);
        innerJson = encrypter.decrypt(encrypted, iv: iv);
      } catch (_) {
        throw const FormatException('Invalid QR code or wrong PIN');
      }

      // 4. Parse inner JSON
      late Map<String, dynamic> inner;
      try {
        inner = jsonDecode(innerJson) as Map<String, dynamic>;
      } catch (_) {
        throw const FormatException('Invalid QR code or wrong PIN');
      }

      final seedPhrase = inner['seed_phrase'] as String?;
      final host = inner['node_host'] as String?;
      final port = inner['node_port'] as String?;
      final password = inner['node_password'] as String?;

      if (seedPhrase == null || host == null || port == null || password == null) {
        throw const FormatException('Incomplete data in QR code');
      }

      // 5. Derive keys from seed phrase
      if (!bip39.validateMnemonic(seedPhrase)) {
        throw const FormatException('Invalid seed phrase in QR code');
      }
      final keys = _deriveKeys(seedPhrase);

      // 6. Test connection to node
      await _testNodeConnection(host, port, password);

      // 7. Store everything and complete onboarding
      final decSvc = Get.find<DecentralizedService>();
      await decSvc.importFromPairing(
        seedPhrase: seedPhrase,
        privateKey: keys['privateKey']!,
        publicKey: keys['publicKey']!,
        host: host,
        port: port,
        password: password,
      );

      // Reload SiaService so _currentConfig reflects the imported node config.
      try {
        final siaService = Get.find<SiaService>();
        await siaService.loadSiaConfiguration();
      } catch (_) {}

      try {
        final secSvc = Get.find<SecurityService>();
        await secSvc.markInitialSetupComplete();
      } catch (_) {}

      Get.offAllNamed('/home');
    } on FormatException catch (e) {
      setState(() => _qrError = e.message);
    } catch (e) {
      setState(() => _qrError = e.toString());
    } finally {
      if (mounted) setState(() => _qrDecrypting = false);
    }
  }

  Future<void> _testNodeConnection(
      String host, String port, String password) async {
    final url = Uri.parse('http://$host:$port/api/bus/state');
    final credentials = base64Encode(utf8.encode(':$password'));
    final response = await http.get(
      url,
      headers: {'Authorization': 'Basic $credentials'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception(
          'Node connection failed (HTTP ${response.statusCode}). '
          'Check the node is running and credentials are correct.');
    }
  }

  Future<void> _testManualConnection() async {
    if (!_manualFormKey.currentState!.validate()) return;

    setState(() {
      _manualTesting = true;
      _manualConnectionMessage = null;
      _manualConnectionOk = false;
    });

    try {
      await _testNodeConnection(
        _manualHostController.text.trim(),
        _manualPortController.text.trim(),
        _manualPasswordController.text,
      );
      setState(() {
        _manualConnectionOk = true;
        _manualConnectionMessage = 'Connection successful.';
      });
    } catch (e) {
      setState(() {
        _manualConnectionMessage = e.toString();
      });
    } finally {
      setState(() => _manualTesting = false);
    }
  }

  Future<void> _saveManual() async {
    if (!_manualConnectionOk) {
      Get.snackbar('Test first',
          'Please test the connection before saving.');
      return;
    }

    final phrase = _seedController.text.trim();
    if (!bip39.validateMnemonic(phrase)) {
      Get.snackbar('Invalid seed phrase',
          'The seed phrase you entered is not valid BIP39.');
      return;
    }

    setState(() => _manualSaving = true);
    try {
      final keys = _deriveKeys(phrase);
      final decSvc = Get.find<DecentralizedService>();
      await decSvc.importFromPairing(
        seedPhrase: phrase,
        privateKey: keys['privateKey']!,
        publicKey: keys['publicKey']!,
        host: _manualHostController.text.trim(),
        port: _manualPortController.text.trim(),
        password: _manualPasswordController.text,
      );

      // Reload SiaService so _currentConfig reflects the imported node config.
      try {
        final siaService = Get.find<SiaService>();
        await siaService.loadSiaConfiguration();
      } catch (_) {}

      try {
        final secSvc = Get.find<SecurityService>();
        await secSvc.markInitialSetupComplete();
      } catch (_) {}

      Get.offAllNamed('/home');
    } catch (e) {
      Get.snackbar('Error', 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _manualSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F0F0F),
                Color(0xFF1A1A1A),
                Color(0xFF0F0F0F),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    _buildBrandingPanel(),
                    if (_isOnboarding)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios,
                              color: Colors.white70, size: 20),
                          onPressed: _handleBack,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                  margin: const EdgeInsets.all(24),
                  child: Card(
                    elevation: 8,
                    color: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_mode != _ImportMode.choosing)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: () => setState(() {
                                    _mode = _ImportMode.choosing;
                                    _scannedPayload = null;
                                    _qrError = null;
                                  }),
                                ),
                              ),
                            _buildBody(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Configuration'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: _mode != _ImportMode.choosing
              ? () => setState(() {
                    _mode = _ImportMode.choosing;
                    _scannedPayload = null;
                    _qrError = null;
                  })
              : _handleBack,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _ImportMode.choosing:
        return _buildChooser();
      case _ImportMode.qr:
        return _buildQrPath();
      case _ImportMode.manual:
        return _buildManualPath();
    }
  }

  // ── Mode chooser ───────────────────────────────────────────────────────────

  Widget _buildChooser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.devices_outlined, size: 56, color: Color(0xFF1E8E3E)),
        const SizedBox(height: 16),
        const Text(
          'Import from another device',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'How would you like to import?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),

        if (!_isDesktop)
          _OptionTile(
            icon: Icons.qr_code_scanner,
            title: 'Scan QR code',
            subtitle: 'Scan the QR shown on your other device',
            onTap: () => setState(() => _mode = _ImportMode.qr),
          ),

        if (_isDesktop)
          _OptionTile(
            icon: Icons.content_paste_outlined,
            title: 'Paste QR text',
            subtitle:
                'Paste the text copied from the other device\'s "Copy as text" button',
            onTap: () => setState(() => _mode = _ImportMode.qr),
          ),

        const SizedBox(height: 16),

        _OptionTile(
          icon: Icons.keyboard_outlined,
          title: 'Enter seed phrase manually',
          subtitle: 'Type your 12-word seed phrase and node config',
          onTap: () => setState(() => _mode = _ImportMode.manual),
        ),
      ],
    );
  }

  // ── QR / paste path ────────────────────────────────────────────────────────

  Widget _buildQrPath() {
    // If we haven't captured a payload yet, show scanner or paste field
    if (_scannedPayload == null) {
      return _isDesktop ? _buildPasteField() : _buildScanner();
    }
    // Payload captured — ask for PIN
    return _buildPinEntry();
  }

  Widget _buildScanner() {
    _scannerController ??= MobileScannerController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Scan the QR code shown on your other device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _scannerController!,
              onDetect: (capture) {
                final barcode = capture.barcodes.first;
                final raw = barcode.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _scannerController?.stop();
                  setState(() => _scannedPayload = raw);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paste the text from the other device\'s "Copy as text" button.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _pasteController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Paste QR payload here',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            final text = _pasteController.text.trim();
            if (text.isEmpty) {
              Get.snackbar('Empty', 'Please paste the QR payload text first.');
              return;
            }
            setState(() => _scannedPayload = text);
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildPinEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.pin_outlined, size: 56, color: Color(0xFF1E8E3E)),
        const SizedBox(height: 16),
        const Text(
          'Enter the 6-digit PIN',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter the PIN shown on the other device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _qrPinController,
          obscureText: !_qrPinVisible,
          maxLength: 6,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '6-digit pairing PIN',
            prefixIcon: const Icon(Icons.pin),
            errorText: _qrError,
            suffixIcon: IconButton(
              icon: Icon(
                  _qrPinVisible ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _qrPinVisible = !_qrPinVisible),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_qrDecrypting)
          const Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Decrypting… this may take a moment.',
                  style: TextStyle(color: Colors.grey)),
            ],
          )
        else
          ElevatedButton(
            onPressed: () {
              final pin = _qrPinController.text.trim();
              if (pin.length != 6) {
                setState(() => _qrError = 'Enter the 6-digit PIN');
                return;
              }
              _decryptAndImport(_scannedPayload!, pin);
            },
            child: const Text('Import'),
          ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _scannedPayload = null;
            _qrError = null;
            _qrPinController.clear();
            _scannerController?.dispose();
            _scannerController = null;
          }),
          child: const Text('Scan again'),
        ),
      ],
    );
  }

  // ── Manual path ────────────────────────────────────────────────────────────

  Widget _buildManualPath() {
    return Form(
      key: _manualFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.keyboard_outlined,
              size: 48, color: Color(0xFF1E8E3E)),
          const SizedBox(height: 16),
          const Text(
            'Enter your seed phrase and node config.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Seed phrase
          TextFormField(
            controller: _seedController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '12-word seed phrase',
              hintText: 'word1 word2 word3 ... word12',
              alignLabelWithHint: true,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (!bip39.validateMnemonic(v.trim())) {
                return 'Not a valid BIP39 seed phrase';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Host
          TextFormField(
            controller: _manualHostController,
            decoration: const InputDecoration(
              labelText: 'Host',
              prefixIcon: Icon(Icons.computer_outlined),
            ),
            keyboardType: TextInputType.url,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Required'
                : null,
          ),
          const SizedBox(height: 12),

          // Port
          TextFormField(
            controller: _manualPortController,
            decoration: const InputDecoration(
              labelText: 'Port',
              prefixIcon: Icon(Icons.settings_ethernet),
            ),
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final n = int.tryParse(v.trim());
              if (n == null || n < 1 || n > 65535) {
                return 'Invalid port';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // Password
          TextFormField(
            controller: _manualPasswordController,
            obscureText: !_manualPasswordVisible,
            decoration: InputDecoration(
              labelText: 'API Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_manualPasswordVisible
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () => setState(
                    () => _manualPasswordVisible = !_manualPasswordVisible),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          // Connection status
          if (_manualConnectionMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _manualConnectionOk
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _manualConnectionOk
                      ? Colors.green.withOpacity(0.4)
                      : Colors.red.withOpacity(0.4),
                ),
              ),
              child: Text(
                _manualConnectionMessage!,
                style: TextStyle(
                  color: _manualConnectionOk
                      ? Colors.green
                      : Colors.redAccent,
                ),
              ),
            ),

          OutlinedButton.icon(
            onPressed: _manualTesting ? null : _testManualConnection,
            icon: _manualTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: Text(
                _manualTesting ? 'Testing...' : 'Test Connection'),
          ),
          const SizedBox(height: 12),

          ElevatedButton(
            onPressed: (_manualConnectionOk && !_manualSaving)
                ? _saveManual
                : null,
            child: _manualSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Import'),
          ),
        ],
      ),
    );
  }
  Widget _buildBrandingPanel() {
    return Container(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.security,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 20),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DecVault',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Desktop Edition',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 48),
          const Text(
            'Secure Password Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          ...[
            'Decentralized with seed phrase authentication',
            'End-to-end encryption for all your data',
            'Secure file vault with Sia network backup',
            'Cross-platform sync and accessibility',
            'Desktop-optimized productivity features',
          ].map((feature) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34A853).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF34A853),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    feature,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Enter • Proceed\nTab • Switch mode\nEsc • Go back',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widget ─────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1E8E3E), size: 32),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
      ),
    );
  }
}

enum _ImportMode { choosing, qr, manual }

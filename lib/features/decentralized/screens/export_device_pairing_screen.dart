import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:decvault/features/auth/screens/pin_setup_screen.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/decentralized/services/decentralized_service.dart';

class ExportDevicePairingScreen extends StatefulWidget {
  const ExportDevicePairingScreen({super.key});

  @override
  State<ExportDevicePairingScreen> createState() =>
      _ExportDevicePairingScreenState();
}

class _ExportDevicePairingScreenState
    extends State<ExportDevicePairingScreen> {
  static const int _countdownSeconds = 60;
  static const int _pbkdf2Iterations = 100000;

  // State machine
  _ExportState _state = _ExportState.checkingPin;

  // PIN confirmation
  final _pinController = TextEditingController();
  bool _pinVisible = false;
  String? _pinError;

  // QR generation
  String? _pairingPin; // 6-digit string shown to user
  String? _qrPayload; // base64-encoded outer JSON
  int _secondsLeft = _countdownSeconds;
  Timer? _countdownTimer;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _checkPinStatus();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _checkPinStatus() async {
    try {
      final secSvc = Get.find<SecurityService>();
      final hasPin = await secSvc.hasPinSet();
      setState(() {
        _state =
            hasPin ? _ExportState.confirmingPin : _ExportState.noPinSet;
      });
    } catch (_) {
      setState(() => _state = _ExportState.noPinSet);
    }
  }

  Future<void> _verifyPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _pinError = 'Enter your 6-digit PIN');
      return;
    }
    try {
      final secSvc = Get.find<SecurityService>();
      final ok = await secSvc.verifyPinCode(pin);
      if (ok) {
        setState(() {
          _pinError = null;
          _state = _ExportState.showingQr;
        });
        _generate();
      } else {
        setState(() => _pinError = 'Incorrect PIN');
      }
    } catch (e) {
      setState(() => _pinError = 'Error verifying PIN: $e');
    }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    _countdownTimer?.cancel();

    try {
      final decSvc = Get.find<DecentralizedService>();
      final seedPhrase = await decSvc.getSeedPhrase();
      final nodeConfig = await decSvc.getNodeConfig();

      if (seedPhrase == null || nodeConfig == null) {
        Get.snackbar('Error',
            'Could not read seed phrase or node config from secure storage.');
        return;
      }

      // Generate a random 6-digit pairing PIN (100000–999999)
      final random = Random.secure();
      final pairingPin =
          (100000 + random.nextInt(900000)).toString();

      // Build the inner plaintext JSON
      final innerJson = jsonEncode({
        'seed_phrase': seedPhrase,
        'node_host': nodeConfig['host'],
        'node_port': nodeConfig['port'],
        'node_password': nodeConfig['password'],
        'version': 1,
      });

      // Generate random 16-byte salt and IV
      final salt = Uint8List.fromList(
          List.generate(16, (_) => random.nextInt(256)));
      final ivBytes = Uint8List.fromList(
          List.generate(16, (_) => random.nextInt(256)));

      // Derive AES-256 key from pairing PIN using PBKDF2-HMAC-SHA256
      final aesKey = await Future(
          () => _pbkdf2(pairingPin, salt, _pbkdf2Iterations, 32));

      // Encrypt using AES-256-CBC
      final key = enc.Key(aesKey);
      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(key));
      final encrypted = encrypter.encrypt(innerJson, iv: iv);

      // Build outer JSON: salt + iv + ciphertext
      final outerJson = jsonEncode({
        'salt': base64Encode(salt),
        'iv': base64Encode(ivBytes),
        'ciphertext': encrypted.base64,
      });

      final qrPayload = base64Encode(utf8.encode(outerJson));

      setState(() {
        _pairingPin = pairingPin;
        _qrPayload = qrPayload;
        _secondsLeft = _countdownSeconds;
        _generating = false;
      });

      _startCountdown();
    } catch (e) {
      setState(() => _generating = false);
      Get.snackbar('Error', 'Failed to generate QR code: $e');
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _generate(); // Auto-regenerate with new PIN after expiry
      }
    });
  }

  Future<void> _copyPayload() async {
    if (_qrPayload == null) return;
    await Clipboard.setData(ClipboardData(text: _qrPayload!));
    Get.snackbar('Copied', 'QR payload copied to clipboard',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Device')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ExportState.checkingPin:
        return const Center(child: CircularProgressIndicator());

      case _ExportState.noPinSet:
        return _buildNoPinView();

      case _ExportState.confirmingPin:
        return _buildPinConfirmView();

      case _ExportState.showingQr:
        return _buildQrView();
    }
  }

  // ── No PIN set ─────────────────────────────────────────────────────────────

  Widget _buildNoPinView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.lock_open_outlined, size: 64, color: Colors.orange),
        const SizedBox(height: 24),
        const Text(
          'PIN Required',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'You need to set a PIN before exporting. This protects your seed '
          'phrase during device transfer.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          icon: const Icon(Icons.pin),
          label: const Text('Set PIN'),
          onPressed: () async {
            await Get.to(() => const PinSetupScreen(
                  isOptional: false,
                  title: 'Set a PIN to protect your export',
                ));
            // Re-check after returning from PIN setup
            _checkPinStatus();
          },
        ),
      ],
    );
  }

  // ── PIN confirmation ───────────────────────────────────────────────────────

  Widget _buildPinConfirmView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.verified_user_outlined,
            size: 64, color: Color(0xFF1E8E3E)),
        const SizedBox(height: 24),
        const Text(
          'Confirm Your PIN',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Enter your app PIN to unlock the export.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _pinController,
          obscureText: !_pinVisible,
          maxLength: 6,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'PIN',
            prefixIcon: const Icon(Icons.pin),
            errorText: _pinError,
            suffixIcon: IconButton(
              icon: Icon(
                  _pinVisible ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _pinVisible = !_pinVisible),
            ),
          ),
          onFieldSubmitted: (_) => _verifyPin(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _verifyPin,
          child: const Text('Confirm'),
        ),
      ],
    );
  }

  // ── QR display ─────────────────────────────────────────────────────────────

  Widget _buildQrView() {
    if (_generating) {
      return const Column(
        children: [
          SizedBox(height: 80),
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Generating secure QR code...',
              style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    if (_qrPayload == null || _pairingPin == null) {
      return const SizedBox.shrink();
    }

    // Countdown colour
    final countdownColor = _secondsLeft <= 10
        ? Colors.red
        : (_secondsLeft <= 30 ? Colors.orange : Colors.green);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Instructions
        const Text(
          'Show this screen to your other device',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'On the other device, choose "I already set up on another device" '
          'and scan this QR code. You will also need the PIN shown below.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // QR code (desktop shows a message instead if this is too large)
        Center(
          child: QrImageView(
            data: _qrPayload!,
            version: QrVersions.auto,
            size: 240,
            backgroundColor: Colors.white,
            errorStateBuilder: (ctx, _) => const SizedBox(
              width: 240,
              height: 240,
              child: Center(
                  child: Text(
                'QR too large.\nUse "Copy as text" instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              )),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Copy as text (useful on desktop and when QR is too large)
        OutlinedButton.icon(
          onPressed: _copyPayload,
          icon: const Icon(Icons.content_copy, size: 16),
          label: const Text('Copy as text'),
        ),
        const SizedBox(height: 24),

        // Pairing PIN display
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3C4043)),
          ),
          child: Column(
            children: [
              const Text(
                'Show this PIN on your other device',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                _pairingPin!,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 10,
                  color: Color(0xFF34A853),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Countdown
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, color: countdownColor, size: 20),
            const SizedBox(width: 6),
            Text(
              'Refreshes in $_secondsLeft s',
              style: TextStyle(color: countdownColor, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Regenerate now'),
        ),
      ],
    );
  }
}

enum _ExportState { checkingPin, noPinSet, confirmingPin, showingQr }

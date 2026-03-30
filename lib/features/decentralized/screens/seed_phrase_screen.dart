import 'dart:io';
import 'package:bip32/bip32.dart' as bip32;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hex/hex.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/decentralized/services/decentralized_service.dart';
import 'package:decvault/features/sia/services/sia_service.dart';

class DecentralizedSeedPhraseScreen extends StatefulWidget {
  const DecentralizedSeedPhraseScreen({super.key});

  @override
  State<DecentralizedSeedPhraseScreen> createState() =>
      _DecentralizedSeedPhraseScreenState();
}

class _DecentralizedSeedPhraseScreenState
    extends State<DecentralizedSeedPhraseScreen> {
  late final String _seedPhrase;
  late final List<String> _words;
  bool _confirmed = false;
  bool _saving = false;
  bool _isOnboarding = true;

  @override
  void initState() {
    super.initState();
    _seedPhrase = bip39.generateMnemonic();
    _words = _seedPhrase.split(' ');
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

  Map<String, String> _deriveKeys(String seedPhrase) {
    final seed = bip39.mnemonicToSeed(seedPhrase);
    final node = bip32.BIP32.fromSeed(seed);
    final child = node.derivePath("m/44'/0'/0'/0/0");
    return {
      'privateKey': HEX.encode(child.privateKey!),
      'publicKey': HEX.encode(child.publicKey),
    };
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      final keys = _deriveKeys(_seedPhrase);
      final decSvc = Get.find<DecentralizedService>();

      await decSvc.saveKeys(_seedPhrase, keys['privateKey']!);
      await decSvc.deriveAndStoreUserId(keys['publicKey']!);
      await decSvc.completeOnboarding();

      // Reload SiaService so it picks up the node config written during this
      // session (init() ran before onboarding completed, so _currentConfig is stale).
      try {
        final siaService = Get.find<SiaService>();
        await siaService.loadSiaConfiguration();
      } catch (_) {}

      // Mark initial setup complete so SecurityService stops blocking.
      try {
        final secSvc = Get.find<SecurityService>();
        await secSvc.markInitialSetupComplete();
      } catch (_) {}

      Get.offAllNamed('/home');
    } catch (e) {
      Get.snackbar('Error', 'Failed to save keys: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _seedPhrase));
    Get.snackbar('Copied', 'Seed phrase copied to clipboard',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    final bodyChildren = <Widget>[
            // Warning banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Write these words down in order. If you lose them you '
                      'will permanently lose access to your data. We cannot '
                      'recover them for you.',
                      style: TextStyle(color: Colors.orange, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Word grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _words.length,
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF3C4043)),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: '${index + 1}. ',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      TextSpan(
                        text: _words[index],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Copy button
            OutlinedButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy to clipboard'),
            ),
            const SizedBox(height: 24),

            // Confirmation checkbox
            CheckboxListTile(
              value: _confirmed,
              onChanged: (v) => setState(() => _confirmed = v ?? false),
              title: const Text(
                'I have written down my seed phrase',
                style: TextStyle(fontSize: 15),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),

            // Continue button
            ElevatedButton(
              onPressed: (_confirmed && !_saving) ? _continue : null,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Continue'),
            ),
    ];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: bodyChildren,
    );
    if (isDesktop) {
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
                        child: body,
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
        title: const Text('Your Seed Phrase'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: _handleBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: body,
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

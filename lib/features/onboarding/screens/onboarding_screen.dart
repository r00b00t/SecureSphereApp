import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static bool get _isDesktop {
    if (kIsWeb) return false;
    try {
      return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    } catch (_) {
      return false;
    }
  }

  Future<void> _chooseManagedPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'managed');
    await prefs.setBool('onboarding_complete', true);
    Get.offAllNamed('/auth');
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  vertical: 60.0, horizontal: 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._buildHeader(desktop: true),
                  const SizedBox(height: 40),
                  ..._buildOptionCards(desktop: true),
                  const SizedBox(height: 40),
                  const Text(
                    'You can change this later in Settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              ..._buildHeader(desktop: false),
              const Spacer(),
              ..._buildOptionCards(desktop: false),
              const Spacer(),
              const Text(
                'You can change this later in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildHeader({required bool desktop}) {
    return [
      Icon(Icons.lock_outline,
          size: desktop ? 80 : 72, color: const Color(0xFF1E8E3E)),
      SizedBox(height: desktop ? 32 : 24),
      Text(
        'Welcome to DecVault',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: desktop ? 32 : 28, fontWeight: FontWeight.bold),
      ),
      SizedBox(height: desktop ? 16 : 12),
      Text(
        'Choose how you want to use DecVault.',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: desktop ? 17 : 16, color: Colors.grey),
      ),
    ];
  }

  List<Widget> _buildOptionCards({required bool desktop}) {
    final gap = SizedBox(height: desktop ? 20 : 16);
    return [
      _OptionCard(
        icon: Icons.dns_outlined,
        iconColor: const Color(0xFF1E8E3E),
        title: 'I have a Sia node',
        subtitle:
            'Fully decentralized. Your data stays on your own renterd '
            'node. No account, no backend.',
        onTap: () => Get.toNamed('/decentralized-node-setup'),
        desktop: desktop,
      ),
      gap,
      _OptionCard(
        icon: Icons.cloud_outlined,
        iconColor: const Color(0xFF4285F4),
        title: 'Set it up for me',
        subtitle:
            'Use the DecVault managed node. Quick setup, account required.',
        onTap: _chooseManagedPath,
        desktop: desktop,
      ),
      gap,
      _OptionCard(
        icon: Icons.devices_outlined,
        iconColor: const Color(0xFFF57C00),
        title: 'I already set up on another device',
        subtitle:
            'Import your configuration by scanning a QR code or entering '
            'your seed phrase.',
        onTap: () => Get.toNamed('/device-pairing-import'),
        desktop: desktop,
      ),
    ];
  }
}

// ── Option card ──────────────────────────────────────────────────────────────

class _OptionCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool desktop;

  const _OptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.desktop,
  });

  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  bool _hovered = false;

  Widget _buildContent() {
    return Padding(
      padding: EdgeInsets.all(widget.desktop ? 24.0 : 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon,
              size: widget.desktop ? 40 : 36, color: widget.iconColor),
          SizedBox(width: widget.desktop ? 20 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                      fontSize: widget.desktop ? 17 : 16,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: widget.desktop ? 8 : 6),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                      fontSize: widget.desktop ? 13.5 : 13,
                      color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.arrow_forward_ios,
            size: widget.desktop ? 18 : 16,
            color: _hovered ? const Color(0xFF1E8E3E) : Colors.grey,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.desktop) {
      return Card(
        elevation: 2,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          child: _buildContent(),
        ),
      );
    }

    // Desktop: hover-aware animated card
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color:
                _hovered ? const Color(0xFF252525) : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? const Color(0xFF1E8E3E)
                  : const Color(0xFF3C4043),
              width: _hovered ? 1.5 : 1.0,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: const Color(0xFF1E8E3E).withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: _buildContent(),
        ),
      ),
    );
  }
}

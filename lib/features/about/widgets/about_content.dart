import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutContent extends StatefulWidget {
  final bool isDesktop;

  const AboutContent({super.key, this.isDesktop = false});

  @override
  State<AboutContent> createState() => _AboutContentState();
}

class _AboutContentState extends State<AboutContent> {
  String _appVersion = '';
  bool _isLoadingVersion = true;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version}+${info.buildNumber}';
        _isLoadingVersion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = 'Unavailable';
        _isLoadingVersion = false;
      });
    }
  }

  Future<void> _launchLink(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open link. Please try again later.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bodyColor = Colors.white.withOpacity(0.85);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About DecVault',
          style: textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'DecVault is a secure, privacy-first password manager built for multi-platform use. '
          'Easily organize your passwords, encrypted files, and breach monitoring from one protected workspace.',
          style: textTheme.bodyMedium?.copyWith(color: bodyColor, height: 1.4),
        ),
        const SizedBox(height: 24),
        _buildInfoCard(
          context,
          title: 'App Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Version', _isLoadingVersion ? 'Loading…' : _appVersion),
              const SizedBox(height: 12),
              _buildDetailRow('Channel', widget.isDesktop ? 'Desktop' : 'Mobile'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildInfoCard(
          context,
          title: 'Policies',
          child: Column(
            children: [
              _buildLinkTile(
                context,
                label: 'Privacy Policy',
                subtitle: 'Understand how we protect your data',
                icon: Icons.privacy_tip_outlined,
                onTap: () => _launchLink('https://decvault.com/privacy-policy'),
              ),
              const Divider(color: Color(0x13FFFFFF), height: 0),
              _buildLinkTile(
                context,
                label: 'Terms of Service',
                subtitle: 'Review your rights & responsibilities',
                icon: Icons.library_books_outlined,
                onTap: () => _launchLink('https://decvault.com/terms'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildInfoCard(
          context,
          title: 'Need help?',
          child: Text(
            'Visit decvault.com/support for onboarding guides, troubleshooting steps, and release notes.',
            style: textTheme.bodyMedium?.copyWith(color: bodyColor, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context, {required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLinkTile(
    BuildContext context, {
    required String label,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withOpacity(0.6)),
      ),
      trailing: const Icon(Icons.arrow_outward, color: Colors.white54),
      onTap: onTap,
    );
  }
}


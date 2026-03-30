import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/common/widgets/custom_title_bar.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/auth/screens/pin_setup_screen.dart';
import 'package:decvault/features/subscription/services/storage_service.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:decvault/features/decentralized/services/decentralized_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class DesktopSettingsScreen extends StatefulWidget {
  const DesktopSettingsScreen({super.key});

  @override
  State<DesktopSettingsScreen> createState() => _DesktopSettingsScreenState();
}

class _DesktopSettingsScreenState extends State<DesktopSettingsScreen> {
  String _selectedCategory = 'general';
  
  // Security settings controllers and variables
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  bool _biometricsAvailable = false;
  bool _useBiometrics = false;
  bool _seedPhraseVisible = false;
  int _autoLockTimeSeconds = 60; // Default 60 seconds
  
  final AuthService _authService = Get.find<AuthService>();
  SecurityService? get _securityService {
    try {
      return Get.find<SecurityService>();
    } catch (e) {
      return null;
    }
  }


  @override
  void initState() {
    super.initState();
    _checkBiometrics();

    // Allow deep-linking into a specific settings category (e.g. About)
    try {
      final args = Get.arguments;
      if (args is Map && args['initialCategory'] is String) {
        final initial = args['initialCategory'] as String;
        // Only apply if it matches a known category
        const allowed = ['security', 'backup', 'general', 'about'];
        if (allowed.contains(initial)) {
          _selectedCategory = initial;
        }
      }
    } catch (_) {
      // Ignore invalid arguments
    }
    _loadBiometricsSetting();
    _loadSecuritySettings();
    _refreshProStatus();
  }
  
  Future<void> _refreshProStatus() async {
    try {
      final revenueCatService = Get.find<RevenueCatService>();
      await revenueCatService.refreshProStatus();
    } catch (e) {
      // RevenueCatService not available or refresh failed — non-fatal
    }
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  String _getAutoLockTimeLabel(int seconds) {
    if (seconds == 0) return 'Disabled';
    if (seconds < 60) return '$seconds seconds';
    final minutes = seconds ~/ 60;
    if (minutes == 1) return '1 minute';
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    if (hours == 1) return '1 hour';
    return '$hours hours';
  }

  Future<void> _showLogoutDialog() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Color(0xFF8E24AA)),
            SizedBox(width: 8),
            Text(
              'Sign Out',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to sign out?',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
            SizedBox(height: 8),
            Text(
              'You will need your recovery phrase to sign back in.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E24AA),
              foregroundColor: Colors.white,
            ),
            child: Text('sign_out'.tr),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final authService = Get.find<AuthService>();
        await authService.logoutUser();
        Get.offAllNamed('/auth');
      } catch (e) {
        SnackbarUtils.showError(
          title: 'Error',
          message: 'Failed to sign out: $e',
        );
      }
    }
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!mounted) return;
      setState(() {
        _biometricsAvailable = canCheck && isDeviceSupported;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _biometricsAvailable = false;
      });
    }
  }

  Future<void> _loadBiometricsSetting() async {
    if (_securityService != null) {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final enabled = prefs.getBool('biometrics_enabled') ?? false;
      setState(() {
        _useBiometrics = enabled;
      });
    }
  }

  Future<void> _loadSecuritySettings() async {
    // Load auto-lock time setting
    if (_securityService != null) {
      final settings = _securityService!.securitySettings;
      setState(() {
        _autoLockTimeSeconds = settings.autoLockTimeSeconds;
      });
    }
  }

  Future<Map<String, String>?> _getDecentralizedNodeInfo() async {
    try {
      final config = await Get.find<DecentralizedService>().getNodeConfig();
      if (config == null) return null;
      return {
        'host': config['host'] ?? '',
        'port': config['port'] ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  Widget _buildSidebar() {
    final categories = [
      {'id': 'security', 'label': 'Security', 'icon': Icons.security},
      {'id': 'backup', 'label': 'Backup & Storage', 'icon': Icons.backup},
      {'id': 'general', 'label': 'General', 'icon': Icons.settings},
      {'id': 'about', 'label': 'About', 'icon': Icons.info_outline},
    ];

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          right: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.settings, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Configuration',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Categories
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: categories.map((category) {
                final isSelected = _selectedCategory == category['id'];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: ListTile(
                    leading: Icon(
                      category['icon'] as IconData,
                      color: isSelected ? const Color(0xFF34A853) : Colors.white70,
                      size: 20,
                    ),
                    title: Text(
                      category['label'] as String,
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF34A853) : Colors.white70,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor: const Color(0xFF34A853).withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    onTap: () => setState(() => _selectedCategory = category['id'] as String),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // Logout Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextButton.icon(
              onPressed: _showLogoutDialog,
              icon: const Icon(Icons.logout, size: 16, color: Color(0xFF8E24AA)),
              label: Text('sign_out'.tr),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8E24AA),
                minimumSize: const Size(double.infinity, 36),
                side: const BorderSide(color: Color(0xFF8E24AA), width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          
          // Back to Home
          Container(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () => Get.offNamed('/home'),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text('back_to_home'.tr),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedCategory) {
      case 'security':
        return _buildSecuritySettings();
      case 'backup':
        return _buildBackupSettings();
      case 'general':
        return _buildGeneralSettings();
      case 'about':
        return _buildAboutSettings();
      default:
        return _buildSecuritySettings();
    }
  }

  Widget _buildSecuritySettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'security_settings'.tr,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          
          // PIN Settings
          _buildSettingsCard(
            title: 'PIN Protection',
            icon: Icons.pin,
            children: [
              ListTile(
                title: Text('change_pin'.tr),
                subtitle: Text('update_security_pin'.tr),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Get.to(() => const PinSetupScreen());
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Auto-Lock Timer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose how long the app stays unlocked when inactive',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: _autoLockTimeSeconds,
                      decoration: const InputDecoration(
                        labelText: 'Auto-Lock After',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.timer),
                      ),
                      items: [
                        DropdownMenuItem(value: 30, child: Text('30_seconds'.tr)),
                        DropdownMenuItem(value: 60, child: Text('1_minute'.tr)),
                        DropdownMenuItem(value: 120, child: Text('2_minutes'.tr)),
                        DropdownMenuItem(value: 300, child: Text('5_minutes'.tr)),
                        DropdownMenuItem(value: 600, child: Text('10_minutes'.tr)),
                        DropdownMenuItem(value: 1800, child: Text('30_minutes'.tr)),
                        DropdownMenuItem(value: 0, child: Text('never_disabled'.tr)),
                      ],
                      onChanged: (value) async {
                        if (value != null && _securityService != null) {
                          setState(() {
                            _autoLockTimeSeconds = value;
                          });
                          
                          await _securityService!.setAutoLockTime(value);
                          
                          if (mounted) {
                            String message = value == 0 
                                ? 'Auto-lock disabled' 
                                : 'Auto-lock timer set to ${_getAutoLockTimeLabel(value)}';
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Text(message),
                                  ],
                                ),
                                duration: const Duration(seconds: 2),
                                backgroundColor: const Color(0xFF1E8E3E),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Biometric Settings
          if (_biometricsAvailable)
            _buildSettingsCard(
              title: 'Biometric Authentication',
              icon: Icons.fingerprint,
              children: [
                SwitchListTile(
                  title: Text('enable_biometrics'.tr),
                  subtitle: Text('use_fingerprint_face'.tr),
                  value: _useBiometrics,
                  onChanged: (value) async {
                    if (_securityService != null) {
                      // For now, just save to shared preferences since the method doesn't exist
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('biometrics_enabled', value);
                      setState(() {
                        _useBiometrics = value;
                      });
                    }
                  },
                ),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Seed Phrase
          _buildSettingsCard(
            title: 'Recovery Phrase',
            icon: Icons.key,
            children: [
              ListTile(
                title: Text('view_seed_phrase'.tr),
                subtitle: Text('show_recovery_phrase'.tr),
                trailing: const Icon(Icons.visibility),
                onTap: () {
                  _showSeedPhraseDialog();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSettings() {
    final bool isDecentralized = () {
      try {
        return Get.find<DecentralizedService>().isDecentralized;
      } catch (_) {
        return false;
      }
    }();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Backup & Storage Settings',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),

          if (isDecentralized) ...[
            _buildSettingsCard(
              title: 'Storage Node',
              icon: Icons.dns_outlined,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your data is stored on your own renterd node.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<Map<String, String>?>(
                        future: _getDecentralizedNodeInfo(),
                        builder: (context, snapshot) {
                          final info = snapshot.data;
                          return Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Connected node',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      info != null
                                          ? '${info['host']}:${info['port']}'
                                          : 'Not configured',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontFamily: 'monospace',
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    Get.toNamed('/decentralized-node-setup'),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('Change node'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF34A853),
                                  side: const BorderSide(
                                      color: Color(0xFF34A853)),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingsCard(
              title: 'Storage',
              icon: Icons.storage,
              children: const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.all_inclusive,
                          color: Color(0xFF1E8E3E), size: 28),
                      SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unlimited Storage',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Using your own renterd node',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            GetX<StorageService>(
              builder: (storageService) {
                return _buildSettingsCard(
                  title: 'Storage Usage',
                  icon: Icons.storage,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    storageService.getStorageUsageText(),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${storageService.getPercentageText()} used',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                              GetX<RevenueCatService>(
                                builder: (revenueCatService) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: revenueCatService.isPro.value
                                          ? const Color(0xFF1E8E3E)
                                          : Colors.grey.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      revenueCatService.isPro.value
                                          ? 'PRO PLAN'
                                          : 'FREE PLAN',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value:
                                  storageService.percentageUsed.value / 100,
                              backgroundColor:
                                  Colors.grey.withOpacity(0.2),
                              color: storageService.getStorageStatusColor(),
                              minHeight: 14,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Storage Plan',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[400],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    storageService.getStorageTierName(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              GetX<RevenueCatService>(
                                builder: (revenueCatService) {
                                  if (!revenueCatService.isPro.value) {
                                    return ElevatedButton.icon(
                                      onPressed: () {
                                        revenueCatService.presentPaywall();
                                      },
                                      icon: const Icon(Icons.upgrade,
                                          size: 18),
                                      label:
                                          const Text('Upgrade to Pro'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1E8E3E),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }




  Widget _buildGeneralSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'General Settings',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          
          // Account Information Card
          _buildSettingsCard(
            title: 'Account Information',
            icon: Icons.account_circle,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: FutureBuilder<String?>(
                  future: _authService.getUserId(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 16),
                          Text('Loading user information...'),
                        ],
                      );
                    }
                    
                    final userId = snapshot.data;
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.fingerprint, size: 24, color: Color(0xFF1E8E3E)),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'User ID',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Used for subscription and storage tracking',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (userId != null)
                              ElevatedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: userId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Row(
                                        children: [
                                          Icon(Icons.check_circle, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text('User ID copied to clipboard'),
                                        ],
                                      ),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: const Color(0xFF1E8E3E),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 18),
                                label: const Text('Copy'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E8E3E),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: SelectableText(
                            userId ?? 'Not available',
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          _buildSettingsCard(
            title: 'Application',
            icon: Icons.settings,
            children: [
              ListTile(
                title: const Text('Clear Cache'),
                subtitle: const Text('Clear application cache'),
                trailing: const Icon(Icons.delete_outline),
                onTap: () {
                  // Implement cache clearing
                },
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Language Settings Card
          _buildSettingsCard(
                title: 'Language',
                icon: Icons.language,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Choose your preferred language',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const ListTile(
                          leading: Icon(Icons.language, color: Color(0xFF34A853)),
                          title: Text('English'),
                          trailing: Icon(Icons.check_circle, color: Color(0xFF34A853)),
                        ),
                        const Divider(),
                        const ListTile(
                          leading: Icon(Icons.language, color: Color(0xFF34A853)),
                          title: Text('Français'),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'The app will automatically detect your device language on first launch.',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

          const SizedBox(height: 16),

          // Storage Usage Card
          Builder(
            builder: (context) {
              bool isDecentralized = false;
              try {
                isDecentralized = Get.find<DecentralizedService>().isDecentralized;
              } catch (_) {}

              if (isDecentralized) {
                return _buildSettingsCard(
                  title: 'Storage',
                  icon: Icons.storage,
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.all_inclusive, color: Color(0xFF1E8E3E), size: 28),
                          SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unlimited Storage',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Using your own renterd node',
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return GetX<StorageService>(
                builder: (storageService) {
                  return _buildSettingsCard(
                    title: 'Storage Usage',
                    icon: Icons.storage,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Storage usage text
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      storageService.getStorageUsageText(),
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${storageService.getPercentageText()} used',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                                GetX<RevenueCatService>(
                                  builder: (revenueCatService) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: revenueCatService.isPro.value
                                            ? const Color(0xFF1E8E3E)
                                            : Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        revenueCatService.isPro.value ? 'PRO PLAN' : 'FREE PLAN',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: storageService.percentageUsed.value / 100,
                                backgroundColor: Colors.grey.withOpacity(0.2),
                                color: storageService.getStorageStatusColor(),
                                minHeight: 14,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Storage tier info and upgrade button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Storage Plan',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[400],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      storageService.getStorageTierName(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                GetX<RevenueCatService>(
                                  builder: (revenueCatService) {
                                    if (!revenueCatService.isPro.value) {
                                      return ElevatedButton.icon(
                                        onPressed: () {
                                          revenueCatService.presentPaywall();
                                        },
                                        icon: const Icon(Icons.upgrade, size: 18),
                                        label: const Text('Upgrade to Pro'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1E8E3E),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About DecVault',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          
          _buildSettingsCard(
            title: 'Application Info',
            icon: Icons.info,
            children: [
              const ListTile(
                title: Text('Version'),
                subtitle: Text('1.0.0'),
                trailing: Icon(Icons.info_outline),
              ),
              const Divider(),
              const ListTile(
                title: Text('Developer'),
                subtitle: Text('DecVault Team'),
                trailing: Icon(Icons.person),
              ),
              const Divider(),
              ListTile(
                title: const Text('Privacy Policy'),
                subtitle: const Text('View our privacy policy'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final url = Uri.parse('https://decvault.com/privacy-policy');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open privacy policy'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Terms of Service'),
                subtitle: const Text('View our terms of service'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () async {
                  final url = Uri.parse('https://decvault.com/terms');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open terms of service'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Delete Account Card (at the end)
          _buildSettingsCard(
            title: 'Delete Account',
            icon: Icons.delete_forever,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.warning, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Danger Zone',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Permanently delete your account and all associated data. This action cannot be undone.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showDeleteAccountDialog(),
                        icon: const Icon(Icons.delete_forever, size: 18),
                        label: const Text('Delete Account'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF34A853)),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
  Future<void> _showSeedPhraseDialog() async {
    try {
      final seedPhrase = await _authService.getStoredSeedPhrase();
      
      if (seedPhrase == null || seedPhrase.isEmpty) {
        SnackbarUtils.showError(
          title: 'Error', 
          message: 'No recovery phrase found',
        );
        return;
      }

      // Reset visibility state when opening dialog
      setState(() {
        _seedPhraseVisible = false;
      });

      await Get.dialog(
        StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Recovery Seed Phrase',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500, // Set wider width for desktop
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Safety Warning
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.security, color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'SECURITY WARNING',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              '• Never share your recovery phrase with anyone\n'
                              '• DecVault will never ask for your phrase\n'
                              '• Store it safely offline in multiple locations\n'
                              '• Anyone with this phrase can access your account',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Seed Phrase Display
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            if (!_seedPhraseVisible) ...[
                              // Blurred state
                              Container(
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.visibility_off, size: 32, color: Colors.grey),
                                      SizedBox(height: 8),
                                      Text(
                                        'Tap "Show" to reveal your recovery phrase',
                                        style: TextStyle(color: Colors.grey),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    setDialogState(() {
                                      _seedPhraseVisible = true;
                                    });
                                  },
                                  icon: const Icon(Icons.visibility),
                                  label: const Text('Show Recovery Phrase'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ] else ...[
                              // Visible state
                              SelectableText(
                                seedPhrase,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        setDialogState(() {
                                          _seedPhraseVisible = false;
                                        });
                                      },
                                      icon: const Icon(Icons.visibility_off),
                                      label: const Text('Hide'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        // Copy to clipboard functionality could be added here
                                        SnackbarUtils.showInfo(
                                          title: 'Info',
                                          message: 'For security, copy manually by selecting the text',
                                        );
                                      },
                                      icon: const Icon(Icons.copy),
                                      label: const Text('Copy'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _seedPhraseVisible = false; // Reset state when closing
                    });
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to load recovery phrase: $e',
      );
    }
  }
  
  Future<void> _showDeleteAccountDialog() async {
    // Show confirmation dialog
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Account',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you absolutely sure you want to delete your account?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'This action will permanently:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• Delete your account from our servers',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              '• Remove all your backups and data',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              '• Clear all local app data',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 12),
            Text(
              'This action cannot be undone. Make sure you have backed up your recovery phrase if you want to recover your data later.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Show loading indicator
      Get.dialog(
        const Center(
          child: CircularProgressIndicator(),
        ),
        barrierDismissible: false,
      );
      
      try {
        await _authService.logoutUser();

        Get.back(); // Close loading dialog

        SnackbarUtils.showSuccess(
          title: 'Account Deleted',
          message: 'Your account has been permanently deleted',
        );
      } catch (e) {
        Get.back(); // Close loading dialog
        
        SnackbarUtils.showError(
          title: 'Error',
          message: 'Failed to delete account: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/common/widgets/app_drawer.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/auth/services/qr_login_service.dart';
import 'package:decvault/features/auth/screens/pin_setup_screen.dart';
import 'package:decvault/features/auth/screens/qr_scanner_screen.dart';
import 'package:decvault/features/decentralized/services/decentralized_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Security settings controllers and variables
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  bool _biometricsAvailable = false;
  bool _useBiometrics = false;
  bool _seedPhraseVisible = false;
  
  final AuthService _authService = Get.find<AuthService>();
  SecurityService? get _securityService {
    try {
      return Get.find<SecurityService>();
    } catch (e) {
      return null;
    }
  }
  QrLoginService? get _qrLoginService {
    try {
      return Get.find<QrLoginService>();
    } catch (e) {
      return null;
    }
  }
  bool get _isDecentralized {
    try {
      return Get.find<DecentralizedService>().isDecentralized;
    } catch (_) {
      return false;
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

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadBiometricsSetting();
    _loadSecuritySettings();
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
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _useBiometrics = prefs.getBool('use_biometrics') ?? false;
    });
  }
  
  Future<void> _loadSecuritySettings() async {
    try {
      final securityService = _securityService;
      if (securityService != null) {
        final settings = securityService.securitySettings;
        setState(() {
          _useBiometrics = settings.biometricEnabled;
        });
      }
    } catch (e) {
      // ignore
    }
  }
  
  Future<void> _changePin() async {
    final securityService = _securityService;
    if (securityService == null) {
      Get.snackbar('Error', 'Security service not available');
      return;
    }
    
    if (_newPinController.text != _confirmPinController.text) {
      Get.snackbar('Error', 'New PIN codes do not match');
      return;
    }
    
    if (_newPinController.text.isEmpty || _newPinController.text.length != 6) {
      Get.snackbar('Error', 'PIN must be exactly 6 digits');
      return;
    }
    
    try {
      final success = await securityService.changePinCode(
        _currentPinController.text, 
        _newPinController.text
      );
      
      if (success) {
        Get.snackbar('Success', 'PIN changed successfully');
        _currentPinController.clear();
        _newPinController.clear();
        _confirmPinController.clear();
      } else {
        Get.snackbar('Error', 'Failed to change PIN. Please check your current PIN.');
      }
    } catch (e) {
      Get.snackbar('Error', 'Error changing PIN: $e');
    }
  }

  Future<void> _setupNewPin() async {
    final result = await Get.to(() => const PinSetupScreen(
      title: 'Set up new PIN',
    ));
    
    if (result == true) {
      setState(() {
        // PIN was set successfully
      });
    }
  }

  Future<void> _removePin() async {
    final securityService = _securityService;
    if (securityService == null) {
      Get.snackbar('Error', 'Security service not available');
      return;
    }
    
    // Show confirmation dialog
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Remove PIN'),
        content: const Text('Are you sure you want to remove your PIN? This will disable PIN-based app locking.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await securityService.removePinCode(_currentPinController.text);
        
        if (success) {
          Get.snackbar('Success', 'PIN removed successfully');
          _currentPinController.clear();
          setState(() {
            // Update UI
          });
        } else {
          Get.snackbar('Error', 'Failed to remove PIN. Please check your current PIN.');
        }
      } catch (e) {
        Get.snackbar('Error', 'Error removing PIN: $e');
      }
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    final securityService = _securityService;
    if (securityService == null) {
      Get.snackbar('Error', 'Security service not available');
      return;
    }
    
    try {
      if (value) {
        final success = await securityService.enableBiometrics();
        if (success) {
          setState(() {
            _useBiometrics = value;
          });
          Get.snackbar('Success', 'Biometric authentication enabled');
        } else {
          Get.snackbar('Error', 'Failed to enable biometric authentication');
        }
      } else {
        final success = await securityService.disableBiometrics();
        if (success) {
          setState(() {
            _useBiometrics = value;
          });
          Get.snackbar('Success', 'Biometric authentication disabled');
        }
      }
    } catch (e) {
      Get.snackbar('Error', 'Error toggling biometrics: $e');
    }
  }

  Future<void> _openQrScanner() async {
    // Check if QR service is available
    final qrService = _qrLoginService;
    if (qrService == null) {
      Get.snackbar(
        'Error', 
        'QR service not available. Please restart the app.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withOpacity(0.8),
        colorText: Colors.white,
      );
      return;
    }
    
    // Navigate to QR scanner screen
    await Get.to(() => const QrScannerScreen());
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Security Settings Section
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.security, color: Color(0xFF1E8E3E)),
                        const SizedBox(width: 8),
                        const Text(
                          'Security & Privacy',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Biometric Authentication
                    ListTile(
                      leading: const Icon(Icons.fingerprint, color: Color(0xFF1E8E3E)),
                      title: const Text('Biometric Authentication'),
                      subtitle: Text(_biometricsAvailable
                          ? (_useBiometrics ? 'Enabled' : 'Disabled')
                          : 'Not available on this device'),
                      trailing: Switch(
                        value: _useBiometrics && _biometricsAvailable,
                        onChanged: _biometricsAvailable ? _toggleBiometrics : null,
                      ),
                    ),
                    const Divider(),
                    
                    // PIN Management
                    FutureBuilder<bool>(
                      future: _securityService?.hasPinSet() ?? Future.value(false),
                      builder: (context, snapshot) {
                        final hasPinSet = snapshot.data ?? false;
                        return ListTile(
                          leading: const Icon(Icons.pin, color: Color(0xFF1E8E3E)),
                          title: Text(hasPinSet ? 'PIN Protection' : 'Set up PIN'),
                          subtitle: Text(hasPinSet ? 'Active' : 'Add extra security layer'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _showPinManagementDialog(hasPinSet),
                        );
                      },
                    ),
                    const Divider(),
                    
                    // Auto-lock Settings
                    FutureBuilder<bool>(
                      future: _securityService?.hasPinSet() ?? Future.value(false),
                      builder: (context, snapshot) {
                        final hasPinSet = snapshot.data ?? false;
                        return ListTile(
                          leading: const Icon(Icons.timer, color: Color(0xFF1E8E3E)),
                          title: const Text('Auto-lock Settings'),
                          subtitle: Text(hasPinSet ? _getAutoLockTimeString() : 'Requires PIN setup'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: hasPinSet ? () => _showAutoLockDialog() : null,
                        );
                      },
                    ),
                    const Divider(),
                    
                    // Device Pairing with QR
                    ListTile(
                      leading: const Icon(Icons.qr_code_scanner, color: Color(0xFF1E8E3E)),
                      title: const Text('Pair Device'),
                      subtitle: const Text('Scan QR code to pair with desktop'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _openQrScanner,
                    ),
                  ],
                ),
              ),
            ),
            
            // Recovery & Backup Section
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.security, color: Color(0xFFF57C00)),
                        const SizedBox(width: 8),
                        const Text(
                          'Recovery & Backup',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Seed Phrase Display
                    ListTile(
                      leading: const Icon(Icons.vpn_key, color: Color(0xFFF57C00)),
                      title: const Text('Recovery Seed Phrase'),
                      subtitle: const Text('View your recovery phrase'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showSeedPhraseDialog(),
                    ),
                  ],
                ),
              ),
            ),
            
            // Decentralized Device Pairing (Path A only)
            if (_isDecentralized)
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.devices_outlined, color: Color(0xFF1E8E3E)),
                          SizedBox(width: 8),
                          Text(
                            'Decentralized',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.add_to_photos_outlined,
                            color: Color(0xFF1E8E3E)),
                        title: const Text('Add new device'),
                        subtitle: const Text(
                            'Transfer your config to another device via QR code'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => Get.toNamed('/device-pairing-export'),
                      ),
                      const Divider(),
                      FutureBuilder<Map<String, String>?>(
                        future: _getDecentralizedNodeInfo(),
                        builder: (context, snapshot) {
                          final info = snapshot.data;
                          return ListTile(
                            leading: const Icon(Icons.dns_outlined,
                                color: Color(0xFF1E8E3E)),
                            title: const Text('Storage Node'),
                            subtitle: Text(
                              info != null
                                  ? '${info['host']}:${info['port']}'
                                  : 'Not configured',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 13),
                            ),
                            trailing: OutlinedButton(
                              onPressed: () =>
                                  Get.toNamed('/decentralized-node-setup'),
                              child: const Text('Change'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }


  String _getAutoLockTimeString() {
    try {
      return _securityService?.autoLockTimeString ?? '5 minutes';
    } catch (e) {
      return '5 minutes'; // default
    }
  }

  Future<bool> _getLockOnAppCloseStatus() async {
    try {
      return _securityService?.securitySettings.lockOnAppClose ?? true;
    } catch (e) {
      return true; // default
    }
  }

  Future<void> _showPinManagementDialog(bool hasPinSet) async {
    if (hasPinSet) {
      // Show PIN change dialog
      await Get.dialog(
        AlertDialog(
          title: const Text('PIN Management'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _currentPinController,
                  decoration: const InputDecoration(
                    labelText: 'Current PIN',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPinController,
                  decoration: const InputDecoration(
                    labelText: 'New PIN',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                    helperText: 'PIN must be exactly 6 digits',
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPinController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New PIN',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _currentPinController.clear();
                _newPinController.clear();
                _confirmPinController.clear();
                Get.back();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Get.back();
                await _removePin();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove PIN'),
            ),
            ElevatedButton(
              onPressed: () async {
                Get.back();
                await _changePin();
              },
              child: const Text('Update PIN'),
            ),
          ],
        ),
      );
    } else {
      // Navigate to PIN setup
      await _setupNewPin();
    }
  }

  Future<void> _showAutoLockDialog() async {
    final securityService = _securityService;
    if (securityService == null) {
      Get.snackbar('Error', 'Security service not available');
      return;
    }

    await Get.dialog(
      AlertDialog(
        title: const Text('Auto-lock Settings'),
        content: FutureBuilder<bool>(
          future: _getLockOnAppCloseStatus(),
          builder: (context, lockSnapshot) {
            final lockOnClose = lockSnapshot.data ?? true;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Auto-lock after'),
                  subtitle: Text(_getAutoLockTimeString()),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Get.back();
                    _showAutoLockTimePicker();
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Lock when app closes'),
                  subtitle: const Text('Require PIN when reopening the app'),
                  value: lockOnClose,
                  onChanged: (value) async {
                    final securityService = _securityService;
                    if (securityService != null) {
                      await securityService.setLockOnAppClose(value);
                      setState(() {});
                    }
                  },
                  secondary: const Icon(Icons.exit_to_app),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAutoLockTimePicker() async {
    final securityService = _securityService;
    if (securityService == null) {
      Get.snackbar('Error', 'Security service not available');
      return;
    }
    
    int currentMinutes;
    try {
      currentMinutes = securityService.securitySettings.autoLockTimeSeconds ~/ 60;
    } catch (e) {
      currentMinutes = 5; // default
    }
    
    final options = [
      {'label': 'Disabled', 'minutes': 0},
      {'label': '1 minute', 'minutes': 1},
      {'label': '2 minutes', 'minutes': 2},
      {'label': '5 minutes', 'minutes': 5},
      {'label': '10 minutes', 'minutes': 10},
      {'label': '15 minutes', 'minutes': 15},
      {'label': '30 minutes', 'minutes': 30},
      {'label': '1 hour', 'minutes': 60},
    ];
    
    final selectedOption = await Get.dialog<Map<String, dynamic>>(
      AlertDialog(
        title: const Text('Auto-lock Timer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final isSelected = option['minutes'] == currentMinutes;
            return ListTile(
              title: Text(option['label'] as String),
              leading: Radio<int>(
                value: option['minutes'] as int,
                groupValue: currentMinutes,
                onChanged: (_) => Get.back(result: option),
              ),
              selected: isSelected,
              onTap: () => Get.back(result: option),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    if (selectedOption != null) {
      try {
        await securityService.setAutoLockTime(selectedOption['minutes'] as int);
        setState(() {});
        Get.snackbar('Success', 'Auto-lock timer updated');
      } catch (e) {
        Get.snackbar('Error', 'Failed to update auto-lock timer: $e');
      }
    }
  }

  Future<void> _showSeedPhraseDialog() async {
    try {
      final seedPhrase = await _authService.getStoredSeedPhrase();
      
      if (seedPhrase == null || seedPhrase.isEmpty) {
        Get.snackbar(
          'Error', 
          'No recovery phrase found',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Safety Warning
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
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
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          if (!_seedPhraseVisible) ...[
                            // Blurred state
                            Container(
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.3),
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
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      // Copy to clipboard functionality could be added here
                                      Get.snackbar(
                                        'Info',
                                        'For security, copy manually by selecting the text',
                                        snackPosition: SnackPosition.BOTTOM,
                                      );
                                    },
                                    icon: const Icon(Icons.copy),
                                    label: const Text('Copy'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
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
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _seedPhraseVisible = false; // Reset state when closing
                    });
                    Get.back();
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Error', 
        'Failed to retrieve recovery phrase: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withOpacity(0.8),
        colorText: Colors.white,
      );
    }
  }
}
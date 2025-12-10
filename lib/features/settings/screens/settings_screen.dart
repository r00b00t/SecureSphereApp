import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/common/widgets/app_drawer.dart';
import 'package:decvault/config/api_config.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/sia/services/sia_service.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/auth/services/qr_login_service.dart';
import 'package:decvault/features/auth/screens/pin_setup_screen.dart';
import 'package:decvault/features/auth/screens/qr_scanner_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:decvault/features/subscription/services/storage_service.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';
import 'package:decvault/services/localization_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Backup storage options
  final List<String> _backupOptions = [
    'DecVault',
    'Self-Hosted SIA Node'
  ];
  String _selectedBackupOption = 'DecVault';
  // Controllers for text fields
  final TextEditingController _siaIpController = TextEditingController();
  final TextEditingController _siaPortController = TextEditingController();
  final TextEditingController _siaPasswordController = TextEditingController();
  String? _siaStatusMessage;
  String? _siaPutCommand;
  bool _siaConnecting = false;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _secretKeyController = TextEditingController();
  
  // Security settings controllers and variables
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  bool _biometricsAvailable = false;
  bool _useBiometrics = false;
  bool _siaConnected = false;
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
      // QR service not initialized yet - this should not happen if main.dart is working correctly
      return null;
    }
  }
  static const _storage = FlutterSecureStorage(
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
  static const _siaPasswordKey = 'sia_password';

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadBiometricsSetting();
    _loadBackupOption();
    _loadSiaConnectionStatus();
    _loadSiaConfiguration();
    _loadSecuritySettings();
    _refreshProStatus();
    
    // Load SIA configuration after service initialization (without overriding user choice)
    Future.delayed(const Duration(milliseconds: 1000), () {
      _loadSiaConfiguration();
    });
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      setState(() {
        _biometricsAvailable = canCheck && isDeviceSupported;
      });
    } catch (e) {
      setState(() {
        _biometricsAvailable = false;
      });
    }
  }
  
  Future<void> _refreshProStatus() async {
    try {
      final revenueCatService = Get.find<RevenueCatService>();
      await revenueCatService.refreshProStatus();
    } catch (e) {
    }
  }

  Future<void> _loadBackupOption() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOption = prefs.getString('backupOption');
    if (savedOption != null && _backupOptions.contains(savedOption)) {
      setState(() {
        _selectedBackupOption = savedOption;
      });
    }
  }

  Future<void> _loadBiometricsSetting() async {
    final prefs = await SharedPreferences.getInstance();
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
    }
  }
  
  Future<void> _loadSiaConnectionStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isVerified = prefs.getBool('sia_verified') ?? false;
      final configJson = prefs.getString('sia_config');
      
      setState(() {
        _siaConnected = isVerified && configJson != null;
      });
      
      // Load SIA config into form fields if connected (but never pre-fill password)
      if (_siaConnected && configJson != null) {
        try {
          final config = jsonDecode(configJson) as Map<String, dynamic>;
          _siaIpController.text = config['ip'] ?? '';
          _siaPortController.text = config['port'] ?? '';
          _siaPasswordController.text = ''; // Never pre-fill password in settings
          _siaStatusMessage = 'Connected to Self-Hosted SIA';
        } catch (e) {
        }
      }
    } catch (e) {
    }
  }
  
  Future<void> _loadSiaConfiguration() async {
    try {
      
      // First, force SIA service to reload from backend
      try {
        final siaService = Get.find<SiaService>();
        await siaService.loadSiaConfiguration();
      } catch (e) {
      }
      
      // Load saved backup option (might have been updated by SIA service)
      final prefs = await SharedPreferences.getInstance();
      final savedOption = prefs.getString('backupOption') ?? 'DecVault';
      
      setState(() {
        _selectedBackupOption = savedOption;
      });
      
      // If self-hosted, load config from backend
      if (savedOption == 'Self-Hosted SIA Node') {
        await _loadSelfHostedConfig();
      }
    } catch (e) {
    }
  }
  
  Future<void> _loadSelfHostedConfig() async {
    try {
      final userId = await _authService.getUserId();
      if (userId == null) return;
      
      // Load SIA node config from backend
      final url = Uri.parse(ApiConfig.getSiaNodeEndpoint(userId));
      final headers = {
        'Content-Type': 'application/json',
        'api-key': ApiConfig.psqlApiKey,
      };
      
      final response = await http.get(url, headers: headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final node = data['node'] as Map<String, dynamic>;
        
        // Populate form with backend data
        setState(() {
          _siaIpController.text = node['host'] ?? '';
          _siaPortController.text = (node['port'] ?? '').toString();
          
          // Check if password is stored locally
          _checkStoredPassword();
        });
      } else {
        // No config in backend, clear form
        setState(() {
          _siaIpController.clear();
          _siaPortController.clear();
          _siaPasswordController.clear();
          _siaStatusMessage = null;
          _siaConnected = false;
        });
      }
    } catch (e) {
    }
  }
  
  Future<void> _checkStoredPassword() async {
    try {
      // Use SIA service to properly check for stored password
      final siaService = Get.find<SiaService>();
      final storedPassword = await siaService.getStoredPassword();
      if (storedPassword != null && storedPassword.isNotEmpty) {
        setState(() {
          _siaStatusMessage = 'SIA node configured (password stored)';
          _siaConnected = true;
        });
      } else {
        setState(() {
          _siaStatusMessage = 'SIA node configured (password required)';
          _siaConnected = false;
        });
      }
    } catch (e) {
    }
  }
  
  Future<void> _disconnectSia() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Clear SIA configuration and verification status (both legacy and new formats)
      await prefs.remove('sia_config'); // Legacy format for vault/backup services
      await prefs.setBool('sia_verified', false);
      
      // Clear manual connection flag and local config
      await prefs.setBool('sia_manually_connected', false);
      await prefs.remove('local_sia_config'); // Remove local SIA config
      
      // Clear form fields
      _siaIpController.clear();
      _siaPortController.clear();
      _siaPasswordController.clear();
      
      // Clear stored password from SIA service
      try {
        final siaService = Get.find<SiaService>();
        await siaService.clearStoredPassword();
      } catch (e) {
      }
      
      setState(() {
        _siaConnected = false;
        _siaStatusMessage = 'Disconnected from SIA';
        _siaPutCommand = null;
      });
      
      SnackbarUtils.showWarning(
        title: 'SIA Disconnected',
        message: 'Successfully disconnected from Self-Hosted SIA',
      );
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to disconnect from SIA: $e',
      );
    }
  }
  
  Future<void> _changePin() async {
    final securityService = _securityService;
    if (securityService == null) {
      SnackbarUtils.showError(title: 'Error', message: 'Security service not available');
      return;
    }
    
    if (_newPinController.text != _confirmPinController.text) {
      SnackbarUtils.showError(title: 'Error', message: 'New PIN codes do not match');
      return;
    }
    
    if (_newPinController.text.isEmpty || _newPinController.text.length != 6) {
      SnackbarUtils.showError(title: 'Error', message: 'PIN must be exactly 6 digits');
      return;
    }
    
    try {
      final success = await securityService.changePinCode(
        _currentPinController.text, 
        _newPinController.text
      );
      
      if (success) {
        SnackbarUtils.showSuccess(title: 'Success', message: 'PIN changed successfully');
        _currentPinController.clear();
        _newPinController.clear();
        _confirmPinController.clear();
      } else {
        SnackbarUtils.showError(title: 'Error', message: 'Failed to change PIN. Please check your current PIN.');
      }
    } catch (e) {
      SnackbarUtils.showError(title: 'Error', message: 'Error changing PIN: $e');
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
      SnackbarUtils.showError(title: 'Error', message: 'Security service not available');
      return;
    }
    
    // Show confirmation dialog
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('remove_pin'.tr),
        content: Text('remove_pin_confirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('remove'.tr),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await securityService.removePinCode(_currentPinController.text);
        
        if (success) {
          SnackbarUtils.showSuccess(title: 'Success', message: 'PIN removed successfully');
          _currentPinController.clear();
          setState(() {
            // Update UI
          });
        } else {
          SnackbarUtils.showError(title: 'Error', message: 'Failed to remove PIN. Please check your current PIN.');
        }
      } catch (e) {
        SnackbarUtils.showError(title: 'Error', message: 'Error removing PIN: $e');
      }
    }
  }

  /// Safely shows a snackbar by ensuring the overlay is ready
  void _safeShowSnackbar({
    required String title,
    required String message,
    Color? backgroundColor,
  }) {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Get.overlayContext != null) {
          SnackbarUtils.showSnackbar(
            title: title,
            message: message,
            backgroundColor: backgroundColor,
            duration: const Duration(seconds: 3),
          );
        }
      });
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    final securityService = _securityService;
    if (securityService == null) {
      _safeShowSnackbar(
        title: 'Error',
        message: 'Security service not available',
        backgroundColor: Colors.red.withOpacity(0.8),
      );
      return;
    }
    
    try {
      if (value) {
        // Check if PIN is set before enabling biometrics
        final hasPIN = await securityService.hasPinSet();
        if (!hasPIN) {
          // Show dialog to inform user they need to create a PIN first
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.security, color: Colors.orange),
                  SizedBox(width: 12),
                  Text('PIN Required'),
                ],
              ),
              content: const Text(
                'You need to create a PIN code before enabling biometric authentication. '
                'The PIN serves as a backup when biometrics fail or are unavailable.\n\n'
                'Would you like to create a PIN now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showPinSetup();
                  },
                  child: Text('create_pin'.tr),
                ),
              ],
            ),
          );
          return;
        }
        
        final success = await securityService.enableBiometrics();
        if (success) {
          setState(() {
            _useBiometrics = value;
          });
          _safeShowSnackbar(
            title: 'Success',
            message: 'Biometric authentication enabled',
            backgroundColor: Colors.green.withOpacity(0.8),
          );
        } else {
          _safeShowSnackbar(
            title: 'Error',
            message: 'Failed to enable biometric authentication',
            backgroundColor: Colors.red.withOpacity(0.8),
          );
        }
      } else {
        final success = await securityService.disableBiometrics();
        if (success) {
          setState(() {
            _useBiometrics = value;
          });
          _safeShowSnackbar(
            title: 'Success',
            message: 'Biometric authentication disabled',
            backgroundColor: Colors.green.withOpacity(0.8),
          );
        }
      }
    } catch (e) {
      _safeShowSnackbar(
        title: 'Error',
        message: 'Error toggling biometrics: $e',
        backgroundColor: Colors.red.withOpacity(0.8),
      );
    }
  }
  
  Future<void> _showPinSetup() async {
    // Navigate to PIN setup and wait for result
    final result = await Get.to(() => const PinSetupScreen(
      isOptional: false,
      title: 'Create Your PIN',
    ));
    
    // After PIN is created (if successful), automatically try to enable biometrics
    if (result == true && mounted) {
      // Small delay to ensure UI is stable
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _toggleBiometrics(true);
        }
      });
    }
  }

  Future<void> _openQrScanner() async {
    // Check if QR service is available
    final qrService = _qrLoginService;
    if (qrService == null) {
      SnackbarUtils.showError(
        title: 'Error', 
        message: 'QR service not available. Please restart the app.',
      );
      return;
    }
    
    // Navigate to QR scanner screen
    await Get.to(() => const QrScannerScreen());
  }

  @override
  void dispose() {
    _urlController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _keyController.dispose();
    _secretKeyController.dispose();
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    _siaIpController.dispose();
    _siaPortController.dispose();
    _siaPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text('settings'.tr),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF121212),
              const Color(0xFF1E1E1E),
              Theme.of(context).primaryColor.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account Information Section
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
                        const Icon(Icons.account_circle, color: Color(0xFF1E8E3E)),
                        const SizedBox(width: 8),
                        Text(
                          'account_information'.tr,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<String?>(
                      future: _authService.getUserId(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Text('loading_user_id'.tr),
                            ],
                          );
                        }
                        
                        final userId = snapshot.data;
                        
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.fingerprint, size: 20, color: Color(0xFF1E8E3E)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'user_id'.tr,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (userId != null)
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 18),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: userId));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('user_id_copied'.tr),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      tooltip: 'copy_user_id'.tr,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                userId ?? 'not_available'.tr,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (userId != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'user_id_description'.tr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            // Storage Usage Section
            GetX<StorageService>(
              builder: (storageService) {
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.storage, color: storageService.getStorageStatusColor()),
                            const SizedBox(width: 8),
                            Text(
                              'storage_usage'.tr,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            GetX<RevenueCatService>(
                              builder: (revenueCatService) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: revenueCatService.isPro.value 
                                        ? const Color(0xFF1E8E3E) 
                                        : Colors.grey.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    revenueCatService.isPro.value ? 'pro'.tr : 'free'.tr,
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
                        
                        // Storage usage text
                        Text(
                          storageService.getStorageUsageText(),
                          style: const TextStyle(
                            fontSize: 24,
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
                        const SizedBox(height: 16),
                        
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: storageService.percentageUsed.value / 100,
                            backgroundColor: Colors.grey.withOpacity(0.2),
                            color: storageService.getStorageStatusColor(),
                            minHeight: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Storage tier info
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Storage Plan: ${storageService.getStorageTierName()}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                            GetX<RevenueCatService>(
                              builder: (revenueCatService) {
                                if (!revenueCatService.isPro.value) {
                                  return TextButton.icon(
                                    onPressed: () {
                                      revenueCatService.presentPaywall();
                                    },
                                    icon: const Icon(Icons.upgrade, size: 16),
                                    label: const Text('Upgrade'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF1E8E3E),
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
                );
              },
            ),
            
            // Basic Settings Section
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
                        const Icon(Icons.backup, color: Color(0xFF4285F4)),
                        const SizedBox(width: 8),
                        Text(
                          'backup_storage'.tr,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'backup_storage_description'.tr,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedBackupOption == 'Self-Hosted SIA Node' ? 'DecVault' : _selectedBackupOption,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      items: ['DecVault'].map((String option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(option),
                        );
                      }).toList(),
                      onChanged: (String? newValue) async {
                        if (newValue != null) {
                          setState(() {
                            _selectedBackupOption = newValue;
                            _siaStatusMessage = 'Using DecVault SIA Node';
                            _siaConnected = false;
                          });
                          
                          // Clear SIA form when switching to DecVault
                          _siaIpController.clear();
                          _siaPortController.clear();
                          _siaPasswordController.clear();
                          
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('backupOption', newValue);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'decvault_description'.tr,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
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
                        Text(
                          'security_privacy'.tr,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Biometric Authentication
                    ListTile(
                      leading: const Icon(Icons.fingerprint, color: Color(0xFF1E8E3E)),
                      title: Text('biometric_authentication'.tr),
                      subtitle: Text(_biometricsAvailable
                          ? (_useBiometrics ? 'enabled'.tr : 'disabled'.tr)
                          : 'not_available_on_device'.tr),
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
                          title: Text(hasPinSet ? 'pin_protection'.tr : 'setup_pin'.tr),
                          subtitle: Text(hasPinSet ? 'active'.tr : 'add_extra_security_layer'.tr),
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
                          title: Text('auto_lock_settings'.tr),
                          subtitle: Text(hasPinSet ? _getAutoLockTimeString() : 'requires_pin_setup'.tr),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: hasPinSet ? () => _showAutoLockDialog() : null,
                        );
                      },
                    ),
                    const Divider(),
                    
                    // Device Pairing with QR
                    ListTile(
                      leading: const Icon(Icons.qr_code_scanner, color: Color(0xFF1E8E3E)),
                      title: Text('pair_device'.tr),
                      subtitle: Text('scan_qr_to_pair'.tr),
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
                        Text(
                          'recovery_backup'.tr,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Seed Phrase Display
                    ListTile(
                      leading: const Icon(Icons.vpn_key, color: Color(0xFFF57C00)),
                      title: Text('recovery_seed_phrase'.tr),
                      subtitle: Text('view_recovery_phrase'.tr),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showSeedPhraseDialog(),
                    ),
                  ],
                ),
              ),
            ),
            
            // Advanced Settings Section
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
                        const Icon(Icons.settings_applications, color: Color(0xFFDB4437)),
                        const SizedBox(width: 8),
                        Text(
                          'advanced_settings'.tr,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Advanced configuration options for power users',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    
                    // SIA Node Configuration
                    ListTile(
                      leading: const Icon(Icons.storage, color: Color(0xFFDB4437)),
                      title: Text('sia_node_configuration'.tr),
                      subtitle: Text(_selectedBackupOption == 'Self-Hosted SIA Node' 
                          ? 'self_hosted_node_configured'.tr
                          : 'use_custom_sia_node'.tr),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showSiaConfigurationDialog(),
                    ),
                  ],
                ),
              ),
            ),
            
            // Language Settings Section
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
                        const Icon(Icons.language, color: Color(0xFF34A853)),
                        const SizedBox(width: 8),
                        const Text(
                          'Language',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Choose your preferred language',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    GetX<LocalizationService>(
                      builder: (localizationService) {
                        return Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.check_circle, color: Color(0xFF34A853)),
                              title: const Text('English'),
                              trailing: localizationService.isLanguageSelected('en')
                                  ? const Icon(Icons.check, color: Color(0xFF34A853))
                                  : null,
                              onTap: () async {
                                await localizationService.changeLanguage('en');
                                SnackbarUtils.showSuccess(
                                  title: 'Success',
                                  message: 'Language changed to English',
                                );
                              },
                            ),
                            const Divider(),
                            ListTile(
                              leading: const Icon(Icons.check_circle, color: Color(0xFF34A853)),
                              title: const Text('Français'),
                              trailing: localizationService.isLanguageSelected('fr')
                                  ? const Icon(Icons.check, color: Color(0xFF34A853))
                                  : null,
                              onTap: () async {
                                await localizationService.changeLanguage('fr');
                                SnackbarUtils.showSuccess(
                                  title: 'Succès',
                                  message: 'Langue changée en français',
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
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
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'language_auto_detect_info'.tr,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // About Section
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
                        const Icon(Icons.info_outline, color: Color(0xFF4285F4)),
                        const SizedBox(width: 8),
                        Text(
                          'about_decvault'.tr,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // App Version
                    ListTile(
                      leading: const Icon(Icons.info, color: Color(0xFF4285F4)),
                      title: Text('version'.tr),
                      subtitle: const Text('1.0.0'),
                    ),
                    const Divider(),
                    
                    // Developer
                    ListTile(
                      leading: const Icon(Icons.person, color: Color(0xFF4285F4)),
                      title: Text('developer'.tr),
                      subtitle: Text('decvault_team'.tr),
                    ),
                    const Divider(),
                    
                    // Privacy Policy
                    ListTile(
                      leading: const Icon(Icons.privacy_tip, color: Color(0xFF4285F4)),
                      title: Text('privacy_policy'.tr),
                      subtitle: Text('view_privacy_policy'.tr),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () async {
                        final url = Uri.parse('https://decvault.com/privacy-policy');
                        try {
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
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(),
                    
                    // Terms of Service
                    ListTile(
                      leading: const Icon(Icons.description, color: Color(0xFF4285F4)),
                      title: Text('terms_of_service'.tr),
                      subtitle: Text('view_terms_of_service'.tr),
                      trailing: const Icon(Icons.open_in_new, size: 16),
                      onTap: () async {
                        final url = Uri.parse('https://decvault.com/terms');
                        try {
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
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            // Delete Account Section (at the end)
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
                        const Icon(Icons.warning, color: Colors.red, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'delete_account'.tr,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'danger_zone'.tr,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'delete_account_description'.tr,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _showDeleteAccountDialog(),
                              icon: const Icon(Icons.delete_forever, size: 18),
                              label: Text('delete_account'.tr),
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
              ),
            ),

          ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSiaForm() {
    return [
      const Text(
        'Self-hosted SIA Configuration',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _urlController,
        decoration: const InputDecoration(
          labelText: 'URL/IP',
          hintText: 'e.g., http://localhost or 192.168.1.100',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _portController,
        decoration: const InputDecoration(
          labelText: 'Port',
          hintText: 'e.g., 9980',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        decoration: const InputDecoration(
          labelText: 'Password',
          border: OutlineInputBorder(),
        ),
        obscureText: true,
      ),
    ];
  }

  List<Widget> _buildS3Form() {
    return [
      const Text(
        'S3 Server Configuration',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _urlController,
        decoration: const InputDecoration(
          labelText: 'URL/IP',
          hintText: '',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _keyController,
        decoration: const InputDecoration(
          labelText: 'Access Key',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _secretKeyController,
        decoration: const InputDecoration(
          labelText: 'Secret Key',
          border: OutlineInputBorder(),
        ),
        obscureText: true,
      ),
    ];
  }

  void _saveSiaSettings() async {
    setState(() {
      _siaStatusMessage = null;
      _siaPutCommand = null;
      _siaConnecting = true;
    });
    
    final host = _siaIpController.text.trim();
    final portText = _siaPortController.text.trim();
    final password = _siaPasswordController.text;
    
    
    // Input validation
    if (host.isEmpty) {
      setState(() {
        _siaStatusMessage = 'Host/IP address cannot be empty.';
        _siaConnecting = false;
      });
      return;
    }
    
    final port = int.tryParse(portText);
    if (port == null || port <= 0 || port > 65535) {
      setState(() {
        _siaStatusMessage = 'Please enter a valid port number (1-65535).';
        _siaConnecting = false;
      });
      return;
    }
    
    if (password.isEmpty) {
      setState(() {
        _siaStatusMessage = 'Password cannot be empty.';
        _siaConnecting = false;
      });
      return;
    }
    
    try {
      // Save SIA node config to backend (but continue even if backend fails)
      final backendSaved = await _saveSiaConfigToBackend(host, port);
      
      // Always save config locally for offline use
      final localConfigSaved = await _saveSiaConfigLocally(host, port);
      if (!localConfigSaved) {
        setState(() {
          _siaStatusMessage = 'Failed to save SIA configuration locally.';
          _siaConnected = false;
          _siaConnecting = false;
        });
        return;
      }
      
      // Save password locally using SiaService encryption
      try {
        final siaService = Get.find<SiaService>();
        final passwordSaved = await siaService.savePasswordLocally(password);
        if (!passwordSaved) {
          setState(() {
            _siaStatusMessage = 'Failed to save SIA password locally.';
            _siaConnected = false;
            _siaConnecting = false;
          });
          return;
        }
        
        // Force reload SIA configuration to include the new password
        await siaService.loadSiaConfiguration();
        
        // Also save in the format that vault/backup services expect
        await _saveSiaConfigForServices(host, port, password);
        
      } catch (e) {
        setState(() {
          _siaStatusMessage = 'Failed to save SIA password: $e';
          _siaConnected = false;
          _siaConnecting = false;
        });
        return;
      }
      
      // Test connection to SIA node
      final authHeader = 'Basic ' + base64Encode(utf8.encode(':$password'));
      final url = 'http://$host:$port${ApiConfig.siaWorkerStatePath}';
      
      final response = await http.get(Uri.parse(url), headers: {'Authorization': authHeader});
      
      if (response.statusCode == 200) {
        try {
          final responseData = jsonDecode(response.body);
          // Check if response contains expected worker state fields
          if (responseData is Map<String, dynamic> && 
              responseData.containsKey('id') && 
              responseData.containsKey('version')) {
            setState(() {
              _siaStatusMessage = 'Connected to Self-Hosted SIA (${responseData['version']})';
              _siaConnected = true;
            });
            
            // Set backup option to Self-Hosted since connection succeeded
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('backupOption', 'Self-Hosted SIA Node');
            
            // Set flag to indicate successful manual connection
            await prefs.setBool('sia_manually_connected', true);
            
            SnackbarUtils.showSuccess(title: 'Success', message: 'SIA node connected and configured successfully');
          } else {
            setState(() {
              _siaStatusMessage = 'Invalid response from SIA worker. Please check your connection.';
              _siaConnected = false;
            });
          }
        } catch (e) {
          setState(() {
            _siaStatusMessage = 'Invalid JSON response from SIA worker.';
            _siaConnected = false;
          });
        }
      } else if (response.statusCode == 401 || response.body.contains('Unauthorized')) {
        setState(() {
          _siaStatusMessage = 'Authentication failed. Please verify your password.';
          _siaConnected = false;
        });
      } else {
        setState(() {
          _siaStatusMessage = 'Connection failed. Please verify your host and port.';
          _siaConnected = false;
        });
      }
    } catch (e) {
      setState(() {
        _siaStatusMessage = 'Connection error: $e';
        _siaConnected = false;
      });
    }
    
    setState(() {
      _siaConnecting = false;
    });
  }
  
  Future<bool> _saveSiaConfigToBackend(String host, int port) async {
    try {
      final userId = await _authService.getUserId();
      if (userId == null) {
        SnackbarUtils.showError(
          title: 'Error',
          message: 'User ID not available. Please try logging in again.',
        );
        return false;
      }
      
      // Check if API key is configured
      if (ApiConfig.psqlApiKey.isEmpty) {
        SnackbarUtils.showWarning(
          title: 'Configuration Error',
          message: 'Backend API key not configured. SIA config will be saved locally only.',
        );
        return true; // Continue with local storage only
      }
      
      final url = Uri.parse(ApiConfig.siaNodeEndpoint);
      final payloadData = {
        'uuid': userId, // Backend expects lowercase 'uuid' field
        'host': host,
        'port': port,
      };
      final payload = jsonEncode(payloadData);
      final headers = {
        'Content-Type': 'application/json',
        'api-key': ApiConfig.psqlApiKey,
        'user-id': userId,
      };
      
      // Debug logging
      
      final response = await http.post(url, headers: headers, body: payload).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Backend server timeout - please check your connection');
        },
      );
      
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        SnackbarUtils.showWarning(
          title: 'Backend Error',
          message: 'Failed to save SIA config to server (${response.statusCode}). Config saved locally.',
        );
        return true; // Continue with local storage
      }
    } catch (e) {
      
      String userMessage = 'Backend server not available. Config saved locally only.';
      if (e.toString().contains('Connection refused')) {
        userMessage = 'Cannot connect to backend server. SIA config saved locally only.';
      } else if (e.toString().contains('timeout')) {
        userMessage = 'Backend server timeout. SIA config saved locally only.';
      }
      
      SnackbarUtils.showWarning(
        title: 'Backend Unavailable',
        message: userMessage,
      );
      
      return true; // Continue with local storage only
    }
  }
  
  Future<bool> _saveSiaConfigLocally(String host, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save the SIA config in the same format the SIA service expects
      final configData = {
        'host': host,
        'port': port,
        'isDecVaultManagedNode': false,
      };
      
      // Save to a key that SIA service can read
      await prefs.setString('local_sia_config', jsonEncode(configData));
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  Future<void> _saveSiaConfigForServices(String host, int port, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save in the legacy format that vault/backup services expect
      final legacyConfig = {
        'ip': host,
        'port': port.toString(),
        'password': password,
      };
      
      await prefs.setString('sia_config', jsonEncode(legacyConfig));
      await prefs.setBool('sia_verified', true);
      
    } catch (e) {
    }
  }
  
  void _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backupOption', _selectedBackupOption);
      
      SnackbarUtils.showSuccess(title: 'Settings', message: 'Settings saved successfully');
    } catch (e) {
      SnackbarUtils.showError(title: 'Error', message: 'Failed to save settings: $e');
    }
  }
  
  /// Get current SIA configuration based on user selection
  Future<Map<String, String>?> getCurrentSiaConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupOption = prefs.getString('backupOption') ?? 'DecVault';
      
      if (backupOption == 'DecVault') {
        // Use DecVault config from api_config.dart (but hide password in settings)
        return {
          'host': ApiConfig.SSip,
          'port': ApiConfig.SSport,
          'password': '', // Never show DecVault password in settings
        };
      } else {
        // Get self-hosted config from backend
        final userId = await _authService.getUserId();
        if (userId == null) return null;
        
        final url = Uri.parse(ApiConfig.getSiaNodeEndpoint(userId));
        final headers = {
          'Content-Type': 'application/json',
          'api-key': ApiConfig.psqlApiKey,
        };
        
        final response = await http.get(url, headers: headers);
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final node = data['node'] as Map<String, dynamic>;
          
          // For settings display, never show the actual password
          
          return {
            'host': node['host'] ?? '',
            'port': (node['port'] ?? '').toString(),
            'password': '', // Always empty for settings display
          };
        }
      }
    } catch (e) {
    }
    return null;
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
          title: Text('pin_management'.tr),
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
            child: Text('remove_pin'.tr),
          ),
          ElevatedButton(
              onPressed: () async {
                Get.back();
                await _changePin();
              },
              child: Text('update_pin'.tr),
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
      SnackbarUtils.showError(title: 'Error', message: 'Security service not available');
      return;
    }
    
    await Get.dialog(
      AlertDialog(
        title: Text('auto_lock_settings'.tr),
        content: FutureBuilder<bool>(
          future: _getLockOnAppCloseStatus(),
          builder: (context, lockSnapshot) {
            final lockOnClose = lockSnapshot.data ?? true;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text('auto_lock_after'.tr),
                  subtitle: Text(_getAutoLockTimeString()),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Get.back();
                    _showAutoLockTimePicker();
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: Text('lock_when_app_closes'.tr),
                  subtitle: Text('require_pin_on_reopen'.tr),
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
            child: Text('close'.tr),
          ),
        ],
      ),
    );
  }

  Future<void> _showSiaConfigurationDialog() async {
    String dialogBackupOption = _selectedBackupOption;
    
    await Get.dialog(
      StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('sia_node_configuration'.tr),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Configure your own SIA node for backup storage. This requires advanced technical knowledge.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: dialogBackupOption,
                    decoration: const InputDecoration(
                      labelText: 'Backup Option',
                      border: OutlineInputBorder(),
                    ),
                    items: _backupOptions.map((String option) {
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(option),
                      );
                    }).toList(),
                    onChanged: (String? newValue) async {
                      if (newValue != null) {
                        setDialogState(() {
                          dialogBackupOption = newValue;
                        });
                        
                        setState(() {
                          _selectedBackupOption = newValue;
                          _siaStatusMessage = null;
                          _siaPutCommand = null;
                        });
                        
                        if (newValue == 'Self-Hosted SIA Node') {
                          await _loadSelfHostedConfig();
                        } else {
                          _siaIpController.clear();
                          _siaPortController.clear();
                          _siaPasswordController.clear();
                          setState(() {
                            _siaConnected = false;
                            _siaStatusMessage = null;
                            _siaPutCommand = null;
                          });
                        }
                        
                        // Update the dialog state to reflect changes
                        setDialogState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  if (dialogBackupOption == 'Self-Hosted SIA Node') ...[
                    TextFormField(
                      controller: _siaIpController,
                      decoration: const InputDecoration(
                        labelText: 'IP Address',
                        hintText: 'e.g., 192.168.1.100',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _siaPortController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: 'e.g., 9980',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _siaPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    if (_siaStatusMessage != null)
                      Text(
                        _siaStatusMessage!,
                        style: TextStyle(
                          color: _siaStatusMessage!.contains('Connected') ? Colors.green : Colors.red,
                        ),
                      ),
                    if (_siaPutCommand != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          const Text('PUT Command:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          SelectableText(_siaPutCommand!, style: const TextStyle(fontFamily: 'monospace')),
                        ],
                      ),
                    if (_siaConnected && dialogBackupOption == 'Self-Hosted SIA Node' && _selectedBackupOption == 'Self-Hosted SIA Node') ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setDialogState(() {});
                            _disconnectSia();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Disconnect SIA'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('Cancel'),
              ),
              if (dialogBackupOption == 'Self-Hosted SIA Node')
                ElevatedButton(
                  onPressed: _siaConnecting ? null : () {
                    Get.back();
                    _saveSiaSettings();
                  },
                  child: _siaConnecting ? const CircularProgressIndicator() : const Text('Connect & Save'),
                ),
              if (dialogBackupOption != 'Self-Hosted SIA Node')
                ElevatedButton(
                  onPressed: () {
                    Get.back();
                    _saveSettings();
                  },
                  child: const Text('Save'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAutoLockTimePicker() async {
    final securityService = _securityService;
    if (securityService == null) {
      SnackbarUtils.showError(title: 'Error', message: 'Security service not available');
      return;
    }
    
    int currentSeconds;
    try {
      currentSeconds = securityService.securitySettings.autoLockTimeSeconds;
    } catch (e) {
      currentSeconds = 60; // default 1 minute
    }
    
    final options = [
      {'label': 'Disabled', 'seconds': 0},
      {'label': '30 seconds', 'seconds': 30},
      {'label': '1 minute', 'seconds': 60},
      {'label': '2 minutes', 'seconds': 120},
      {'label': '5 minutes', 'seconds': 300},
      {'label': '10 minutes', 'seconds': 600},
      {'label': '15 minutes', 'seconds': 900},
      {'label': '30 minutes', 'seconds': 1800},
      {'label': '1 hour', 'seconds': 3600},
    ];
    
    final selectedOption = await Get.dialog<Map<String, dynamic>>(
      AlertDialog(
        title: const Text('Auto-lock Timer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            final isSelected = option['seconds'] == currentSeconds;
            return ListTile(
              title: Text(option['label'] as String),
              leading: Radio<int>(
                value: option['seconds'] as int,
                groupValue: currentSeconds,
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
        await securityService.setAutoLockTime(selectedOption['seconds'] as int);
        setState(() {});
        SnackbarUtils.showSuccess(title: 'Success', message: 'Auto-lock timer updated');
      } catch (e) {
        SnackbarUtils.showError(title: 'Error', message: 'Failed to update auto-lock timer: $e');
      }
    }
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
      SnackbarUtils.showError(
        title: 'Error', 
        message: 'Failed to retrieve recovery phrase: $e',
      );
    }
  }
  
  Future<void> _showDeleteAccountDialog() async {
    // Show confirmation dialog
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'This action will permanently:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('• Delete your account from our servers'),
            Text('• Remove all your backups and data'),
            Text('• Clear all local app data'),
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
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
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
        final success = await _authService.deleteAccount();
        
        Get.back(); // Close loading dialog
        
        if (success) {
          SnackbarUtils.showSuccess(
            title: 'Account Deleted',
            message: 'Your account has been permanently deleted',
          );
        } else {
          SnackbarUtils.showError(
            title: 'Error',
            message: 'Failed to delete account. Please try again.',
          );
        }
      } catch (e) {
        Get.back(); // Close loading dialog
        
        SnackbarUtils.showError(
          title: 'Error',
          message: 'Failed to delete account: $e',
        );
      }
    }
  }
}

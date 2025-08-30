import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';
import 'package:securesphere/config/api_config.dart';
import 'package:securesphere/features/auth/services/auth_service.dart';
import 'package:securesphere/features/sia/services/sia_service.dart';
import 'package:securesphere/features/auth/services/security_service.dart';
import 'package:securesphere/features/auth/screens/pin_setup_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Backup storage options
  final List<String> _backupOptions = [
    'SecureSphere',
    'Self-Hosted SIA Node'
  ];
  String _selectedBackupOption = 'SecureSphere';
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
  static const _storage = FlutterSecureStorage();
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
      final savedOption = prefs.getString('backupOption') ?? 'SecureSphere';
      
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
      
      Get.snackbar(
        'SIA Disconnected',
        'Successfully disconnected from Self-Hosted SIA',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to disconnect from SIA: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
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
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                        const Text(
                          'Backup Storage',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Choose your preferred backup storage option:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedBackupOption == 'Self-Hosted SIA Node' ? 'SecureSphere' : _selectedBackupOption,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      items: ['SecureSphere'].map((String option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(option),
                        );
                      }).toList(),
                      onChanged: (String? newValue) async {
                        if (newValue != null) {
                          setState(() {
                            _selectedBackupOption = newValue;
                            _siaStatusMessage = 'Using SecureSphere SIA Node';
                            _siaConnected = false;
                          });
                          
                          // Clear SIA form when switching to SecureSphere
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
                          const Expanded(
                            child: Text(
                              'SecureSphere uses decentralized servers with full encryption. No one has access to your data.',
                              style: TextStyle(fontSize: 13),
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
                        const Text(
                          'Advanced Settings',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                      title: const Text('SIA Node Configuration'),
                      subtitle: Text(_selectedBackupOption == 'Self-Hosted SIA Node' 
                          ? 'Self-hosted node configured' 
                          : 'Use custom SIA node'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _showSiaConfigurationDialog(),
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
            
            Get.snackbar('Success', 'SIA node connected and configured successfully');
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
        Get.snackbar(
          'Error',
          'User ID not available. Please try logging in again.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
        );
        return false;
      }
      
      if (ApiConfig.psqlApiKey.isEmpty) {
        Get.snackbar(
          'Configuration Error',
          'Backend API key not configured. SIA config will be saved locally only.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange.withOpacity(0.8),
          colorText: Colors.white,
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
        Get.snackbar(
          'Backend Error',
          'Failed to save SIA config to server (${response.statusCode}). Config saved locally.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange.withOpacity(0.8),
          colorText: Colors.white,
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
      
      Get.snackbar(
        'Backend Unavailable',
        userMessage,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.withOpacity(0.8),
        colorText: Colors.white,
      );
      
      return true; // Continue with local storage only
    }
  }
  
  Future<bool> _saveSiaConfigLocally(String host, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final configData = {
        'host': host,
        'port': port,
        'isSecureSphereManagedNode': false,
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
      
      Get.snackbar('Settings', 'Settings saved successfully');
    } catch (e) {
      Get.snackbar('Error', 'Failed to save settings: $e');
    }
  }
  
  /// Get current SIA configuration based on user selection
  Future<Map<String, String>?> getCurrentSiaConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupOption = prefs.getString('backupOption') ?? 'SecureSphere';
      
      if (backupOption == 'SecureSphere') {
        // Use SecureSphere config from api_config.dart (but hide password in settings)
        return {
          'host': ApiConfig.SSip,
          'port': ApiConfig.SSport,
          'password': '', // Never show SecureSphere password in settings
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

  Future<void> _showSiaConfigurationDialog() async {
    String dialogBackupOption = _selectedBackupOption;
    
    await Get.dialog(
      StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('SIA Node Configuration'),
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
      Get.snackbar('Error', 'Security service not available');
      return;
    }
    
    int currentMinutes;
    try {
      currentMinutes = securityService.securitySettings.autoLockTimeMinutes;
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
                            '• SecureSphere will never ask for your phrase\n'
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
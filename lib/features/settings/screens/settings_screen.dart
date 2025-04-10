import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Backup storage options
  final List<String> _backupOptions = [
    'SecureSphere Decentralized Server',
    'Self-hosted SIA',
    'S3 Server'
  ];
  String _selectedBackupOption = 'SecureSphere Decentralized Server';
  
  // Controllers for text fields
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

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadBiometricsSetting();
  }

  Future<void> _checkBiometrics() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    setState(() {
      _biometricsAvailable = canCheck;
    });
  }

  Future<void> _loadBiometricsSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useBiometrics = prefs.getBool('use_biometrics') ?? false;
    });
  }

  Future<void> _changePin() async {
    if (_newPinController.text != _confirmPinController.text) {
      Get.snackbar('Error', 'New PIN codes do not match');
      return;
    }
    
    if (_newPinController.text.isEmpty || _newPinController.text.length < 4) {
      Get.snackbar('Error', 'PIN must be at least 4 digits');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final storedPin = prefs.getString('pin');
    
    if (storedPin != _currentPinController.text) {
      Get.snackbar('Error', 'Current PIN is incorrect');
      return;
    }
    
    await prefs.setString('pin', _newPinController.text);
    
    Get.snackbar('Success', 'PIN changed successfully');
    _currentPinController.clear();
    _newPinController.clear();
    _confirmPinController.clear();
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (value) {
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Authenticate to enable biometric login',
        );
        
        if (authenticated) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('use_biometrics', value);
          setState(() {
            _useBiometrics = value;
          });
        }
      } catch (e) {
        Get.snackbar('Error', 'Biometric authentication failed: $e');
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('use_biometrics', value);
      setState(() {
        _useBiometrics = value;
      });
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
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              child: Column(
                ),
            ),
            const Divider(),
            const Text(
              'Backup Storage Configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select where you want to store your backups:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedBackupOption,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              items: _backupOptions.map((String option) {
                return DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedBackupOption = newValue;
                  });
                }
              },
            ),
            const SizedBox(height: 24),
            
            // Conditional form fields based on selected option
            if (_selectedBackupOption == 'Self-hosted SIA') ..._buildSiaForm(),
            if (_selectedBackupOption == 'S3 Server') ..._buildS3Form(),
            
            const SizedBox(height: 32),
            
            // Security Settings Section
            const Divider(),
            const Text(
              'Security Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Biometric Authentication Section
            if (_biometricsAvailable) ...[              
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
                          const Icon(Icons.fingerprint, color: Color(0xFF1E8E3E)),
                          const SizedBox(width: 8),
                          const Text(
                            'Biometric Authentication',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Use your fingerprint, face, or other biometric method to quickly access your account.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Enable Biometric Login'),
                        subtitle: Text(_useBiometrics 
                            ? 'Biometric authentication is enabled' 
                            : 'Biometric authentication is disabled'),
                        value: _useBiometrics,
                        onChanged: _toggleBiometrics,
                        secondary: Icon(
                          _useBiometrics ? Icons.check_circle : Icons.cancel,
                          color: _useBiometrics ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            // PIN Management Section
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pin, color: Color(0xFF1E8E3E)),
                        const SizedBox(width: 8),
                        const Text(
                          'Change PIN',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your PIN is used to secure access to your account. Make sure to use a PIN that you can remember but is difficult for others to guess.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _currentPinController,
                      decoration: const InputDecoration(
                        labelText: 'Current PIN',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      obscureText: true,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newPinController,
                      decoration: const InputDecoration(
                        labelText: 'New PIN',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                        helperText: 'PIN must be at least 4 digits',
                      ),
                      obscureText: true,
                      keyboardType: TextInputType.number,
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
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _changePin,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: const Color(0xFF1E8E3E),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Update PIN'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Save Settings'),
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
          hintText: 'e.g., https://s3.amazonaws.com',
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

  void _saveSettings() {
    // This is just UI implementation, actual saving functionality would be implemented later
    Get.snackbar(
      'Settings Saved',
      'Your backup configuration has been saved',
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}
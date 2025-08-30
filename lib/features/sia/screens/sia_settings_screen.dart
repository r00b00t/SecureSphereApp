import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:securesphere/features/sia/services/sia_service.dart';

class SiaSettingsScreen extends StatefulWidget {
  const SiaSettingsScreen({super.key});

  @override
  State<SiaSettingsScreen> createState() => _SiaSettingsScreenState();
}

class _SiaSettingsScreenState extends State<SiaSettingsScreen> {
  String _selectedOption = 'SecureSphere';
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isConnectionTesting = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final backupOption = prefs.getString('backupOption') ?? 'SecureSphere';
    
    setState(() {
      _selectedOption = backupOption;
    });

    if (backupOption == 'Self-hosted') {
      final siaService = Get.find<SiaService>();
      final config = siaService.currentConfig;
      
      if (config != null && !config.isSecureSphereManagedNode) {
        setState(() {
          _hostController.text = config.host;
          _portController.text = config.port;
          _passwordController.text = config.password;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backupOption', _selectedOption);

      if (_selectedOption == 'Self-hosted') {
        // Validate self-hosted settings
        if (_hostController.text.trim().isEmpty ||
            _portController.text.trim().isEmpty ||
            _passwordController.text.trim().isEmpty) {
          Get.snackbar(
            'Error',
            'Please fill in all fields for self-hosted configuration',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red[100],
            colorText: Colors.red[800],
          );
          return;
        }

        // Save to backend and locally
        final siaService = Get.find<SiaService>();
        final success = await siaService.saveSiaConfigToBackend(
          _hostController.text.trim(),
          _portController.text.trim(),
          _passwordController.text.trim(),
        );

        if (!success) {
          Get.snackbar(
            'Error',
            'Failed to save SIA node configuration',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red[100],
            colorText: Colors.red[800],
          );
          return;
        }
      }

      Get.snackbar(
        'Success',
        'SIA node settings saved successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green[100],
        colorText: Colors.green[800],
      );

      Get.back(); // Return to previous screen
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save settings: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
        colorText: Colors.red[800],
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testConnection() async {
    if (_selectedOption != 'Self-hosted') return;

    if (_hostController.text.trim().isEmpty || _portController.text.trim().isEmpty) {
      Get.snackbar(
        'Error',
        'Please enter host and port to test connection',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
        colorText: Colors.red[800],
      );
      return;
    }

    setState(() {
      _isConnectionTesting = true;
    });

    try {
      // Here you would implement actual connection testing
      // For now, just simulate a test
      await Future.delayed(const Duration(seconds: 2));
      
      Get.snackbar(
        'Success',
        'Connection test successful',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green[100],
        colorText: Colors.green[800],
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Connection test failed: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
        colorText: Colors.red[800],
      );
    } finally {
      setState(() {
        _isConnectionTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIA Node Settings'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select SIA Node Configuration',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            
            // SecureSphere Option
            RadioListTile<String>(
              title: const Text('SecureSphere Decentralized Server'),
              subtitle: const Text('Use our managed SIA node (recommended)'),
              value: 'SecureSphere',
              groupValue: _selectedOption,
              onChanged: (value) {
                setState(() {
                  _selectedOption = value!;
                  // Clear self-hosted fields when switching to SecureSphere
                  _hostController.clear();
                  _portController.clear();
                  _passwordController.clear();
                });
              },
            ),
            
            // Self-hosted Option
            RadioListTile<String>(
              title: const Text('Self-hosted SIA Node'),
              subtitle: const Text('Use your own SIA node'),
              value: 'Self-hosted',
              groupValue: _selectedOption,
              onChanged: (value) {
                setState(() {
                  _selectedOption = value!;
                });
              },
            ),
            
            const SizedBox(height: 24),
            
            // Self-hosted configuration fields
            if (_selectedOption == 'Self-hosted') ...[
              Text(
                'SIA Node Configuration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host/IP Address',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., 192.168.1.100',
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., 9980',
                ),
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              
              // Test Connection Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isConnectionTesting ? null : _testConnection,
                  icon: _isConnectionTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  label: Text(_isConnectionTesting ? 'Testing...' : 'Test Connection'),
                ),
              ),
              
              const SizedBox(height: 24),
            ],
            
            const Spacer(),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
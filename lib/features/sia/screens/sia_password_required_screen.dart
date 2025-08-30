import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/sia/services/sia_service.dart';

class SiaPasswordRequiredScreen extends StatefulWidget {
  const SiaPasswordRequiredScreen({super.key});

  @override
  State<SiaPasswordRequiredScreen> createState() => _SiaPasswordRequiredScreenState();
}

class _SiaPasswordRequiredScreenState extends State<SiaPasswordRequiredScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  Map<String, String>? _siaConfig;

  @override
  void initState() {
    super.initState();
    _loadSiaConfig();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSiaConfig() async {
    try {
      final siaService = Get.find<SiaService>();
      
      // Force load the SIA configuration first
      await siaService.loadSiaConfiguration();
      
      final config = siaService.currentConfig;
      
      if (config != null) {
        setState(() {
          _siaConfig = {
            'host': config.host,
            'port': config.port,
          };
        });
      } else {
      }
    } catch (e) {
    }
  }

  Future<void> _savePasswordAndContinue() async {
    final password = _passwordController.text.trim();
    
    if (password.isEmpty) {
      Get.snackbar(
        'Password Required',
        'Please enter your SIA node password to continue',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange[100],
        colorText: Colors.orange[800],
        icon: const Icon(Icons.warning, color: Colors.orange),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final siaService = Get.find<SiaService>();
      await siaService.updatePassword(password);
      
      
      // Navigate to home screen
      Get.offAllNamed('/home');
      
      Get.snackbar(
        'Password Saved',
        'Your SIA node password has been saved securely',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green[100],
        colorText: Colors.green[800],
        icon: const Icon(Icons.check_circle, color: Colors.green),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save password: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[100],
        colorText: Colors.red[800],
        icon: const Icon(Icons.error, color: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _skipToHome() {
    Get.offAllNamed('/home');
    
    Get.snackbar(
      'Skipped',
      'You can add your SIA password later in Settings',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.blue[100],
      colorText: Colors.blue[800],
      icon: const Icon(Icons.info, color: Colors.blue),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Force dark background
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                const SizedBox(height: 40),
                Icon(
                  Icons.security,
                  size: 80,
                  color: const Color(0xFF1E8E3E), // Green primary color
                ),
                const SizedBox(height: 24),
                Text(
                  'SIA Node Password Required',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'We found your self-hosted SIA node configuration',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Config Info Card
                if (_siaConfig != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E), // Force dark card color
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3C4043)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        spreadRadius: 1,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns, color: Theme.of(context).primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Your SIA Node Configuration',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildConfigRow('Host', _siaConfig!['host']!),
                      _buildConfigRow('Port', _siaConfig!['port']!),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ] else ...[
                // Fallback when config is not loaded
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3C4043)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns, color: const Color(0xFF1E8E3E), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Loading SIA Configuration...',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Please wait while we load your self-hosted SIA node details.',
                        style: TextStyle(
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // Password Input
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E), // Force dark card color
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3C4043)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter Your SIA Node Password',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      autofocus: true,
                      enabled: !_isLoading,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'SIA Node Password',
                        labelStyle: const TextStyle(color: Colors.grey),
                        hintText: 'Enter your password...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock, color: Colors.grey[400]),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            color: Colors.grey[400],
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                      ),
                      onSubmitted: (_) => _savePasswordAndContinue(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This password will be encrypted and stored locally for secure access to your SIA node.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 60), // Replace Spacer with fixed spacing

              // Action Buttons
              Column(
                children: [
                  SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _savePasswordAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E8E3E), // Force green primary
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Saving...', style: TextStyle(color: Colors.white)),
                                ],
                              )
                            : const Text(
                                'Save Password & Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _skipToHome,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[400],
                          side: BorderSide(color: Colors.grey[600]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Skip (Add Later in Settings)',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfigRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[400],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SiaPasswordDialog extends StatefulWidget {
  final String host;
  final String port;
  
  const SiaPasswordDialog({
    super.key,
    required this.host,
    required this.port,
  });

  @override
  State<SiaPasswordDialog> createState() => _SiaPasswordDialogState();
}

class _SiaPasswordDialogState extends State<SiaPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  static const _storage = FlutterSecureStorage();
  static const _siaPasswordKey = 'sia_password';
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    final password = _passwordController.text.trim();
    
    if (password.isEmpty) {
      Get.snackbar('Error', 'Please enter your SIA node password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Save password locally
      await _storage.write(key: _siaPasswordKey, value: password);
      Get.back(result: true);
      Get.snackbar('Success', 'SIA node password saved successfully');
    } catch (e) {
      Get.snackbar('Error', 'Failed to save password: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _skipForNow() {
    Get.back(result: false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('SIA Node Password Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your SIA node configuration is ready but requires a password to connect.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'SIA Node: ${widget.host}:${widget.port}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'SIA Node Password',
              hintText: 'Enter your SIA node password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            obscureText: _obscurePassword,
            enabled: !_isLoading,
            onSubmitted: (_) => _savePassword(),
          ),
          const SizedBox(height: 12),
          Text(
            'This password will be stored securely on your device only.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[400],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : _skipForNow,
          child: const Text('Skip for now'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _savePassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[900],
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Save Password'),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/sia/services/sia_service.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

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
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    
    if (_passwordController.text.trim().isEmpty) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Please enter your SIA node password',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final siaService = Get.find<SiaService>();
      await siaService.updatePassword(_passwordController.text.trim());
      
      Get.back(); // Close dialog
      
      SnackbarUtils.showSuccess(
        title: 'Success',
        message: 'SIA node password saved successfully',
      );
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to save password: $e',
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back button dismissal
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.security, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Expanded(child: Text('SIA Node Password Required')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your self-hosted SIA node configuration:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Host: ${widget.host}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Port: ${widget.port}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Please enter your SIA node password to continue:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'SIA Node Password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
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
              onSubmitted: (_) => _savePassword(),
            ),
            const SizedBox(height: 8),
            Text(
              'This password will be encrypted and stored locally for future use.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _savePassword,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Saving...'),
                      ],
                    )
                  : const Text('Save Password'),
            ),
          ),
        ],
      ),
    );
  }
}

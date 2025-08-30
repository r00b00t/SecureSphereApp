import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/auth/services/security_service.dart';

class PinVerificationScreen extends StatefulWidget {
  final VoidCallback? onSuccess;
  final bool isLockScreen;
  const PinVerificationScreen({Key? key, this.onSuccess, this.isLockScreen = false}) : super(key: key);

  @override
  State<PinVerificationScreen> createState() => _PinVerificationScreenState();
}

class _PinVerificationScreenState extends State<PinVerificationScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _verifyPin() async {
    // Enforce 6-digit PIN requirement
    if (_pinController.text.length != 6) {
      setState(() {
        _error = 'PIN must be exactly 6 digits';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final securityService = Get.find<SecurityService>();
      final isValid = await securityService.verifyPinCode(_pinController.text);
      setState(() {
        _isLoading = false;
      });
      
      if (isValid) {
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _error = 'Incorrect 6-digit PIN. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error verifying PIN. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isLockScreen
          ? null
          : AppBar(
              title: const Text('Verify PIN'),
              automaticallyImplyLeading: !widget.isLockScreen,
            ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                widget.isLockScreen ? 'App Locked' : 'Enter your PIN to continue',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.pin),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onSubmitted: (_) => _verifyPin(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyPin,
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Verify'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
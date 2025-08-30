import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/security_service.dart';
import 'forgot_pin_screen.dart';

class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({super.key});

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen> with WidgetsBindingObserver {
  final SecurityService _securityService = Get.find<SecurityService>();
  final TextEditingController _pinController = TextEditingController();
  
  String _enteredPin = '';
  bool _isLoading = false;
  String? _errorMessage;
  int _failedAttempts = 0;
  static const int _maxFailedAttempts = 5;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Auto-trigger biometric authentication if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometricAuth();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reset failed attempts when app resumes
      setState(() {
        _failedAttempts = 0;
        _errorMessage = null;
      });
    }
  }

  Future<void> _tryBiometricAuth() async {
    if (!_securityService.securitySettings.biometricEnabled) return;
    if (!_securityService.biometricsAvailable) return;
    if (_isLoading) return; // Prevent multiple attempts
    
    setState(() {
      _isLoading = true;
    });
    
    // Small delay to ensure screen is rendered
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      final success = await _securityService.unlockWithBiometrics();
      if (success) {
        _onUnlockSuccess();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Continue with PIN entry
    }
  }

  void _onNumberPressed(String number) {
    if (_enteredPin.length < 6) { // Max 6 digits
      setState(() {
        _enteredPin += number;
        _errorMessage = null;
      });
      
      
      // Auto-verify when exactly 6 digits are entered
      if (_enteredPin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = null;
      });
    }
  }

  Future<void> _verifyPin() async {
    if (_enteredPin.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final success = await _securityService.unlockWithPin(_enteredPin);
      
      if (success) {
        _onUnlockSuccess();
      } else {
        setState(() {
          _failedAttempts++;
          _enteredPin = '';
          _errorMessage = _failedAttempts >= _maxFailedAttempts 
              ? 'Too many failed attempts. Please try again later.'
              : 'Incorrect PIN. Try again.';
          _isLoading = false;
        });
        
        // Vibrate on failed attempt
        // HapticFeedback.mediumImpact();
      }
    } catch (e) {
      setState(() {
        _enteredPin = '';
        _errorMessage = 'Authentication error. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _onUnlockSuccess() {
    // Close the dialog and unlock the app
    
    // Add longer delay to prevent immediate re-lock from lifecycle events
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Get.back(); // Close the PIN dialog
        
        // If we're on the auth screen (fresh startup), navigate to home
        if (Get.currentRoute == '/auth') {
          Get.offAllNamed('/home');
        }
      }
    });
  }

  Future<void> _showBiometricAuth() async {
    try {
      final success = await _securityService.unlockWithBiometrics();
      if (success) {
        _onUnlockSuccess();
      }
    } catch (e) {
      Get.snackbar(
        'Authentication Failed',
        'Biometric authentication failed. Please use your PIN.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biometricsEnabled = _securityService.securitySettings.biometricEnabled;
    final biometricsAvailable = _securityService.biometricsAvailable;
    
    return PopScope(
      canPop: false, // Disable back button completely
      onPopInvoked: (didPop) {
        if (didPop) return;
        // Show message that PIN is required
        Get.snackbar(
          'Security Required',
          'Please enter your PIN to continue',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      },
      child: Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                        MediaQuery.of(context).padding.top - 
                        MediaQuery.of(context).padding.bottom - 40,
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),
              
              // App Logo/Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.security,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Text(
                'Enter PIN to unlock',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              Text(
                'Enter your 6-digit PIN to access SecureSphere',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 32),
              
              // PIN dots indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled 
                          ? theme.primaryColor 
                          : theme.colorScheme.outline.withOpacity(0.3),
                      border: Border.all(
                        color: theme.primaryColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                  );
                }),
              ),
              
              const SizedBox(height: 12),
              
              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              const SizedBox(height: 32),
              
              // PIN keypad
              if (_failedAttempts < _maxFailedAttempts) ...[
                _buildKeypad(theme),
                
                const SizedBox(height: 12),
                
                // Biometric authentication button
                if (biometricsEnabled && biometricsAvailable)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _showBiometricAuth,
                        icon: const Icon(Icons.fingerprint, size: 20),
                        label: const Text('Use Biometric'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: theme.colorScheme.secondary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                // Locked out message
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.warning,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Too many failed attempts',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please close and reopen the app to try again.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    ), // Close Scaffold
    ); // Close PopScope
  }

  Widget _buildKeypad(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        children: [
          // Row 1: 1, 2, 3
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('1', theme),
              _buildKeypadButton('2', theme),
              _buildKeypadButton('3', theme),
            ],
          ),
          const SizedBox(height: 12),
          
          // Row 2: 4, 5, 6
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('4', theme),
              _buildKeypadButton('5', theme),
              _buildKeypadButton('6', theme),
            ],
          ),
          const SizedBox(height: 12),
          
          // Row 3: 7, 8, 9
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('7', theme),
              _buildKeypadButton('8', theme),
              _buildKeypadButton('9', theme),
            ],
          ),
          const SizedBox(height: 12),
          
          // Row 4: empty, 0, backspace
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 60, height: 60), // Empty space
              _buildKeypadButton('0', theme),
              _buildBackspaceButton(theme),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Forgot PIN button
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : () {
                Get.to(() => const ForgotPinScreen());
              },
              style: TextButton.styleFrom(
                foregroundColor: theme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: const Text(
                'Forgot PIN?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadButton(String number, ThemeData theme) {
    return GestureDetector(
      onTap: _isLoading ? null : () => _onNumberPressed(number),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            number,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton(ThemeData theme) {
    return GestureDetector(
      onTap: _isLoading ? null : _onBackspacePressed,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.backspace_outlined,
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }
}
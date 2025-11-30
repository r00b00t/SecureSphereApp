import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'dart:io';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/auth/screens/pin_setup_screen.dart';
import 'package:decvault/features/auth/screens/pin_unlock_screen.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Text controllers
  final TextEditingController _seedPhraseController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  

  final List<TextEditingController> _wordControllers = 
      List.generate(12, (_) => TextEditingController());
      
  // UI state variables
  bool _showWelcome = true;  // Show welcome screen first
  bool _isRegistering = true; 
  bool _biometricsAvailable = false;
  bool _useBiometrics = false;
  String? _generatedSeedPhrase;
  
  
  final AuthService _authService = Get.find<AuthService>();
  SecurityService? get _securityService {
    try {
      return Get.find<SecurityService>();
    } catch (e) {
      return null;
    }
  } 
  
  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _checkLoggedInStatus();
    // Don't generate seed phrase yet - wait until user chooses to sign up
  }

  Future<void> _checkLoggedInStatus() async {
    final isLoggedIn = await _authService.checkLoginStatus();
    if (isLoggedIn) {
      // Quick check if PIN authentication might be required
      final securityService = _securityService;
      if (securityService != null && securityService.hasSecurityEnabled && securityService.isAppLocked) {
        // Show PIN unlock screen instead of navigating to home
        Get.dialog(
          const PinUnlockScreen(),
          barrierDismissible: false,
          barrierColor: Colors.black87,
        );
        return;
      }
      
      // No PIN required - navigate immediately to home
      Get.offAllNamed('/home');
    }
  }

  Future<void> _checkBiometrics() async {
 
    if (kIsWeb) {
      setState(() {
        _biometricsAvailable = false;
      });
      return;
    }
    
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      setState(() {
        _biometricsAvailable = canCheck;
      });
    } catch (e) {

      setState(() {
        _biometricsAvailable = false;
      });
    }
  }

  Future<void> _generateSeedPhrase() async {
    final seedPhrase = bip39.generateMnemonic();
    setState(() {
      _generatedSeedPhrase = seedPhrase;
      _seedPhraseController.text = _generatedSeedPhrase ?? '';
    });
  }
  
  /// Safely shows a snackbar by ensuring the overlay is ready
  void _safeShowSnackbar({
    required String title,
    required String message,
    Color? backgroundColor,
    Color? colorText,
    Duration? duration,
  }) {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      title == 'Copied' ? Icons.check_circle : Icons.info,
                      color: colorText ?? Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorText ?? Colors.white,
                            ),
                          ),
                          Text(
                            message,
                            style: TextStyle(
                              color: colorText ?? Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                backgroundColor: backgroundColor ?? Theme.of(context).primaryColor.withOpacity(0.8),
                duration: duration ?? const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          } catch (e) {
          }
        }
      });
    }
  }

  Future<void> _copySeedPhrase() async {
    if (_generatedSeedPhrase != null) {
      await Clipboard.setData(ClipboardData(text: _generatedSeedPhrase!));
      _safeShowSnackbar(
        title: 'Copied',
        message: 'Seed phrase copied to clipboard',
        backgroundColor: Colors.green.withOpacity(0.8),
      );
    }
  }
  
  Future<void> _promptPinCreationIfNeeded() async {
    final securityService = _securityService;
    if (securityService == null) {
      return;
    }
    
    try {
      final hasPIN = await securityService.hasPinSet();
      if (!hasPIN) {
        // Show dialog to ask user if they want to create a PIN
        final shouldCreatePin = await showDialog<bool>(
          context: Get.context!,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.security, color: Colors.blue),
                SizedBox(width: 12),
                Flexible(
                  child: Text('Secure Your Account'),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Would you like to create a 6-digit PIN code to secure your account?',
                  ),
                  SizedBox(height: 16),
                  Text(
                    'A PIN provides:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text('• Quick access to your vault'),
                  SizedBox(height: 4),
                  Text('• Backup authentication method'),
                  SizedBox(height: 4),
                  Text('• Required for biometric unlock'),
                  SizedBox(height: 16),
                  Text(
                    'You can set this up later in Settings if you prefer.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Skip for Now'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Create PIN'),
              ),
            ],
          ),
        );
        
        if (shouldCreatePin == true) {
          // Import PinSetupScreen if not already imported
          final result = await Get.to(() => const PinSetupScreen(
            isOptional: true,
            title: 'Create Your Security PIN',
          ));
          
          if (result == true) {
            _safeShowSnackbar(
              title: 'Success',
              message: 'PIN created successfully! You can now enable biometric authentication in Settings.',
              backgroundColor: Colors.green.withOpacity(0.8),
            );
          }
        }
      }
    } catch (e) {
    }
  }
  
  Future<void> _loginWithSeedPhrase() async {

    final enteredSeedPhrase = _wordControllers.map((controller) => controller.text.trim()).join(' ');

    
    // Show loading indicator
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );
    
    try {

      final loginSuccess = await _authService.loginUser(enteredSeedPhrase);
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
      
      if (loginSuccess) {
        // Mark initial setup as complete after successful login
        final securityService = _securityService;
        if (securityService != null) {
          await securityService.markInitialSetupComplete();
        }

        // Check if PIN is set, if not, prompt user to create one
        await _promptPinCreationIfNeeded();

        Get.offAllNamed('/home');
      } else {
        _safeShowSnackbar(
          title: 'Login Issue',
          message: 'Unable to verify credentials. Please check your seed phrase.',
          backgroundColor: Colors.orange.withOpacity(0.8),
        );
      }
    } catch (e) {
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
      _safeShowSnackbar(
        title: 'Notice',
        message: 'Login could not be completed. Please try again.',
        backgroundColor: Colors.orange.withOpacity(0.8),
      );
    }
  }

  @override
  void dispose() {

    if (Get.isDialogOpen ?? false) {
      Get.back();
    }
    _seedPhraseController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    for (var controller in _wordControllers) {
      controller.dispose();
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF121212),
              const Color(0xFF1E1E1E),
              Theme.of(context).primaryColor.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  
                  // Welcome text
                  TweenAnimationBuilder(
                    duration: const Duration(milliseconds: 600),
                    tween: Tween<double>(begin: 0, end: 1),
                    builder: (context, double value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: const Text(
                      'Welcome to',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // App Logo/Icon
                  TweenAnimationBuilder(
                    duration: const Duration(milliseconds: 800),
                    tween: Tween<double>(begin: 0, end: 1),
                    builder: (context, double value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: value,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/logo/green.png',
                        width: 100,
                        height: 100,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // App Name
                  TweenAnimationBuilder(
                    duration: const Duration(milliseconds: 600),
                    tween: Tween<double>(begin: 0, end: 1),
                    builder: (context, double value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: const Text(
                      'DecVault',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Secure Decentralized Storage',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.1),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _showWelcome 
                        ? _buildWelcomeView(context)
                        : (_isRegistering ? _buildRegistrationView(context) : _buildLoginView(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeView(BuildContext context) {
    return Column(
      key: const ValueKey('welcome'),
      children: [
        // Welcome content
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Your private, secure, and decentralized storage solution',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[400],
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 40),
        
        // Features section
        _buildFeatureItem(
          icon: Icons.security,
          title: 'Bank-Level Security',
          description: 'Your data is encrypted with industry-standard encryption',
          color: Colors.green,
        ),
        const SizedBox(height: 20),
        _buildFeatureItem(
          icon: Icons.cloud_off,
          title: 'Decentralized Storage',
          description: 'Store your files across a distributed network',
          color: Colors.blue,
        ),
        const SizedBox(height: 20),
        _buildFeatureItem(
          icon: Icons.key,
          title: 'You Own Your Keys',
          description: 'Only you have access to your data, always',
          color: Colors.purple,
        ),
        
        const SizedBox(height: 50),
        
        // Sign Up button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _showWelcome = false;
                _isRegistering = true;
                _generateSeedPhrase();
              });
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add, size: 24),
                SizedBox(width: 12),
                Text(
                  'Create New Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Sign In button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _showWelcome = false;
                _isRegistering = false;
              });
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.login,
                  size: 24,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Text(
                  'Sign In',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[400],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationView(BuildContext context) {
    return Column(
      key: const ValueKey('registration'),
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () {
              setState(() {
                _showWelcome = true;
              });
            },
            icon: const Icon(Icons.arrow_back),
            iconSize: 28,
            tooltip: 'Back',
          ),
        ),
        const SizedBox(height: 16),
        
        // REGISTRATION SCREEN
        const Text(
          'Create New Account',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your gateway to secure decentralized storage',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[400],
          ),
        ),
        const SizedBox(height: 32),
        
        // Seed phrase section with improved design
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1E8E3E).withValues(alpha: 0.1),
                const Color(0xFF34A853).withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.key,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Your Recovery Seed Phrase',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Display seed phrase as numbered grid
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _generatedSeedPhrase != null
                    ? _buildSeedPhraseGrid(_generatedSeedPhrase!)
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
              ),
              const SizedBox(height: 16),
              
              // Copy button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _copySeedPhrase,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy to Clipboard'),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.stars_rounded,
                      color: Colors.amber,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Important!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Write this down and store it safely. You\'ll need it to recover your account.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[300],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Security Setup Card with improved design
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue.withValues(alpha: 0.1),
                Colors.purple.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.security,
                      color: Colors.blueAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Extra Security',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Optional',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Add an extra layer of security with PIN and biometric authentication.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[300],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              
              // PIN Setup Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final result = await Get.to(() => const PinSetupScreen(
                      isOptional: true,
                      title: 'Set up PIN for extra security',
                    ));
                    
                    if (result == true) {
                      setState(() {
                        // PIN was set successfully
                      });
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.blueAccent),
                  ),
                  icon: const Icon(Icons.pin, color: Colors.blueAccent),
                  label: const Text('Set up PIN'),
                ),
              ),
              
              // Biometrics option
              if (_biometricsAvailable) ...[
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: _useBiometrics
                        ? Colors.blue.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _useBiometrics
                          ? Colors.blueAccent
                          : Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'Biometric Authentication',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Use fingerprint or face recognition',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _useBiometrics,
                    onChanged: (value) async {
                      if (value) {
                        try {
                          final authenticated = await _localAuth.authenticate(
                            localizedReason: 'Authenticate to enable biometric login',
                            options: const AuthenticationOptions(
                              biometricOnly: true,
                              stickyAuth: true,
                            ),
                          );
                          
                          if (authenticated) {
                            setState(() {
                              _useBiometrics = value;
                            });
                          }
                        } catch (e) {
                          _safeShowSnackbar(
                            title: 'Notice',
                            message: 'Biometric authentication could not be completed.',
                            backgroundColor: Colors.orange.withOpacity(0.8),
                          );
                        }
                      } else {
                        setState(() {
                          _useBiometrics = value;
                        });
                      }
                    },
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _useBiometrics
                            ? Colors.blueAccent.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.fingerprint,
                        color: _useBiometrics ? Colors.blueAccent : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Register button with improved design
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              if (_generatedSeedPhrase != null) {
                // Show loading dialog
                Get.dialog(
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF1E1E1E),
                              const Color(0xFF2A2A2A),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor.withValues(alpha: 0.2),
                                    Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                  ],
                                ),
                              ),
                              child: Image.asset(
                                'assets/logo/green.png',
                                width: 64,
                                height: 64,
                              ),
                            ),
                            const SizedBox(height: 24),
                            CircularProgressIndicator(
                              color: Theme.of(context).primaryColor,
                              strokeWidth: 3,
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Creating your account...',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Setting up your secure vault',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF9E9E9E),
                                decoration: TextDecoration.none,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  barrierDismissible: false,
                );
                
                try {
                  final success = await _authService.registerUser(_generatedSeedPhrase!);
                  
                  if (Get.isDialogOpen ?? false) {
                    Get.back();
                  }
                  
                  if (success) {
                    // Mark initial setup as complete after successful registration
                    final securityService = _securityService;
                    if (securityService != null) {
                      await securityService.markInitialSetupComplete();
                    }
                    
                    // Check if PIN is set, if not, prompt user to create one
                    // This must happen before enabling biometrics
                    await _promptPinCreationIfNeeded();
                    
                    // Now enable biometrics if user wanted it AND has created a PIN
                    if (_useBiometrics && _biometricsAvailable) {
                      final securityService = _securityService;
                      if (securityService != null) {
                        final hasPIN = await securityService.hasPinSet();
                        if (hasPIN) {
                          await securityService.enableBiometrics();
                        } else {
                          // User wanted biometrics but didn't create PIN
                          _safeShowSnackbar(
                            title: 'Info',
                            message: 'Biometric authentication requires a PIN. You can enable it later in Settings after creating a PIN.',
                            backgroundColor: Colors.orange.withOpacity(0.8),
                          );
                        }
                      }
                    }
                    
                    // Show paywall on mobile after signup
                    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
                      try {
                        final revenueCatService = Get.find<RevenueCatService>();
                        await revenueCatService.presentPaywall();
                      } catch (e) {
                      }
                    }
                    
                    Get.offAllNamed('/home');
                  } else {
                    _safeShowSnackbar(
                      title: 'Notice',
                      message: 'Unable to complete registration. Please try again.',
                      backgroundColor: Colors.orange.withOpacity(0.8),
                    );
                  }
                } catch (e) {
                  if (Get.isDialogOpen ?? false) {
                    Get.back();
                  }
                  _safeShowSnackbar(
                    title: 'Notice',
                    message: 'Registration could not be completed. Please try again.',
                    backgroundColor: Colors.orange.withOpacity(0.8),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 24),
                SizedBox(width: 12),
                Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLoginView(BuildContext context) {
    return Column(
      key: const ValueKey('login'),
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () {
              setState(() {
                _showWelcome = true;
              });
            },
            icon: const Icon(Icons.arrow_back),
            iconSize: 28,
            tooltip: 'Back',
          ),
        ),
        const SizedBox(height: 16),
        
        const Text(
          'Welcome Back',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Enter your recovery phrase to continue',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[400],
          ),
        ),
        const SizedBox(height: 32),
        
        // Seed phrase input
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1E8E3E).withValues(alpha: 0.1),
                const Color(0xFF34A853).withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.key,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Recovery Seed Phrase',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Enter your 12-word recovery phrase',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 20),
              
              // Grid of word inputs
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 3.5,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                    child: TextFormField(
                      controller: _wordControllers[index],
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '${index + 1}',
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).primaryColor,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      textInputAction: index < 11 
                          ? TextInputAction.next 
                          : TextInputAction.done,
                      onFieldSubmitted: index == 11 
                          ? (_) => _loginWithSeedPhrase() 
                          : null,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Login button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loginWithSeedPhrase,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.login, size: 24),
                SizedBox(width: 12),
                Text(
                  'Login',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSeedPhraseGrid(String seedPhrase) {
    final words = seedPhrase.split(' ');
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: words.length,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  words[index],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

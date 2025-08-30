import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:securesphere/features/auth/services/auth_service.dart';
import 'package:securesphere/features/auth/services/security_service.dart';
import 'package:securesphere/features/auth/screens/pin_setup_screen.dart';
import 'package:securesphere/features/auth/screens/pin_unlock_screen.dart';

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
    _generateSeedPhrase();
    _checkLoggedInStatus();
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
  
  Future<void> _copySeedPhrase() async {
    if (_generatedSeedPhrase != null) {
      await Clipboard.setData(ClipboardData(text: _generatedSeedPhrase!));
      Get.snackbar('Copied', 'Seed phrase copied to clipboard');
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    if (kIsWeb) {
      Get.snackbar('Not Available', 'Biometric authentication is not available on web');
      return;
    }
    
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access SecureSphere',
      );
      
      if (authenticated) {
        Get.offAllNamed('/home');
      }
    } catch (e) {
      Get.snackbar('Error', 'Biometric authentication failed: $e');
    }
  }

  Future<void> _skipToHome() async {
    if (kDebugMode) {
      
      if (_generatedSeedPhrase != null) {
        final keys = _authService.deriveKeysFromSeedPhrase(_generatedSeedPhrase!);
      }
    }
    Get.offAllNamed('/home');
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
        if (kDebugMode) {
          final keys = _authService.deriveKeysFromSeedPhrase(enteredSeedPhrase);

        }

        // Mark initial setup as complete after successful login
        final securityService = _securityService;
        if (securityService != null) {
          await securityService.markInitialSetupComplete();
        }

        Get.offAllNamed('/home');
      } else {
        Get.snackbar('Login Failed', 'Invalid seed phrase or server error.');
      }
    } catch (e) {
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
      Get.snackbar('Error', 'Login failed: $e');
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              

              if (_isRegistering) ...[  // REGISTRATION SCREEN
                const Text(
                  'Create New Account',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                
                // Seed phrase section
                const Text(
                  'Your Seed Phrase:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _generatedSeedPhrase ?? 'Generating...',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy to clipboard',
                      onPressed: _copySeedPhrase,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Write this down and keep it safe!',
                  style: TextStyle(fontSize: 14, color: Colors.red),
                ),
                const SizedBox(height: 16),
                
                // Security Setup Card
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.security, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'Security Setup (Optional)',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Add an extra layer of security to your account with PIN and biometric authentication.',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        
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
                            icon: const Icon(Icons.pin),
                            label: const Text('Set up PIN (Optional)'),
                          ),
                        ),
                        
                        // Biometrics option
                        if (_biometricsAvailable) ...[
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: const Text('Enable Biometric Authentication'),
                            subtitle: const Text('Use fingerprint, face, or voice to login'),
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
                                  Get.snackbar('Error', 'Biometric authentication failed: $e');
                                }
                              } else {
                                setState(() {
                                  _useBiometrics = value;
                                });
                              }
                            },
                            secondary: const Icon(Icons.fingerprint),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Skip button
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_generatedSeedPhrase != null) {
                        // Show loading dialog
                        Get.dialog(
                          const Center(child: CircularProgressIndicator()),
                          barrierDismissible: false,
                        );
                        
                        try {
                          final success = await _authService.registerUser(_generatedSeedPhrase!);
                          
                          if (Get.isDialogOpen ?? false) {
                            Get.back();
                          }
                          
                          if (success) {
                            // Save biometric preference if enabled
                            if (_useBiometrics && _biometricsAvailable) {
                              final securityService = _securityService;
                              if (securityService != null) {
                                await securityService.enableBiometrics();
                              }
                            }
                            
                            // Mark initial setup as complete after successful registration
                            final securityService = _securityService;
                            if (securityService != null) {
                              await securityService.markInitialSetupComplete();
                            }
                            
                            Get.offAllNamed('/home');
                          } else {
                            Get.snackbar('Error', 'Failed to register with server');
                          }
                        } catch (e) {
                          if (Get.isDialogOpen ?? false) {
                            Get.back();
                          }
                          Get.snackbar('Error', 'Registration failed: $e');
                        }
                      }
                    },
                    child: const Text('Register'),
                  ),
                ),
                
                // Switch to login
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account?'),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isRegistering = false;
                          _seedPhraseController.clear();
                          _pinController.clear();
                          _confirmPinController.clear();
                          _useBiometrics = false;
                          // Clear word controllers
                          for (var controller in _wordControllers) {
                            controller.clear();
                          }
                        });
                      },
                      child: const Text('Login'),
                    ),
                  ],
                ),
              ] else ...[  
                const Text(
                  'Login to SecureSphere',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                

                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      const Text(
                        'Enter your 12-word seed phrase:',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 350,
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: 12,
                          itemBuilder: (context, index) {
                            return TextFormField(
                              controller: _wordControllers[index],
                              decoration: InputDecoration(
                                labelText: 'Word ${index + 1}',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              textInputAction: index < 11 ? TextInputAction.next : TextInputAction.done,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loginWithSeedPhrase,
                          child: const Text('Login with Seed Phrase'),
                        ),
                      ),
                    ],
                  ),
                ),
                
                
                // Switch to registration
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _isRegistering = true;
                            _seedPhraseController.clear();
                            _pinController.clear();
                            _confirmPinController.clear();
                            _generateSeedPhrase();
                          });
                        },
                        child: const Text('Create Account'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
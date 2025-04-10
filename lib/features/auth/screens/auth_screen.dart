import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:securesphere/features/auth/services/auth_service.dart';

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
  
  // Controllers for individual seed phrase words in login mode
  final List<TextEditingController> _wordControllers = 
      List.generate(12, (_) => TextEditingController());
      
  // UI state variables
  bool _isRegistering = true; // Default to registration screen
  bool _biometricsAvailable = false;
  bool _useBiometrics = false;
  String? _generatedSeedPhrase;
  
  // Auth service for Supabase integration
  final AuthService _authService = Get.put(AuthService());
  
  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _generateSeedPhrase();
    _checkLoggedInStatus();
  }

  Future<void> _checkLoggedInStatus() async {
    // Use the async version of login check to prevent infinite rebuilds
    final isLoggedIn = await _authService.checkLoginStatus();
    if (isLoggedIn) {
      Get.offAllNamed('/home');
    }
  }

  Future<void> _checkBiometrics() async {
    // Skip biometric check on web platform to prevent MissingPluginException
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
      // Handle exception gracefully
      debugPrint('Biometric check failed: $e');
      setState(() {
        _biometricsAvailable = false;
      });
    }
  }

  Future<void> _generateSeedPhrase() async {
    // Generate a cryptographically secure mnemonic using BIP39
    final seedPhrase = bip39.generateMnemonic();
    setState(() {
      _generatedSeedPhrase = seedPhrase;
      // Set the seed phrase in the controller for registration
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
    // Skip biometric authentication on web platform
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
      print('Generated Seed Phrase: $_generatedSeedPhrase');
      
      // Derive actual public/private keys from the seed phrase
      if (_generatedSeedPhrase != null) {
        final keys = _authService.deriveKeysFromSeedPhrase(_generatedSeedPhrase!);
        print('Public Key: ${keys['publicKey']}');
        print('Private Key: ${keys['privateKey']}');
      }
    }
    Get.offAllNamed('/home');
  }
  
  Future<void> _loginWithSeedPhrase() async {
    // Combine all word inputs into a single seed phrase
    final enteredSeedPhrase = _wordControllers.map((controller) => controller.text.trim()).join(' ');
    
    // Show loading indicator - use await to ensure dialog is fully shown before proceeding
    await Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );
    
    try {
      final isValid = await _authService.verifySeedPhrase(enteredSeedPhrase);
      
      // Close loading dialog - ensure dialog is closed before navigation
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
      
      if (isValid) {
        // Derive and display keys in debug mode
        if (kDebugMode) {
          final keys = _authService.deriveKeysFromSeedPhrase(enteredSeedPhrase);
          print('Seed Phrase: $enteredSeedPhrase');
          print('Public Key: ${keys['publicKey']}');
          print('Private Key: ${keys['privateKey']}');
        }
        
        // Navigate after dialog is closed
        Get.offAllNamed('/home');
      } else {
        Get.snackbar('Error', 'Incorrect seed phrase');
      }
    } catch (e) {
      // Close loading dialog - ensure dialog is closed before showing error
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
      Get.snackbar('Error', 'Verification failed: $e');
    }
  }

  @override
  void dispose() {
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
                
                // PIN fields
                TextFormField(
                  controller: _pinController,
                  decoration: const InputDecoration(
                    labelText: 'Create PIN',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.pin),
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPinController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm PIN',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.pin),
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                ),
                
                // Biometrics option
                if (_biometricsAvailable) ...[  
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _useBiometrics,
                        onChanged: (value) {
                          setState(() {
                            _useBiometrics = value ?? false;
                          });
                        },
                      ),
                      const Text('Enable Biometric Authentication'),
                    ],
                  ),
                ],
                
                // Skip button
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_generatedSeedPhrase != null) {
                        final keys = _authService.deriveKeysFromSeedPhrase(_generatedSeedPhrase!);
                        final success = await _authService.registerUser(_generatedSeedPhrase!);
                        if (success) {
                          Get.offAllNamed('/home');
                        } else {
                          Get.snackbar('Error', 'Failed to register with server');
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
              ] else ...[  // LOGIN SCREEN
                const Text(
                  'Login to SecureSphere',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                
                // Seed Phrase Login
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
                
                // Biometrics option
                if (_biometricsAvailable) ...[              
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _authenticateWithBiometrics,
                      child: const Text('Use Biometrics Instead'),
                    ),
                  ),
                ],
                
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
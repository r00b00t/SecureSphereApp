import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/auth/screens/pin_setup_screen.dart';
import 'package:decvault/features/auth/screens/pin_unlock_screen.dart';

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
  bool _showingPathChoice = false;
  bool _isRegistering = true;
  bool _biometricsAvailable = false;
  bool _useBiometrics = false;
  bool _seedPhraseConfirmed = false;
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
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    await Future.delayed(const Duration(milliseconds: 100));
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    if (!onboardingComplete && mounted) {
      setState(() => _showingPathChoice = true);
    } else if (mounted) {
      _checkLoggedInStatus();
    }
  }

  Future<void> _chooseManaged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'managed');
    await prefs.setBool('onboarding_complete', true);
    if (mounted) setState(() => _showingPathChoice = false);
  }

  Future<void> _goBackToPathChoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_mode');
    await prefs.remove('onboarding_complete');
    if (mounted) setState(() => _showingPathChoice = true);
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
        localizedReason: 'Authenticate to access DecVault',
      );
      
      if (authenticated) {
        Get.offAllNamed('/home');
      }
    } catch (e) {
      Get.snackbar('Error', 'Biometric authentication failed: $e');
    }
  }

  Future<void> _skipToHome() async {
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
  
  Widget _buildPathChoicePage() {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.shield_outlined,
                  size: 56, color: Color(0xFF34A853)),
              const SizedBox(height: 16),
              const Text(
                'Welcome to DecVault',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'How would you like to store your data?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              _MobilePathCard(
                icon: Icons.cloud_outlined,
                title: 'DecVault Managed',
                subtitle:
                    'We handle the storage for you. Quick setup — just create an account and go.',
                onTap: _chooseManaged,
              ),
              const SizedBox(height: 16),
              _MobilePathCard(
                icon: Icons.dns_outlined,
                title: 'Use My Own Sia Node',
                subtitle:
                    'Store data on your own Sia/renterd node. No account needed — your data never leaves your server.',
                onTap: () => Get.toNamed('/decentralized-node-setup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showingPathChoice) return _buildPathChoicePage();
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _goBackToPathChoice,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_isRegistering) ...[  // REGISTRATION SCREEN
                const Text(
                  'Create New Account',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                
                // Seed phrase warning banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Save your Recovery Phrase',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Write these 12 words down in order and store them somewhere safe. '
                              'This is the only way to recover your account — we cannot retrieve it for you.',
                              style: TextStyle(
                                  color: Colors.orange, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Seed phrase numbered grid
                if (_generatedSeedPhrase != null) ...[
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      final words = _generatedSeedPhrase!.split(' ');
                      final word =
                          index < words.length ? words[index] : '';
                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2C),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: const Color(0xFF3C4043)),
                        ),
                        alignment: Alignment.centerLeft,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        child: RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: '${index + 1}. ',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                            TextSpan(
                              text: word,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ] else
                  const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copySeedPhrase,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy to clipboard'),
                  ),
                ),
                const SizedBox(height: 16),

                // Confirmation checkbox
                CheckboxListTile(
                  value: _seedPhraseConfirmed,
                  onChanged: (v) =>
                      setState(() => _seedPhraseConfirmed = v ?? false),
                  title: const Text(
                    'I have written down my seed phrase',
                    style: TextStyle(fontSize: 14),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                
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
                    onPressed: _seedPhraseConfirmed ? () async {
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
                    } : null,
                    child: const Text('Create Account'),
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
                  'Login to DecVault',
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

class _MobilePathCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MobilePathCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_MobilePathCard> createState() => _MobilePathCardState();
}

class _MobilePathCardState extends State<_MobilePathCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF252525) : const Color(0xFF1E1E1E),
          border: Border.all(
            color: _hovered
                ? const Color(0xFF1E8E3E)
                : const Color(0xFF3C4043),
            width: _hovered ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(widget.icon,
                size: 32,
                color: _hovered
                    ? const Color(0xFF34A853)
                    : Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _hovered
                              ? const Color(0xFF34A853)
                              : Colors.white)),
                  const SizedBox(height: 4),
                  Text(widget.subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.grey)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 16,
                color: _hovered
                    ? const Color(0xFF34A853)
                    : Colors.grey),
          ],
        ),
      ),
    );
  }
}
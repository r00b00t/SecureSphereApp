import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/auth/services/auth_service.dart';
import 'package:securesphere/features/auth/screens/pin_setup_screen.dart';
import 'package:securesphere/features/auth/screens/seed_phrase_screen.dart';

class DesktopAuthScreen extends StatefulWidget {
  const DesktopAuthScreen({super.key});

  @override
  State<DesktopAuthScreen> createState() => _DesktopAuthScreenState();
}

class _DesktopAuthScreenState extends State<DesktopAuthScreen> {
  final AuthService _authService = Get.find();
  final PageController _pageController = PageController();
  
  bool _isLoading = false;
  int _currentStep = 0;
  
  // Login form
  final _seedPhraseController = TextEditingController();
  final _seedPhraseFocusNode = FocusNode();
  
  final _createSeedController = TextEditingController();
  bool _seedPhraseVisible = false;
  bool _isCreatingAccount = false;

  @override
  void initState() {
    super.initState();
    _setupKeyboardShortcuts();
    _checkExistingUser();
  }

  @override
  void dispose() {
    _seedPhraseController.dispose();
    _createSeedController.dispose();
    _seedPhraseFocusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _setupKeyboardShortcuts() {
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && mounted) {
      // Enter to proceed
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_currentStep == 0) {
          _isCreatingAccount ? _proceedToCreateAccount() : _proceedToLogin();
        }
        return true;
      }
      // Escape to go back
      if (event.logicalKey == LogicalKeyboardKey.escape && _currentStep > 0) {
        _goBack();
        return true;
      }
      // Tab to switch between login/create
      if (event.logicalKey == LogicalKeyboardKey.tab && _currentStep == 0) {
        setState(() {
          _isCreatingAccount = !_isCreatingAccount;
        });
        return true;
      }
    }
    return false;
  }

  Future<void> _checkExistingUser() async {
    try {
      final hasUser = await _authService.hasSeedPhrase();
      if (hasUser) {
        setState(() {
          _isCreatingAccount = false;
        });
      }
    } catch (e) {
    }
  }

  void _proceedToLogin() {
    if (_seedPhraseController.text.trim().isEmpty) {
      Get.snackbar('Error', 'Please enter your seed phrase');
      return;
    }
    
    setState(() {
      _currentStep = 1;
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _performLogin();
  }

  void _proceedToCreateAccount() {
    setState(() {
      _currentStep = 1;
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _generateSeedPhrase();
  }

  Future<void> _generateSeedPhrase() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final seedPhrase = await _authService.generateAndStoreSeedPhrase();
      setState(() {
        _createSeedController.text = seedPhrase ?? '';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      Get.snackbar('Error', 'Failed to generate seed phrase: $e');
    }
  }

  Future<void> _performLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _authService.loginUser(_seedPhraseController.text.trim());
      
      setState(() {
        _isLoading = false;
      });

      if (success) {
        final hasPin = await _authService.checkLoginStatus();
        if (hasPin) {
          Get.offAllNamed('/home');
        } else {
          Get.offAll(() => const PinSetupScreen());
        }
      } else {
        Get.snackbar('Error', 'Invalid seed phrase. Please try again.');
        _goBack();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      Get.snackbar('Error', 'Login failed: $e');
      _goBack();
    }
  }

  Future<void> _createAccount() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _authService.registerUser(_createSeedController.text.trim());
      
      setState(() {
        _isLoading = false;
      });

      if (success) {
        Get.offAll(() => const PinSetupScreen());
      } else {
        Get.snackbar('Error', 'Failed to create account');
        _goBack();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      Get.snackbar('Error', 'Account creation failed: $e');
      _goBack();
    }
  }

  void _goBack() {
    if (_currentStep > 0 && mounted) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _copySeedPhrase() {
    Clipboard.setData(ClipboardData(text: _createSeedController.text));
    Get.snackbar(
      'Copied',
      'Seed phrase copied to clipboard',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0F0F),
              Color(0xFF1A1A1A),
              Color(0xFF0F0F0F),
            ],
          ),
        ),
        child: Row(
          children: [
            // Left Panel - Branding
            Expanded(
              flex: 5,
              child: _buildBrandingPanel(),
            ),
            
            // Right Panel - Authentication
            Expanded(
              flex: 4,
              child: _buildAuthPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandingPanel() {
    return Container(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo and Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.security,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 20),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SecureSphere',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Desktop Edition',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 48),
          
          // Features
          const Text(
            'Secure Password Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 24),
          
          ...[
            'Decentralized with seed phrase authentication',
            'End-to-end encryption for all your data',
            'Secure file vault with Sia network backup',
            'Cross-platform sync and accessibility',
            'Desktop-optimized productivity features',
          ].map((feature) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34A853).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF34A853),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    feature,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          )),
          
          const SizedBox(height: 32),
          
          // Keyboard shortcuts info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Enter • Proceed\nTab • Switch mode\nEsc • Go back',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthPanel() {
    return Container(
      margin: const EdgeInsets.all(24),
      child: Card(
        elevation: 8,
        color: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(32),
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildWelcomePage(),
              _buildAuthenticationPage(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isCreatingAccount ? 'Create New Vault' : 'Welcome Back',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        
        const SizedBox(height: 12),
        
        Text(
          _isCreatingAccount 
              ? 'Set up your secure password vault'
              : 'Access your secure password vault',
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 32),
        
        // Mode Toggle
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isCreatingAccount = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !_isCreatingAccount 
                          ? const Color(0xFF34A853) 
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Sign In',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: !_isCreatingAccount ? Colors.white : Colors.white70,
                        fontWeight: !_isCreatingAccount ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isCreatingAccount = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isCreatingAccount 
                          ? const Color(0xFF34A853) 
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Create Account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isCreatingAccount ? Colors.white : Colors.white70,
                        fontWeight: _isCreatingAccount ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        
        if (!_isCreatingAccount) ...[
          // Login Form
          TextField(
            controller: _seedPhraseController,
            focusNode: _seedPhraseFocusNode,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Seed Phrase',
              hintText: 'Enter your 12-word recovery phrase...',
              alignLabelWithHint: true,
            ),
            onSubmitted: (_) => _proceedToLogin(),
          ),
          
          const SizedBox(height: 24),
          
          ElevatedButton(
            onPressed: _proceedToLogin,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Access Vault'),
          ),
        ] else ...[
          // Create Account Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF34A853).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF34A853).withOpacity(0.3),
              ),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Color(0xFF34A853),
                  size: 24,
                ),
                SizedBox(height: 8),
                Text(
                  'A secure 12-word seed phrase will be generated for you. This is your master key - keep it safe!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          ElevatedButton(
            onPressed: _proceedToCreateAccount,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Create New Vault'),
          ),
        ],
        
        const SizedBox(height: 24),
        
        // Footer info
        Text(
          'Powered by blockchain technology and end-to-end encryption',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.5),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAuthenticationPage() {
    if (_isLoading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text(
            'Setting up your secure vault...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
        ],
      );
    }

    if (_isCreatingAccount) {
      return _buildSeedPhraseDisplay();
    } else {
      return _buildLoginProgress();
    }
  }

  Widget _buildSeedPhraseDisplay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Your Recovery Phrase',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        
        const SizedBox(height: 16),
        
        const Text(
          'Write down these 12 words in order and store them safely. You\'ll need this phrase to recover your account.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
          textAlign: TextAlign.center,
        ),
        
        const SizedBox(height: 24),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3C4043)),
          ),
          child: Column(
            children: [
              TextField(
                controller: _createSeedController,
                maxLines: 4,
                readOnly: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Generating seed phrase...',
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copySeedPhrase,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _seedPhraseVisible = !_seedPhraseVisible;
                        });
                      },
                      icon: Icon(
                        _seedPhraseVisible ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      label: Text(_seedPhraseVisible ? 'Hide' : 'Show'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _goBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _createSeedController.text.isNotEmpty ? _createAccount : null,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoginProgress() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          'Authenticating...',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Verifying your seed phrase and setting up your vault',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: _goBack,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
} 
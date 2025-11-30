import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/auth/services/qr_login_service.dart';
import 'package:decvault/features/auth/screens/pin_setup_screen.dart';
import 'package:decvault/features/auth/screens/seed_phrase_screen.dart';
import 'package:decvault/features/auth/screens/pin_unlock_screen.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/common/widgets/custom_title_bar.dart';

class DesktopAuthScreen extends StatefulWidget {
  const DesktopAuthScreen({super.key});

  @override
  State<DesktopAuthScreen> createState() => _DesktopAuthScreenState();
}

class _DesktopAuthScreenState extends State<DesktopAuthScreen> {
  final AuthService _authService = Get.find();
  final PageController _pageController = PageController();
  late final QrLoginService _qrLoginService;
  
  SecurityService? get _securityService {
    try {
      return Get.find<SecurityService>();
    } catch (e) {
      return null;
    }
  }
  
  bool _isLoading = false;
  int _currentStep = 0;
  
  // Login form
  final _seedPhraseController = TextEditingController();
  final _seedPhraseFocusNode = FocusNode();
  
  // Create account form
  final _createSeedController = TextEditingController();
  bool _isCreatingAccount = false;
  
  // QR code login
  bool _showQrLogin = false;
  String? _qrData;

  @override
  void initState() {
    super.initState();
    _qrLoginService = Get.find<QrLoginService>();
    _setupKeyboardShortcuts();
    _checkLoggedInStatus();
    _checkExistingUser();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your seed phrase'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      
      if (seedPhrase == null || seedPhrase.isEmpty) {
        throw Exception('Generated seed phrase is null or empty');
      }
      
      setState(() {
        _createSeedController.text = seedPhrase;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate seed phrase: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        // Mark initial setup as complete after successful login
        try {
          final securityService = Get.find<SecurityService>();
          await securityService.markInitialSetupComplete();
        } catch (e) {
          // SecurityService not available, continue anyway
        }
        
        // Always navigate to home - PIN setup will be prompted there if needed
        Get.offAllNamed('/home');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid seed phrase. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        _goBack();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _goBack();
    }
  }

  Future<void> _createAccount() async {
    // Prevent duplicate clicks
    if (_isLoading) {
      return;
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _authService.registerUser(_createSeedController.text.trim());
      
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });

      if (success) {
        Get.offAll(() => const PinSetupScreen());
      } else {
        // Registration failed - generate a new seed phrase for next attempt
        await _generateSeedPhrase();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create account. Please try again with the new seed phrase shown.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      
      // Generate a new seed phrase for next attempt
      await _generateSeedPhrase();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account creation failed: ${e.toString()}. Please try again with the new seed phrase.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seed phrase copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _generateQrCode() async {
    setState(() {
      _isLoading = true;
      _showQrLogin = true;
    });

    final qrData = await _qrLoginService.generateQrSession();
    
    setState(() {
      _qrData = qrData;
      _isLoading = false;
    });

    if (qrData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate QR code. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _showQrLogin = false;
      });
    }
  }

  void _cancelQrLogin() {
    setState(() {
      _showQrLogin = false;
      _qrData = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(backgroundColor: Color(0xFF0F0F0F)),
          Expanded(
            child: Container(
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
          ),
        ],
      ),
    );
  }

  Widget _buildBrandingPanel() {
    return Container(
      padding: const EdgeInsets.all(48),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Logo and Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(
                  'assets/logo/green.png',
                  width: 56,
                  height: 56,
                ),
              ),
              const SizedBox(width: 20),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DecVault',
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
    // Show QR code login screen if enabled
    if (_showQrLogin) {
      return _buildQrLoginScreen();
    }

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
        
        // QR Code Login Button (only show for login, not account creation)
        if (!_isCreatingAccount) ...[
          OutlinedButton.icon(
            onPressed: _generateQrCode,
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            label: const Text('Login with Mobile App'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        
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

  Widget _buildQrLoginScreen() {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Scan QR Code',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          
          const SizedBox(height: 8),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Open the mobile app and scan this QR code to log in',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          const SizedBox(height: 24),
          
          if (_isLoading)
            const CircularProgressIndicator()
          else if (_qrData != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: _qrData!,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          
          const SizedBox(height: 24),
        
        Obx(() {
          final status = _qrLoginService.sessionStatus.value;
          String statusText = 'Waiting for mobile app to scan...';
          Color statusColor = Colors.white70;
          
          switch (status) {
            case QrSessionStatus.waitingForScan:
              statusText = 'Waiting for mobile app to scan...';
              statusColor = Colors.white70;
              break;
            case QrSessionStatus.authenticated:
              statusText = 'Authenticated! Logging in...';
              statusColor = const Color(0xFF34A853);
              break;
            case QrSessionStatus.loggingIn:
              statusText = 'Logging in...';
              statusColor = const Color(0xFF34A853);
              break;
            case QrSessionStatus.error:
              statusText = 'Authentication failed';
              statusColor = Colors.red;
              break;
            default:
              break;
          }
          
          return Column(
            children: [
              Icon(
                status == QrSessionStatus.authenticated || status == QrSessionStatus.loggingIn
                    ? Icons.check_circle_outline
                    : status == QrSessionStatus.error
                        ? Icons.error_outline
                        : Icons.phone_android,
                color: statusColor,
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 14,
                  color: statusColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          );
        }),
        
        const SizedBox(height: 24),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton(
            onPressed: _cancelQrLogin,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Back to Seed Phrase Login'),
          ),
        ),
        
        const SizedBox(height: 12),
        
        Text(
          'QR code expires in 5 minutes',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 20),
      ],
      ),
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
                onPressed: _isLoading ? null : _goBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_createSeedController.text.isNotEmpty && !_isLoading) ? _createAccount : null,
                child: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
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

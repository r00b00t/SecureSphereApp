import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/auth/services/qr_login_service.dart';
import 'package:decvault/features/auth/screens/pin_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DesktopAuthScreen extends StatefulWidget {
  const DesktopAuthScreen({super.key});

  @override
  State<DesktopAuthScreen> createState() => _DesktopAuthScreenState();
}

class _DesktopAuthScreenState extends State<DesktopAuthScreen> {
  final AuthService _authService = Get.find();
  final PageController _pageController = PageController();
  late final QrLoginService _qrLoginService;
  
  bool _isLoading = false;
  int _currentStep = 0;

  // Path choice (shown before sign-in/create tabs when onboarding is incomplete)
  bool _showingPathChoice = false;

  // Login form
  final _seedPhraseController = TextEditingController();
  final _seedPhraseFocusNode = FocusNode();

  // Create account form
  final _createSeedController = TextEditingController();
  bool _seedPhraseVisible = true;
  bool _seedPhraseConfirmed = false;
  bool _isCreatingAccount = false;

  // QR code login
  bool _showQrLogin = false;
  String? _qrData;

  @override
  void initState() {
    super.initState();
    _qrLoginService = Get.put(QrLoginService());
    _setupKeyboardShortcuts();
    _checkExistingUser();
    _checkOnboardingStatus();
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
      // ignore
    }
  }

  Future<void> _checkOnboardingStatus() async {
    await Future.delayed(const Duration(milliseconds: 100));
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    if (!onboardingComplete && mounted) {
      setState(() => _showingPathChoice = true);
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
        // Check if PIN setup is needed (simplified check)
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
      Get.snackbar(
        'Error',
        'Failed to generate QR code. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
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
    // Show path choice before sign-in/create tabs when onboarding is not done.
    if (_showingPathChoice) return _buildPathChoicePage();

    // Show QR code login screen if enabled
    if (_showQrLogin) {
      return _buildQrLoginScreen();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _goBackToPathChoice,
            icon: const Icon(Icons.arrow_back, size: 16, color: Colors.white54),
            label: const Text('Back', style: TextStyle(color: Colors.white54, fontSize: 14)),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ),
        const SizedBox(height: 8),
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

  Widget _buildPathChoicePage() {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1E8E3E), Color(0xFF34A853)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.security, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 20),
          const Text(
            'Welcome to DecVault',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose how you want to get started.',
            style: TextStyle(fontSize: 15, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // ── Set it up for me ──────────────────────────────────────────
          _DesktopPathCard(
            icon: Icons.cloud_outlined,
            iconColor: const Color(0xFF4285F4),
            title: 'Set it up for me',
            subtitle:
                'DecVault manages the storage for you. Quick setup — just create an account.',
            onTap: _chooseManaged,
          ),
          const SizedBox(height: 14),

          // ── I have a Sia node ─────────────────────────────────────────
          _DesktopPathCard(
            icon: Icons.dns_outlined,
            iconColor: const Color(0xFF1E8E3E),
            title: 'I have a Sia node',
            subtitle:
                'Fully decentralized. Your data stays on your own renterd node. '
                'No account, no backend.',
            onTap: () => Get.toNamed('/decentralized-node-setup'),
          ),
          const SizedBox(height: 14),

          // ── Already set up on another device ─────────────────────────
          _DesktopPathCard(
            icon: Icons.devices_outlined,
            iconColor: const Color(0xFFF57C00),
            title: 'Already set up on another device',
            subtitle:
                'Import your configuration by scanning a QR code or entering '
                'your seed phrase.',
            onTap: () => Get.toNamed('/device-pairing-import'),
          ),

          const SizedBox(height: 24),
          Text(
            'You can change this later in Settings.',
            style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.45)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
      ),
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
    final words = _createSeedController.text.trim().split(' ');
    final hasWords = words.length == 12 && words.first.isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Your Recovery Phrase',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 12),

          // Warning banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.5)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Write these 12 words down in order and store them safely. '
                    'This is the only way to recover your account — we cannot retrieve it for you.',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Numbered word grid
          if (!hasWords)
            const Center(child: CircularProgressIndicator())
          else if (_seedPhraseVisible)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.8,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2C),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF3C4043)),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: '${index + 1}. ',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11),
                      ),
                      TextSpan(
                        text: words[index],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
                );
              },
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: const Text(
                'Seed phrase hidden',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),

          const SizedBox(height: 10),

          // Copy / Show-Hide row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copySeedPhrase,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _seedPhraseVisible = !_seedPhraseVisible),
                  icon: Icon(
                    _seedPhraseVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 16,
                  ),
                  label: Text(_seedPhraseVisible ? 'Hide' : 'Show'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Confirmation checkbox
          CheckboxListTile(
            value: _seedPhraseConfirmed,
            onChanged: (v) =>
                setState(() => _seedPhraseConfirmed = v ?? false),
            title: const Text(
              'I have written down my seed phrase',
              style: TextStyle(fontSize: 13, color: Colors.white),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 16),

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
                  onPressed: (_createSeedController.text.isNotEmpty &&
                          _seedPhraseConfirmed)
                      ? _createAccount
                      : null,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
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

// ── Path-choice card (hover-aware) ────────────────────────────────────────────

class _DesktopPathCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DesktopPathCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_DesktopPathCard> createState() => _DesktopPathCardState();
}

class _DesktopPathCardState extends State<_DesktopPathCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                _hovered ? const Color(0xFF353535) : const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  _hovered ? const Color(0xFF34A853) : const Color(0xFF3C4043),
              width: _hovered ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 28, color: widget.iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: _hovered
                    ? const Color(0xFF34A853)
                    : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
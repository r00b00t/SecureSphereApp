import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'dart:math';
import 'package:decvault/common/widgets/custom_title_bar.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class DesktopPasswordGeneratorScreen extends StatefulWidget {
  const DesktopPasswordGeneratorScreen({super.key});

  @override
  State<DesktopPasswordGeneratorScreen> createState() => _DesktopPasswordGeneratorScreenState();
}

class _DesktopPasswordGeneratorScreenState extends State<DesktopPasswordGeneratorScreen> {
  String _generatedPassword = '';
  int _passwordLength = 16;
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  bool _excludeSimilar = false;
  bool _excludeAmbiguous = false;
  
  final List<String> _passwordHistory = [];
  final TextEditingController _customCharsetController = TextEditingController();
  bool _useCustomCharset = false;
  
  // Strength analysis
  String _strengthLevel = '';
  double _strengthScore = 0.0;
  List<String> _strengthFeedback = [];

  @override
  void initState() {
    super.initState();
    _generatePassword();
    _setupKeyboardShortcuts();
  }

  @override
  void dispose() {
    _customCharsetController.dispose();
    super.dispose();
  }

  void _setupKeyboardShortcuts() {
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+G for generate
      if (event.logicalKey == LogicalKeyboardKey.keyG && 
          HardwareKeyboard.instance.isControlPressed) {
        _generatePassword();
        return true;
      }
      // Ctrl+C for copy
      if (event.logicalKey == LogicalKeyboardKey.keyC && 
          HardwareKeyboard.instance.isControlPressed && 
          _generatedPassword.isNotEmpty) {
        _copyPassword();
        return true;
      }
      // Space for generate
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _generatePassword();
        return true;
      }
    }
    return false;
  }

  void _generatePassword() {
    if (!_includeUppercase && !_includeLowercase && !_includeNumbers && !_includeSymbols && !_useCustomCharset) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Please select at least one character type',
      );
      return;
    }

    String charset = '';
    
    if (_useCustomCharset && _customCharsetController.text.isNotEmpty) {
      charset = _customCharsetController.text;
    } else {
      if (_includeUppercase) charset += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      if (_includeLowercase) charset += 'abcdefghijklmnopqrstuvwxyz';
      if (_includeNumbers) charset += '0123456789';
      if (_includeSymbols) charset += '!@#\$%^&*()_+-=[]{}|;:,.<>?';
    }

    if (_excludeSimilar) {
      charset = charset.replaceAll(RegExp(r'[il1Lo0O]'), '');
    }
    
    if (_excludeAmbiguous) {
      const ambiguous = '{}[]()\/\\\'\"~,;<>.:';
      for (var char in ambiguous.split('')) {
        charset = charset.replaceAll(char, '');
      }
    }

    if (charset.isEmpty) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'No valid characters available with current settings',
      );
      return;
    }

    final random = Random.secure();
    String password = '';
    
    for (int i = 0; i < _passwordLength; i++) {
      password += charset[random.nextInt(charset.length)];
    }

    setState(() {
      _generatedPassword = password;
      if (_passwordHistory.length >= 10) {
        _passwordHistory.removeLast();
      }
      _passwordHistory.insert(0, password);
    });
    
    _analyzeStrength();
  }

  void _analyzeStrength() {
    if (_generatedPassword.isEmpty) return;

    double score = 0;
    List<String> feedback = [];

    if (_generatedPassword.length >= 12) {
      score += 25;
    } else if (_generatedPassword.length >= 8) {
      score += 15;
      feedback.add('Consider using 12+ characters');
    } else {
      score += 5;
      feedback.add('Password is too short');
    }

    bool hasUpper = _generatedPassword.contains(RegExp(r'[A-Z]'));
    bool hasLower = _generatedPassword.contains(RegExp(r'[a-z]'));
    bool hasNumbers = _generatedPassword.contains(RegExp(r'[0-9]'));
    bool hasSymbols = _generatedPassword.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]'));

    int diversity = [hasUpper, hasLower, hasNumbers, hasSymbols].where((x) => x).length;
    score += diversity * 15;

    if (diversity < 3) {
      feedback.add('Add more character types');
    }

    bool hasRepeats = RegExp(r'(.)\1{2,}').hasMatch(_generatedPassword);
    if (hasRepeats) {
      score -= 10;
      feedback.add('Avoid repeated characters');
    } else {
      score += 10;
    }

    bool hasSequential = RegExp(r'(abc|123|qwe)').hasMatch(_generatedPassword.toLowerCase());
    if (hasSequential) {
      score -= 15;
      feedback.add('Avoid sequential patterns');
    } else {
      score += 10;
    }

    score = score.clamp(0, 100);

    setState(() {
      _strengthScore = score / 100;
      _strengthFeedback = feedback;
      
      if (score >= 80) {
        _strengthLevel = 'Very Strong';
      } else if (score >= 60) {
        _strengthLevel = 'Strong';
      } else if (score >= 40) {
        _strengthLevel = 'Medium';
      } else if (score >= 20) {
        _strengthLevel = 'Weak';
      } else {
        _strengthLevel = 'Very Weak';
      }
    });
  }

  void _copyPassword() {
    if (_generatedPassword.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _generatedPassword));
      SnackbarUtils.showSnackbar(
        title: 'Copied',
        message: 'Password copied to clipboard',
      );
    }
  }

  Color _getStrengthColor() {
    if (_strengthScore >= 0.8) return Colors.green;
    if (_strengthScore >= 0.6) return Colors.lightGreen;
    if (_strengthScore >= 0.4) return Colors.orange;
    if (_strengthScore >= 0.2) return Colors.deepOrange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          right: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.vpn_key, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Password Generator',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Create Secure Passwords',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Settings
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSettingsSection(),
                  const SizedBox(height: 24),
                  _buildAdvancedOptions(),
                  const SizedBox(height: 24),
                  _buildCustomCharset(),
                ],
              ),
            ),
          ),
          
          // Back button
          Container(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () {
                try {
                  Get.back();
                } catch (e) {
                  // Already on the correct page or navigation failed
                }
              },
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password Length',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _passwordLength.toDouble(),
                min: 4,
                max: 64,
                divisions: 60,
                label: _passwordLength.toString(),
                onChanged: (value) {
                  setState(() {
                    _passwordLength = value.toInt();
                  });
                  _generatePassword();
                },
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                _passwordLength.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        const Text(
          'Character Types',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        
        _buildCheckboxTile(
          'Uppercase Letters (A-Z)',
          _includeUppercase,
          (value) => setState(() => _includeUppercase = value),
        ),
        _buildCheckboxTile(
          'Lowercase Letters (a-z)',
          _includeLowercase,
          (value) => setState(() => _includeLowercase = value),
        ),
        _buildCheckboxTile(
          'Numbers (0-9)',
          _includeNumbers,
          (value) => setState(() => _includeNumbers = value),
        ),
        _buildCheckboxTile(
          'Symbols (!@#\$%^&*)',
          _includeSymbols,
          (value) => setState(() => _includeSymbols = value),
        ),
      ],
    );
  }

  Widget _buildAdvancedOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Advanced Options',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        
        _buildCheckboxTile(
          'Exclude Similar Characters (il1Lo0O)',
          _excludeSimilar,
          (value) => setState(() => _excludeSimilar = value),
        ),
        _buildCheckboxTile(
          'Exclude Ambiguous Characters ({}[]()...)',
          _excludeAmbiguous,
          (value) => setState(() => _excludeAmbiguous = value),
        ),
      ],
    );
  }

  Widget _buildCustomCharset() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCheckboxTile(
          'Use Custom Character Set',
          _useCustomCharset,
          (value) => setState(() => _useCustomCharset = value),
        ),
        
        if (_useCustomCharset) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customCharsetController,
            decoration: const InputDecoration(
              labelText: 'Custom Characters',
              hintText: 'Enter custom characters...',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _generatePassword(),
          ),
        ],
      ],
    );
  }

  Widget _buildCheckboxTile(String title, bool value, Function(bool) onChanged) {
    return CheckboxListTile(
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
        ),
      ),
      value: value,
      onChanged: (newValue) {
        onChanged(newValue ?? false);
        _generatePassword();
      },
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildMainContent() {
    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildPasswordDisplay(),
                  const SizedBox(height: 24),
                  _buildStrengthAnalysis(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _buildPasswordHistory(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Password Generator',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Tooltip(
            message: 'Generate Password (Ctrl+G or Space)',
            child: ElevatedButton.icon(
              onPressed: _generatePassword,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Generate'),
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Copy Password (Ctrl+C)',
            child: OutlinedButton.icon(
              onPressed: _generatedPassword.isNotEmpty ? _copyPassword : null,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3C4043)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.vpn_key,
                color: Color(0xFF34A853),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Generated Password',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                '${_generatedPassword.length} characters',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3C4043)),
            ),
            child: SelectableText(
              _generatedPassword.isEmpty ? 'Click Generate to create a password' : _generatedPassword,
              style: TextStyle(
                fontSize: 20,
                fontFamily: 'monospace',
                color: _generatedPassword.isEmpty ? Colors.white54 : Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrengthAnalysis() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3C4043)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.security,
                color: Color(0xFF34A853),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Strength Analysis',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStrengthColor().withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _getStrengthColor()),
                ),
                child: Text(
                  _strengthLevel,
                  style: TextStyle(
                    color: _getStrengthColor(),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _strengthScore,
            backgroundColor: const Color(0xFF2C2C2C),
            valueColor: AlwaysStoppedAnimation<Color>(_getStrengthColor()),
          ),
          const SizedBox(height: 16),
          if (_strengthFeedback.isNotEmpty) ...[
            const Text(
              'Suggestions:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            ..._strengthFeedback.map((feedback) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    feedback,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordHistory() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3C4043)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(
                  Icons.history,
                  color: Color(0xFF34A853),
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Password History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_passwordHistory.length}/10',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _passwordHistory.isEmpty
                ? const Center(
                    child: Text(
                      'No password history yet\nGenerated passwords will appear here',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _passwordHistory.length,
                    itemBuilder: (context, index) {
                      final password = _passwordHistory[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF34A853).withOpacity(0.2),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Color(0xFF34A853),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          title: Text(
                            password,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${password.length} characters',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: password));
                              SnackbarUtils.showSnackbar(
                                title: 'Copied',
                                message: 'Password copied to clipboard',
                              );
                            },
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Copy Password',
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
} 

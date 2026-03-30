import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'dart:math';
import 'package:decvault/common/widgets/custom_title_bar.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:decvault/config/api_config.dart';

class DesktopAddPasswordScreen extends StatefulWidget {
  final PasswordModel? password; // For editing existing passwords

  const DesktopAddPasswordScreen({super.key, this.password});

  @override
  State<DesktopAddPasswordScreen> createState() => _DesktopAddPasswordScreenState();
}

class _DesktopAddPasswordScreenState extends State<DesktopAddPasswordScreen> {
  final PasswordRepository _passwordRepo = Get.find();
  final _formKey = GlobalKey<FormState>();
  
  // Form controllers
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _websiteController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Focus nodes for better keyboard navigation
  final _titleFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _websiteFocusNode = FocusNode();
  final _notesFocusNode = FocusNode();
  
  String _selectedCategory = 'Other';
  bool _passwordVisible = false;
  bool _isLoading = false;
  bool _isEditing = false;
  
  // Password generation settings
  int _generatedPasswordLength = 16;
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  
  // Predefined categories
  final List<String> _categories = [
    'Personal',
    'Work',
    'Banking',
    'Social Media',
    'Email',
    'Shopping',
    'Entertainment',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _setupKeyboardShortcuts();
    
    // If editing, populate fields
    if (widget.password != null) {
      _isEditing = true;
      _populateFields();
    }
    
    // Request focus after a short delay to ensure widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _websiteController.dispose();
    _notesController.dispose();
    _titleFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _websiteFocusNode.dispose();
    _notesFocusNode.dispose();
    super.dispose();
  }

  void _setupKeyboardShortcuts() {
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+S to save
      if (event.logicalKey == LogicalKeyboardKey.keyS && 
          HardwareKeyboard.instance.isControlPressed) {
        _savePassword();
        return true;
      }
      // Ctrl+G to generate password
      if (event.logicalKey == LogicalKeyboardKey.keyG && 
          HardwareKeyboard.instance.isControlPressed) {
        _generatePassword();
        return true;
      }
      // Escape to cancel
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Get.back();
        return true;
      }
    }
    return false;
  }

  void _populateFields() {
    final password = widget.password!;
    _titleController.text = password.title;
    _usernameController.text = password.username;
    _passwordController.text = password.encryptedPassword; // This should be decrypted in real implementation
    _selectedCategory = password.category;
    _notesController.text = password.notes;
  }

  void _generatePassword() {
    String charset = '';
    if (_includeUppercase) charset += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (_includeLowercase) charset += 'abcdefghijklmnopqrstuvwxyz';
    if (_includeNumbers) charset += '0123456789';
    if (_includeSymbols) charset += '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    if (charset.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Please select at least one character type'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final random = Random.secure();
    String password = '';
    
    for (int i = 0; i < _generatedPasswordLength; i++) {
      password += charset[random.nextInt(charset.length)];
    }

    setState(() {
      _passwordController.text = password;
      _passwordVisible = true;
    });
  }

  Future<void> _savePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final passwordText = _passwordController.text;
      
      // Check password breach status before saving (similar to mobile version)
      bool breached = false;
      int breachCount = 0;
      bool breachCheckFailed = false;
      
      try {
        // Check password using the breach API (GET request)
        final url = Uri.parse('${ApiConfig.checkPasswordBreachEndpoint}?password=${Uri.encodeComponent(passwordText)}');
        final response = await http.get(url).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          breachCount = data['count'] ?? 0;
          breached = breachCount > 0;
        } else {
          breachCheckFailed = true;
        }
      } catch (e) {
        breachCheckFailed = true;
        // Continue with saving even if breach check fails
      }
      
      // Show warnings if needed
      if (breached) {
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('Security Warning', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              'This password has appeared in known data breaches (Count: $breachCount).\n\nIt is not safe to use compromised passwords as they can be easily guessed by attackers.\n\nDo you still want to save this password?',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Change Password'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        );
        
        if (result != true) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      } else if (breachCheckFailed) {
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.info, color: Colors.blue),
                SizedBox(width: 8),
                Text('Notice', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              'Unable to check if this password has been compromised due to network issues.\n\nThe password will be saved, but we recommend checking your internet connection and updating the password later if needed.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save Password'),
              ),
            ],
          ),
        );
        
        if (result != true) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }
      
      if (_isEditing) {
        // Update existing password
        final updatedPassword = PasswordModel(
          id: widget.password!.id,
          title: _titleController.text.trim(),
          username: _usernameController.text.trim(),
          encryptedPassword: _passwordController.text, // Should be encrypted
          category: _selectedCategory,
          notes: _notesController.text.trim(),
          createdAt: widget.password!.createdAt,
          updatedAt: DateTime.now(),
        );
        
        await _passwordRepo.updatePassword(updatedPassword);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Success: Password updated successfully'),
              backgroundColor: Color(0xFF34A853),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Create new password
        final now = DateTime.now();
        final newPassword = PasswordModel(
          id: '${now.millisecondsSinceEpoch}_${_titleController.text.trim().replaceAll(' ', '_')}',
          title: _titleController.text.trim(),
          username: _usernameController.text.trim(),
          encryptedPassword: _passwordController.text,
          category: _selectedCategory,
          notes: _notesController.text.trim(),
          createdAt: now,
          updatedAt: now,
        );
        
        await _passwordRepo.addPassword(newPassword);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Success: Password saved successfully'),
              backgroundColor: Color(0xFF34A853),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      
      // Navigate back to home and refresh the password list
      Get.offAllNamed('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Failed to save password: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
                  child: Icon(
                    _isEditing ? Icons.edit : Icons.add,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditing ? 'Edit Password' : 'Add Password',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Secure Credentials',
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
          
          // Password Generator Settings
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Password Generator',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Length slider
                  Text(
                    'Length: $_generatedPasswordLength',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Slider(
                    value: _generatedPasswordLength.toDouble(),
                    min: 8,
                    max: 32,
                    divisions: 24,
                    onChanged: (value) {
                      setState(() {
                        _generatedPasswordLength = value.toInt();
                      });
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Character type checkboxes
                  CheckboxListTile(
                    title: const Text('Uppercase (A-Z)', style: TextStyle(color: Colors.white)),
                    value: _includeUppercase,
                    onChanged: (value) => setState(() => _includeUppercase = value!),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Lowercase (a-z)', style: TextStyle(color: Colors.white)),
                    value: _includeLowercase,
                    onChanged: (value) => setState(() => _includeLowercase = value!),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Numbers (0-9)', style: TextStyle(color: Colors.white)),
                    value: _includeNumbers,
                    onChanged: (value) => setState(() => _includeNumbers = value!),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Symbols (!@#)', style: TextStyle(color: Colors.white)),
                    value: _includeSymbols,
                    onChanged: (value) => setState(() => _includeSymbols = value!),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  ElevatedButton.icon(
                    onPressed: _generatePassword,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Generate'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 40),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Categories
                  const Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  ..._categories.map((category) => RadioListTile<String>(
                    title: Row(
                      children: [
                        Icon(_getCategoryIcon(category), size: 18, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text(category, style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                    value: category,
                    groupValue: _selectedCategory,
                    onChanged: (value) => setState(() => _selectedCategory = value!),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  )),
                ],
              ),
            ),
          ),
          
          // Keyboard shortcuts info
          Container(
            margin: const EdgeInsets.all(16),
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
                  'Ctrl+S • Save\nCtrl+G • Generate\nEsc • Cancel',
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

  Widget _buildMainContent() {
    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFormField(
                          controller: _titleController,
                          focusNode: _titleFocusNode,
                          nextFocusNode: _usernameFocusNode,
                          label: 'Title',
                          hint: 'e.g., Gmail, Facebook, Banking',
                          icon: Icons.title,
                          validator: (value) {
                            if (value?.isEmpty ?? true) {
                              return 'Please enter a title';
                            }
                            return null;
                          },
                        ),
                        
                        const SizedBox(height: 20),
                        
                        _buildFormField(
                          controller: _usernameController,
                          focusNode: _usernameFocusNode,
                          nextFocusNode: _passwordFocusNode,
                          label: 'Username/Email',
                          hint: 'Enter username or email',
                          icon: Icons.person,
                        ),
                        
                        const SizedBox(height: 20),
                        
                        _buildPasswordField(),
                        
                        const SizedBox(height: 20),
                        
                        _buildFormField(
                          controller: _websiteController,
                          focusNode: _websiteFocusNode,
                          nextFocusNode: _notesFocusNode,
                          label: 'Website (Optional)',
                          hint: 'https://example.com',
                          icon: Icons.language,
                        ),
                        
                        const SizedBox(height: 20),
                        
                        _buildCategoryField(),
                        
                        const SizedBox(height: 20),
                        
                        _buildFormField(
                          controller: _notesController,
                          focusNode: _notesFocusNode,
                          label: 'Notes (Optional)',
                          hint: 'Additional information...',
                          icon: Icons.notes,
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                ),
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
          IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back (Esc)',
          ),
          const SizedBox(width: 12),
          Text(
            _isEditing ? 'Edit Password' : 'Add New Password',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          OutlinedButton(
            onPressed: _isLoading ? null : () => Get.back(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _savePassword,
            icon: const Icon(Icons.save, size: 18),
            label: Text(_isEditing ? 'Update' : 'Save'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocusNode,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          validator: validator,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onFieldSubmitted: (_) {
            if (nextFocusNode != null) {
              nextFocusNode.requestFocus();
            }
          },
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          obscureText: !_passwordVisible,
          validator: (value) {
            if (value?.isEmpty ?? true) {
              return 'Please enter a password';
            }
            return null;
          },
          decoration: InputDecoration(
            hintText: 'Enter a strong password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _passwordVisible = !_passwordVisible;
                    });
                  },
                  icon: Icon(
                    _passwordVisible ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: 'Toggle visibility',
                ),
                IconButton(
                  onPressed: _generatePassword,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Generate password (Ctrl+G)',
                ),
                IconButton(
                  onPressed: () {
                    if (_passwordController.text.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: _passwordController.text));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied: Password copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy password',
                ),
              ],
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onFieldSubmitted: (_) => _websiteFocusNode.requestFocus(),
        ),
      ],
    );
  }

  Widget _buildCategoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedCategory,
          decoration: InputDecoration(
            hintText: 'Select a category',
            prefixIcon: const Icon(Icons.category),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
                     items: _categories.map((category) {
             return DropdownMenuItem<String>(
               value: category,
               child: Row(
                 children: [
                   Icon(_getCategoryIcon(category), size: 20, color: Colors.white70),
                   const SizedBox(width: 12),
                   Text(category, style: const TextStyle(color: Colors.white)),
                 ],
               ),
             );
           }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedCategory = value;
              });
            }
          },
          validator: (value) {
            if (value == null) {
              return 'Please select a category';
            }
            return null;
          },
        ),
      ],
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Personal':
        return Icons.person;
      case 'Work':
        return Icons.work;
      case 'Banking':
        return Icons.account_balance;
      case 'Social Media':
        return Icons.share;
      case 'Email':
        return Icons.email;
      case 'Shopping':
        return Icons.shopping_cart;
      case 'Entertainment':
        return Icons.movie;
      default:
        return Icons.category;
    }
  }
} 
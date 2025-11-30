import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/common/widgets/app_drawer.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class PasswordGeneratorScreen extends StatefulWidget {
  const PasswordGeneratorScreen({super.key});

  @override
  State<PasswordGeneratorScreen> createState() => _PasswordGeneratorScreenState();
}

class _PasswordGeneratorScreenState extends State<PasswordGeneratorScreen> {
  final PasswordRepository _passwordRepo = Get.find();
  
  // Password generation options
  int _passwordLength = 12;
  bool _includeLetters = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  String _generatedPassword = '';
  
  // Form controllers for saving password
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Category selection
  String _selectedCategory = 'Other';
  
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
    _generatePassword();
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _generatePassword() {
    if (!_includeLetters && !_includeNumbers && !_includeSymbols) {
      // At least one option must be selected
      setState(() {
        _includeLetters = true;
      });
    }
    
    const String letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const String numbers = '0123456789';
    const String symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
    
    String validChars = '';
    if (_includeLetters) validChars += letters;
    if (_includeNumbers) validChars += numbers;
    if (_includeSymbols) validChars += symbols;
    
    final random = Random.secure();
    final password = List.generate(_passwordLength, (index) {
      final randomIndex = random.nextInt(validChars.length);
      return validChars[randomIndex];
    }).join('');
    
    setState(() {
      _generatedPassword = password;
    });
  }
  
  Future<void> _savePassword() async {
    if (_titleController.text.isEmpty) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Please enter a title for the password',
      );
      return;
    }
    
    try {
      final newPassword = PasswordModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text,
        username: _usernameController.text,
        encryptedPassword: _generatedPassword,
        category: _selectedCategory,
        notes: _notesController.text,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _passwordRepo.addPassword(newPassword);
      
      SnackbarUtils.showSuccess(
        title: 'Success',
        message: 'Password saved successfully',
      );
      
      // Clear form fields
      _titleController.clear();
      _usernameController.clear();
      setState(() {
        _selectedCategory = 'Other';
      });
      _notesController.clear();
      
      // Generate a new password
      _generatePassword();
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to save password: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Password Generator'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF121212),
              const Color(0xFF1E1E1E),
              Theme.of(context).primaryColor.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Generated password display - moved to top
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor.withValues(alpha: 0.15),
                      Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(context).colorScheme.secondary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.vpn_key,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Generated Password',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Tap to copy',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.refresh,
                            color: Theme.of(context).primaryColor,
                            size: 28,
                          ),
                          onPressed: _generatePassword,
                          tooltip: 'Generate new',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _generatedPassword));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Password copied to clipboard!'),
                            backgroundColor: Theme.of(context).primaryColor,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _generatedPassword,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.copy,
                              color: Theme.of(context).primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Password generation options
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1E1E1E),
                      Color(0xFF2C2C2C),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune, color: Theme.of(context).primaryColor, size: 24),
                        const SizedBox(width: 12),
                        const Text(
                          'Password Options',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Length slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Password Length',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            '$_passwordLength',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                      ),
                      child: Slider(
                        value: _passwordLength.toDouble(),
                        min: 4,
                        max: 32,
                        divisions: 28,
                        onChanged: (value) {
                          setState(() {
                            _passwordLength = value.toInt();
                          });
                          _generatePassword();
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Options switches
                    _buildOptionSwitch(
                      'Include Letters (a-z, A-Z)',
                      _includeLetters,
                      Icons.text_fields,
                      (value) {
                        setState(() {
                          _includeLetters = value;
                        });
                        _generatePassword();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildOptionSwitch(
                      'Include Numbers (0-9)',
                      _includeNumbers,
                      Icons.pin,
                      (value) {
                        setState(() {
                          _includeNumbers = value;
                        });
                        _generatePassword();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildOptionSwitch(
                      'Include Symbols (!@#\$%^&*)',
                      _includeSymbols,
                      Icons.tag,
                      (value) {
                        setState(() {
                          _includeSymbols = value;
                        });
                        _generatePassword();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Save password form
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1E1E1E),
                      Color(0xFF2C2C2C),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.save, color: Theme.of(context).primaryColor, size: 24),
                        const SizedBox(width: 12),
                        const Text(
                          'Save Password',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Title *',
                        hintText: 'e.g., Gmail, Facebook',
                        prefixIcon: Icon(Icons.title, color: Theme.of(context).primaryColor),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username/Email',
                        hintText: 'e.g., user@example.com',
                        prefixIcon: Icon(Icons.person, color: Theme.of(context).primaryColor),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(_getCategoryIcon(_selectedCategory), color: Theme.of(context).primaryColor),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: _categories.map((category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Row(
                            children: [
                              Icon(_getCategoryIcon(category), size: 20),
                              const SizedBox(width: 12),
                              Text(category),
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
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: 'Notes (Optional)',
                        hintText: 'Add any additional information...',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.notes, color: Theme.of(context).primaryColor),
                        ),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _savePassword,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save, size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Save Password',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionSwitch(String title, bool value, IconData icon, Function(bool) onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: value 
            ? Theme.of(context).primaryColor.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value 
              ? Theme.of(context).primaryColor.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
          width: value ? 2 : 1,
        ),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: value ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        secondary: Icon(
          icon,
          color: value ? Theme.of(context).primaryColor : Colors.grey,
        ),
        value: value,
        onChanged: onChanged,
      ),
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
      case 'Other':
      default:
        return Icons.folder;
    }
  }
}
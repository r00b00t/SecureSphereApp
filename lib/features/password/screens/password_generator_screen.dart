import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';

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
  final _categoryController = TextEditingController();
  final _notesController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _generatePassword();
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _categoryController.dispose();
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
      Get.snackbar(
        'Error',
        'Please enter a title for the password',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    
    try {
      final newPassword = PasswordModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text,
        username: _usernameController.text,
        encryptedPassword: _generatedPassword,
        category: _categoryController.text.isEmpty ? 'Other' : _categoryController.text,
        notes: _notesController.text,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _passwordRepo.addPassword(newPassword);
      
      Get.snackbar(
        'Success',
        'Password saved successfully',
        snackPosition: SnackPosition.BOTTOM,
      );
      
      // Clear form fields
      _titleController.clear();
      _usernameController.clear();
      _categoryController.clear();
      _notesController.clear();
      
      // Generate a new password
      _generatePassword();
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to save password: $e',
        snackPosition: SnackPosition.BOTTOM,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Password generation options
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Password Options',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Password Length:'),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: _passwordLength > 4
                                  ? () {
                                      setState(() {
                                        _passwordLength--;
                                      });
                                      _generatePassword();
                                    }
                                  : null,
                            ),
                            Text('$_passwordLength'),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _passwordLength < 32
                                  ? () {
                                      setState(() {
                                        _passwordLength++;
                                      });
                                      _generatePassword();
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('Include Letters (a-z, A-Z)'),
                      value: _includeLetters,
                      onChanged: (value) {
                        setState(() {
                          _includeLetters = value;
                        });
                        _generatePassword();
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Include Numbers (0-9)'),
                      value: _includeNumbers,
                      onChanged: (value) {
                        setState(() {
                          _includeNumbers = value;
                        });
                        _generatePassword();
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Include Symbols (!@#\$%^&*)'),
                      value: _includeSymbols,
                      onChanged: (value) {
                        setState(() {
                          _includeSymbols = value;
                        });
                        _generatePassword();
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _generatePassword,
                      child: const Text('Generate New Password'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Generated password display
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Generated Password',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _generatedPassword,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _generatedPassword));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Password copied to clipboard')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Save password form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Save Password',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        hintText: 'e.g., Gmail, Facebook',
                      ),
                    ),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username/Email',
                        hintText: 'e.g., user@example.com',
                      ),
                    ),
                    TextField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        hintText: 'e.g., Social Media, Email',
                      ),
                    ),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _savePassword,
                      child: const Text('Save Password'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
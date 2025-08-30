import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sha3/sha3.dart';
import 'package:securesphere/config/api_config.dart'; // Added this line


class AddPasswordScreen extends StatefulWidget {
  final PasswordModel? passwordToEdit;
  const AddPasswordScreen({super.key, this.passwordToEdit});

  @override
  State<AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends State<AddPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Create unique keys for form fields
  final _titleFieldKey = UniqueKey();
  final _usernameFieldKey = UniqueKey();
  final _passwordFieldKey = UniqueKey();
  final _notesFieldKey = UniqueKey();
  
  final PasswordRepository _passwordRepo = Get.find();
  bool _obscurePassword = true;
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
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.passwordToEdit != null) {
      _titleController.text = widget.passwordToEdit!.title;
      _usernameController.text = widget.passwordToEdit!.username;
      _passwordController.text = widget.passwordToEdit!.encryptedPassword;
      _notesController.text = widget.passwordToEdit!.notes;
      _selectedCategory = widget.passwordToEdit!.category;
    }
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

  Future<void> _loadPasswordFromStorage() async {
    try {
      final fullPassword = await _passwordRepo.getPassword(widget.passwordToEdit!.id);
      if (fullPassword != null && fullPassword.encryptedPassword.isNotEmpty) {
        setState(() {
          _passwordController.text = fullPassword.encryptedPassword;
        });
      }
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.passwordToEdit != null ? 'Edit Password' : 'Add New Password'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: _titleFieldKey,
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.title),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      validator: (value) => value?.isEmpty ?? true ? 'Please enter a title' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: _usernameFieldKey,
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username/Email',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: _passwordFieldKey,
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (value) => value?.isEmpty ?? true ? 'Please enter a password' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: _categories.map((String category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Row(
                            children: [
                              Icon(_getCategoryIcon(category), size: 20),
                              SizedBox(width: 12),
                              Text(category),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedCategory = newValue!;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a category';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: _notesFieldKey,
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: 'Notes',
                        prefixIcon: Icon(Icons.note),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.save),
                        label: Text(widget.passwordToEdit != null ? 'Update Password' : 'Save Password', style: TextStyle(fontSize: 18)),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _savePassword,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _savePassword() async {
    if (_formKey.currentState?.validate() ?? false) {
      final passwordText = _passwordController.text;
      try {
        // Debug: Print the password
        // Try to check password breach status, but allow saving even if check fails
        bool breached = false;
        int breachCount = 0;
        bool breachCheckFailed = false;
        
        try {
          // Hash password using SHA3-512 and extract first 10 chars
          final k = SHA3(512, KECCAK_PADDING, 512);
          k.update(utf8.encode(passwordText));
          final hash = k.digest().map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          final hashPrefix = hash.substring(0, 10);
          final url = '${ApiConfig.passwordApiBaseUrl}${ApiConfig.passwordAnonPath}$hashPrefix';
          
          final response = await http.get(
            Uri.parse(url),
            headers: {'User-Agent': 'SecureSphere-App'},
          ).timeout(Duration(seconds: 10));
          
          
          if (response.statusCode == 200) {
            // HaveIBeenPwned API returns plain text with hash suffixes and counts
            final lines = response.body.split('\n');
            final remainingHash = hash.substring(10).toUpperCase();
            
            for (final line in lines) {
              if (line.trim().isNotEmpty) {
                final parts = line.split(':');
                if (parts.length == 2 && parts[0] == remainingHash) {
                  breached = true;
                  breachCount = int.tryParse(parts[1]) ?? 0;
                  break;
                }
              }
            }
          }
        } catch (e) {
          breachCheckFailed = true;
          // Continue with saving the password even if breach check fails
        }
        // Show warnings if needed
        if (breached) {
          final result = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Row(children: [Icon(Icons.warning, color: Colors.orange), SizedBox(width: 8), Text('Security Warning')]),
              content: Text('This password has appeared in known data breaches (Count: $breachCount).\nIt is not safe to use compromised passwords as they can be easily guessed by attackers.\n\nDo you still want to save this password?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Change Password'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Save Anyway'),
                ),
              ],
            ),
          );
          if (result != true) {
            return;
          }
        } else if (breachCheckFailed) {
          final result = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Row(children: [Icon(Icons.info, color: Colors.blue), SizedBox(width: 8), Text('Notice')]),
              content: Text('Unable to check if this password has been compromised due to network issues.\n\nThe password will be saved, but we recommend checking your internet connection and updating the password later if needed.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Save Password'),
                ),
              ],
            ),
          );
          if (result != true) {
            return;
          }
        }
        final now = DateTime.now();
        final isEdit = widget.passwordToEdit != null;
        final passwordModel = PasswordModel(
          id: isEdit ? widget.passwordToEdit!.id : now.millisecondsSinceEpoch.toString(),
          title: _titleController.text,
          username: _usernameController.text,
          encryptedPassword: _passwordController.text,
          category: _selectedCategory,
          notes: _notesController.text,
          createdAt: isEdit ? widget.passwordToEdit!.createdAt : now,
          updatedAt: now,
        );
        if (isEdit) {
          await _passwordRepo.updatePassword(passwordModel);
        } else {
          await _passwordRepo.addPassword(passwordModel);
        }
        Get.snackbar(
          'Success',
          isEdit ? 'Password updated successfully!' : 'Password saved successfully!',
          snackPosition: SnackPosition.BOTTOM,
        );
        Navigator.of(context).pop(true);
      } catch (e, stackTrace) {
        Get.snackbar(
          'Error',
          'Failed to save password',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }
}
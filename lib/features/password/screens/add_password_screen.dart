import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:decvault/config/api_config.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';


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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1E1E1E),
                      const Color(0xFF2C2C2C),
                    ],
                  ),
                ),
                child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
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
                          child: Icon(
                            widget.passwordToEdit != null ? Icons.edit : Icons.add_circle_outline,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.passwordToEdit != null ? 'Edit Password' : 'New Password',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Secure your credentials',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Title Field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.label, size: 16, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'Title',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: _titleFieldKey,
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: 'e.g., Gmail, Facebook',
                            prefixIcon: Icon(Icons.title, color: Theme.of(context).primaryColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.3),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          validator: (value) => value?.isEmpty ?? true ? 'Please enter a title' : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Username Field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person, size: 16, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'Username / Email',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: _usernameFieldKey,
                          controller: _usernameController,
                          decoration: InputDecoration(
                            hintText: 'your@email.com',
                            prefixIcon: Icon(Icons.alternate_email, color: Theme.of(context).primaryColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.3),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Password Field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock, size: 16, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'Password',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: _passwordFieldKey,
                          controller: _passwordController,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: Icon(Icons.vpn_key, color: Theme.of(context).primaryColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.3),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: Colors.grey[400],
                              ),
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
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Category Selection
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.category, size: 16, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'Category',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: InputDecoration(
                            prefixIcon: Icon(_getCategoryIcon(_selectedCategory), color: Theme.of(context).primaryColor),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.3),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          items: _categories.map((String category) {
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
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Notes Field
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.note_alt, size: 16, color: Theme.of(context).primaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'Notes (Optional)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: _notesFieldKey,
                          controller: _notesController,
                          decoration: InputDecoration(
                            hintText: 'Add any additional information...',
                            prefixIcon: Padding(
                              padding: const EdgeInsets.only(bottom: 60),
                              child: Icon(Icons.notes, color: Theme.of(context).primaryColor),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.3),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 4,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Save Button
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _savePassword,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.passwordToEdit != null ? Icons.check_circle : Icons.save,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              widget.passwordToEdit != null ? 'Update Password' : 'Save Password',
                              style: const TextStyle(
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
          // Check password using the new breach API
          final url = Uri.parse('${ApiConfig.checkPasswordBreachEndpoint}?password=${Uri.encodeComponent(passwordText)}');
          
          final response = await http.get(url).timeout(Duration(seconds: 10));
          
          
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final bool success = data['success'] ?? false;
            breachCount = data['count'] ?? 0;
            breached = breachCount > 0;
            
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
        SnackbarUtils.showSuccess(
          title: 'Success',
          message: isEdit ? 'Password updated successfully!' : 'Password saved successfully!',
        );
        Navigator.of(context).pop(true);
      } catch (e, stackTrace) {
        SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to save password',
      );
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/models/password_model.dart';

class AddPasswordScreen extends StatefulWidget {
  const AddPasswordScreen({super.key});

  @override
  State<AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends State<AddPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _categoryController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Create unique keys for form fields
  final _titleFieldKey = UniqueKey();
  final _usernameFieldKey = UniqueKey();
  final _passwordFieldKey = UniqueKey();
  final _categoryFieldKey = UniqueKey();
  final _notesFieldKey = UniqueKey();
  
  final PasswordRepository _passwordRepo = Get.find();

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _categoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Password'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                key: _titleFieldKey,
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (value) => value?.isEmpty ?? true ? 'Please enter a title' : null,
              ),
              TextFormField(
                key: _usernameFieldKey,
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username/Email',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              TextFormField(
                key: _passwordFieldKey,
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.visibility),
                    onPressed: () {},
                  ),
                ),
                obscureText: true,
                validator: (value) => value?.isEmpty ?? true ? 'Please enter a password' : null,
              ),
              TextFormField(
                key: _categoryFieldKey,
                controller: _categoryController,
                decoration: InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              TextFormField(
                key: _notesFieldKey,
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _savePassword,
                child: const Text('Save Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _savePassword() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        final newPassword = PasswordModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: _titleController.text,
          username: _usernameController.text,
          encryptedPassword: _passwordController.text,
          category: _categoryController.text.isNotEmpty ? _categoryController.text : 'Other',
          notes: _notesController.text,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        
        await _passwordRepo.addPassword(newPassword);
        Get.back(result: true);
      } catch (e, stackTrace) {
        debugPrint('Error saving password: $e\n$stackTrace');
        Get.snackbar(
          'Error', 
          'Failed to save password',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }
}
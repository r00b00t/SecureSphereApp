import 'package:flutter/material.dart';
import 'package:decvault/common/widgets/app_drawer.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/features/password/screens/add_password_screen.dart';
import 'package:decvault/features/password/screens/desktop_add_password_screen.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class PasswordDetailScreen extends StatefulWidget {
  final PasswordModel password;
  
  const PasswordDetailScreen({super.key, required this.password});

  @override
  State<PasswordDetailScreen> createState() => _PasswordDetailScreenState();
}

class _PasswordDetailScreenState extends State<PasswordDetailScreen> {
  bool _isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(widget.password.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              _editPassword(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              _confirmDeletePassword(context);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailItem('Title', widget.password.title),
            _buildDetailItem('Username/Email', widget.password.username),
            _buildPasswordItem('Password', widget.password.encryptedPassword),
            _buildDetailItem('Category', widget.password.category),
            if (widget.password.notes.isNotEmpty) _buildDetailItem('Notes', widget.password.notes),
            _buildDetailItem('Created', _formatDate(widget.password.createdAt)),
            _buildDetailItem('Last Updated', _formatDate(widget.password.updatedAt)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _isPasswordVisible ? value : '••••••••••••',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              IconButton(
                icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  SnackbarUtils.showSnackbar(
                    title: 'Copied',
                    message: 'Password copied to clipboard',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _editPassword(BuildContext context) async {
    try {
      // Ensure we get the full password data from secure storage before editing
      final passwordRepository = Get.find<PasswordRepository>();
      final fullPassword = await passwordRepository.getPassword(widget.password.id);
      
      if (fullPassword != null) {
        // Use desktop version on desktop platforms  
        Get.to(() => DesktopAddPasswordScreen(password: fullPassword));
        // Close current detail screen since edit will navigate to home
        Navigator.of(context).pop();
      } else {
        SnackbarUtils.showError(
        title: 'Error',
        message: 'Unable to load password data for editing',
      );
      }
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to load password: $e',
      );
    }
  }

  void _confirmDeletePassword(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Password'),
        content: const Text('Are you sure you want to delete this password?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _deletePassword(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePassword(BuildContext context) async {
    try {
      final passwordRepository = Get.find<PasswordRepository>();
      await passwordRepository.deletePassword(widget.password.id);
      SnackbarUtils.showSnackbar(
        title: 'Deleted',
        message: 'Password deleted successfully',
      );
      // Return true to indicate the password was deleted successfully
      Navigator.of(context).pop(true);
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to delete password: $e',
      );
      // Don't return true on error - this prevents unnecessary reload
    }
  }
}
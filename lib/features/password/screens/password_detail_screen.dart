import 'package:flutter/material.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/password/models/password_model.dart';

class PasswordDetailScreen extends StatelessWidget {
  final PasswordModel password;
  
  const PasswordDetailScreen({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(password.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Implement edit functionality
              Get.snackbar(
                'Coming Soon',
                'Edit functionality will be available soon',
                snackPosition: SnackPosition.BOTTOM,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              // TODO: Implement delete functionality
              Get.snackbar(
                'Coming Soon',
                'Delete functionality will be available soon',
                snackPosition: SnackPosition.BOTTOM,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailItem('Title', password.title),
            _buildDetailItem('Username/Email', password.username),
            _buildPasswordItem('Password', password.encryptedPassword),
            _buildDetailItem('Category', password.category),
            if (password.notes.isNotEmpty) _buildDetailItem('Notes', password.notes),
            _buildDetailItem('Created', _formatDate(password.createdAt)),
            _buildDetailItem('Last Updated', _formatDate(password.updatedAt)),
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
    return StatefulBuilder(
      builder: (context, setState) {
        bool isVisible = false;
        
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
                      isVisible ? value : '••••••••••••',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: Icon(isVisible ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        isVisible = !isVisible;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      Get.snackbar(
                        'Copied',
                        'Password copied to clipboard',
                        snackPosition: SnackPosition.BOTTOM,
                        duration: const Duration(seconds: 2),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
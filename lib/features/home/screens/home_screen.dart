import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/screens/add_password_screen.dart';
import 'package:securesphere/features/password/screens/password_detail_screen.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PasswordRepository _passwordRepo = Get.find();
  List<PasswordModel> _passwords = [];
  bool _isLoading = true;
  
  // Helper method to build avatar content
  Widget _buildAvatarContent(String title) {
    // Check if title is not null, not empty, and contains at least one letter or digit
    if (title.isNotEmpty && title.trim().isNotEmpty) {
      final trimmedTitle = title.trim();
      // Check if the first character is a letter or digit that can be displayed
      if (trimmedTitle.length > 0 && RegExp(r'[a-zA-Z0-9]').hasMatch(trimmedTitle[0])) {
        return Text(
          trimmedTitle[0].toUpperCase(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        );
      }
    }
    // Fallback to lock icon
    return const Icon(Icons.lock, color: Colors.white, size: 20);
  }

  @override
  void initState() {
    super.initState();
    _loadPasswords();
  }

  Future<void> _loadPasswords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final passwords = await _passwordRepo.getAllPasswords();
      setState(() {
        _passwords = passwords;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading passwords: $e');
      setState(() {
        _isLoading = false;
      });
      Get.snackbar(
        'Error',
        'Failed to load passwords',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SecureSphere'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            onPressed: () {
              // TODO: Implement lock functionality
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search passwords...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
              ),
              onChanged: (value) async {
                final allPasswords = await _passwordRepo.getAllPasswords();
                setState(() {
                  _passwords = allPasswords.where((password) {
                    return password.title.toLowerCase().contains(value.toLowerCase()) ||
                        password.username.toLowerCase().contains(value.toLowerCase());
                  }).toList();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Your Passwords',
              style: TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _passwords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_open, size: 80, color: Color(0xFF34A853)),
                            const SizedBox(height: 24),
                            Text(
                              'No passwords saved yet',
                              style: TextStyle(fontSize: 18, color: Colors.white70),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final result = await Get.to(() => const AddPasswordScreen());
                                if (result == true) {
                                  _loadPasswords();
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Add Your First Password'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPasswords,
                        child: ListView.builder(
                          itemCount: _passwords.length,
                          itemBuilder: (context, index) {
                            final password = _passwords[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF1E8E3E),
                                  child: _buildAvatarContent(password.title),
                                ),
                                title: Text(
                                  password.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  password.username,
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFF34A853),
                                ),
                                onTap: () {
                                  Get.to(() => PasswordDetailScreen(password: password));
                                },
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Get.to(() => const AddPasswordScreen());
          if (result == true) {
            _loadPasswords();
          }
        },
        backgroundColor: const Color(0xFF1E8E3E),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
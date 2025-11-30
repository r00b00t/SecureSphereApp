import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/features/password/screens/add_password_screen.dart';
import 'package:decvault/features/password/screens/password_detail_screen.dart';
import 'package:decvault/common/widgets/app_drawer.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/auth/screens/pin_unlock_screen.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PasswordRepository _passwordRepo = Get.find();
  List<PasswordModel> _passwords = [];
  List<PasswordModel> _filteredPasswords = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  
  // Predefined categories
  final List<String> _categories = [
    'All',
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
    _searchController.dispose();
    super.dispose();
  }
  
  void _filterPasswords(String query) {
    setState(() {
      _filteredPasswords = _passwords.where((p) {
        // Check category filter
        bool categoryMatch = _selectedCategory == 'All' || p.category == _selectedCategory;
        
        // Check search query
        bool searchMatch = query.isEmpty || 
          p.title.toLowerCase().contains(query.toLowerCase()) ||
          p.username.toLowerCase().contains(query.toLowerCase());
        
        return categoryMatch && searchMatch;
      }).toList();
    });
  }
  
  void _filterByCategory(String category) {
    setState(() {
      _selectedCategory = category;
    });
    _filterPasswords(_searchController.text);
  }
  

  Widget _buildAvatarContent(String title) {
    if (title.isNotEmpty && title.trim().isNotEmpty) {
      final trimmedTitle = title.trim();

      if (trimmedTitle.length > 0 && RegExp(r'[a-zA-Z0-9]').hasMatch(trimmedTitle[0])) {
        return Text(
          trimmedTitle[0].toUpperCase(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        );
      }
    }

    return const Icon(Icons.lock, color: Colors.white, size: 20);
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
      case 'All':
        return Icons.apps;
      case 'Other':
      default:
        return Icons.folder;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Personal':
        return Colors.blue;
      case 'Work':
        return Colors.orange;
      case 'Banking':
        return Colors.green;
      case 'Social Media':
        return Colors.purple;
      case 'Email':
        return Colors.red;
      case 'Shopping':
        return Colors.pink;
      case 'Entertainment':
        return Colors.amber;
      case 'All':
        return Colors.grey;
      case 'Other':
      default:
        return Colors.blueGrey;
    }
  }

  int _getPasswordCountForCategory(String category) {
    if (category == 'All') return _passwords.length;
    return _passwords.where((p) => p.category == category).length;
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
        _filteredPasswords = List.from(passwords);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to load passwords',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Passwords'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock App',
            onPressed: () async {
              try {
                final securityService = Get.find<SecurityService>();
                
                // Check if PIN or biometric is configured
                final hasPIN = await securityService.hasPinSet();
                final hasBiometric = securityService.securitySettings.biometricEnabled;
                
                if (!hasPIN && !hasBiometric) {
                  // Show dialog to inform user they need to set up security first
                  Get.dialog(
                    AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.security, color: Colors.orange),
                          SizedBox(width: 12),
                          Text('Security Not Configured'),
                        ],
                      ),
                      content: const Text(
                        'You need to set up a PIN code or biometric authentication before you can lock the app.\n\n'
                        'Would you like to create a PIN now?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(Get.context!).pop(),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(Get.context!).pop();
                            Get.offAllNamed('/settings');
                          },
                          child: const Text('Go to Settings'),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                
                // Lock the app first
                await securityService.lockApp();
                
                // Immediately show PIN unlock screen
                Get.dialog(
                  const PinUnlockScreen(),
                  barrierDismissible: false,
                  barrierColor: Colors.black87,
                );
              } catch (e) {
                SnackbarUtils.showError(
                  title: 'Error',
                  message: 'Could not lock app',
                );
              }
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
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
        child: Column(
          children: [
          // Enhanced Category Tabs with Better Visual Design
          Container(
            height: 100,
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                final categoryColor = _getCategoryColor(category);
                final passwordCount = _getPasswordCountForCategory(category);
                
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: GestureDetector(
                    onTap: () => _filterByCategory(category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: isSelected ? 95 : 80,
                      decoration: BoxDecoration(
                        gradient: isSelected 
                          ? LinearGradient(
                              colors: [
                                categoryColor.withValues(alpha: 0.95),
                                categoryColor.withValues(alpha: 0.75),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            )
                          : LinearGradient(
                              colors: [
                                categoryColor.withValues(alpha: 0.15),
                                categoryColor.withValues(alpha: 0.08),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected 
                            ? categoryColor.withValues(alpha: 0.6)
                            : categoryColor.withValues(alpha: 0.25),
                          width: isSelected ? 2.5 : 1.5,
                        ),
                        boxShadow: isSelected ? [
                          BoxShadow(
                            color: categoryColor.withValues(alpha: 0.5),
                            blurRadius: 16,
                            spreadRadius: 1,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: categoryColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: -2,
                            offset: const Offset(0, 2),
                          ),
                        ] : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Icon with Badge and Enhanced Styling
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: isSelected 
                                    ? LinearGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0.35),
                                          Colors.white.withValues(alpha: 0.15),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : LinearGradient(
                                        colors: [
                                          categoryColor.withValues(alpha: 0.2),
                                          categoryColor.withValues(alpha: 0.1),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                  shape: BoxShape.circle,
                                  boxShadow: isSelected ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ] : [],
                                ),
                                child: Icon(
                                  _getCategoryIcon(category),
                                  size: isSelected ? 26 : 22,
                                  color: isSelected 
                                    ? Colors.white
                                    : categoryColor,
                                  shadows: isSelected ? [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      offset: const Offset(0, 1),
                                      blurRadius: 2,
                                    ),
                                  ] : [],
                                ),
                              ),
                              if (passwordCount > 0)
                                Positioned(
                                  right: -5,
                                  top: -5,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isSelected 
                                          ? [Colors.white, Colors.white.withValues(alpha: 0.9)]
                                          : [categoryColor, categoryColor.withValues(alpha: 0.9)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected 
                                          ? categoryColor
                                          : Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.25),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        passwordCount > 99 ? '99' : passwordCount.toString(),
                                        style: TextStyle(
                                          color: isSelected 
                                            ? categoryColor
                                            : Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          height: 1,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Category Name
                          Text(
                            category,
                            style: TextStyle(
                              color: isSelected 
                                ? Colors.white
                                : categoryColor.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              letterSpacing: 0.2,
                              height: 1.1,
                              shadows: isSelected ? [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ] : [],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Enhanced Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search passwords...',
                  hintStyle: TextStyle(
                    color: Theme.of(context).hintColor.withOpacity(0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: Theme.of(context).hintColor,
                        ),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                          _filterPasswords('');
                        },
                      )
                    : null,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                onChanged: _filterPasswords,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPasswords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor.withValues(alpha: 0.2),
                                    Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                  ],
                                ),
                              ),
                              child: Icon(
                                Icons.lock_outline,
                                size: 80,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'No Passwords Yet',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Start securing your accounts by\nadding your first password',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[400],
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const AddPasswordScreen(),
                                  ),
                                );
                                if (result == true) {
                                  _loadPasswords();
                                }
                              },
                              icon: const Icon(Icons.add, size: 24),
                              label: const Text(
                                'Add Your First Password',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredPasswords.length,
                        itemBuilder: (context, index) {
                          final password = _filteredPasswords[index];
                          final categoryColor = _getCategoryColor(password.category);
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                color: Theme.of(context).dividerColor.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              leading: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      categoryColor.withOpacity(0.8),
                                      categoryColor.withOpacity(0.6),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: categoryColor.withOpacity(0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  backgroundColor: Colors.transparent,
                                  radius: 24,
                                  child: _buildAvatarContent(password.title),
                                ),
                              ),
                              title: Text(
                                password.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: Theme.of(context).textTheme.titleLarge?.color,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    password.username,
                                    style: TextStyle(
                                      color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: categoryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: categoryColor.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _getCategoryIcon(password.category),
                                              size: 12,
                                              color: categoryColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              password.category,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: categoryColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Theme.of(context).hintColor.withOpacity(0.5),
                              ),
                              isThreeLine: true,
                              onTap: () async {
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => PasswordDetailScreen(password: password),
                                  ),
                                );
                                if (result == true) {
                                  _loadPasswords();
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AddPasswordScreen(),
            ),
          );
          if (result == true) {
            _loadPasswords();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

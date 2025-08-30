import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/screens/add_password_screen.dart';
import 'package:securesphere/features/password/screens/password_detail_screen.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';
import 'package:securesphere/features/auth/services/security_service.dart';
import 'package:securesphere/features/auth/screens/pin_unlock_screen.dart';

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
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock App',
            onPressed: () async {
              try {
                final securityService = Get.find<SecurityService>();
                
                // Lock the app first
                await securityService.lockApp();
                
                // Immediately show PIN unlock screen
                Get.dialog(
                  const PinUnlockScreen(),
                  barrierDismissible: false,
                  barrierColor: Colors.black87,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  'Could not lock app',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red.withOpacity(0.8),
                  colorText: Colors.white,
                );
              }
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // Enhanced Category Tabs
          Container(
            height: 90,
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                final categoryColor = _getCategoryColor(category);
                final passwordCount = _getPasswordCountForCategory(category);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: GestureDetector(
                    onTap: () => _filterByCategory(category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      constraints: const BoxConstraints(minWidth: 70),
                      decoration: BoxDecoration(
                        gradient: isSelected 
                          ? LinearGradient(
                              colors: [
                                categoryColor.withOpacity(0.8),
                                categoryColor.withOpacity(0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.surface,
                                Theme.of(context).colorScheme.surface.withOpacity(0.9),
                              ],
                            ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected 
                            ? categoryColor.withOpacity(0.8)
                            : Theme.of(context).dividerColor.withOpacity(0.3),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected ? [
                          BoxShadow(
                            color: categoryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ] : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isSelected 
                                    ? Colors.white.withOpacity(0.9)
                                    : categoryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _getCategoryIcon(category),
                                  size: 16,
                                  color: isSelected 
                                    ? categoryColor
                                    : categoryColor.withOpacity(0.8),
                                ),
                              ),
                              if (passwordCount > 0)
                                Positioned(
                                  right: -3,
                                  top: -3,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                        ? Colors.white
                                        : categoryColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected 
                                          ? categoryColor
                                          : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        passwordCount > 99 ? '99+' : passwordCount.toString(),
                                        style: TextStyle(
                                          color: isSelected 
                                            ? categoryColor
                                            : Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Flexible(
                            child: Text(
                              category,
                              style: TextStyle(
                                color: isSelected 
                                  ? Colors.white
                                  : Theme.of(context).textTheme.bodyMedium?.color,
                                fontSize: 10,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                    ? const Center(child: Text('No passwords saved yet.'))
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/screens/desktop_add_password_screen.dart';
import 'package:securesphere/features/auth/services/security_service.dart';
import 'package:securesphere/features/auth/screens/pin_unlock_screen.dart';
import 'package:securesphere/features/vault/models/file_model.dart';
import 'package:securesphere/features/vault/repositories/file_repository.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> with WidgetsBindingObserver {
  final PasswordRepository _passwordRepo = Get.find();
  final FileRepository _fileRepo = Get.find();
  
  List<PasswordModel> _passwords = [];
  List<PasswordModel> _filteredPasswords = [];
  List<FileModel> _recentFiles = [];
  bool _isLoading = true;
  String _selectedView = 'passwords';
  PasswordModel? _selectedPassword;
  bool _isPasswordVisible = false;
  String _selectedCategory = 'All';
  
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _setupKeyboardShortcuts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Refresh data when app returns to foreground
      _loadData();
    }
  }

  void _setupKeyboardShortcuts() {
    // Set up keyboard shortcuts for desktop
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+F for search
      if (event.logicalKey == LogicalKeyboardKey.keyF && 
          HardwareKeyboard.instance.isControlPressed) {
        _searchFocusNode.requestFocus();
        return true;
      }
      // Ctrl+N for new password
      if (event.logicalKey == LogicalKeyboardKey.keyN && 
          HardwareKeyboard.instance.isControlPressed) {
        _addNewPassword();
        return true;
      }
      // Escape to clear search
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _clearSearch();
        return true;
      }
    }
    return false;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final passwords = await _passwordRepo.getAllPasswords();
      final files = await _fileRepo.getAllFiles();
      
      if (mounted) {
        setState(() {
          _passwords = passwords;
          _filteredPasswords = List.from(passwords);
          _recentFiles = files.take(5).toList(); // Get 5 recent files
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      Get.snackbar(
        'Error',
        'Failed to load data',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _filterPasswords(String query) {
    if (!mounted) return;
    setState(() {
      _filteredPasswords = _passwords.where((p) {
        // Check category filter
        bool categoryMatch = _selectedCategory == 'All' || p.category == _selectedCategory;
        
        // Check search query
        bool searchMatch = query.isEmpty || 
          p.title.toLowerCase().contains(query.toLowerCase()) ||
          p.username.toLowerCase().contains(query.toLowerCase()) ||
          p.category.toLowerCase().contains(query.toLowerCase());
        
        return categoryMatch && searchMatch;
      }).toList();
    });
  }
  
  void _filterByCategory(String category) {
    if (!mounted) return;
    setState(() {
      _selectedCategory = category;
    });
    _filterPasswords(_searchController.text);
  }

  void _clearSearch() {
    _searchController.clear();
    _filterPasswords('');
    FocusScope.of(context).unfocus();
  }

  void _addNewPassword() async {
    final result = await Get.to(() => const DesktopAddPasswordScreen());
    if (result == true) {
      _loadData();
    }
  }

  void _editPassword(PasswordModel password) async {
    try {
      final fullPassword = await _passwordRepo.getPassword(password.id);
      
      if (fullPassword != null) {
        // Navigate to edit screen - it will automatically return to home when done
        Get.to(() => DesktopAddPasswordScreen(password: fullPassword));
      } else {
        Get.snackbar(
          'Error',
          'Unable to load password data for editing',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to load password: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _deletePassword(PasswordModel password) async {
    // Show confirmation dialog
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Password', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${password.title}"? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _passwordRepo.deletePassword(password.id);
        Get.snackbar(
          'Deleted',
          'Password deleted successfully',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: const Color(0xFF34A853).withOpacity(0.8),
          colorText: Colors.white,
        );
        _loadData();
        setState(() {
          _selectedPassword = null;
        });
      } catch (e) {
        Get.snackbar(
          'Error',
          'Failed to delete password: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.8),
          colorText: Colors.white,
        );
      }
    }
  }

  void _selectPassword(PasswordModel password) {
    setState(() {
      _selectedPassword = password;
      _isPasswordVisible = false; // Reset visibility when selecting new password
    });
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          right: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.security, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SecureSphere',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Password Manager',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavItem(
                  icon: Icons.password,
                  label: 'Passwords',
                  id: 'passwords',
                  isSelected: _selectedView == 'passwords',
                  onTap: () => setState(() => _selectedView = 'passwords'),
                ),
                _buildNavItem(
                  icon: Icons.folder_special,
                  label: 'Vault',
                  id: 'vault',
                  isSelected: _selectedView == 'vault',
                  onTap: () => Get.toNamed('/vault'),
                ),
                _buildNavItem(
                  icon: Icons.vpn_key,
                  label: 'Generator',
                  id: 'generator',
                  isSelected: _selectedView == 'generator',
                  onTap: () => Get.toNamed('/password-generator'),
                ),
                _buildNavItem(
                  icon: Icons.security,
                  label: 'Breach Monitor',
                  id: 'breach',
                  isSelected: _selectedView == 'breach',
                  onTap: () => Get.toNamed('/breach-monitoring'),
                ),
                const Divider(color: Color(0xFF3C4043), height: 24),
                _buildNavItem(
                  icon: Icons.backup,
                  label: 'Backups',
                  id: 'backups',
                  isSelected: _selectedView == 'backups',
                  onTap: () => Get.toNamed('/backups'),
                ),
                _buildNavItem(
                  icon: Icons.settings,
                  label: 'Settings',
                  id: 'settings',
                  isSelected: _selectedView == 'settings',
                  onTap: () => Get.toNamed('/settings'),
                ),
              ],
            ),
          ),
          
          // Bottom info
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  '${_passwords.length} passwords stored',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      final securityService = Get.find<SecurityService>();
                      final result = await Get.to(() => const PinUnlockScreen());
                      if (result == true) {
                        // Lock app functionality
                        Get.offAllNamed('/auth');
                      }
                    } catch (e) {
                      // SecurityService not available - just go to auth
                      Get.offAllNamed('/auth');
                    }
                  },
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('Lock App'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size(double.infinity, 36),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required String id,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF34A853) : Colors.white70,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF34A853) : Colors.white70,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        selected: isSelected,
        selectedTileColor: const Color(0xFF34A853).withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _buildMainContent() {
    return Expanded(
      child: Row(
        children: [
          // Password List Panel
          Expanded(
            flex: 1,
            child: _buildPasswordListPanel(),
          ),
          
          // Detail Panel
          if (_selectedPassword != null)
            Expanded(
              flex: 1,
              child: _buildDetailPanel(),
            ),
        ],
      ),
    );
  }

  Widget _buildPasswordListPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          right: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header with search and add button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Passwords',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: 'Add Password (Ctrl+N)',
                      child: ElevatedButton.icon(
                        onPressed: _addNewPassword,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(80, 36),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _filterPasswords,
                  decoration: InputDecoration(
                    hintText: 'Search passwords... (Ctrl+F)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          
          // Category filter chips
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: FilterChip(
                    label: Text(
                      category,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      _filterByCategory(category);
                    },
                    selectedColor: const Color(0xFF34A853).withOpacity(0.3),
                    backgroundColor: const Color(0xFF2C2C2C),
                    checkmarkColor: const Color(0xFF34A853),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF34A853) : Colors.transparent,
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Password List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPasswords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchController.text.isNotEmpty
                                  ? Icons.search_off
                                  : Icons.password,
                              size: 64,
                              color: Colors.white30,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No passwords found'
                                  : 'No passwords yet',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'Try a different search term'
                                  : 'Add your first password to get started',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredPasswords.length,
                        itemBuilder: (context, index) {
                          final password = _filteredPasswords[index];
                          final isSelected = _selectedPassword?.id == password.id;
                          
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF34A853),
                                child: _buildAvatarContent(password.title),
                              ),
                              title: Text(
                                password.title,
                                style: TextStyle(
                                  fontWeight: isSelected 
                                      ? FontWeight.w600 
                                      : FontWeight.normal,
                                  color: isSelected 
                                      ? const Color(0xFF34A853) 
                                      : Colors.white,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (password.username.isNotEmpty)
                                    Text(
                                      password.username,
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF34A853).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      password.category,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF34A853),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Colors.white54,
                              ),
                              selected: isSelected,
                              selectedTileColor: const Color(0xFF34A853)
                                  .withOpacity(0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onTap: () => _selectPassword(password),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel() {
    if (_selectedPassword == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF34A853),
                  child: _buildAvatarContent(_selectedPassword!.title),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedPassword!.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_selectedPassword!.category.isNotEmpty)
                        Text(
                          _selectedPassword!.category,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _editPassword(_selectedPassword!),
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Password',
                ),
                IconButton(
                  onPressed: () => _deletePassword(_selectedPassword!),
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete Password',
                  iconSize: 20,
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedPassword = null),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedPassword!.username.isNotEmpty) ...[
                    _buildDetailField('Username', _selectedPassword!.username),
                    const SizedBox(height: 16),
                  ],
                  _buildDetailField(
                    'Password', 
                    _isPasswordVisible ? _selectedPassword!.encryptedPassword : '••••••••••••',
                    isPassword: true,
                  ),
                  const SizedBox(height: 16),
                  if (_selectedPassword!.category.isNotEmpty) ...[
                    _buildDetailField('Category', _selectedPassword!.category),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedPassword!.notes.isNotEmpty) ...[
                    _buildDetailField('Notes', _selectedPassword!.notes, isMultiline: true),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailField(
    String label, 
    String value, {
    bool isPassword = false,
    bool isUrl = false,
    bool isMultiline = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3C4043)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  maxLines: isMultiline ? null : 1,
                  overflow: isMultiline ? null : TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPassword)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                      icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                      iconSize: 18,
                      tooltip: 'Toggle Visibility',
                    ),
                  IconButton(
                    onPressed: () {
                      final actualValue = isPassword ? _selectedPassword!.encryptedPassword : value;
                      Clipboard.setData(ClipboardData(text: actualValue));
                      Get.snackbar(
                        'Copied',
                        '$label copied to clipboard',
                        snackPosition: SnackPosition.BOTTOM,
                        duration: const Duration(seconds: 2),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    iconSize: 18,
                    tooltip: 'Copy',
                  ),
                  if (isUrl)
                    IconButton(
                      onPressed: () {
                        // Launch URL logic here
                      },
                      icon: const Icon(Icons.open_in_new),
                      iconSize: 18,
                      tooltip: 'Open URL',
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarContent(String title) {
    if (title.isNotEmpty && title.trim().isNotEmpty) {
      final trimmedTitle = title.trim();
      if (trimmedTitle.isNotEmpty && 
          RegExp(r'[a-zA-Z0-9]').hasMatch(trimmedTitle[0])) {
        return Text(
          trimmedTitle[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        );
      }
    }
    return const Icon(Icons.lock, color: Colors.white, size: 20);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          _buildMainContent(),
        ],
      ),
    );
  }
} 
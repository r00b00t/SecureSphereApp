import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/common/widgets/custom_title_bar.dart';
import 'package:decvault/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class DesktopUnifiedBreachScreen extends StatefulWidget {
  const DesktopUnifiedBreachScreen({super.key});

  @override
  State<DesktopUnifiedBreachScreen> createState() => _DesktopUnifiedBreachScreenState();
}

class _DesktopUnifiedBreachScreenState extends State<DesktopUnifiedBreachScreen> with SingleTickerProviderStateMixin {
  final PasswordRepository _passwordRepo = Get.find();
  
  late TabController _tabController;
  
  // Password breach data
  List<PasswordModel> _passwords = [];
  List<PasswordBreachResult> _passwordBreachResults = [];
  bool _isPasswordScanning = false;
  bool _hasPasswordScanned = false;
  String _passwordScanProgress = '';
  int _totalPasswords = 0;
  int _scannedPasswords = 0;
  int _breachedPasswords = 0;
  int _safePasswords = 0;
  DateTime? _lastPasswordScanTime;
  
  // Email breach data
  List<EmailBreachResult> _emailBreachResults = [];
  bool _isEmailScanning = false;
  bool _hasEmailScanned = false;
  String _emailScanProgress = '';
  int _totalEmails = 0;
  int _scannedEmails = 0;
  int _breachedEmails = 0;
  int _safeEmails = 0;
  DateTime? _lastEmailScanTime;
  
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _selectedFilter = 'all'; // all, breached, safe

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _searchController.clear();
        _selectedFilter = 'all';
      });
    });
    _loadPasswords();
    _loadSavedBreachData();
    _setupKeyboardShortcuts();
  }

  Future<void> _loadSavedBreachData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final passwordScanTime = prefs.getString('desktop_password_breach_last_scan');
      final emailScanTime = prefs.getString('desktop_email_breach_last_scan');
      
      setState(() {
        if (passwordScanTime != null) {
          _lastPasswordScanTime = DateTime.parse(passwordScanTime);
        }
        if (emailScanTime != null) {
          _lastEmailScanTime = DateTime.parse(emailScanTime);
        }
      });
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _saveBreachData(String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (type == 'password') {
        await prefs.setString('desktop_password_breach_last_scan', DateTime.now().toIso8601String());
      } else {
        await prefs.setString('desktop_email_breach_last_scan', DateTime.now().toIso8601String());
      }
    } catch (e) {
      // Ignore errors
    }
  }

  String _formatScanTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  int get _totalPasswordBreachCount {
    int total = 0;
    for (var result in _passwordBreachResults) {
      if (result.isBreached) {
        total += result.breachCount;
      }
    }
    return total;
  }

  int get _totalEmailBreachCount {
    int total = 0;
    for (var result in _emailBreachResults) {
      total += result.breachCount;
    }
    return total;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _setupKeyboardShortcuts() {
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
      // Ctrl+R for scan
      if (event.logicalKey == LogicalKeyboardKey.keyR && 
          HardwareKeyboard.instance.isControlPressed) {
        if (_tabController.index == 0) {
          _startPasswordBreachScan();
        } else {
          _startEmailBreachScan();
        }
        return true;
      }
      // Escape to clear search
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _searchController.clear();
        FocusScope.of(context).unfocus();
        return true;
      }
      // Ctrl+Tab to switch tabs
      if (event.logicalKey == LogicalKeyboardKey.tab && 
          HardwareKeyboard.instance.isControlPressed) {
        _tabController.index = (_tabController.index + 1) % 2;
        return true;
      }
    }
    return false;
  }

  Future<void> _loadPasswords() async {
    try {
      final passwords = await _passwordRepo.getAllPasswords();
      setState(() {
        _passwords = passwords;
        _totalPasswords = passwords.length;
      });
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to load passwords: $e',
      );
    }
  }

  // PASSWORD BREACH SCANNING
  Future<void> _startPasswordBreachScan() async {
    if (_isPasswordScanning) return;

    setState(() {
      _isPasswordScanning = true;
      _hasPasswordScanned = false;
      _passwordBreachResults.clear();
      _scannedPasswords = 0;
      _breachedPasswords = 0;
      _safePasswords = 0;
      _passwordScanProgress = 'Starting scan...';
    });

    try {
      for (int i = 0; i < _passwords.length; i++) {
        final password = _passwords[i];
        setState(() {
          _passwordScanProgress = 'Checking ${password.title}...';
          _scannedPasswords = i + 1;
        });

        final breachResult = await _checkPasswordBreach(password);
        _passwordBreachResults.add(breachResult);

        if (breachResult.isBreached) {
          _breachedPasswords++;
        } else {
          _safePasswords++;
        }

        await Future.delayed(const Duration(milliseconds: 200));
      }

      setState(() {
        _isPasswordScanning = false;
        _hasPasswordScanned = true;
        _passwordScanProgress = 'Scan completed';
        _lastPasswordScanTime = DateTime.now();
      });
      await _saveBreachData('password');
      
      SnackbarUtils.showSuccess(
        title: 'Scan Complete',
        message: 'Found $_totalPasswordBreachCount breaches in $_breachedPasswords password(s)',
      );
    } catch (e) {
      setState(() {
        _isPasswordScanning = false;
        _passwordScanProgress = 'Scan failed: $e';
      });
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Password breach scan failed: $e',
      );
    }
  }

  Future<PasswordBreachResult> _checkPasswordBreach(PasswordModel password) async {
    try {
      String passwordToCheck = password.encryptedPassword;
      
      if (passwordToCheck.isEmpty || passwordToCheck.length < 4) {
        return PasswordBreachResult(
          password: password,
          isBreached: false,
          breachCount: 0,
          sources: [],
          lastChecked: DateTime.now(),
          error: 'Password too short to check',
        );
      }
      
      final url = Uri.parse('${ApiConfig.checkPasswordBreachEndpoint}?password=${Uri.encodeComponent(passwordToCheck)}');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bool success = data['success'] ?? false;
        final int count = data['count'] ?? 0;
        final List<String> sources = data['sources'] != null 
            ? (data['sources'] as List).map((s) => s.toString()).toList()
            : [];

        return PasswordBreachResult(
          password: password,
          isBreached: count > 0,
          breachCount: count,
          sources: sources,
          lastChecked: DateTime.now(),
        );
      }

      return PasswordBreachResult(
        password: password,
        isBreached: false,
        breachCount: 0,
        sources: [],
        lastChecked: DateTime.now(),
        error: 'Failed to check password (status ${response.statusCode})',
      );
    } catch (e) {
      return PasswordBreachResult(
        password: password,
        isBreached: false,
        breachCount: 0,
        sources: [],
        lastChecked: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  // EMAIL BREACH SCANNING
  Future<void> _startEmailBreachScan() async {
    if (_isEmailScanning) return;

    setState(() {
      _isEmailScanning = true;
      _hasEmailScanned = false;
      _emailBreachResults.clear();
      _scannedEmails = 0;
      _breachedEmails = 0;
      _safeEmails = 0;
      _emailScanProgress = 'Loading emails...';
    });

    try {
      final passwords = await _passwordRepo.getAllPasswords();
      final Set<String> emails = passwords
          .map((p) => p.username.trim())
          .where((e) => e.contains('@'))
          .toSet();

      if (emails.isEmpty) {
        setState(() {
          _isEmailScanning = false;
          _emailScanProgress = 'No emails found';
        });
        SnackbarUtils.showError(
          title: 'Error',
          message: 'No email addresses found in your passwords',
        );
        return;
      }

      setState(() {
        _totalEmails = emails.length;
        _emailScanProgress = 'Found ${emails.length} emails to check...';
      });

      int index = 0;
      for (final email in emails) {
        setState(() {
          _emailScanProgress = 'Checking $email...';
          _scannedEmails = index + 1;
        });

        final breachResult = await _checkEmailBreach(email);
        _emailBreachResults.add(breachResult);

        if (breachResult.breachCount > 0) {
          _breachedEmails++;
        } else {
          _safeEmails++;
        }

        index++;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      setState(() {
        _isEmailScanning = false;
        _hasEmailScanned = true;
        _emailScanProgress = 'Scan completed';
        _lastEmailScanTime = DateTime.now();
      });
      await _saveBreachData('email');
      
      SnackbarUtils.showSuccess(
        title: 'Scan Complete',
        message: 'Found $_totalEmailBreachCount breaches in $_breachedEmails email(s)',
      );
    } catch (e) {
      setState(() {
        _isEmailScanning = false;
        _emailScanProgress = 'Scan failed: $e';
      });
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Email breach scan failed: $e',
      );
    }
  }

  Future<EmailBreachResult> _checkEmailBreach(String email) async {
    try {
      final url = Uri.parse('${ApiConfig.checkEmailBreachEndpoint}?email=${Uri.encodeComponent(email)}');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bool success = data['success'] ?? false;
        final int found = data['found'] ?? 0;
        final List<dynamic> results = data['result'] ?? [];

        List<BreachDetail> breachDetails = [];
        for (var breach in results) {
          breachDetails.add(BreachDetail(
            email: breach['email'] ?? email,
            hasPassword: breach['hash_password'] == true || breach['has_password'] == true,
            maskedPassword: breach['password']?.toString(),
            sha1: breach['sha1']?.toString(),
            hash: breach['hash']?.toString(),
            sources: breach['sources']?.toString() ?? 'Unknown',
          ));
        }

        return EmailBreachResult(
          email: email,
          breachCount: found,
          breachDetails: breachDetails,
          lastChecked: DateTime.now(),
        );
      }

      return EmailBreachResult(
        email: email,
        breachCount: 0,
        breachDetails: [],
        lastChecked: DateTime.now(),
        error: 'Failed to check (status ${response.statusCode})',
      );
    } catch (e) {
      return EmailBreachResult(
        email: email,
        breachCount: 0,
        breachDetails: [],
        lastChecked: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  List<PasswordBreachResult> get _filteredPasswordResults {
    var results = _passwordBreachResults;
    
    switch (_selectedFilter) {
      case 'breached':
        results = results.where((r) => r.isBreached).toList();
        break;
      case 'safe':
        results = results.where((r) => !r.isBreached).toList();
        break;
    }
    
    final searchTerm = _searchController.text.toLowerCase();
    if (searchTerm.isNotEmpty) {
      results = results.where((r) => 
        r.password.title.toLowerCase().contains(searchTerm) ||
        r.password.username.toLowerCase().contains(searchTerm)
      ).toList();
    }
    
    return results;
  }

  List<EmailBreachResult> get _filteredEmailResults {
    var results = _emailBreachResults;
    
    switch (_selectedFilter) {
      case 'breached':
        results = results.where((r) => r.breachCount > 0).toList();
        break;
      case 'safe':
        results = results.where((r) => r.breachCount == 0).toList();
        break;
    }
    
    final searchTerm = _searchController.text.toLowerCase();
    if (searchTerm.isNotEmpty) {
      results = results.where((r) => 
        r.email.toLowerCase().contains(searchTerm)
      ).toList();
    }
    
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final canPop = Navigator.of(context).canPop();
    final isPasswordTab = _tabController.index == 0;
    
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          right: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          if (canPop)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Back',
              ),
            ),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Breach Monitor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Security Check',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Scan Status
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (isPasswordTab) ..._buildPasswordScanStatus()
                        else ..._buildEmailScanStatus(),
                      ],
                    ),
                  ),
                  
                  // Statistics
                  if ((isPasswordTab && _hasPasswordScanned) || (!isPasswordTab && _hasEmailScanned)) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _buildStatCard(
                            'Total Breaches',
                            isPasswordTab ? _totalPasswordBreachCount.toString() : _totalEmailBreachCount.toString(),
                            Icons.warning_amber,
                            (isPasswordTab ? _totalPasswordBreachCount : _totalEmailBreachCount) > 0 ? Colors.red : Colors.green,
                            subtitle: isPasswordTab 
                                ? '$_breachedPasswords password${_breachedPasswords != 1 ? 's' : ''}'
                                : '$_breachedEmails email${_breachedEmails != 1 ? 's' : ''}',
                          ),
                          const SizedBox(height: 12),
                          _buildStatCard(
                            'Breached',
                            isPasswordTab ? _breachedPasswords.toString() : _breachedEmails.toString(),
                            Icons.warning,
                            Colors.red,
                          ),
                          const SizedBox(height: 12),
                          _buildStatCard(
                            'Safe',
                            isPasswordTab ? _safePasswords.toString() : _safeEmails.toString(),
                            Icons.check_circle,
                            Colors.green,
                          ),
                        ],
                      ),
                    ),
                    
                    if ((isPasswordTab && _lastPasswordScanTime != null) || (!isPasswordTab && _lastEmailScanTime != null)) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time, color: Colors.blue, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Last scan: ${_formatScanTime(isPasswordTab ? _lastPasswordScanTime! : _lastEmailScanTime!)}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFF3C4043)),
                    const SizedBox(height: 20),
                    
                    // Filters
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Filter Results',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildFilterOption('All', 'all', isPasswordTab ? _passwordBreachResults.length : _emailBreachResults.length),
                          _buildFilterOption('Breached', 'breached', isPasswordTab ? _breachedPasswords : _breachedEmails),
                          _buildFilterOption('Safe', 'safe', isPasswordTab ? _safePasswords : _safeEmails),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 20),
                  
                  // Info
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info, color: Colors.blue, size: 20),
                        const SizedBox(height: 8),
                        const Text(
                          'About Breach Monitoring',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPasswordTab
                              ? 'We check your passwords against known data breaches using secure breach monitoring.'
                              : 'We check your email addresses against known data breaches to see if your credentials have been exposed.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Back button
          Container(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () => Get.back(),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Home'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPasswordScanStatus() {
    if (_isPasswordScanning) {
      return [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          _passwordScanProgress,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _totalPasswords > 0 ? _scannedPasswords / _totalPasswords : 0,
          backgroundColor: const Color(0xFF2C2C2C),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
        ),
        const SizedBox(height: 8),
        Text(
          '$_scannedPasswords / $_totalPasswords passwords checked',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ];
    } else {
      return [
        ElevatedButton.icon(
          onPressed: _passwords.isEmpty ? null : _startPasswordBreachScan,
          icon: const Icon(Icons.lock, size: 18),
          label: Text(_hasPasswordScanned ? 'Scan Again' : 'Start Password Scan'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        if (_hasPasswordScanned) ...[
          const SizedBox(height: 16),
          const Text(
            'Last scan completed',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ];
    }
  }

  List<Widget> _buildEmailScanStatus() {
    if (_isEmailScanning) {
      return [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          _emailScanProgress,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _totalEmails > 0 ? _scannedEmails / _totalEmails : 0,
          backgroundColor: const Color(0xFF2C2C2C),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
        ),
        const SizedBox(height: 8),
        Text(
          '$_scannedEmails / $_totalEmails emails checked',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ];
    } else {
      return [
        ElevatedButton.icon(
          onPressed: _startEmailBreachScan,
          icon: const Icon(Icons.email, size: 18),
          label: Text(_hasEmailScanned ? 'Scan Again' : 'Start Email Scan'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        if (_hasEmailScanned) ...[
          const SizedBox(height: 16),
          const Text(
            'Last scan completed',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ];
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(String label, String value, int count) {
    final isSelected = _selectedFilter == value;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF34A853).withOpacity(0.2) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFF34A853) : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF34A853) : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected 
                    ? const Color(0xFF34A853).withOpacity(0.3)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: isSelected ? const Color(0xFF34A853) : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF121212),
            const Color(0xFF1E1E1E),
            const Color(0xFF1E8E3E).withOpacity(0.08),
          ],
        ),
      ),
      child: Column(
        children: [
          _buildToolbar(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPasswordResultsList(),
                _buildEmailResultsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final isPasswordTab = _tabController.index == 0;
    final hasScanned = isPasswordTab ? _hasPasswordScanned : _hasEmailScanned;
    final isScanning = isPasswordTab ? _isPasswordScanning : _isEmailScanning;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Breach Monitoring Results',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (hasScanned) ...[
            SizedBox(
              width: 300,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search results... (Ctrl+F)',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear, size: 20),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Tooltip(
            message: isPasswordTab ? 'Start Password Scan (Ctrl+R)' : 'Start Email Scan (Ctrl+R)',
            child: ElevatedButton.icon(
              onPressed: isScanning ? null : (isPasswordTab ? _startPasswordBreachScan : _startEmailBreachScan),
              icon: isScanning 
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isPasswordTab ? Icons.lock : Icons.email, size: 18),
              label: Text(isScanning ? 'Scanning...' : 'Scan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF34A853),
        labelColor: const Color(0xFF34A853),
        unselectedLabelColor: Colors.white70,
        tabs: const [
          Tab(
            icon: Icon(Icons.lock),
            text: 'Password Breach',
          ),
          Tab(
            icon: Icon(Icons.email_outlined),
            text: 'Email Breach',
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordResultsList() {
    if (!_hasPasswordScanned) {
      return _buildEmptyState(
        icon: Icons.lock,
        title: 'No password scan performed yet',
        subtitle: 'Click "Scan" to check your passwords for known breaches',
      );
    }

    final filteredResults = _filteredPasswordResults;

    if (filteredResults.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off,
        title: 'No results found',
        subtitle: 'Try adjusting your search or filter criteria',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredResults.length,
      itemBuilder: (context, index) {
        final result = filteredResults[index];
        return _buildPasswordResultCard(result);
      },
    );
  }

  Widget _buildEmailResultsList() {
    if (!_hasEmailScanned) {
      return _buildEmptyState(
        icon: Icons.email_outlined,
        title: 'No email scan performed yet',
        subtitle: 'Click "Scan" to check your emails for known breaches',
      );
    }

    final filteredResults = _filteredEmailResults;

    if (filteredResults.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off,
        title: 'No results found',
        subtitle: 'Try adjusting your search or filter criteria',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredResults.length,
      itemBuilder: (context, index) {
        final result = filteredResults[index];
        return _buildEmailResultCard(result);
      },
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.4),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordResultCard(PasswordBreachResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: result.isBreached 
                      ? Colors.red.withOpacity(0.2)
                      : Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  result.isBreached ? Icons.warning : Icons.check_circle,
                  color: result.isBreached ? Colors.red : Colors.green,
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.password.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (result.password.username.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        result.password.username,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: result.isBreached 
                                ? Colors.red.withOpacity(0.2)
                                : Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            result.isBreached ? 'BREACHED' : 'SAFE',
                            style: TextStyle(
                              color: result.isBreached ? Colors.red : Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (result.isBreached) ...[
                          const SizedBox(width: 8),
                          Text(
                            'Found in ${result.breachCount} breaches',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (result.isBreached && result.sources.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.source, color: Colors.orangeAccent, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Breach Sources:',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: result.sources.map<Widget>((source) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.orangeAccent.withOpacity(0.3),
                                        Colors.deepOrangeAccent.withOpacity(0.2),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
                                  ),
                                  child: Text(
                                    source,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              if (result.isBreached)
                ElevatedButton.icon(
                  onPressed: () {
                    SnackbarUtils.showError(
                      title: 'Security Alert',
                      message: 'This password has been found in ${result.breachCount} data breaches. Please change it immediately.',
                    );
                  },
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Change'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailResultCard(EmailBreachResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: result.breachCount > 0
                          ? Colors.red.withOpacity(0.2)
                          : Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      result.breachCount > 0 ? Icons.warning : Icons.check_circle,
                      color: result.breachCount > 0 ? Colors.red : Colors.green,
                      size: 24,
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.email,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: result.breachCount > 0
                                    ? Colors.red.withOpacity(0.2)
                                    : Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                result.breachCount > 0 ? 'BREACHED' : 'SAFE',
                                style: TextStyle(
                                  color: result.breachCount > 0 ? Colors.red : Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (result.breachCount > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                'Found in ${result.breachCount} breaches',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              if (result.breachDetails.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF3C4043)),
                const SizedBox(height: 16),
                const Text(
                  'Breach Details:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ...result.breachDetails.map((detail) => _buildBreachDetailCard(detail)),
              ],
              
              if (result.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          result.error!,
                          style: const TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreachDetailCard(BreachDetail detail) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                detail.hasPassword ? Icons.lock : Icons.info_outline,
                color: detail.hasPassword ? Colors.redAccent : Colors.orangeAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                detail.hasPassword ? 'Password Hash Found' : 'Email Only (No Password)',
                style: TextStyle(
                  color: detail.hasPassword ? Colors.redAccent : Colors.orangeAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          if (detail.maskedPassword != null && detail.maskedPassword!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.vpn_key, color: Colors.redAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Masked Password:',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail.maskedPassword!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          
          if (detail.sha1 != null && detail.sha1!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.fingerprint, color: Colors.purpleAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'SHA1 Hash:',
                        style: TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    detail.sha1!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          
          if (detail.hash != null && detail.hash!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tag, color: Colors.blueAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Hash:',
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    detail.hash!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.source, color: Colors.orangeAccent, size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                'Breach Source:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orangeAccent.withOpacity(0.3),
                  Colors.deepOrangeAccent.withOpacity(0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
            ),
            child: Text(
              detail.sources,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Data models
class PasswordBreachResult {
  final PasswordModel password;
  final bool isBreached;
  final int breachCount;
  final List<String> sources;
  final DateTime lastChecked;
  final String? error;

  PasswordBreachResult({
    required this.password,
    required this.isBreached,
    required this.breachCount,
    required this.sources,
    required this.lastChecked,
    this.error,
  });
}

class EmailBreachResult {
  final String email;
  final int breachCount;
  final List<BreachDetail> breachDetails;
  final DateTime lastChecked;
  final String? error;

  EmailBreachResult({
    required this.email,
    required this.breachCount,
    required this.breachDetails,
    required this.lastChecked,
    this.error,
  });
}

class BreachDetail {
  final String email;
  final bool hasPassword;
  final String? maskedPassword;
  final String? sha1;
  final String? hash;
  final String sources;

  BreachDetail({
    required this.email,
    required this.hasPassword,
    this.maskedPassword,
    this.sha1,
    this.hash,
    required this.sources,
  });
}


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

class DesktopBreachMonitoringScreen extends StatefulWidget {
  const DesktopBreachMonitoringScreen({super.key});

  @override
  State<DesktopBreachMonitoringScreen> createState() => _DesktopBreachMonitoringScreenState();
}

class _DesktopBreachMonitoringScreenState extends State<DesktopBreachMonitoringScreen> {
  final PasswordRepository _passwordRepo = Get.find();
  
  List<PasswordModel> _passwords = [];
  List<BreachResult> _breachResults = [];
  bool _isScanning = false;
  bool _hasScanned = false;
  String _scanProgress = '';
  int _totalPasswords = 0;
  int _scannedPasswords = 0;
  int _breachedPasswords = 0;
  int _safePasswords = 0;
  DateTime? _lastScanTime;
  
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _selectedFilter = 'all'; // all, breached, safe

  @override
  void initState() {
    super.initState();
    _loadPasswords();
    _loadSavedBreachData();
    _setupKeyboardShortcuts();
  }

  Future<void> _loadSavedBreachData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTime = prefs.getString('desktop_breach_last_scan');
      if (savedTime != null) {
        setState(() {
          _lastScanTime = DateTime.parse(savedTime);
        });
      }
    } catch (e) {
    }
  }

  Future<void> _saveBreachData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('desktop_breach_last_scan', DateTime.now().toIso8601String());
    } catch (e) {
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

  int get _totalBreachCount {
    int total = 0;
    for (var result in _breachResults) {
      if (result.isBreached) {
        total += result.breachCount;
      }
    }
    return total;
  }

  @override
  void dispose() {
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
         _startBreachScan();
         return true;
       }
      // Escape to clear search
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _searchController.clear();
        FocusScope.of(context).unfocus();
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

  Future<void> _startBreachScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _hasScanned = false;
      _breachResults.clear();
      _scannedPasswords = 0;
      _breachedPasswords = 0;
      _safePasswords = 0;
      _scanProgress = 'Starting scan...';
    });

    try {
      for (int i = 0; i < _passwords.length; i++) {
        final password = _passwords[i];
        setState(() {
          _scanProgress = 'Checking ${password.title}...';
          _scannedPasswords = i + 1;
        });

        final breachResult = await _checkPasswordBreach(password);
        _breachResults.add(breachResult);

        if (breachResult.isBreached) {
          _breachedPasswords++;
        } else {
          _safePasswords++;
        }

        // Add small delay to show progress
        await Future.delayed(const Duration(milliseconds: 200));
      }

      setState(() {
        _isScanning = false;
        _hasScanned = true;
        _scanProgress = 'Scan completed';
        _lastScanTime = DateTime.now();
      });
      await _saveBreachData();
    } catch (e) {
      setState(() {
        _isScanning = false;
        _scanProgress = 'Scan failed: $e';
      });
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Breach scan failed: $e',
      );
    }
  }

  Future<BreachResult> _checkPasswordBreach(PasswordModel password) async {
    try {
      // Get the actual password from secure storage to check for breaches
      // The encryptedPassword field stores the actual password value
      String passwordToCheck = password.encryptedPassword;
      
      // If password is empty or too short, skip the API call
      if (passwordToCheck.isEmpty || passwordToCheck.length < 4) {
        return BreachResult(
          password: password,
          isBreached: false,
          breachCount: 0,
          sources: [],
          lastChecked: DateTime.now(),
          error: 'Password too short to check',
        );
      }
      
      final url = Uri.parse('${ApiConfig.checkPasswordBreachEndpoint}?password=${Uri.encodeComponent(passwordToCheck)}');
      final response = await http.get(url)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bool success = data['success'] ?? false;
        final int count = data['count'] ?? 0;
        final List<String> sources = data['sources'] != null 
            ? (data['sources'] as List).map((s) => s.toString()).toList()
            : [];

        return BreachResult(
          password: password,
          isBreached: count > 0,
          breachCount: count,
          sources: sources,
          lastChecked: DateTime.now(),
        );
      }

      return BreachResult(
        password: password,
        isBreached: false,
        breachCount: 0,
        sources: [],
        lastChecked: DateTime.now(),
        error: 'Failed to check password (status ${response.statusCode})',
      );
    } catch (e) {
      return BreachResult(
        password: password,
        isBreached: false,
        breachCount: 0,
        sources: [],
        lastChecked: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  List<BreachResult> get _filteredResults {
    var results = _breachResults;
    
    // Apply filter
    switch (_selectedFilter) {
      case 'breached':
        results = results.where((r) => r.isBreached).toList();
        break;
      case 'safe':
        results = results.where((r) => !r.isBreached).toList();
        break;
    }
    
    // Apply search
    final searchTerm = _searchController.text.toLowerCase();
    if (searchTerm.isNotEmpty) {
      results = results.where((r) => 
        r.password.title.toLowerCase().contains(searchTerm) ||
        r.password.username.toLowerCase().contains(searchTerm)
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
          // Back button if navigated to this screen
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
          // Header - Fixed at top
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
                        if (_isScanning) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            _scanProgress,
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
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: _passwords.isEmpty ? null : _startBreachScan,
                            icon: const Icon(Icons.security, size: 18),
                            label: Text(_hasScanned ? 'Scan Again' : 'Start Scan'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                          if (_hasScanned) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Last scan completed',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  
                  // Statistics
                  if (_hasScanned) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _buildStatCard(
                            'Total Breaches',
                            _totalBreachCount.toString(),
                            Icons.warning_amber,
                            _totalBreachCount > 0 ? Colors.red : Colors.green,
                            subtitle: '$_breachedPasswords password${_breachedPasswords != 1 ? 's' : ''}',
                          ),
                          const SizedBox(height: 12),
                          _buildStatCard(
                            'Breached',
                            _breachedPasswords.toString(),
                            Icons.warning,
                            Colors.red,
                          ),
                          const SizedBox(height: 12),
                          _buildStatCard(
                            'Safe',
                            _safePasswords.toString(),
                            Icons.check_circle,
                            Colors.green,
                          ),
                        ],
                      ),
                    ),
                    
                    if (_lastScanTime != null) ...[
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
                              Icon(Icons.access_time, color: Colors.blue, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Last scan: ${_formatScanTime(_lastScanTime!)}',
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
                          _buildFilterOption('All', 'all', _breachResults.length),
                          _buildFilterOption('Breached', 'breached', _breachedPasswords),
                          _buildFilterOption('Safe', 'safe', _safePasswords),
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
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info, color: Colors.blue, size: 20),
                        SizedBox(height: 8),
                        Text(
                          'About Breach Monitoring',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'We check your passwords against known data breaches using our secure breach monitoring API.',
                          style: TextStyle(
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
          
          // Back button - Fixed at bottom
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
          Expanded(
            child: _buildResultsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
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
          if (_hasScanned) ...[
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
            message: 'Start Scan (Ctrl+R)',
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _startBreachScan,
              icon: _isScanning 
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.security, size: 18),
              label: Text(_isScanning ? 'Scanning...' : 'Scan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (!_hasScanned) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.security,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'No breach scan performed yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click "Start Scan" to check your passwords for known breaches',
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

    final filteredResults = _filteredResults;

    if (filteredResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'No results found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filter criteria',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredResults.length,
      itemBuilder: (context, index) {
        final result = filteredResults[index];
        return _buildResultCard(result);
      },
    );
  }

  Widget _buildResultCard(BreachResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status Icon
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
              
              // Password Info
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
                            Row(
                              children: [
                                Icon(Icons.source, color: Colors.orangeAccent, size: 16),
                                const SizedBox(width: 8),
                                const Text(
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
              
              // Actions
              if (result.isBreached)
                ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to password edit screen
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
}

class BreachResult {
  final PasswordModel password;
  final bool isBreached;
  final int breachCount;
  final List<String> sources;
  final DateTime lastChecked;
  final String? error;

  BreachResult({
    required this.password,
    required this.isBreached,
    required this.breachCount,
    required this.sources,
    required this.lastChecked,
    this.error,
  });
} 

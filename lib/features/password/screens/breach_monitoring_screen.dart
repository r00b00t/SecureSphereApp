import 'package:flutter/material.dart';
import 'package:decvault/common/widgets/app_drawer.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BreachMonitoringScreen extends StatefulWidget {
  const BreachMonitoringScreen({super.key});

  @override
  State<BreachMonitoringScreen> createState() => _BreachMonitoringScreenState();
}

class _BreachMonitoringScreenState extends State<BreachMonitoringScreen> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _breachResults = [];
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    _loadSavedBreachData();
  }

  Future<void> _loadSavedBreachData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('breach_monitoring_data');
      final savedTime = prefs.getString('breach_monitoring_last_scan');
      
      if (savedData != null) {
        final List<dynamic> data = json.decode(savedData);
        setState(() {
          _breachResults = data.cast<Map<String, dynamic>>();
          if (savedTime != null) {
            _lastScanTime = DateTime.parse(savedTime);
          }
        });
      }
    } catch (e) {
    }
  }

  Future<void> _saveBreachData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('breach_monitoring_data', json.encode(_breachResults));
      await prefs.setString('breach_monitoring_last_scan', DateTime.now().toIso8601String());
    } catch (e) {
    }
  }

  Future<void> _checkBreaches() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _breachResults.clear();
    });
    try {
      final passwordRepo = Get.find<PasswordRepository>();
      final List<PasswordModel> passwords = await passwordRepo.getAllPasswords();
      final Set<String> emails = passwords.map((p) => p.username.trim()).where((e) => e.contains('@')).toSet();
      if (emails.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = 'No saved emails found.';
        });
        return;
      }
      List<Map<String, dynamic>> results = [];
      for (final email in emails) {
        final url = Uri.parse('${ApiConfig.checkEmailBreachEndpoint}?email=$email');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          results.add({
            'email': email,
            'data': data,
          });
        } else {
          results.add({
            'email': email,
            'error': 'Failed to fetch data (status ${response.statusCode})',
          });
        }
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _breachResults = results;
        _lastScanTime = DateTime.now();
      });
      await _saveBreachData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Error: $e';
      });
    }
  }

  int get _totalBreachCount {
    int total = 0;
    for (var result in _breachResults) {
      if (result['data'] != null) {
        total += (result['data']['found'] ?? 0) as int;
      }
    }
    return total;
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

  @override
  Widget build(BuildContext context) {
    final int detectionCount = _breachResults.where((r) => r['data'] != null && (r['data']['found'] ?? 0) > 0).length;
    final int totalBreaches = _totalBreachCount;
    final bool hasBreaches = totalBreaches > 0;

    // Check if we can pop (came from navigation)
    final canPop = Navigator.of(context).canPop();
    
    return Scaffold(
      appBar: AppBar(
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null, // Show drawer icon if can't pop
        title: const Text('Breach Monitoring'),
        actions: [
          if (_lastScanTime != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Text(
                  'Last scan: ${_formatScanTime(_lastScanTime!)}',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      drawer: canPop ? null : const AppDrawer(), // Only show drawer if not navigated to
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
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Card(
              color: hasBreaches ? const Color(0xFFD32F2F) : const Color(0xFF1E8E3E),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      hasBreaches ? Icons.warning : Icons.shield,
                      color: Colors.white,
                      size: 40,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Breaches',
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
                          ),
                          Text(
                            '$totalBreaches',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            hasBreaches 
                                ? '$detectionCount email${detectionCount != 1 ? 's' : ''} affected'
                                : 'No breaches detected',
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Stay informed about recent security breaches and check if your credentials have been compromised.',
              style: TextStyle(fontSize: 16, color: Colors.grey[200]),
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: _isLoading ? const Text('Checking...') : const Text('Check My Credentials'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isLoading ? null : _checkBreaches,
              ),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 20),
              Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
            ],
            if (_breachResults.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(
                'Breach Results',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              ..._breachResults.map((result) {
                final email = result['email'] ?? '';
                if (result['error'] != null) {
                  return Card(
                    color: const Color(0xFF2C2F33),
                    child: ListTile(
                      leading: const Icon(Icons.error, color: Colors.redAccent),
                      title: Text(email, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(result['error'], style: const TextStyle(color: Colors.white70)),
                    ),
                  );
                }
                final data = result['data'] ?? {};
                final bool success = data['success'] ?? false;
                final int found = data['found'] ?? 0;
                final List breachResults = data['result'] ?? [];
                
                return Card(
                  color: const Color(0xFF23272A),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ExpansionTile(
                    leading: Icon(
                      found > 0 ? Icons.warning : Icons.shield,
                      color: found > 0 ? Colors.orangeAccent : Colors.greenAccent,
                    ),
                    title: Text(email, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              found > 0 ? Icons.warning : Icons.check_circle,
                              color: found > 0 ? Colors.orangeAccent : Colors.greenAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Breaches Found',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$found',
                              style: TextStyle(
                                color: found > 0 ? Colors.orangeAccent : Colors.greenAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    children: [
                      if (breachResults.isNotEmpty)
                        ...breachResults.map<Widget>((breach) {
                          return Card(
                            color: const Color(0xFF2C2F33),
                            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.email, color: Colors.blueAccent, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          breach['email'] ?? '',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Password status indicator
                                        if (breach['hash_password'] == true) ...[
                                          Row(
                                            children: [
                                              Icon(Icons.lock, color: Colors.redAccent, size: 18),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Password Hash Found',
                                                style: const TextStyle(
                                                  color: Colors.redAccent,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                        ] else if (breach['has_password'] == false) ...[
                                          Row(
                                            children: [
                                              Icon(Icons.info_outline, color: Colors.orangeAccent, size: 18),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Email Only (No Password)',
                                                style: const TextStyle(
                                                  color: Colors.orangeAccent,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                        
                                        // Masked password
                                        if (breach['password'] != null && breach['password'].toString().isNotEmpty) ...[
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
                                                Row(
                                                  children: [
                                                    Icon(Icons.vpn_key, color: Colors.redAccent, size: 14),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Masked Password:',
                                                      style: const TextStyle(
                                                        color: Colors.redAccent,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  breach['password'].toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontFamily: 'monospace',
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        
                                        // SHA1 hash
                                        if (breach['sha1'] != null && breach['sha1'].toString().isNotEmpty) ...[
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
                                                Row(
                                                  children: [
                                                    Icon(Icons.fingerprint, color: Colors.purpleAccent, size: 14),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'SHA1 Hash:',
                                                      style: const TextStyle(
                                                        color: Colors.purpleAccent,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  breach['sha1'].toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 10,
                                                    fontFamily: 'monospace',
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        
                                        // Hash value
                                        if (breach['hash'] != null && breach['hash'].toString().isNotEmpty) ...[
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
                                                Row(
                                                  children: [
                                                    Icon(Icons.tag, color: Colors.blueAccent, size: 14),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Hash:',
                                                      style: const TextStyle(
                                                        color: Colors.blueAccent,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  breach['hash'].toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 10,
                                                    fontFamily: 'monospace',
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        
                                        // Breach sources
                                        if (breach['sources'] != null && breach['sources'].toString().isNotEmpty) ...[
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: Colors.orangeAccent.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Icon(Icons.source, color: Colors.orangeAccent, size: 16),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Breach Source:',
                                                style: const TextStyle(
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
                                              breach['sources'].toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList()
                      else
                        ListTile(
                          leading: Icon(Icons.check_circle, color: Colors.greenAccent),
                          title: Text('No Breaches Found', style: const TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ],
            const SizedBox(height: 32),
            Text(
              'Detection Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Card(
              color: const Color(0xFF23272A),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.redAccent.withOpacity(0.2),
                                  Colors.deepOrangeAccent.withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.email, color: Colors.redAccent, size: 28),
                                const SizedBox(height: 8),
                                Text(
                                  '$detectionCount',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Affected Emails',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.orangeAccent.withOpacity(0.2),
                                  Colors.orange.withOpacity(0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
                                const SizedBox(height: 8),
                                Text(
                                  '$totalBreaches',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Total Breaches',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

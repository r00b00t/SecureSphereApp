import 'package:flutter/material.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:securesphere/config/api_config.dart'; // Added this line

class BreachMonitoringScreen extends StatefulWidget {
  const BreachMonitoringScreen({super.key});

  @override
  State<BreachMonitoringScreen> createState() => _BreachMonitoringScreenState();
}

class _BreachMonitoringScreenState extends State<BreachMonitoringScreen> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _breachResults = [];
  List<dynamic> recentBreaches = [];
  bool isLoadingRecentBreaches = false;
  String recentBreachesError = '';

  @override
  void initState() {
    super.initState();
    _fetchRecentBreaches().then((breaches) {
      setState(() {
        recentBreaches = breaches;
      });
    });
  }
  Future<void> _checkBreaches() async {
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
        setState(() {
          _isLoading = false;
          _error = 'No saved emails found.';
        });
        return;
      }
      List<Map<String, dynamic>> results = [];
      for (final email in emails) {
        final url = Uri.parse('${ApiConfig.breachApiBaseUrl}${ApiConfig.breachAnalyticsPath}?email=$email');
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
      setState(() {
        _isLoading = false;
        _breachResults = results;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error: $e';
      });
    }
  }

  Future<List<dynamic>> _fetchRecentBreaches() async {
    setState(() {
      isLoadingRecentBreaches = true;
      recentBreachesError = '';
    });
    try {
      final response = await http.get(Uri.parse('${ApiConfig.breachApiBaseUrl}${ApiConfig.breachesPath}'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          isLoadingRecentBreaches = false;
        });
        return data['exposedBreaches']?.take(5).toList() ?? [];
      } else {
        setState(() {
          isLoadingRecentBreaches = false;
          recentBreachesError = 'Failed to fetch recent breaches (status ${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        isLoadingRecentBreaches = false;
        recentBreachesError = 'Error fetching recent breaches: $e';
      });
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final int detectionCount = _breachResults.where((r) => r['data'] != null && (r['data']['BreachesSummary']?['site'] ?? []).isNotEmpty).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Breach Monitoring'),
      ),
      drawer: const AppDrawer(),
      body: Container(
        color: const Color(0xFF181A20),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Card(
              color: const Color(0xFF1E8E3E),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.shield, color: Colors.white, size: 40),
                    const SizedBox(width: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detections',
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
                        ),
                        Text(
                          '$detectionCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          'Breaches detected',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                        ),
                      ],
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
                final breachesSite = data['BreachesSummary']?['site'];
                final List breachesSummary =
                  (breachesSite is String && breachesSite.trim().isNotEmpty)
                    ? breachesSite.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
                    : (breachesSite is List ? breachesSite : []);
                final risk = (data['BreachMetrics']?['risk'] != null && data['BreachMetrics']['risk'].isNotEmpty)
                    ? data['BreachMetrics']['risk'][0]['risk_label']
                    : 'Unknown';
                final riskScore = (data['BreachMetrics']?['risk'] != null && data['BreachMetrics']['risk'].isNotEmpty)
                    ? data['BreachMetrics']['risk'][0]['risk_score'].toString()
                    : '-';
                final breachCount = breachesSummary is List ? breachesSummary.length : 0;
                return Card(
                  color: const Color(0xFF23272A),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ExpansionTile(
                    leading: Icon(Icons.shield, color: Colors.blueAccent),
                    title: Text(email, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text('Detections', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text('$breachCount breach', style: const TextStyle(color: Colors.white, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text('Risk Level', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text('$risk ($riskScore)', style: const TextStyle(color: Colors.white, fontSize: 16)),
                          ],
                        ),
                      ],
                    ),
                    children: [
                      if (breachesSummary.isNotEmpty)
                        ...breachesSummary.map<Widget>((site) {
                          final List breachDetailsList = data['ExposedBreaches']?['breaches_details'] ?? [];
                          final breachDetail = breachDetailsList.firstWhere(
                            (detail) => (detail['breach'] ?? '').toString().trim() == site.toString(),
                            orElse: () => null,
                          );
                          if (breachDetail != null) {
                            return Card(
                              color: const Color(0xFF23272A),
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            breachDetail['breach'] ?? site.toString(),
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if ((breachDetail['details'] ?? '').toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6.0),
                                        child: Text(
                                          'Details: ' + (breachDetail['details'] ?? ''),
                                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    if ((breachDetail['domain'] ?? '').toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2.0),
                                        child: Text(
                                          'Domain: ' + (breachDetail['domain'] ?? ''),
                                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    if ((breachDetail['xposed_data'] ?? '').toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2.0),
                                        child: Text(
                                          'Exposed Data: ' + (breachDetail['xposed_data'] ?? ''),
                                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    if ((breachDetail['xposed_date'] ?? '').toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2.0),
                                        child: Text(
                                          'Exposed Date: ' + (breachDetail['xposed_date'] ?? ''),
                                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          } else {
                            return ListTile(
                              leading: Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                              title: Text(site.toString(), style: const TextStyle(color: Colors.white)),
                            );
                          }
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
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
                            const SizedBox(width: 8),
                            Text('Active Breaches', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('$detectionCount', style: TextStyle(color: Colors.orangeAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.greenAccent, size: 22),
                            const SizedBox(width: 8),
                            Text('Resolved', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('0', style: TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Recent Breaches',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            if (isLoadingRecentBreaches)
              Center(child: CircularProgressIndicator())
            else if (recentBreachesError.isNotEmpty)
              Center(child: Text(recentBreachesError, style: TextStyle(color: Colors.redAccent)))
            else if (recentBreaches.isEmpty)
              Center(child: Text('No recent breaches found.', style: TextStyle(color: Colors.white70)))
            else
              Column(
                children: recentBreaches.map<Widget>((breach) {
                  return Card(
                    color: const Color(0xFF23272A),
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          breach['logo'] != null && breach['logo'].toString().isNotEmpty
                              ? Image.network(
                                  breach['logo'],
                                  width: 40,
                                  height: 40,
                                  errorBuilder: (context, error, stackTrace) => Icon(Icons.shield, color: Colors.blueAccent, size: 40),
                                )
                              : Icon(Icons.shield, color: Colors.blueAccent, size: 40),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  breach['breachID'] ?? '',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  breach['domain'] ?? '',
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Date: ' + (breach['breachedDate'] ?? ''),
                                  style: TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  breach['exposureDescription'] ?? '',
                                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
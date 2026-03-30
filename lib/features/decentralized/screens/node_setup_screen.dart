import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/features/decentralized/services/decentralized_service.dart';

class NodeSetupScreen extends StatefulWidget {
  const NodeSetupScreen({super.key});

  @override
  State<NodeSetupScreen> createState() => _NodeSetupScreenState();
}

class _NodeSetupScreenState extends State<NodeSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '9980');
  final _passwordController = TextEditingController();

  bool _testing = false;
  bool _passwordVisible = false;
  String? _statusMessage;
  bool _connectionSuccess = false;
  bool _isOnboarding = true;

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
  }

  Future<void> _loadOnboardingState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isOnboarding = !(prefs.getBool('onboarding_complete') ?? false);
    });
  }

  void _handleBack() {
    if (_isOnboarding) {
      Get.offAllNamed('/auth');
    } else {
      Get.back();
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _statusMessage = null;
      _connectionSuccess = false;
    });

    final host = _hostController.text.trim();
    final port = _portController.text.trim();
    final password = _passwordController.text;

    try {
      final url = Uri.parse('http://$host:$port/api/bus/state');
      // renterd uses HTTP basic auth: username is empty, password is the node password.
      final credentials = base64Encode(utf8.encode(':$password'));
      final response = await http.get(
        url,
        headers: {'Authorization': 'Basic $credentials'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _connectionSuccess = true;
          _statusMessage = 'Connection successful.';
        });
      } else {
        setState(() {
          _statusMessage =
              'Node responded with status ${response.statusCode}. '
              'Check your password.';
        });
      }
    } on SocketException {
      setState(() {
        _statusMessage =
            'Could not connect. Check the host and port, and make sure renterd is running.';
      });
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('timed out') || msg.contains('TimeoutException')) {
        setState(() {
          _statusMessage =
              'Connection timed out. Check that renterd is accessible from this device.';
        });
      } else {
        setState(() {
          _statusMessage =
              'Could not reach the node. Verify the host, port, and password are correct.';
        });
      }
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_connectionSuccess) {
      Get.snackbar('Test first', 'Please test the connection before continuing.');
      return;
    }

    final decSvc = Get.find<DecentralizedService>();
    await decSvc.saveNodeConfig(
      _hostController.text.trim(),
      _portController.text.trim(),
      _passwordController.text,
    );

    Get.toNamed('/decentralized-seed-phrase');
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    final formChildren = <Widget>[
              const Icon(Icons.dns_outlined,
                  size: 56, color: Color(0xFF1E8E3E)),
              const SizedBox(height: 16),
              const Text(
                'Connect to Your Sia Node',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the address and password for your renterd node. '
                'You can find these in your renterd dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Host
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: '192.168.1.100 or my.node.example.com',
                  prefixIcon: Icon(Icons.computer_outlined),
                ),
                keyboardType: TextInputType.url,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Host is required' : null,
              ),
              const SizedBox(height: 16),

              // Port
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '9980',
                  prefixIcon: Icon(Icons.settings_ethernet),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Port is required';
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 1 || n > 65535) {
                    return 'Enter a valid port (1–65535)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password
              TextFormField(
                controller: _passwordController,
                obscureText: !_passwordVisible,
                decoration: InputDecoration(
                  labelText: 'Node Password',
                  hintText: 'Password set during renterd installation',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_passwordVisible
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Password is required' : null,
              ),
              const SizedBox(height: 24),

              // Status message
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _connectionSuccess
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _connectionSuccess
                          ? Colors.green.withOpacity(0.4)
                          : Colors.red.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _connectionSuccess
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color:
                            _connectionSuccess ? Colors.green : Colors.redAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            color: _connectionSuccess
                                ? Colors.green
                                : Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_statusMessage != null) const SizedBox(height: 16),

              // Test button
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label:
                    Text(_testing ? 'Testing...' : 'Test Connection'),
              ),
              const SizedBox(height: 12),

              // Continue button
              ElevatedButton(
                onPressed: _connectionSuccess ? _save : null,
                child: const Text('Continue'),
              ),
    ];
    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: formChildren,
      ),
    );
    if (isDesktop) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F0F0F),
                Color(0xFF1A1A1A),
                Color(0xFF0F0F0F),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    _buildBrandingPanel(),
                    if (_isOnboarding)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios,
                              color: Colors.white70, size: 20),
                          onPressed: _handleBack,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                  margin: const EdgeInsets.all(24),
                  child: Card(
                    elevation: 8,
                    color: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      child: SingleChildScrollView(
                        child: form,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Your Sia Node'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: _handleBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: form,
      ),
    );
  }

  Widget _buildBrandingPanel() {
    return Container(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.security,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 20),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DecVault',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Desktop Edition',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 48),
          const Text(
            'Secure Password Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          ...[
            'Decentralized with seed phrase authentication',
            'End-to-end encryption for all your data',
            'Secure file vault with Sia network backup',
            'Cross-platform sync and accessibility',
            'Desktop-optimized productivity features',
          ].map((feature) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34A853).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF34A853),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    feature,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Enter • Proceed\nTab • Switch mode\nEsc • Go back',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

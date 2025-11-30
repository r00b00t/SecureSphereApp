import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// Custom Paywall Screen for Desktop platforms (macOS/Windows)
/// Uses RevenueCat SDK directly since purchases_ui_flutter doesn't support desktop
class CustomPaywallScreen extends StatefulWidget {
  const CustomPaywallScreen({super.key});

  @override
  State<CustomPaywallScreen> createState() => _CustomPaywallScreenState();
}

class _CustomPaywallScreenState extends State<CustomPaywallScreen> {
  final RevenueCatService _revenueCatService = Get.find<RevenueCatService>();
  
  bool _isLoading = true;
  bool _isPurchasing = false;
  Offerings? _offerings;
  String? _error;
  Package? _selectedPackage;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final offerings = await _revenueCatService.getOfferings();
      
      if (offerings == null || offerings.current == null) {
        setState(() {
          _isLoading = false;
          _error = 'No subscription plans available at the moment.';
        });
        return;
      }

      setState(() {
        _offerings = offerings;
        _isLoading = false;
        // Auto-select first package (usually monthly)
        if (offerings.current!.availablePackages.isNotEmpty) {
          _selectedPackage = offerings.current!.availablePackages.first;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load subscription plans: $e';
      });
    }
  }

  Future<void> _purchase() async {
    if (_selectedPackage == null) return;

    setState(() {
      _isPurchasing = true;
    });

    try {
      final success = await _revenueCatService.purchasePackage(_selectedPackage!);
      
      if (success && mounted) {
        // Close paywall and show success
        Navigator.of(context).pop(true);
        
        SnackbarUtils.showSuccess(
          title: 'Success!',
          message: 'Welcome to DecVault Pro!',
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      // Error handling is done in the service
    } finally {
      if (mounted) {
        setState(() {
          _isPurchasing = false;
        });
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() {
      _isPurchasing = true;
    });

    try {
      final success = await _revenueCatService.restorePurchases();
      
      if (success && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
    } finally {
      if (mounted) {
        setState(() {
          _isPurchasing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF34A853)))
          : _error != null
              ? _buildErrorView()
              : _buildPaywallContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadOfferings,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E3E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaywallContent() {
    if (_offerings == null || _offerings!.current == null) {
      return const Center(child: Text('No offers available'));
    }

    final packages = _offerings!.current!.availablePackages;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 32),

          // Features List
          _buildFeaturesList(),
          const SizedBox(height: 32),

          // Package Selection
          _buildPackageSelection(packages),
          const SizedBox(height: 32),

          // Purchase Button
          _buildPurchaseButton(),
          const SizedBox(height: 16),

          // Restore Button
          _buildRestoreButton(),
          const SizedBox(height: 24),

          // Terms & Privacy
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E8E3E).withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.workspace_premium,
            size: 64,
            color: Color(0xFF34A853),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Upgrade to Pro',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Unlock all premium features',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[400],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFeaturesList() {
    final features = [
      {
        'icon': Icons.storage,
        'title': '100GB Storage',
        'description': 'Expand from 10GB to 100GB file vault storage',
      },
      {
        'icon': Icons.security,
        'title': 'Advanced Breach Monitoring',
        'description': 'Real-time alerts for compromised credentials',
      },
      {
        'icon': Icons.sync,
        'title': 'Cross-Platform Sync',
        'description': 'Access Pro features on all your devices',
      },
      {
        'icon': Icons.cloud_done,
        'title': 'Priority Support',
        'description': 'Get help faster when you need it',
      },
    ];

    return Column(
      children: features.map((feature) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E8E3E).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  feature['icon'] as IconData,
                  color: const Color(0xFF34A853),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature['title'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feature['description'] as String,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPackageSelection(List<Package> packages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose Your Plan',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...packages.map((package) => _buildPackageCard(package)),
      ],
    );
  }

  Widget _buildPackageCard(Package package) {
    final isSelected = _selectedPackage == package;
    final isYearly = package.identifier.toLowerCase().contains('annual') ||
        package.identifier.toLowerCase().contains('yearly') ||
        package.identifier == r'$rc_annual';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPackage = package;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFF1E8E3E).withOpacity(0.2)
              : const Color(0xFF1E1E1E),
          border: Border.all(
            color: isSelected 
                ? const Color(0xFF34A853)
                : const Color(0xFF3C4043),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFF34A853) : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        package.storeProduct.title.replaceAll('(DecVault)', '').trim(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isYearly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34A853),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'BEST VALUE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    package.storeProduct.description,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              package.storeProduct.priceString,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isPurchasing ? null : _purchase,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E8E3E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: _isPurchasing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                _selectedPackage != null
                    ? 'Subscribe for ${_selectedPackage!.storeProduct.priceString}'
                    : 'Select a plan',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildRestoreButton() {
    return TextButton(
      onPressed: _isPurchasing ? null : _restorePurchases,
      child: const Text(
        'Restore Purchases',
        style: TextStyle(
          color: Color(0xFF34A853),
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () async {
                final url = Uri.parse('https://decvault.com/terms');
                try {
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open terms of service'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(
                'Terms of Service',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ),
            Text('•', style: TextStyle(color: Colors.grey[600])),
            TextButton(
              onPressed: () async {
                final url = Uri.parse('https://decvault.com/privacy-policy');
                try {
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open privacy policy'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(
                'Privacy Policy',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


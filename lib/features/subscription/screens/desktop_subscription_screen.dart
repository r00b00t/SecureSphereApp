import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

/// Desktop Subscription Screen - Optimized for larger screens
class DesktopSubscriptionScreen extends StatelessWidget {
  const DesktopSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Scaffold(
      body: Obx(() {
        if (revenueCatService.isLoading.value) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        
        if (revenueCatService.isPro.value) {
          return _buildProUserView(revenueCatService);
        }
        
        return _buildSubscriptionOptions(revenueCatService);
      }),
    );
  }
  
  Widget _buildProUserView(RevenueCatService service) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF1E8E3E),
                size: 120,
              ),
              const SizedBox(height: 32),
              const Text(
                'You\'re a DecVault Pro Member!',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                service.getSubscriptionStatusText(),
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 64),
              _buildFeaturesList(),
              const SizedBox(height: 64),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => service.presentCustomerCenter(),
                    icon: const Icon(Icons.settings),
                    label: const Text('Manage Subscription'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(250, 56),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () => service.refreshCustomerInfo(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Status'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(200, 56),
                      textStyle: const TextStyle(fontSize: 16),
                      side: const BorderSide(color: Color(0xFF1E8E3E)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSubscriptionOptions(RevenueCatService service) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(48.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                const Text(
                  'Upgrade to DecVault Pro',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unlock the full power of DecVault with premium features',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 64),
                _buildFeaturesList(),
                const SizedBox(height: 64),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => service.presentPaywall(),
                      icon: const Icon(Icons.star, size: 24),
                      label: const Text('View Plans'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(250, 60),
                        backgroundColor: const Color(0xFF1E8E3E),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 24),
                    OutlinedButton.icon(
                      onPressed: () => _showCustomPlans(service),
                      icon: const Icon(Icons.info_outline, size: 24),
                      label: const Text('See Details'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(200, 60),
                        side: const BorderSide(color: Color(0xFF1E8E3E)),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => service.restorePurchases(),
                  child: const Text(
                    'Restore Purchases',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildFeaturesList() {
    final features = [
      {
        'icon': Icons.lock_outline,
        'title': 'Unlimited Password Storage',
        'description': 'Store unlimited passwords securely'
      },
      {
        'icon': Icons.cloud_upload_outlined,
        'title': 'Unlimited File Storage',
        'description': 'Secure your important files with encryption'
      },
      {
        'icon': Icons.security,
        'title': 'Advanced Breach Monitoring',
        'description': 'Real-time alerts for compromised passwords'
      },
      {
        'icon': Icons.support_agent,
        'title': 'Priority Support',
        'description': 'Get help faster with priority customer support'
      },
      {
        'icon': Icons.sync,
        'title': 'Cross-Device Sync',
        'description': 'Access your vault from anywhere'
      },
      {
        'icon': Icons.enhanced_encryption,
        'title': 'Advanced Encryption',
        'description': 'Military-grade encryption for your data'
      },
    ];
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            const Text(
              'Pro Features',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 3,
                crossAxisSpacing: 32,
                mainAxisSpacing: 24,
              ),
              itemCount: features.length,
              itemBuilder: (context, index) {
                final feature = features[index];
                return Row(
                  children: [
                    Icon(
                      feature['icon'] as IconData,
                      color: const Color(0xFF1E8E3E),
                      size: 40,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            feature['title'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            feature['description'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  void _showCustomPlans(RevenueCatService service) async {
    final offerings = await service.getOfferings();
    
    if (offerings == null || offerings.current == null) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Unable to load subscription plans',
      );
      return;
    }
    
    Get.dialog(
      Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Column(
            children: [
              AppBar(
                title: const Text('Choose Your Plan'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Row(
                    children: offerings.current!.availablePackages
                        .map((package) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: _buildPackageCard(package, service),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: TextButton(
                  onPressed: () => service.restorePurchases(),
                  child: const Text(
                    'Restore Purchases',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPackageCard(Package package, RevenueCatService service) {
    final product = package.storeProduct;
    final isMonthly = product.identifier == RevenueCatService.monthlyProductId;
    final isYearly = product.identifier == RevenueCatService.yearlyProductId;
    
    String badge = '';
    Color? badgeColor;
    
    if (isYearly) {
      badge = 'BEST VALUE';
      badgeColor = const Color(0xFF1E8E3E);
    } else if (isMonthly) {
      badge = 'MOST POPULAR';
      badgeColor = Colors.orange;
    }
    
    return Card(
      child: InkWell(
        onTap: () async {
          Get.back(); // Close dialog
          final success = await service.purchasePackage(package);
          if (success) {
            // Success message already shown by service
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (badge.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                package.storeProduct.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                product.description,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                product.priceString,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E8E3E),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  Get.back(); // Close dialog
                  await service.purchasePackage(package);
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
                child: const Text(
                  'Subscribe Now',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}




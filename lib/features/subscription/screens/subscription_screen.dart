import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

/// Subscription Screen - Shows subscription plans and manages purchases
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('DecVault Pro'),
        actions: [
          TextButton(
            onPressed: () => revenueCatService.restorePurchases(),
            child: const Text('Restore'),
          ),
        ],
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              color: Color(0xFF1E8E3E),
              size: 100,
            ),
            const SizedBox(height: 24),
            const Text(
              'You\'re a Pro!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              service.getSubscriptionStatusText(),
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 48),
            _buildFeaturesList(),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: () => service.presentCustomerCenter(),
              icon: const Icon(Icons.settings),
              label: const Text('Manage Subscription'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSubscriptionOptions(RevenueCatService service) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Upgrade to Pro',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Unlock all premium features',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[400],
                ),
              ),
            ),
            const SizedBox(height: 48),
            _buildFeaturesList(),
            const SizedBox(height: 48),
            // Use RevenueCat's pre-built paywall
            ElevatedButton.icon(
              onPressed: () => service.presentPaywall(),
              icon: const Icon(Icons.star),
              label: const Text('View Plans'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: const Color(0xFF1E8E3E),
              ),
            ),
            const SizedBox(height: 16),
            // Alternative: Build custom UI with offerings
            OutlinedButton(
              onPressed: () => _showCustomPlans(service),
              child: const Text('See Detailed Plans'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: Color(0xFF1E8E3E)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFeaturesList() {
    final features = [
      'Unlimited password storage',
      'Unlimited secure file storage',
      'Advanced breach monitoring',
      'Priority customer support',
      'Cross-device sync',
      'Advanced encryption features',
    ];
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pro Features',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF1E8E3E),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            )),
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
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
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
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: offerings.current!.availablePackages.length,
                  itemBuilder: (context, index) {
                    final package = offerings.current!.availablePackages[index];
                    return _buildPackageCard(package, service);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextButton(
                  onPressed: () => service.restorePurchases(),
                  child: const Text('Restore Purchases'),
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
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () async {
          Get.back(); // Close dialog
          final success = await service.purchasePackage(package);
          if (success) {
            // Success message already shown by service
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    package.storeProduct.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (badge.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                product.description,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    product.priceString,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E8E3E),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Get.back(); // Close dialog
                      await service.purchasePackage(package);
                    },
                    child: const Text('Subscribe'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}




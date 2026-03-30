// This file contains examples of how to use the RevenueCat integration
// DO NOT import this file in your actual code - it's for reference only

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';
import 'package:decvault/features/subscription/widgets/pro_feature_gate.dart';

class Example1ProStatusCheck extends StatelessWidget {
  const Example1ProStatusCheck({super.key});

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Scaffold(
      appBar: AppBar(title: const Text('Example 1: Pro Status')),
      body: Center(
        child: Obx(() {
          if (revenueCatService.isPro.value) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                const Text('You have Pro access!', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 8),
                Text(revenueCatService.getSubscriptionStatusText()),
              ],
            );
          } else {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 64),
                const SizedBox(height: 16),
                const Text('Free Plan', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => revenueCatService.presentPaywall(),
                  child: const Text('Upgrade to Pro'),
                ),
              ],
            );
          }
        }),
      ),
    );
  }
}

class Example2FeatureGating extends StatelessWidget {
  const Example2FeatureGating({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Example 2: Feature Gating')),
      body: ProFeatureGate(
        featureName: 'Advanced Analytics',
        featureDescription: 'Access detailed analytics and insights about your data',
        child: const AdvancedAnalyticsScreen(),
      ),
    );
  }
}

class AdvancedAnalyticsScreen extends StatelessWidget {
  const AdvancedAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Advanced Analytics Content Here'),
    );
  }
}

class Example3ManualCheck extends StatelessWidget {
  const Example3ManualCheck({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Example 3: Manual Check')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _onAdvancedFeatureTap(),
          child: const Text('Use Advanced Feature'),
        ),
      ),
    );
  }

  Future<void> _onAdvancedFeatureTap() async {
    final hasAccess = await requireProAccess(
      featureName: 'Advanced Feature',
      message: 'This feature requires DecVault Pro. Would you like to upgrade?',
    );

    if (hasAccess) {
      // User has Pro access, proceed with feature
      SnackbarUtils.showSuccess(title: 'Success', message: 'Advanced feature activated!');
    } else {
      // User declined or doesn't have Pro
      SnackbarUtils.showInfo(title: 'Info', message: 'Advanced feature requires Pro subscription');
    }
  }
}

class Example4ProGatedButton extends StatelessWidget {
  const Example4ProGatedButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Example 4: Pro Gated Button')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ProGatedButton(
              onPressed: _exportAllData,
              featureName: 'Export All Data',
              message: 'Exporting all data requires DecVault Pro',
              child: const Text('Export All Data'),
            ),
            const SizedBox(height: 16),
            ProGatedIconButton(
              onPressed: _advancedSettings,
              icon: const Icon(Icons.settings_applications),
              featureName: 'Advanced Settings',
            ),
          ],
        ),
      ),
    );
  }

  void _exportAllData() {
    // This only executes if user has Pro
  }

  void _advancedSettings() {
    // This only executes if user has Pro
    Get.toNamed('/advanced-settings');
  }
}

class Example5RestorePurchases extends StatelessWidget {
  const Example5RestorePurchases({super.key});

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Scaffold(
      appBar: AppBar(title: const Text('Example 5: Restore Purchases')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Already purchased?',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 16),
            const Text(
              'Restore your purchases to access Pro features',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Obx(() {
              if (revenueCatService.isLoading.value) {
                return const CircularProgressIndicator();
              }
              return ElevatedButton.icon(
                onPressed: () => revenueCatService.restorePurchases(),
                icon: const Icon(Icons.restore),
                label: const Text('Restore Purchases'),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class Example6CustomerCenter extends StatelessWidget {
  const Example6CustomerCenter({super.key});

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Scaffold(
      appBar: AppBar(title: const Text('Example 6: Customer Center')),
      body: Center(
        child: Obx(() {
          if (!revenueCatService.isPro.value) {
            return const Text('You need an active subscription to access Customer Center');
          }
          
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Manage Your Subscription',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => revenueCatService.presentCustomerCenter(),
                icon: const Icon(Icons.manage_accounts),
                label: const Text('Open Customer Center'),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class Example7ConditionalUI extends StatelessWidget {
  const Example7ConditionalUI({super.key});

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Example 7: Conditional UI'),
        actions: [
          Obx(() {
            if (revenueCatService.isPro.value) {
              return IconButton(
                icon: const Icon(Icons.workspace_premium),
                onPressed: () => revenueCatService.presentCustomerCenter(),
                tooltip: 'Manage Subscription',
              );
            } else {
              return TextButton(
                onPressed: () => revenueCatService.presentPaywall(),
                child: const Text('Upgrade'),
              );
            }
          }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFeatureCard(
            'Basic Feature',
            'Available to all users',
            true,
            () => print('Basic feature'),
          ),
          _buildFeatureCard(
            'Pro Feature 1',
            'Advanced analytics',
            revenueCatService.isPro.value,
            () => print('Pro feature 1'),
          ),
          _buildFeatureCard(
            'Pro Feature 2',
            'Export all data',
            revenueCatService.isPro.value,
            () => print('Pro feature 2'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(String title, String description, bool isAvailable, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: Icon(
          isAvailable ? Icons.check_circle : Icons.lock,
          color: isAvailable ? Colors.green : Colors.grey,
        ),
        title: Text(title),
        subtitle: Text(description),
        enabled: isAvailable,
        onTap: isAvailable ? onTap : null,
        trailing: isAvailable
            ? const Icon(Icons.arrow_forward)
            : TextButton(
                onPressed: () {
                  final revenueCatService = Get.find<RevenueCatService>();
                  revenueCatService.presentPaywall();
                },
                child: const Text('Upgrade'),
              ),
      ),
    );
  }
}

class Example8UserIdentification extends StatelessWidget {
  const Example8UserIdentification({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Example 8: User Identification')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _loginUser,
              child: const Text('Login User'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _setUserAttributes,
              child: const Text('Set User Attributes'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _logoutUser,
              child: const Text('Logout User'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loginUser() async {
    final revenueCatService = Get.find<RevenueCatService>();
    
    // Login with your app's user ID
    await revenueCatService.loginUser('user_12345');
    
    // Set user email
    await revenueCatService.setEmail('user@example.com');
    
    SnackbarUtils.showSuccess(title: 'Success', message: 'User logged in to RevenueCat');
  }

  Future<void> _setUserAttributes() async {
    final revenueCatService = Get.find<RevenueCatService>();
    
    await revenueCatService.setUserAttributes({
      'display_name': 'John Doe',
      'account_created': '2024-01-01',
      'user_type': 'premium',
    });
    
    SnackbarUtils.showSuccess(title: 'Success', message: 'User attributes set');
  }

  Future<void> _logoutUser() async {
    final revenueCatService = Get.find<RevenueCatService>();
    
    await revenueCatService.logoutUser();
    
    SnackbarUtils.showSuccess(title: 'Success', message: 'User logged out');
  }
}

class Example9SubscriptionDetails extends StatelessWidget {
  const Example9SubscriptionDetails({super.key});

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Scaffold(
      appBar: AppBar(title: const Text('Example 9: Subscription Details')),
      body: Obx(() {
        if (!revenueCatService.isPro.value) {
          return const Center(child: Text('No active subscription'));
        }
        
        final customerInfo = revenueCatService.customerInfo.value;
        final productId = revenueCatService.getCurrentProductId();
        final willRenew = revenueCatService.willRenew();
        final statusText = revenueCatService.getSubscriptionStatusText();
        
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildDetailCard('Status', statusText),
            _buildDetailCard('Product ID', productId ?? 'Unknown'),
            _buildDetailCard('Will Renew', willRenew ? 'Yes' : 'No'),
            _buildDetailCard('User ID', customerInfo?.originalAppUserId ?? 'Unknown'),
            _buildDetailCard(
              'Active Subscriptions',
              customerInfo?.activeSubscriptions.join(', ') ?? 'None',
            ),
          ],
        );
      }),
    );
  }

  Widget _buildDetailCard(String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value),
          ],
        ),
      ),
    );
  }
}

class Example10RefreshCustomerInfo extends StatelessWidget {
  const Example10RefreshCustomerInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Example 10: Refresh'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => revenueCatService.refreshCustomerInfo(),
          ),
        ],
      ),
      body: Center(
        child: Obx(() {
          if (revenueCatService.isLoading.value) {
            return const CircularProgressIndicator();
          }
          
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                revenueCatService.isPro.value ? 'Pro User' : 'Free User',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => revenueCatService.refreshCustomerInfo(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Status'),
              ),
            ],
          );
        }),
      ),
    );
  }
}


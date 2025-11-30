import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';

/// Widget to gate features behind Pro subscription
/// Wraps a feature and shows an upgrade prompt if user doesn't have Pro
class ProFeatureGate extends StatelessWidget {
  final Widget child;
  final String featureName;
  final String featureDescription;
  
  const ProFeatureGate({
    super.key,
    required this.child,
    required this.featureName,
    this.featureDescription = 'This is a premium feature',
  });

  @override
  Widget build(BuildContext context) {
    final revenueCatService = Get.find<RevenueCatService>();
    
    return Obx(() {
      // Show loading while checking subscription status
      if (revenueCatService.isLoading.value) {
        return Scaffold(
          body: Container(
            color: const Color(0xFF121212),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      }
      
      // If user has Pro subscription, show the feature
      if (revenueCatService.isPro.value) {
        return child;
      }
      
      // Otherwise show upgrade prompt
      return _buildUpgradePrompt(context);
    });
  }
  
  Widget _buildUpgradePrompt(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 64,
            color: Color(0xFF1E8E3E),
          ),
          const SizedBox(height: 24),
          Text(
            featureName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            featureDescription,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF9E9E9E),
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              final revenueCatService = Get.find<RevenueCatService>();
              revenueCatService.presentPaywall();
            },
            icon: const Icon(Icons.star),
            label: const Text('Upgrade to Pro'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(250, 50),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Get.back();
              }
            },
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Go Back'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to check Pro access and show paywall if needed
Future<bool> requireProAccess({
  String? featureName,
  String? message,
}) async {
  final revenueCatService = Get.find<RevenueCatService>();
  
  if (revenueCatService.isPro.value) {
    return true;
  }
  
  // Show dialog asking user to upgrade
  final shouldUpgrade = await Get.dialog<bool>(
    AlertDialog(
      title: Text(featureName ?? 'Pro Feature'),
      content: Text(
        message ?? 'This feature requires DecVault Pro. Would you like to upgrade?',
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Get.back(result: true),
          child: const Text('Upgrade'),
        ),
      ],
    ),
  );
  
  if (shouldUpgrade == true) {
    await revenueCatService.presentPaywall();
    return revenueCatService.isPro.value;
  }
  
  return false;
}

/// Button that checks Pro status before executing action
class ProGatedButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final String? featureName;
  final String? message;
  final ButtonStyle? style;
  
  const ProGatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.featureName,
    this.message,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        final hasAccess = await requireProAccess(
          featureName: featureName,
          message: message,
        );
        
        if (hasAccess) {
          onPressed();
        }
      },
      style: style,
      child: child,
    );
  }
}

/// Icon button variant
class ProGatedIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Icon icon;
  final String? featureName;
  final String? message;
  
  const ProGatedIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.featureName,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        final hasAccess = await requireProAccess(
          featureName: featureName,
          message: message,
        );
        
        if (hasAccess) {
          onPressed();
        }
      },
      icon: icon,
    );
  }
}


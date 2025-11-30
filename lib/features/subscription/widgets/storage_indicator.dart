import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/subscription/services/storage_service.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';

/// Widget to display storage usage indicator
class StorageIndicator extends StatelessWidget {
  final bool showDetails;
  final bool compact;
  
  const StorageIndicator({
    super.key,
    this.showDetails = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final storageService = Get.find<StorageService>();
    
    return Obx(() {
      if (compact) {
        return _buildCompactIndicator(storageService);
      } else {
        return _buildFullIndicator(storageService);
      }
    });
  }
  
  Widget _buildCompactIndicator(StorageService storageService) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storage,
            size: 16,
            color: storageService.getStorageStatusColor(),
          ),
          const SizedBox(width: 8),
          Text(
            storageService.getStorageUsageText(),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFullIndicator(StorageService storageService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.storage,
                      color: storageService.getStorageStatusColor(),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Storage Usage',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                _buildUpgradeButton(),
              ],
            ),
            const SizedBox(height: 16),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: storageService.percentageUsed.value / 100,
                backgroundColor: Colors.grey[800],
                valueColor: AlwaysStoppedAnimation<Color>(
                  storageService.getStorageStatusColor(),
                ),
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 12),
            // Usage text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  storageService.getStorageUsageText(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  storageService.getPercentageText(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: storageService.getStorageStatusColor(),
                  ),
                ),
              ],
            ),
            if (showDetails) ...[
              const SizedBox(height: 12),
              Text(
                'Plan: ${storageService.getStorageTierName()}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Remaining: ${StorageService.formatBytes(storageService.getRemainingStorage())}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ],
            if (storageService.isNearlyFull()) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        storageService.isFull()
                            ? 'Storage limit reached!'
                            : 'Storage nearly full!',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildUpgradeButton() {
    return Obx(() {
      final revenueCatService = Get.find<RevenueCatService>();
      
      if (revenueCatService.isPro.value) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E8E3E),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'PRO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }
      
      return TextButton.icon(
        onPressed: () => revenueCatService.presentPaywall(),
        icon: const Icon(Icons.arrow_upward, size: 14),
        label: const Text('Upgrade', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    });
  }
}

/// Compact storage indicator for app bar or toolbar
class CompactStorageIndicator extends StatelessWidget {
  const CompactStorageIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const StorageIndicator(
      showDetails: false,
      compact: true,
    );
  }
}




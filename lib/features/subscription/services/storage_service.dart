import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:decvault/config/api_config.dart';

/// Storage Service for tracking file vault storage usage
/// Free users: 10GB limit
/// Pro users: 100GB limit
class StorageService extends GetxController {
  // Storage limits in bytes
  static const int freeTierLimit = 10 * 1024 * 1024 * 1024; // 10GB
  static const int proTierLimit = 100 * 1024 * 1024 * 1024; // 100GB
  
  // Observable current usage in bytes
  final RxInt currentUsage = 0.obs;
  
  // Observable storage limit based on subscription
  final RxInt storageLimit = freeTierLimit.obs;
  
  // Observable percentage used
  final RxDouble percentageUsed = 0.0.obs;
  
  // Storage key for SharedPreferences
  static const String _storageUsageKey = 'storage_usage_bytes';
  
  // Backend sync configuration
  static const bool enableBackendSync = true; // Set to false to use local-only
  static const String _lastSyncKey = 'storage_last_sync';
  
  RevenueCatService? _revenueCatService;
  String? _userId;
  
  @override
  Future<void> onInit() async {
    super.onInit();
    await _initialize();
  }
  
  Future<void> _initialize() async {
    try {
      // Get RevenueCat service
      _revenueCatService = Get.find<RevenueCatService>();
      
      // Wait for RevenueCat to finish loading before updating storage limits
      if (_revenueCatService!.isLoading.value) {
        // Wait for RevenueCat to finish initialization
        await Future.doWhile(() async {
          if (!_revenueCatService!.isLoading.value) {
            return false; // Done waiting
          }
          await Future.delayed(const Duration(milliseconds: 100));
          return true; // Keep waiting
        });
      }
      
      // Try to sync with backend first
      if (enableBackendSync) {
        try {
          await syncWithBackend();
        } catch (e) {
          await loadUsage(); // Fall back to local
        }
      } else {
        await loadUsage();
      }
      
      // Update storage limit based on subscription
      _updateStorageLimit();
      
      // Listen to subscription changes
      ever(_revenueCatService!.isPro, (_) => _updateStorageLimit());
      
    } catch (e) {
      rethrow;
    }
  }
  
  /// Set user ID for backend sync
  void setUserId(String userId) {
    _userId = userId;
  }
  
  /// Sync storage data with backend
  Future<void> syncWithBackend() async {
    if (!enableBackendSync || _userId == null) {
      return;
    }
    
    try {
      
      final response = await http.get(
        Uri.parse('${ApiConfig.psqlBaseUrl}/api/storage/usage/$_userId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Update local storage from backend
        currentUsage.value = data['totalBytes'] ?? 0;
        storageLimit.value = data['storageLimit'] ?? freeTierLimit;
        _calculatePercentage();
        
        // Save locally as cache
        await _saveUsage();
        
        // Save last sync time
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
        
      } else {
        throw Exception('Backend returned ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
  
  /// Update storage limit based on subscription tier
  void _updateStorageLimit() {
    final isPro = _revenueCatService?.isPro.value ?? false;
    storageLimit.value = isPro ? proTierLimit : freeTierLimit;
    _calculatePercentage();
    
  }
  
  /// Load current usage from persistent storage
  Future<void> loadUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      currentUsage.value = prefs.getInt(_storageUsageKey) ?? 0;
      _calculatePercentage();
    } catch (e) {
    }
  }
  
  /// Save current usage to persistent storage
  Future<void> _saveUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageUsageKey, currentUsage.value);
    } catch (e) {
    }
  }
  
  /// Add file size to current usage
  Future<bool> addFileSize(int sizeInBytes, {String? fileId, String? fileName}) async {
    // Check if adding this file would exceed the limit
    if (!canUploadFile(sizeInBytes)) {
      return false;
    }
    
    // Update backend if enabled
    if (enableBackendSync && _userId != null) {
      try {
        await _addFileSizeToBackend(fileId ?? 'unknown', sizeInBytes, fileName);
      } catch (e) {
      }
    }
    
    currentUsage.value += sizeInBytes;
    _calculatePercentage();
    await _saveUsage();
    
    
    return true;
  }
  
  /// Add file size to backend
  Future<void> _addFileSizeToBackend(String fileId, int sizeInBytes, String? fileName) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.psqlBaseUrl}/api/storage/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _userId,
          'fileId': fileId,
          'sizeBytes': sizeInBytes,
          'fileName': fileName,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
      } else if (response.statusCode == 413) {
        // Storage limit exceeded on backend
        final data = jsonDecode(response.body);
        throw Exception('Storage limit exceeded: ${data['error']}');
      } else {
        throw Exception('Backend returned ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
  
  /// Remove file size from current usage
  Future<void> removeFileSize(int sizeInBytes, {String? fileId}) async {
    // Update backend if enabled
    if (enableBackendSync && _userId != null && fileId != null) {
      try {
        await _removeFileSizeFromBackend(fileId);
      } catch (e) {
      }
    }
    
    currentUsage.value = (currentUsage.value - sizeInBytes).clamp(0, storageLimit.value);
    _calculatePercentage();
    await _saveUsage();
    
  }
  
  /// Remove file size from backend
  Future<void> _removeFileSizeFromBackend(String fileId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.psqlBaseUrl}/api/storage/remove'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _userId,
          'fileId': fileId,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
      } else {
        throw Exception('Backend returned ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
  
  /// Check if a file can be uploaded without exceeding limit
  bool canUploadFile(int fileSizeInBytes) {
    final newTotal = currentUsage.value + fileSizeInBytes;
    final canUpload = newTotal <= storageLimit.value;
    
    if (!canUpload) {
    }
    
    return canUpload;
  }
  
  /// Get remaining storage in bytes
  int getRemainingStorage() {
    return (storageLimit.value - currentUsage.value).clamp(0, storageLimit.value);
  }
  
  /// Calculate percentage of storage used
  void _calculatePercentage() {
    if (storageLimit.value > 0) {
      percentageUsed.value = (currentUsage.value / storageLimit.value * 100).clamp(0.0, 100.0);
    } else {
      percentageUsed.value = 0.0;
    }
  }
  
  /// Check if storage is nearly full (>90%)
  bool isNearlyFull() {
    return percentageUsed.value >= 90.0;
  }
  
  /// Check if storage is full
  bool isFull() {
    return currentUsage.value >= storageLimit.value;
  }
  
  /// Get storage tier name
  String getStorageTierName() {
    final isPro = _revenueCatService?.isPro.value ?? false;
    return isPro ? 'Pro (100GB)' : 'Free (10GB)';
  }
  
  /// Get formatted storage usage text
  String getStorageUsageText() {
    return '${formatBytes(currentUsage.value)} / ${formatBytes(storageLimit.value)}';
  }
  
  /// Get formatted percentage text
  String getPercentageText() {
    return '${percentageUsed.value.toStringAsFixed(1)}%';
  }
  
  /// Format bytes to human-readable string
  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
  
  /// Reset usage (for testing or account reset)
  Future<void> resetUsage() async {
    currentUsage.value = 0;
    _calculatePercentage();
    await _saveUsage();
  }
  
  /// Recalculate usage from actual files (for sync/recovery)
  Future<void> recalculateUsage(List<Map<String, dynamic>> files) async {
    // Sync with backend if enabled
    if (enableBackendSync && _userId != null) {
      try {
        await _recalculateOnBackend(files);
        await syncWithBackend(); // Re-sync to get updated values
        return;
      } catch (e) {
      }
    }
    
    // Local recalculation
    final totalSize = files.fold<int>(0, (sum, file) => sum + (file['size'] as int));
    currentUsage.value = totalSize;
    _calculatePercentage();
    await _saveUsage();
    
  }
  
  /// Recalculate storage on backend
  Future<void> _recalculateOnBackend(List<Map<String, dynamic>> files) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.psqlBaseUrl}/api/storage/recalculate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _userId,
          'files': files,
        }),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
      } else {
        throw Exception('Backend returned ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
  
  /// Show storage limit exceeded dialog
  Future<void> showStorageLimitDialog() async {
    final isPro = _revenueCatService?.isPro.value ?? false;
    
    await Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storage, color: Colors.orange),
            SizedBox(width: 8),
            Text('Storage Limit Reached'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPro
                  ? 'You\'ve reached your 100GB Pro storage limit.'
                  : 'You\'ve reached your 10GB free storage limit.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              'Current usage: ${getStorageUsageText()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (!isPro) ...[
              const SizedBox(height: 16),
              const Text(
                'Upgrade to Pro for 100GB of storage!',
                style: TextStyle(color: Color(0xFF1E8E3E)),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          if (!isPro)
            ElevatedButton(
              onPressed: () {
                Get.back();
                _revenueCatService?.presentPaywall();
              },
              child: const Text('Upgrade to Pro'),
            )
          else
            ElevatedButton(
              onPressed: () => Get.back(),
              child: const Text('OK'),
            ),
        ],
      ),
    );
  }
  
  /// Show storage warning (when near limit)
  Future<void> showStorageWarningDialog() async {
    await Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Storage Nearly Full'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'re using ${getPercentageText()} of your storage.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              'Current usage: ${getStorageUsageText()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Consider deleting old files or upgrading to Pro for more storage.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  /// Get storage status color
  Color getStorageStatusColor() {
    if (percentageUsed.value >= 95) {
      return Colors.red;
    } else if (percentageUsed.value >= 80) {
      return Colors.orange;
    } else if (percentageUsed.value >= 60) {
      return Colors.yellow;
    } else {
      return const Color(0xFF1E8E3E); // Green
    }
  }
}


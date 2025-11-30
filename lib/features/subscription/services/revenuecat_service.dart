import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/config/api_config.dart';
import 'package:decvault/features/subscription/screens/custom_paywall_screen.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

/// RevenueCat Service for managing subscriptions
/// Handles initialization, purchases, entitlements, and customer info
class RevenueCatService extends GetxController {
  // API Keys - Production keys for each platform
  static const String _appleApiKey = 'appl_lmNOoOsbzBXGvFIagMPluRFGGsr';
  static const String _googleApiKey = 'goog_QtWzkPdBHaMryqUZuVtLDgbdTJh';
  static const String _windowsWebApiKey = 'rcb_sb_UshmtbqycgfmLRvkxohsMrgua';
  
  // Get platform-specific API key
  static String get _apiKey {
    if (kIsWeb) {
      return _appleApiKey; // Default for web
    }
    
    if (Platform.isIOS || Platform.isMacOS) {
      return _appleApiKey;
    } else if (Platform.isAndroid) {
      return _googleApiKey;
    } else if (Platform.isWindows) {
      return _windowsWebApiKey; // RevenueCat Web for Windows
    }
    
    return _appleApiKey; // Default fallback
  }
  
  // Entitlement identifiers
  static const String proEntitlementId = 'pro';
  
  // Product identifiers
  static const String monthlyProductId = 'pro_m';
  static const String yearlyProductId = 'pro_a';
  
  // Observable customer info
  final Rx<CustomerInfo?> customerInfo = Rx<CustomerInfo?>(null);
  
  // Observable entitlement status
  final RxBool isPro = false.obs;
  
  // Observable loading state
  final RxBool isLoading = false.obs;
  
  // Current user ID
  String? _currentUserId;
  
  @override
  Future<void> onInit() async {
    super.onInit();
    await initialize();
  }
  
  /// Initialize RevenueCat SDK
  Future<void> initialize() async {
    try {
      isLoading.value = true;
      
      // Ensure isPro starts as false
      isPro.value = false;
      
      // Configure SDK
      PurchasesConfiguration configuration = PurchasesConfiguration(_apiKey);
      
      // Enable debug logs in debug mode
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      
      // Initialize Purchases
      await Purchases.configure(configuration);
      
      // Set up listener for customer info updates
      Purchases.addCustomerInfoUpdateListener((info) async {
        await _updateCustomerInfo(info);
      });
      
      // Get initial customer info
      await refreshCustomerInfo();
      
    } catch (e) {
      // On error, ensure user is not marked as Pro
      isPro.value = false;
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }
  
  /// Refresh customer info from RevenueCat
  Future<void> refreshCustomerInfo() async {
    try {
      isLoading.value = true;
      final info = await Purchases.getCustomerInfo();
      await _updateCustomerInfo(info);
    } catch (e) {
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }
  
  /// Update customer info and entitlement status
  Future<void> _updateCustomerInfo(CustomerInfo info) async {
    customerInfo.value = info;
    _currentUserId = info.originalAppUserId;
    
    // Check if user has Pro entitlement from RevenueCat
    final entitlement = info.entitlements.all[proEntitlementId];
    final hasRevenueCatPro = entitlement?.isActive ?? false;
    
    // Also check backend for granted Pro access
    final hasBackendPro = await _checkBackendProAccess(info.originalAppUserId);
    
    // User has Pro if EITHER RevenueCat OR backend grants it
    final newProStatus = hasRevenueCatPro || hasBackendPro;
    
    // Only update if status actually changed to prevent unnecessary refreshes
    if (isPro.value != newProStatus) {
      isPro.value = newProStatus;
    }
    
    if (hasRevenueCatPro && entitlement != null) {
    }
  }
  
  /// Check backend for granted Pro access
  /// Uses DecVault user ID from AuthService, not RevenueCat ID
  Future<bool> _checkBackendProAccess(String revenueCatUserId) async {
    try {
      // Get the actual DecVault user ID from AuthService
      final authService = Get.find<AuthService>();
      final decVaultUserId = await authService.getUserId();
      
      // If no DecVault user ID, user isn't logged in
      if (decVaultUserId == null) {
        return false;
      }
      
      
      final response = await http.get(
        Uri.parse('${ApiConfig.psqlBaseUrl}/api/pro/check/$decVaultUserId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isPro = data['isPro'] as bool? ?? false;
        final isGranted = data['isGranted'] as bool? ?? false;
        
        if (isPro) {
          if (isGranted) {
          }
        } else {
        }
        
        return isPro;
      } else if (response.statusCode == 404) {
      } else {
      }
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('Connection reset') || errorStr.contains('Connection refused')) {
      } else {
      }
    }
    return false;
  }
  
  /// Manually refresh Pro status (checks both RevenueCat and backend)
  Future<void> refreshProStatus() async {
    try {
      isLoading.value = true;
      
      // Get current customer info from RevenueCat
      final info = await Purchases.getCustomerInfo();
      await _updateCustomerInfo(info);
      
    } catch (e) {
    } finally {
      isLoading.value = false;
    }
  }
  
  /// Get available offerings from RevenueCat
  Future<Offerings?> getOfferings() async {
    try {
      isLoading.value = true;
      final offerings = await Purchases.getOfferings();
      
      if (offerings.current != null) {
        
        for (var package in offerings.current!.availablePackages) {
        }
      }
      
      return offerings;
    } catch (e) {
      return null;
    } finally {
      isLoading.value = false;
    }
  }
  
  /// Purchase a package
  // ignore: deprecated_member_use
  Future<bool> purchasePackage(Package package) async {
    try {
      isLoading.value = true;
      
      // ignore: deprecated_member_use
      final customerInfo = await Purchases.purchasePackage(package);
      
      // Update customer info
      await _updateCustomerInfo(customerInfo);
      
      // Check if purchase was successful
      final entitlement = customerInfo.entitlements.all[proEntitlementId];
      final success = entitlement?.isActive ?? false;
      
      if (success) {
        SnackbarUtils.showSuccess(
          title: 'Success!',
          message: 'Welcome to DecVault Pro!',
          duration: const Duration(seconds: 3),
        );
      }
      
      return success;
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        SnackbarUtils.showWarning(
          title: 'Cancelled',
          message: 'Purchase was cancelled',
        );
      } else if (errorCode == PurchasesErrorCode.purchaseNotAllowedError) {
        SnackbarUtils.showError(
          title: 'Error',
          message: 'Purchases are not allowed on this device',
        );
      } else {
        SnackbarUtils.showError(
          title: 'Error',
          message: 'Failed to complete purchase: ${e.message}',
        );
      }
      
      return false;
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'An unexpected error occurred',
      );
      return false;
    } finally {
      isLoading.value = false;
    }
  }
  
  /// Restore purchases
  Future<bool> restorePurchases() async {
    try {
      isLoading.value = true;
      
      final customerInfo = await Purchases.restorePurchases();
      await _updateCustomerInfo(customerInfo);
      
      final entitlement = customerInfo.entitlements.all[proEntitlementId];
      final hasActivePurchase = entitlement?.isActive ?? false;
      
      if (hasActivePurchase) {
        SnackbarUtils.showSuccess(
          title: 'Success',
          message: 'Your subscription has been restored!',
        );
      } else {
        SnackbarUtils.showInfo(
          title: 'No Purchases Found',
          message: 'No active subscription to restore',
        );
      }
      
      return hasActivePurchase;
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to restore purchases',
      );
      return false;
    } finally {
      isLoading.value = false;
    }
  }
  
  /// Present the RevenueCat Paywall
  /// Uses pre-built UI on iOS/Android, custom UI on desktop platforms
  Future<PaywallResult> presentPaywall() async {
    try {
      
      // Check if platform supports RevenueCat UI
      if (!_isPaywallUISupported()) {
        
        // Show custom paywall for desktop
        final result = await Get.to<bool>(
          () => const CustomPaywallScreen(),
          transition: Transition.fade,
          duration: const Duration(milliseconds: 300),
        );
        
        // Refresh customer info after paywall
        await refreshCustomerInfo();
        
        return result == true ? PaywallResult.purchased : PaywallResult.cancelled;
      }
      
      // Use RevenueCat UI for iOS/Android
      final result = await RevenueCatUI.presentPaywall();
      
      
      // Refresh customer info after paywall dismissal
      await refreshCustomerInfo();
      
      return result;
    } catch (e) {
      
      // Fallback dialog if custom paywall fails
      if (e.toString().contains('MissingPluginException') || 
          e.toString().contains('CustomPaywallScreen')) {
        await Get.dialog(
          Builder(
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Upgrade to Pro', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: const Text(
                'To upgrade to Pro on desktop, please visit our website or use the mobile app.\n\nYour Pro features will sync automatically across all devices.',
                style: TextStyle(color: Colors.grey),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
        return PaywallResult.cancelled;
      }
      
      rethrow;
    }
  }
  
  /// Check if RevenueCat UI is supported on current platform
  bool _isPaywallUISupported() {
    // RevenueCat UI only supports iOS and Android
    try {
      return !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    } catch (e) {
      return false;
    }
  }
  
  /// Present the RevenueCat Paywall if user is not Pro
  Future<bool> presentPaywallIfNeeded() async {
    if (isPro.value) {
      return true;
    }
    
    final result = await presentPaywall();
    return result == PaywallResult.purchased || result == PaywallResult.restored;
  }
  
  /// Present Customer Center
  /// This shows the user's subscription management UI
  Future<void> presentCustomerCenter() async {
    try {
      
      await RevenueCatUI.presentCustomerCenter();
      
      // Refresh customer info after customer center dismissal
      await refreshCustomerInfo();
    } catch (e) {
      rethrow;
    }
  }
  
  /// Check if user has access to Pro features
  /// Can optionally refresh status from backend
  Future<bool> hasProAccess({bool refresh = false}) async {
    if (refresh) {
      await refreshProStatus();
    }
    return isPro.value;
  }
  
  /// Get subscription status text
  String getSubscriptionStatusText() {
    if (!isPro.value) {
      return 'Free Plan';
    }
    
    final entitlement = customerInfo.value?.entitlements.all[proEntitlementId];
    
    // If user has Pro but no RevenueCat entitlement, it's backend-granted
    if (entitlement == null || !entitlement.isActive) {
      return 'DecVault Pro (Granted)';
    }
    
    // User has active RevenueCat subscription
    if (entitlement.willRenew) {
      final expirationDate = entitlement.expirationDate;
      if (expirationDate != null) {
        return 'DecVault Pro - Renews ${_formatDate(expirationDate)}';
      }
      return 'DecVault Pro';
    } else {
      final expirationDate = entitlement.expirationDate;
      if (expirationDate != null) {
        return 'DecVault Pro - Expires ${_formatDate(expirationDate)}';
      }
      return 'DecVault Pro';
    }
  }
  
  /// Get product identifier for current subscription
  String? getCurrentProductId() {
    final entitlement = customerInfo.value?.entitlements.all[proEntitlementId];
    return entitlement?.productIdentifier;
  }
  
  /// Check if subscription will renew
  bool willRenew() {
    final entitlement = customerInfo.value?.entitlements.all[proEntitlementId];
    return entitlement?.willRenew ?? false;
  }
  
  /// Set user attributes (useful for analytics)
  Future<void> setUserAttributes(Map<String, String> attributes) async {
    try {
      await Purchases.setAttributes(attributes);
    } catch (e) {
    }
  }
  
  /// Set user email
  Future<void> setEmail(String email) async {
    try {
      await Purchases.setEmail(email);
    } catch (e) {
    }
  }
  
  /// Log in user with custom ID
  Future<void> loginUser(String userId) async {
    try {
      final logInResult = await Purchases.logIn(userId);
      await _updateCustomerInfo(logInResult.customerInfo);
      
      // Force refresh Pro status after login to check backend grants
      await refreshProStatus();
      
    } catch (e) {
      rethrow;
    }
  }
  
  /// Log out current user
  Future<void> logoutUser() async {
    try {
      final customerInfo = await Purchases.logOut();
      await _updateCustomerInfo(customerInfo);
    } catch (e) {
      rethrow;
    }
  }
  
  /// Format date for display
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = date.difference(now);
      
      if (difference.inDays > 30) {
        return '${date.month}/${date.day}/${date.year}';
      } else if (difference.inDays > 0) {
        return 'in ${difference.inDays} days';
      } else {
        return 'today';
      }
    } catch (e) {
      return dateString;
    }
  }
}


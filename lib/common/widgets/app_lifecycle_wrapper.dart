import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../features/auth/services/security_service.dart';
import '../../features/auth/screens/pin_unlock_screen.dart';

/// Wrapper widget that handles app lifecycle events for security
class AppLifecycleWrapper extends StatefulWidget {
  final Widget child;

  const AppLifecycleWrapper({
    super.key,
    required this.child,
  });

  @override
  State<AppLifecycleWrapper> createState() => _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends State<AppLifecycleWrapper> with WidgetsBindingObserver {
  DateTime? _pausedTime;
  bool _isInitialized = false;
  int _retryCount = 0;
  static const int _maxRetries = 10; // Limit retries to prevent infinite loop

  SecurityService? get _securityService {
    try {
      return Get.find<SecurityService>();
    } catch (e) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Delay initialization to ensure services are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSecurityCheck();
    });
  }

  void _initializeSecurityCheck() {
    if (!mounted || _retryCount >= _maxRetries) {
      if (_retryCount >= _maxRetries) {
        _isInitialized = true; // Mark as initialized to prevent further retries
      }
      return;
    }
    
    final service = _securityService;
    if (service != null) {
      _isInitialized = true;
      _checkInitialLockState();
    } else {
      _retryCount++;
      if (_retryCount <= 3) { // Only log first few attempts
      }
      // Retry after a progressively longer delay
      final delay = Duration(milliseconds: 500 + (_retryCount * 200));
      Future.delayed(delay, () {
        if (mounted && !_isInitialized) {
          _initializeSecurityCheck();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkInitialLockState() async {
    final service = _securityService;
    if (service == null) return;
    
    try {
      // Small delay to ensure app is fully initialized
      await Future.delayed(const Duration(milliseconds: 500));
      
      
      if (service.hasSecurityEnabled && service.isAppLocked) {
        _showPinUnlock();
      } else {
      }
    } catch (e) {
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.paused:
        _onAppPaused();
        break;
      case AppLifecycleState.inactive:
        // App is transitioning between states, don't lock here
        break;
      case AppLifecycleState.detached:
        // App is being terminated
        break;
      case AppLifecycleState.hidden:
        // App is hidden but still running
        break;
    }
  }

  Future<void> _onAppResumed() async {
    
    final service = _securityService;
    if (service == null) return;
    
    try {
      await service.onAppResumed();
      
      // Add small delay to prevent immediate locking after biometric auth
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Check if we need to show PIN unlock screen
      if (service.hasSecurityEnabled && service.isAppLocked) {
        _showPinUnlock();
      }
      
      // Update activity tracking
      await service.updateActivity();
    } catch (e) {
    }
  }

  Future<void> _onAppPaused() async {
    
    try {
      _pausedTime = DateTime.now();
      final service = _securityService;
      if (service != null) {
        await service.onAppPaused();
      }
    } catch (e) {
    }
  }

  void _showPinUnlock() {
    // Only show if not already showing and we're not in auth flow
    final currentRoute = Get.currentRoute;
    if (currentRoute != '/auth' && !Get.isDialogOpen! && !Get.isBottomSheetOpen!) {
      Get.dialog(
        const PinUnlockScreen(),
        barrierDismissible: false,
        barrierColor: Colors.black87,
      );
    } else {
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _securityService;
    
    // If SecurityService is not available or not initialized, just return the child
    if (service == null || !_isInitialized) {
      return widget.child;
    }
    
    // Use a simple state check instead of Obx to avoid dependency issues
    try {
      // Check if security is enabled and app is locked
      final isLocked = service.isAppLocked;
      final hasSecurityEnabled = service.hasSecurityEnabled;
      
                    // If security is enabled and app is locked, show dialog instead of overlay
              if (hasSecurityEnabled && isLocked) {
                // Show PIN unlock dialog immediately and return normal child
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!Get.isDialogOpen!) {
                    _showPinUnlock();
                  }
                });
                
                // Return the child with just back button protection, no overlay
                return PopScope(
                  canPop: false,
                  onPopInvoked: (didPop) {
                    if (didPop) return;
                    if (!Get.isDialogOpen!) {
                      _showPinUnlock();
                    }
                  },
                  child: widget.child,
                );
      }
      
      return widget.child;
    } catch (e) {
      return widget.child;
    }
  }
}

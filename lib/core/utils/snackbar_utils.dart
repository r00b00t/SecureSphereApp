import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Safely shows a snackbar using GetX, with fallback handling for missing overlay
class SnackbarUtils {
  /// Shows a snackbar with proper error handling for overlay availability
  static void showSnackbar({
    required String title,
    required String message,
    Color? backgroundColor,
    Color? colorText,
    Duration? duration,
    SnackPosition? snackPosition,
    Widget? icon,
    bool? isDismissible,
    DismissDirection? dismissDirection,
    Widget? mainButton,
  }) {
    // Check if overlay context is available and has an overlay widget
    if (Get.overlayContext == null) {
      // If no overlay context, log the error and return
      debugPrint('⚠️ Cannot show snackbar: No overlay context available');
      debugPrint('Title: $title, Message: $message');
      return;
    }

    try {
      // Additional check: verify the context has an actual Overlay widget
      final overlay = Overlay.maybeOf(Get.overlayContext!);
      if (overlay == null) {
        debugPrint('⚠️ Cannot show snackbar: Overlay widget not found in context');
        debugPrint('Title: $title, Message: $message');
        return;
      }

      Get.showSnackbar(
        GetSnackBar(
          titleText: Text(
            title,
            style: TextStyle(
              color: colorText ?? Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          messageText: Text(
            message,
            style: TextStyle(
              color: colorText ?? Colors.white,
              fontSize: 14,
            ),
          ),
          backgroundColor: backgroundColor ?? Colors.black87,
          duration: duration ?? const Duration(seconds: 3),
          snackPosition: snackPosition ?? SnackPosition.BOTTOM,
          icon: icon,
          isDismissible: isDismissible ?? true,
          dismissDirection: dismissDirection ?? DismissDirection.horizontal,
          margin: const EdgeInsets.all(8),
          borderRadius: 8,
          mainButton: mainButton,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Error showing snackbar: $e');
      debugPrint('Title: $title, Message: $message');
    }
  }

  /// Shows a success snackbar
  static void showSuccess({
    required String title,
    required String message,
    Duration? duration,
  }) {
    showSnackbar(
      title: title,
      message: message,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      duration: duration,
      icon: const Icon(Icons.check_circle, color: Colors.white),
    );
  }

  /// Shows an error snackbar
  static void showError({
    required String title,
    required String message,
    Duration? duration,
  }) {
    showSnackbar(
      title: title,
      message: message,
      backgroundColor: Colors.red,
      colorText: Colors.white,
      duration: duration,
      icon: const Icon(Icons.error, color: Colors.white),
    );
  }

  /// Shows a warning snackbar
  static void showWarning({
    required String title,
    required String message,
    Duration? duration,
  }) {
    showSnackbar(
      title: title,
      message: message,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
      duration: duration,
      icon: const Icon(Icons.warning, color: Colors.white),
    );
  }

  /// Shows an info snackbar
  static void showInfo({
    required String title,
    required String message,
    Duration? duration,
  }) {
    showSnackbar(
      title: title,
      message: message,
      backgroundColor: Colors.blue,
      colorText: Colors.white,
      duration: duration,
      icon: const Icon(Icons.info, color: Colors.white),
    );
  }

  /// Safely closes the current dialog without triggering snackbar close logic
  static void safeCloseDialog() {
    if (Get.isDialogOpen == true) {
      try {
        // Use Navigator directly to avoid triggering snackbar close
        if (Get.overlayContext != null) {
          Navigator.of(Get.overlayContext!, rootNavigator: true).pop();
        }
      } catch (e) {
        debugPrint('⚠️ Error closing dialog: $e');
      }
    }
  }
}


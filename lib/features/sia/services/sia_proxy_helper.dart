import 'package:get/get.dart';
import '../../auth/services/auth_service.dart';

/// Helper class for SIA backend proxy authentication
/// 
/// This helper provides authentication headers for all SIA proxy requests.
/// The backend proxy validates these headers to ensure only authenticated
/// users can access their SIA storage.
/// 
/// Security:
/// - User ID is verified on backend before proxying to SIA
/// - Each user has isolated bucket (user-vault-{userId})
/// - No SIA credentials stored in app binary
class SiaProxyHelper {
  /// Get authentication headers for SIA proxy requests
  /// 
  /// Returns a map with:
  /// - 'user-id': The authenticated user's ID
  /// - 'Content-Type': 'application/json'
  /// 
  /// Throws an exception if user is not authenticated
  static Future<Map<String, String>> getProxyHeaders() async {
    try {
      final authService = Get.find<AuthService>();
      final userId = await authService.getUserId();
      
      if (userId == null || userId.isEmpty) {
        throw Exception('User not authenticated. Please log in to access SIA storage.');
      }
      
      return {
        'user-id': userId,
        'Content-Type': 'application/json',
      };
    } catch (e) {
      if (e.toString().contains('not authenticated')) {
        rethrow;
      }
      throw Exception('Failed to get authentication headers: $e');
    }
  }
  
  /// Get authentication headers specifically for file upload
  /// 
  /// Same as getProxyHeaders() but with Content-Type set for binary uploads
  static Future<Map<String, String>> getProxyHeadersForUpload() async {
    final headers = await getProxyHeaders();
    headers['Content-Type'] = 'application/octet-stream';
    return headers;
  }
  
  /// Get authentication headers for download requests
  /// 
  /// Same as getProxyHeaders() but optimized for downloads
  static Future<Map<String, String>> getProxyHeadersForDownload() async {
    final headers = await getProxyHeaders();
    // Remove Content-Type for download requests
    headers.remove('Content-Type');
    return headers;
  }
  
  /// Validate that user is authenticated before making SIA requests
  /// 
  /// Returns true if user is authenticated, false otherwise
  /// Use this for pre-flight checks before expensive operations
  static Future<bool> isUserAuthenticated() async {
    try {
      final authService = Get.find<AuthService>();
      final userId = await authService.getUserId();
      return userId != null && userId.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}


import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../settings/services/settings_service.dart';
import '../../auth/services/auth_service.dart';
import 'encryption_service.dart';

class RenterdUploader {
  final SettingsService _settingsService;
  final EncryptionService _encryptionService;
  
  static const int _maxMemoryLoadSize = 200 * 1024 * 1024; // 200 MB
  static const Duration _timeout = Duration(seconds: 600); // 10 minutes
  
  // Store metadata from download response
  int? _lastDownloadOriginalSize;
  
  RenterdUploader(this._settingsService, this._encryptionService);

  /// Get bucket name based on user configuration
  /// - DecVault: user-specific bucket (user-vault-USERID) - S3 compliant naming
  /// - Self-hosted: shared 'vault' bucket
  Future<String> _getBucketName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupOption = prefs.getString('backupOption') ?? 'DecVault';
      
      
      if (backupOption == 'DecVault') {
        // Use user ID as bucket for DecVault (secure isolation)
        final authService = Get.find<AuthService>();
        final userId = await authService.getUserId();
        
        
        if (userId != null && userId.isNotEmpty) {
          final bucketName = 'user-vault-$userId'; // S3-compliant naming (hyphens, no underscores)
          return bucketName;
        } else {
          return 'vault';
        }
      } else {
        // Self-hosted: use shared vault bucket
        return 'vault';
      }
    } catch (e) {
      return 'vault'; // Fallback to default
    }
  }

  /// Checks if SIA operations are supported on current platform
  bool get isSupported => !kIsWeb;

  /// Uploads a file to SIA renterd v2 with automatic encryption
  /// Returns the unique filename used in SIA for future reference
  Future<String> uploadFile(
    File file,
    String filename,
    {Function(double progress)? onProgress}
  ) async {
    try {
      
      // Generate unique filename for SIA to prevent conflicts
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = filename.contains('.') ? filename.split('.').last : '';
      final baseName = filename.contains('.') 
          ? filename.substring(0, filename.lastIndexOf('.'))
          : filename;
      
      final uniqueFilename = extension.isNotEmpty 
          ? '${baseName}_$timestamp.$extension'
          : '${baseName}_$timestamp';
      
      
      if (!isSupported) {
        throw RenterdUploadException('SIA operations are not supported on web due to CORS restrictions. Please use the mobile or desktop app.');
      }
      
      await _validateFileForUpload(file, filename);
      
      final hasKeys = await _encryptionService.validateEncryptionKeys();
      if (!hasKeys) {
        throw RenterdUploadException('Encryption keys not available. User must be authenticated.');
      }
      
      final siaConfig = await _settingsService.getSiaConfig();
      if (siaConfig == null) {
        throw RenterdUploadException('SIA configuration not found. Please configure SIA settings first.');
      }
      
      
      await testConnection();
      
      // Get the bucket name and ensure it exists
      final bucketName = await _getBucketName();
      await _ensureBucketExists(siaConfig, bucketName);
      
      onProgress?.call(5.0);
      // Encrypt file before upload
      final encryptedFile = await _encryptFileForUpload(file, uniqueFilename);
      onProgress?.call(10.0);
      
      // Verify encryption worked
      final originalSize = await file.length();
      final encryptedSize = await encryptedFile.length();
      
      if (encryptedSize <= originalSize) {
        throw RenterdUploadException('Encryption verification failed: encrypted file should be larger than original');
      }
      
      
      // Embed original size in filename for instant decryption
      final sizeEmbeddedFilename = '${uniqueFilename}.orig${originalSize}';
      
      await _performSingleUpload(encryptedFile, sizeEmbeddedFilename, siaConfig, onProgress, isEncrypted: true, originalSize: originalSize);
      
      // Clean up temporary encrypted file
      await encryptedFile.delete();
      
      onProgress?.call(100.0);
      
      
      return sizeEmbeddedFilename;
      
    } catch (e) {
      throw RenterdUploadException('Upload failed: $e');
    }
  }

  /// Encrypts a file for upload with enhanced error handling
  Future<File> _encryptFileForUpload(File file, String filename) async {
    try {
    final bytes = await file.readAsBytes();
      
      if (bytes.isEmpty) {
        throw RenterdUploadException('Cannot encrypt empty file');
      }
    
    final encryptedFileData = await _encryptionService.encryptFileContent(bytes, filename);
    
    
    final tempDir = Directory.systemTemp;
    final encryptedFile = File('${tempDir.path}/encrypted_${DateTime.now().millisecondsSinceEpoch}_$filename');
    
    // Create a combined format: IV + encrypted bytes
    final combinedBytes = <int>[];
    combinedBytes.addAll(encryptedFileData.iv);
    combinedBytes.addAll(encryptedFileData.encryptedBytes);
    
    
    await encryptedFile.writeAsBytes(Uint8List.fromList(combinedBytes));
    
    final finalSize = await encryptedFile.length();
      
      // Verify the encrypted file was written correctly
      if (finalSize != combinedBytes.length) {
        throw RenterdUploadException('Encrypted file size mismatch: expected ${combinedBytes.length}, got $finalSize');
      }
    
    return encryptedFile;
    } catch (e) {
      throw RenterdUploadException('File encryption failed: $e');
    }
  }

  /// Performs a single file upload to SIA
  Future<void> _performSingleUpload(
    File file,
    String filename,
    dynamic siaConfig,
    Function(double progress)? onProgress,
    {bool isEncrypted = false, int? originalSize}
  ) async {
    try {
      final bytes = await file.readAsBytes();
      
      final client = http.Client();
      
      final headers = {
        'Content-Type': 'application/octet-stream',
        'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
      };
      
      // Store original size in filename for encrypted files (SIA-compatible approach)
      if (isEncrypted && originalSize != null) {
      }
      
      final cleanFilename = filename.startsWith('/') ? filename.substring(1) : filename;
      final bucketName = await _getBucketName();
      final uploadUrl = '${siaConfig.renterdUrl}/api/worker/object/$cleanFilename?bucket=$bucketName';
      
      final response = await client
          .put(
            Uri.parse(uploadUrl),
            headers: headers,
            body: bytes,
          )
          .timeout(_timeout);
      
      client.close();
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw RenterdUploadException(
          'Upload failed with status ${response.statusCode}: ${response.body}'
        );
      }
      
      final uploadProgress = isEncrypted ? 90.0 : 100.0;
      onProgress?.call(uploadProgress);
      
    } catch (e) {
      if (e is TimeoutException) {
        throw RenterdUploadException('Upload timeout: $e');
      }
      rethrow;
    }
  }

  /// Downloads and decrypts a file from SIA renterd v2
  Future<File> downloadFile(
    String filename,
    String localPath,
    {Function(double progress)? onProgress}
  ) async {
    // This method estimates the original size - use downloadFileWithSize for better accuracy
    return downloadFileWithSize(filename, localPath, 0, onProgress: onProgress);
  }

  /// Downloads and decrypts a file from SIA renterd v2 with known original file size
  Future<File> downloadFileWithSize(
    String filename,
    String localPath,
    int originalFileSize,
    {Function(double progress)? onProgress}
  ) async {
    try {
      
      if (!isSupported) {
        throw RenterdUploadException('SIA operations are not supported on web due to CORS restrictions. Please use the mobile or desktop app.');
      }
      
      final hasKeys = await _encryptionService.validateEncryptionKeys();
      if (!hasKeys) {
        throw RenterdUploadException('Encryption keys not available. User must be authenticated.');
      }
      
      final siaConfig = await _settingsService.getSiaConfig();
      if (siaConfig == null) {
        throw RenterdUploadException('SIA configuration not found. Please configure SIA settings first.');
      }
      
      onProgress?.call(5.0);
      final encryptedFile = await _downloadFromSia(filename, siaConfig, (progress) {
        // Map the internal download progress from 5% to 85%
        final mappedProgress = 5.0 + (progress * 0.8);
        onProgress?.call(mappedProgress);
      });
      
      onProgress?.call(90.0);
      onProgress?.call(95.0);
      // Decrypt the downloaded file
      final finalFile = await _decryptDownloadedFileWithSize(encryptedFile, localPath, originalFileSize, filename);
      onProgress?.call(100.0);
      
      // Clean up temporary encrypted file
      await encryptedFile.delete();
      
      return finalFile;
    } catch (e) {
      throw RenterdUploadException('Download failed: $e');
    }
  }

  /// Deletes a file from SIA renterd v2
  Future<void> deleteFile(String filename) async {
    try {
      if (!isSupported) {
        throw RenterdUploadException('SIA operations are not supported on web due to CORS restrictions. Please use the mobile or desktop app.');
      }
      
      final siaConfig = await _settingsService.getSiaConfig();
      if (siaConfig == null) {
        throw RenterdUploadException('SIA configuration not found. Please configure SIA settings first.');
      }
      
      final client = http.Client();
      
      try {
        final headers = {
          'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
        };
        
        final cleanFilename = filename.startsWith('/') ? filename.substring(1) : filename;
        final bucketName = await _getBucketName();
        final deleteUrl = '${siaConfig.renterdUrl}/api/worker/object/$cleanFilename?bucket=$bucketName';
        
        final response = await client
            .delete(
              Uri.parse(deleteUrl),
              headers: headers,
            )
            .timeout(_timeout);
        
        if (response.statusCode != 200 && response.statusCode != 204) {
          throw RenterdUploadException(
            'Delete failed with status ${response.statusCode}: ${response.body}'
          );
        }
        
      } finally {
        client.close();
      }
      
    } catch (e) {
      throw RenterdUploadException('Delete failed: $e');
    }
  }

  /// Downloads encrypted file from SIA
  Future<File> _downloadFromSia(
    String filename,
    dynamic siaConfig,
    Function(double progress)? onProgress,
  ) async {
    try {
      final client = http.Client();
      
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
      };
      
      final cleanFilename = filename.startsWith('/') ? filename.substring(1) : filename;
      final bucketName = await _getBucketName();
      final downloadUrl = '${siaConfig.renterdUrl}/api/worker/object/$cleanFilename?bucket=$bucketName';
      
      
      onProgress?.call(10.0); // Starting download
      
      final response = await client
          .get(
            Uri.parse(downloadUrl),
            headers: headers,
          )
          .timeout(_timeout);
      
      client.close();
      
      onProgress?.call(50.0); // Download response received
      
      
      // Extract original size from filename (embedded approach)
      final originalSizeFromFilename = _extractOriginalSizeFromFilename(filename);
      if (originalSizeFromFilename != null) {
        _lastDownloadOriginalSize = originalSizeFromFilename;
      } else {
        _lastDownloadOriginalSize = null;
      }
      
      if (response.statusCode != 200) {
        throw RenterdUploadException('Download failed with status ${response.statusCode}: ${response.body}');
      }
      
      onProgress?.call(70.0); // Processing downloaded data
      
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/encrypted_${DateTime.now().millisecondsSinceEpoch}_$cleanFilename');
      await tempFile.writeAsBytes(response.bodyBytes);
      
      onProgress?.call(85.0); // File written to disk
      
      
      return tempFile;
    } catch (e) {
      throw RenterdUploadException('Download from SIA failed: $e');
    }
  }

  /// Decrypts a downloaded file and saves it to the specified path
  Future<File> _decryptDownloadedFile(File encryptedFile, String localPath) async {
    try {
      final combinedBytes = await encryptedFile.readAsBytes();
      
      
      // Extract IV (first 16 bytes) and encrypted content (remaining bytes)
      if (combinedBytes.length < 16) {
        throw RenterdUploadException('Invalid encrypted file format: too short');
      }
      
      final iv = Uint8List.sublistView(combinedBytes, 0, 16);
      final encryptedBytes = Uint8List.sublistView(combinedBytes, 16);
      
      
      // Extract filename from localPath for decryption
      final filename = localPath.split('/').last;
      
      // We need the original size, but we don't have it stored in the file
      // For now, we'll estimate it based on the encrypted size
      final estimatedOriginalSize = encryptedBytes.length;
      
      final decryptedBytes = await _encryptionService.decryptFileContent(
        encryptedBytes,
        iv,
        filename,
        estimatedOriginalSize,
      );
      
      
      final localFile = File(localPath);
      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(decryptedBytes);
      
      return localFile;
    } catch (e) {
      throw RenterdUploadException('Decryption failed: $e');
    }
  }

  /// Decrypts a downloaded file with known original size and saves it to the specified path
  Future<File> _decryptDownloadedFileWithSize(File encryptedFile, String localPath, int originalFileSize, String siaFilename) async {
    try {
      final combinedBytes = await encryptedFile.readAsBytes();
      
      
      // Check if this looks like an encrypted file by examining the first 16 bytes (IV)
      // If the file is encrypted, the first 16 bytes should be a random IV
      bool looksEncrypted = false;
      if (combinedBytes.length >= 16) {
        final possibleIV = combinedBytes.sublist(0, 16);
        // Check if it's not all zeros and has some randomness
        final nonZeroBytes = possibleIV.where((b) => b != 0).length;
        looksEncrypted = nonZeroBytes > 8; // At least half the bytes are non-zero
      }
      
      if (!looksEncrypted) {
        
        // Handle unencrypted file - just copy it directly
        final localFile = File(localPath);
        await localFile.parent.create(recursive: true);
        await localFile.writeAsBytes(combinedBytes);
        
        return localFile;
      }
      
      
      // Validate encrypted file format
      if (combinedBytes.length < 16) {
        throw RenterdUploadException('Invalid encrypted file format: file too short (${combinedBytes.length} bytes)');
      }
      
      if (combinedBytes.length < 32) {
        throw RenterdUploadException('Invalid encrypted file format: minimum encrypted size not met');
      }
      
      // Extract IV (first 16 bytes) and encrypted content (remaining bytes)
      final iv = Uint8List.sublistView(combinedBytes, 0, 16);
      final encryptedBytes = Uint8List.sublistView(combinedBytes, 16);
      
      
      // Validate IV
      if (iv.every((byte) => byte == 0)) {
        throw RenterdUploadException('Invalid IV: all zeros detected');
      }
      
      // Use the original SIA filename for decryption (same as used during encryption)
      // The 'siaFilename' parameter contains the SIA filename with timestamp
      // Extract base filename for key generation (remove .origXXXXX suffix)
      final baseFilename = siaFilename.replaceAll(RegExp(r'\.orig\d+$'), '');
      
      // Smart size detection to minimize decryption attempts
      int primaryEstimate;
      if (originalFileSize > 0 && originalFileSize < combinedBytes.length) {
        // If stored size is smaller than downloaded size, it's likely correct
        primaryEstimate = originalFileSize;
      } else {
        // Calculate estimate from encrypted size
        final base64DecodedSize = encryptedBytes.length;
        primaryEstimate = (base64DecodedSize * 3) ~/ 4;
      }
      
      
      // Try decryption with the calculated size, and if that fails, try nearby sizes
      Uint8List? decryptedBytes;
      Exception? lastException;
      
      // PRIORITY 1: Use metadata original size if available (instant decryption!)
      final sizesToTry = <int>[];
      
      if (_lastDownloadOriginalSize != null) {
        sizesToTry.add(_lastDownloadOriginalSize!);
      } else {
        
        // FALLBACK: Mathematical calculation for files without metadata
        final encryptedDataSize = combinedBytes.length - 16; // Remove IV (16 bytes)
        final base64DecodedSize = (encryptedDataSize * 3) ~/ 4;
        
        // AES-256-CBC uses PKCS7 padding: 1-16 bytes padding possible
        for (int padding = 1; padding <= 16; padding++) {
          final possibleOriginalSize = base64DecodedSize - padding;
          if (possibleOriginalSize > 0) {
            sizesToTry.add(possibleOriginalSize);
          }
        }
        
        // Include the original estimate as fallback
        if (!sizesToTry.contains(primaryEstimate)) {
          sizesToTry.add(primaryEstimate);
        }
        
      }
      
      for (final trySize in sizesToTry) {
        try {
          decryptedBytes = await _encryptionService.decryptFileContent(
        encryptedBytes,
        iv,
            baseFilename,
            trySize,
          );
          break; // Success! Exit the loop
        } catch (e) {
          lastException = e is Exception ? e : Exception(e.toString());
          continue; // Try the next size
        }
      }
      
      if (decryptedBytes == null) {
        throw RenterdUploadException('Decryption failed with all attempted sizes. Last error: $lastException');
      }
      
      
      // Validate decrypted content
      if (decryptedBytes!.isEmpty) {
        throw RenterdUploadException('Decryption resulted in empty file');
      }
      
      // Create target directory if it doesn't exist
      final localFile = File(localPath);
      await localFile.parent.create(recursive: true);
      
      // Write decrypted file
      await localFile.writeAsBytes(decryptedBytes!);
      
      // Verify file was written correctly
      final writtenSize = await localFile.length();
      if (writtenSize != decryptedBytes!.length) {
        throw RenterdUploadException('File write verification failed: expected ${decryptedBytes!.length}, got $writtenSize');
      }
      
      
      return localFile;
    } catch (e) {
      throw RenterdUploadException('Decryption failed: $e');
    }
  }

  /// Tests connection to SIA renterd
  Future<bool> testConnection() async {
    try {
      if (!isSupported) return false;
      
      final siaConfig = await _settingsService.getSiaConfig();
      if (siaConfig == null) return false;
      
      final client = http.Client();
      
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
      };
      
      final response = await client
          .get(
            Uri.parse('${siaConfig.renterdUrl}/api/worker/state'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      
      client.close();
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData is Map<String, dynamic> &&
               responseData.containsKey('id') &&
               responseData.containsKey('version');
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Lists files in the SIA vault bucket
  Future<List<Map<String, dynamic>>> listVaultFiles() async {
    try {
      if (!isSupported) {
        throw RenterdUploadException('SIA operations are not supported on web');
      }
      
      final siaConfig = await _settingsService.getSiaConfig();
      if (siaConfig == null) {
        throw RenterdUploadException('SIA configuration not found');
      }
      
      final client = http.Client();
      
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
      };
      
      final bucketName = await _getBucketName();
      
      final response = await client
          .get(
            Uri.parse('${siaConfig.renterdUrl}/api/bus/objects/?bucket=$bucketName'),
            headers: headers,
          )
          .timeout(_timeout);
      
      client.close();
      
      if (response.statusCode != 200) {
        throw RenterdUploadException('Failed to list files: ${response.statusCode} - ${response.body}');
      }
      
      final responseData = jsonDecode(response.body);
      
      if (responseData is! Map<String, dynamic> || !responseData.containsKey('objects')) {
        throw RenterdUploadException('Invalid response format from SIA');
      }
      
      final objects = responseData['objects'] as List<dynamic>? ?? [];
      
      return objects.map((obj) => {
        'name': (obj['key'] as String? ?? '').startsWith('/')
            ? (obj['key'] as String).substring(1)
            : obj['key'] ?? '',
        'size': obj['size'] ?? 0,
        'modTime': obj['modTime'] ?? '',
      }).toList();
      
    } catch (e) {
      throw RenterdUploadException('List files failed: $e');
    }
  }

  Future<void> _validateFileForUpload(File file, String filename) async {
    try {
      if (!await file.exists()) {
        throw RenterdUploadException('File does not exist: ${file.path}');
      }
      
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw RenterdUploadException('Cannot upload empty file: $filename');
      }
      
      try {
        await file.readAsBytes();
      } catch (e) {
        throw RenterdUploadException('File is not readable: $filename');
      }
      
      if (filename.trim().isEmpty) {
        throw RenterdUploadException('Filename cannot be empty');
      }
      
      const invalidChars = ['<', '>', ':', '"', '|', '?', '*'];
      for (final char in invalidChars) {
        if (filename.contains(char)) {
          throw RenterdUploadException('Filename contains invalid character: $char');
        }
      }
      
    } catch (e) {
      rethrow;
    }
  }


  int? _extractOriginalSizeFromFilename(String filename) {
    final regex = RegExp(r'\.orig(\d+)$');
    final match = regex.firstMatch(filename);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  int _estimateEncryptedSize(int originalSize) {
    final paddedSize = ((originalSize + 15) ~/ 16) * 16;
    final base64Size = ((paddedSize * 4 + 2) ~/ 3);
    return base64Size + 16 + 64;
  }

  /// Ensures the bucket exists in SIA using the correct API
  Future<void> _ensureBucketExists(dynamic siaConfig, String bucketName) async {
    try {
      // Skip bucket creation for default vault bucket (already exists)
      if (bucketName == 'vault') {
        return;
      }
      
      final client = http.Client();
      
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
        'Content-Type': 'application/json',
      };
      
      
      // Use the correct API: POST /api/bus/buckets with name in JSON body
      final response = await client
          .post(
            Uri.parse('${siaConfig.renterdUrl}/api/bus/buckets'),
            headers: headers,
            body: jsonEncode({
              'name': bucketName,
            }),
          )
          .timeout(_timeout);
      
      client.close();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Small delay to ensure bucket propagation
        await Future.delayed(const Duration(milliseconds: 500));
      } else if (response.statusCode == 409) {
      } else {
        throw RenterdUploadException('Failed to create bucket "$bucketName": ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      throw RenterdUploadException('Failed to create bucket "$bucketName": $e');
    }
  }
}

class RenterdUploadException implements Exception {
  final String message;

  RenterdUploadException(this.message);

  @override
  String toString() => 'RenterdUploadException: $message';
} 

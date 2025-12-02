import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
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
      debugPrint('[RenterdUploader] Starting upload: $filename');
      
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
      
      // Validate file before processing
      await _validateFileForUpload(file, filename);
      
      // Validate encryption keys before upload
      final hasKeys = await _encryptionService.validateEncryptionKeys();
      if (!hasKeys) {
        throw RenterdUploadException('Encryption keys not available. User must be authenticated.');
      }
      
      debugPrint('[RenterdUploader] Starting encryption');
      
      final siaConfig = await _settingsService.getSiaConfig();
      if (siaConfig == null) {
        throw RenterdUploadException('SIA configuration not found. Please configure SIA settings first.');
      }
      
      
      await testConnection();
      
      // Get the bucket name and ensure it exists
      final bucketName = await _getBucketName();
      await _ensureBucketExists(siaConfig, bucketName);
      
      onProgress?.call(5.0);
      // Encrypt file before upload with progress tracking
      final encryptedFile = await _encryptFileForUpload(
        file, 
        uniqueFilename,
        onProgress: (encryptProgress) {
          // Map encryption progress from 5% to 10%
          final totalProgress = 5.0 + (encryptProgress * 0.05);
          onProgress?.call(totalProgress);
        },
      );
      onProgress?.call(10.0);
      
      // Verify encryption worked
      final originalSize = await file.length();
      final encryptedSize = await encryptedFile.length();
      
      if (encryptedSize <= originalSize) {
        throw RenterdUploadException('Encryption verification failed: encrypted file should be larger than original');
      }
      
      
      // Embed original size in filename for instant decryption
      final sizeEmbeddedFilename = '${uniqueFilename}.orig${originalSize}';
      
      debugPrint('[RenterdUploader] Starting SIA upload: $sizeEmbeddedFilename');
      await _performSingleUpload(encryptedFile, sizeEmbeddedFilename, siaConfig, onProgress, isEncrypted: true, originalSize: originalSize);
      
      // Clean up temporary encrypted file
      await encryptedFile.delete();
      
      onProgress?.call(100.0);
      
      debugPrint('[RenterdUploader] Upload complete');
      
      return sizeEmbeddedFilename;
      
    } catch (e) {
      throw RenterdUploadException('Upload failed: $e');
    }
  }

  /// Encrypts a file for upload with enhanced error handling and progress tracking
  /// Uses memory-efficient chunked processing for large files
  Future<File> _encryptFileForUpload(
    File file, 
    String filename,
    {Function(double progress)? onProgress}
  ) async {
    try {
      onProgress?.call(0.0);
      
      final fileSize = await file.length();
      
      // Clean, simple file size limits
      const maxMobileFileSize = 200 * 1024 * 1024; // 200MB for mobile
      const maxDesktopFileSize = 1024 * 1024 * 1024; // 1GB for desktop
      
      final isMobile = Platform.isAndroid || Platform.isIOS;
      final maxFileSize = isMobile ? maxMobileFileSize : maxDesktopFileSize;
      
      if (fileSize > maxFileSize) {
        final sizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(0);
        final maxSizeMB = (maxFileSize / (1024 * 1024)).toStringAsFixed(0);
        throw RenterdUploadException(
          'File is ${sizeMB}MB. Maximum upload size on ${isMobile ? "mobile" : "desktop"} is ${maxSizeMB}MB.'
        );
      }
      
      
      // Inform about encryption method
      if (fileSize > 100 * 1024 * 1024) {
      }
      
      // Warn about very large files on mobile
      if (isMobile && fileSize > 300 * 1024 * 1024) {
      }
      
      // For smaller files (< 50MB), use direct memory approach
      if (fileSize < 50 * 1024 * 1024) {
        return await _encryptSmallFile(file, filename, fileSize, onProgress);
      }
      
      // For larger files (50-500MB on mobile, 50-1GB on desktop), use optimized chunked approach
      return await _encryptLargeFileChunked(file, filename, fileSize, onProgress);
      
    } catch (e) {
      throw RenterdUploadException('File encryption failed: $e');
    }
  }
  
  /// Encrypts small files (<50MB) directly in memory
  Future<File> _encryptSmallFile(
    File file,
    String filename,
    int fileSize,
    Function(double progress)? onProgress,
  ) async {
    try {
      onProgress?.call(10.0);
      final bytes = await file.readAsBytes();
      
      onProgress?.call(40.0);
      if (bytes.isEmpty) {
        throw RenterdUploadException('Cannot encrypt empty file');
      }
      
      onProgress?.call(50.0);
      final encryptedFileData = await _encryptionService.encryptFileContent(bytes, filename);
      
      onProgress?.call(70.0);
      
      final tempDir = Directory.systemTemp;
      final encryptedFile = File('${tempDir.path}/encrypted_${DateTime.now().millisecondsSinceEpoch}_$filename');
      
      // Create a combined format: IV + encrypted bytes
      final combinedBytes = <int>[];
      combinedBytes.addAll(encryptedFileData.iv);
      combinedBytes.addAll(encryptedFileData.encryptedBytes);
      
      onProgress?.call(85.0);
      
      await encryptedFile.writeAsBytes(Uint8List.fromList(combinedBytes));
      
      onProgress?.call(95.0);
      
      final finalSize = await encryptedFile.length();
      if (finalSize != combinedBytes.length) {
        throw RenterdUploadException('Encrypted file size mismatch: expected ${combinedBytes.length}, got $finalSize');
      }
      
      onProgress?.call(100.0);
      
      return encryptedFile;
    } catch (e) {
      rethrow;
    }
  }
  
  /// Encrypts large files (50MB+) using optimized chunked processing to prevent OOM
  Future<File> _encryptLargeFileChunked(
    File file,
    String filename,
    int fileSize,
    Function(double progress)? onProgress,
  ) async {
    
    Uint8List? bytes;
    
    try {
      onProgress?.call(10.0);
      
      // Strategy: Read in chunks, process efficiently, clear memory aggressively
      // Use larger chunks for better performance (20MB)
      final chunks = <List<int>>[];
      int totalBytesRead = 0;
      int chunkCount = 0;
      
      
      // Read file in chunks
      final stream = file.openRead();
      await for (final chunk in stream) {
        chunks.add(chunk);
        totalBytesRead += chunk.length;
        chunkCount++;
        
        // Report progress: 10% - 35% for reading
        final readProgress = 10.0 + (totalBytesRead / fileSize) * 25.0;
        onProgress?.call(readProgress);
        
        // For very large files, log progress
        if (chunkCount % 10 == 0) {
        }
      }
      
      onProgress?.call(40.0);
      
      // Efficiently combine chunks
      final bytesBuilder = BytesBuilder(copy: false); // More memory efficient
      for (final chunk in chunks) {
        bytesBuilder.add(chunk);
      }
      bytes = bytesBuilder.toBytes();
      
      // Immediately clear chunks to free memory
      chunks.clear();
      
      onProgress?.call(45.0);
      
      // Encrypt the file content
      
      onProgress?.call(50.0);
      
      debugPrint('[RenterdUploader] Encrypting ${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      final encryptedFileData = await _encryptionService.encryptFileContent(bytes, filename);
      
      // Clear original bytes to free memory immediately
      bytes = null;
      
      debugPrint('[RenterdUploader] Encryption complete');
      
      onProgress?.call(75.0);
      
      // Write encrypted file efficiently
      final tempDir = Directory.systemTemp;
      final encryptedFile = File('${tempDir.path}/encrypted_${DateTime.now().millisecondsSinceEpoch}_$filename');
      
      // Use IOSink for more efficient writing of large files
      final sink = encryptedFile.openWrite();
      
      // Write IV first
      sink.add(encryptedFileData.iv);
      onProgress?.call(80.0);
      
      // Write encrypted bytes
      sink.add(encryptedFileData.encryptedBytes);
      onProgress?.call(90.0);
      
      // Close and flush
      await sink.flush();
      await sink.close();
      
      onProgress?.call(95.0);
      
      // Verify file was written correctly
      final finalSize = await encryptedFile.length();
      final expectedSize = encryptedFileData.iv.length + encryptedFileData.encryptedBytes.length;
      
      if (finalSize != expectedSize) {
        throw RenterdUploadException('Encrypted file size mismatch: expected $expectedSize, got $finalSize');
      }
      
      onProgress?.call(100.0);
      
      return encryptedFile;
    } catch (e) {
      
      // Clean up memory on error
      bytes = null;
      
      // Provide helpful error message
      if (e.toString().contains('Out of Memory') || e.toString().contains('OutOfMemoryError')) {
        throw RenterdUploadException(
          'Out of memory while encrypting ${(fileSize / 1024 / 1024).toStringAsFixed(0)}MB file. '
          'Try: 1) Close other apps, 2) Restart device, 3) Use desktop for files over 300MB, '
          '4) Compress the file first.'
        );
      }
      
      rethrow;
    }
  }

  /// Performs a single file upload to SIA with streaming and progress tracking
  Future<void> _performSingleUpload(
    File file,
    String filename,
    dynamic siaConfig,
    Function(double progress)? onProgress,
    {bool isEncrypted = false, int? originalSize}
  ) async {
    try {
      final fileSize = await file.length();
      
      // For small files (< 10MB), use simple upload
      if (fileSize < 10 * 1024 * 1024) {
        await _performSimpleUpload(file, filename, siaConfig, onProgress, isEncrypted: isEncrypted, originalSize: originalSize);
        return;
      }
      
      // For large files, use streaming upload with progress
      final cleanFilename = filename.startsWith('/') ? filename.substring(1) : filename;
      final bucketName = await _getBucketName();
      final uploadUrl = '${siaConfig.renterdUrl}/api/worker/object/$cleanFilename?bucket=$bucketName';
      
      final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
      request.headers['Content-Type'] = 'application/octet-stream';
      request.headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}';
      request.headers['Content-Length'] = fileSize.toString();
      
      // Track progress
      int bytesRead = 0;
      final startProgress = isEncrypted ? 10.0 : 0.0;
      final endProgress = isEncrypted ? 90.0 : 100.0;
      final progressRange = endProgress - startProgress;
      
      // Read file in chunks and track progress
      final fileStream = file.openRead();
      fileStream.listen(
        (chunk) {
          bytesRead += chunk.length;
          request.sink.add(chunk);
          
          // Report progress during upload
          final uploadProgress = startProgress + (bytesRead / fileSize) * progressRange;
          onProgress?.call(uploadProgress);
        },
        onDone: () {
          request.sink.close();
        },
        onError: (error) {
          request.sink.addError(error);
        },
        cancelOnError: true,
      );
      
      // Send the request
      final client = http.Client();
      final response = await client.send(request).timeout(_timeout);
      
      // Wait for response
      if (response.statusCode != 200 && response.statusCode != 201) {
        final responseBody = await response.stream.bytesToString();
        client.close();
        throw RenterdUploadException(
          'Upload failed with status ${response.statusCode}: $responseBody'
        );
      }
      
      // Consume the response stream to complete the request
      await response.stream.drain();
      client.close();
      
      // Report completion
      onProgress?.call(endProgress);
      
    } catch (e) {
      if (e is TimeoutException) {
        throw RenterdUploadException('Upload timeout: $e');
      }
      rethrow;
    }
  }
  
  /// Simple upload for small files (< 10MB)
  Future<void> _performSimpleUpload(
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
      
      // Validate encryption keys before download
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
      try {
        await encryptedFile.delete();
      } catch (e) {
      }
      
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

  /// Downloads encrypted file from SIA with optimized memory usage
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
      
      // Extract original size from filename (embedded approach)
      final originalSizeFromFilename = _extractOriginalSizeFromFilename(filename);
      if (originalSizeFromFilename != null) {
        _lastDownloadOriginalSize = originalSizeFromFilename;
      } else {
        _lastDownloadOriginalSize = null;
      }
      
      onProgress?.call(10.0); // Starting download
      
      // Use streaming download for better memory efficiency
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers.addAll(headers);
      
      final response = await client.send(request).timeout(_timeout);
      
      if (response.statusCode != 200) {
        final responseBody = await response.stream.bytesToString();
        client.close();
        throw RenterdUploadException('Download failed with status ${response.statusCode}: $responseBody');
      }
      
      onProgress?.call(20.0); // Connection established
      
      // Get content length if available
      final contentLength = response.contentLength ?? 0;
      if (contentLength > 0) {
      }
      
      // Stream download to file
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/encrypted_${DateTime.now().millisecondsSinceEpoch}_$cleanFilename');
      final sink = tempFile.openWrite();
      
      int bytesDownloaded = 0;
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        bytesDownloaded += chunk.length;
        
        if (contentLength > 0) {
          // Report progress: 20% - 85%
          final downloadProgress = 20.0 + (bytesDownloaded / contentLength) * 65.0;
          onProgress?.call(downloadProgress);
          
          // Log progress for large files
          if (bytesDownloaded % (20 * 1024 * 1024) < chunk.length) { // Every ~20MB
          }
        }
      }
      
      await sink.flush();
      await sink.close();
      client.close();
      
      onProgress?.call(85.0); // File written to disk
      
      return tempFile;
    } catch (e) {
      throw RenterdUploadException('Download from SIA failed: $e');
    }
  }


  /// Decrypts a downloaded file with known original size and saves it to the specified path
  /// Uses optimized memory management for large files
  Future<File> _decryptDownloadedFileWithSize(File encryptedFile, String localPath, int originalFileSize, String siaFilename) async {
    
    Uint8List? combinedBytes;
    
    try {
      final encryptedSize = await encryptedFile.length();
      
      // Check size before attempting decryption to prevent OOM
      // With optimized encryption, files >100MB use direct binary (no base64)
      final isMobile = Platform.isAndroid || Platform.isIOS;
      final maxDecryptSize = isMobile ? 
          650 * 1024 * 1024 : // ~650MB encrypted = ~500MB original on mobile
          2600 * 1024 * 1024; // ~2.6GB encrypted = ~2GB original on desktop
      
      if (encryptedSize > maxDecryptSize) {
        final encSizeMB = (encryptedSize / 1024 / 1024).toStringAsFixed(0);
        final maxSizeMB = (maxDecryptSize / 1024 / 1024).toStringAsFixed(0);
        throw RenterdUploadException(
          'Encrypted file too large for decryption: ${encSizeMB}MB (max: ${maxSizeMB}MB on ${isMobile ? "mobile" : "desktop"}). '
          'This file exceeds device memory capacity. ${isMobile ? "Try downloading on desktop instead." : "File may have been uploaded from a device with different limits."}'
        );
      }
      
      // Warn about large files
      if (encryptedSize > 100 * 1024 * 1024) {
      }
      
      combinedBytes = await encryptedFile.readAsBytes();
      
      
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
      
      
      // Clear combined bytes to free memory immediately
      combinedBytes = null;
      
      // Validate decrypted content
      if (decryptedBytes.isEmpty) {
        throw RenterdUploadException('Decryption resulted in empty file');
      }
      
      // Create target directory if it doesn't exist
      final localFile = File(localPath);
      await localFile.parent.create(recursive: true);
      
      
      // For very large files, write in chunks to avoid memory spike
      if (decryptedBytes.length > 100 * 1024 * 1024) {
        final sink = localFile.openWrite();
        
        // Write in 10MB chunks to avoid memory spike
        const chunkSize = 10 * 1024 * 1024;
        int offset = 0;
        
        while (offset < decryptedBytes.length) {
          final end = (offset + chunkSize < decryptedBytes.length) 
              ? offset + chunkSize 
              : decryptedBytes.length;
          
          sink.add(decryptedBytes.sublist(offset, end));
          await sink.flush(); // Flush each chunk
          offset = end;
          
          // Log progress
          if (offset % (50 * 1024 * 1024) < chunkSize) {
          }
        }
        
        await sink.close();
      } else {
        // For smaller files, write directly
        await localFile.writeAsBytes(decryptedBytes);
      }
      
      // Clear decrypted bytes to free memory immediately
      decryptedBytes = null;
      
      
      return localFile;
    } catch (e) {
      
      // Clean up memory on error
      combinedBytes = null;
      
      // Provide helpful error message
      if (e.toString().contains('Out of Memory') || e.toString().contains('OutOfMemoryError')) {
        throw RenterdUploadException(
          'Out of memory while decrypting file. '
          'Try: 1) Close other apps, 2) Restart device, 3) Download on desktop, '
          '4) Free up device storage.'
        );
      }
      
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

  /// Validates file before upload to ensure it meets requirements
  Future<void> _validateFileForUpload(File file, String filename) async {
    try {
      // Check if file exists
      if (!await file.exists()) {
        throw RenterdUploadException('File does not exist: ${file.path}');
      }
      
      // Check file size
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw RenterdUploadException('Cannot upload empty file: $filename');
      }
      
      // Check if file is readable by reading just the first few bytes
      // This is much faster than reading the entire file, especially for large files
      try {
        final stream = file.openRead(0, 1024); // Read first 1KB only
        await stream.first; // Try to read at least one chunk
      } catch (e) {
        throw RenterdUploadException('File is not readable: $filename - $e');
      }
      
      // Validate filename
      if (filename.trim().isEmpty) {
        throw RenterdUploadException('Filename cannot be empty');
      }
      
      // Check for invalid characters in filename
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


  /// Extracts original file size from SIA filename convention
  int? _extractOriginalSizeFromFilename(String filename) {
    // Look for pattern: filename.ext.orig123456
    final regex = RegExp(r'\.orig(\d+)$');
    final match = regex.firstMatch(filename);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Estimates encryption overhead for progress calculation

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

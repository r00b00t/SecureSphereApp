import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/features/password/repositories/password_repository.dart';
import 'package:decvault/features/password/models/password_model.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/vault/services/renterd_uploader.dart';
import 'package:decvault/features/settings/services/settings_service.dart';
import 'package:decvault/features/vault/services/encryption_service.dart';

class BackupService extends GetxService {
  Box? _backupBox;
  PasswordRepository? _passwordRepository;
  RenterdUploader? _renterdUploader;
  SettingsService? _settingsService;
  EncryptionService? _encryptionService;
  bool _isInitialized = false;
  Map<String, dynamic>? _lastDownloadedBackup;
  
  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    
    try {
      _backupBox = await Hive.openBox('backups');
      
      _passwordRepository = Get.find<PasswordRepository>();
      
      _settingsService = Get.find<SettingsService>();
      
      _encryptionService = Get.find<EncryptionService>();
      
      _renterdUploader = RenterdUploader(_settingsService!, _encryptionService!);
      
      // Validate that all components are properly initialized
      if (_renterdUploader == null) {
        throw Exception('RenterdUploader is null after creation');
      }
      if (_settingsService == null) {
        throw Exception('SettingsService is null after initialization');
      }
      if (_passwordRepository == null) {
        throw Exception('PasswordRepository is null after initialization');
      }
      if (_backupBox == null) {
        throw Exception('BackupBox is null after initialization');
      }
      if (_encryptionService == null) {
        throw Exception('EncryptionService is null after initialization');
      }
      
      _isInitialized = true;
    } catch (e) {
      rethrow;
    }
  }

  /// Get backup bucket name based on user configuration
  /// - SecureSphere: user-specific backup bucket (user-backup-USERID)
  /// - Self-hosted: user-specific backup bucket (user-backup-USERID)
  Future<String> _getBackupBucketName() async {
    final prefs = await SharedPreferences.getInstance();
    final backupOption = prefs.getString('backupOption') ?? 'SecureSphere';
    final authService = Get.find<AuthService>();
    final userId = await authService.getUserId();
    if (userId == null || userId.isEmpty) {
      throw Exception('Cannot determine backup bucket: user ID is not available');
    }
    if (backupOption == 'SecureSphere') {
      // Use user ID as backup bucket for SecureSphere (secure isolation)
      final bucketName = 'user-backup-$userId'; // S3-compliant naming
      return bucketName;
    } else {
      // Self-hosted: use user-specific backup bucket (secure isolation)
      final bucketName = 'user-backup-$userId'; // S3-compliant naming
      return bucketName;
    }
  }
  
  Future<void> triggerBackup({String? customName, Function()? onBackupComplete}) async {
    try {
      if (!_isInitialized) {
        await init();
      }
      if (_passwordRepository == null) {
        throw Exception('PasswordRepository is not initialized');
      }

      // Guard: refuse to attempt backup if no node host is configured.
      final siaConfig = await _settingsService?.getSiaConfig();
      if (siaConfig != null && siaConfig.ip.isEmpty) {
        throw Exception(
            'Sia node not configured. Please set up your node in Settings.');
      }

      // Get passwords from repository
      List<PasswordModel> passwords = [];
      try {
        passwords = await _passwordRepository!.getAllPasswords();
  
      } catch (e) {
      }
      final passwordMaps = passwords.map((p) => p.toMap()).toList();
      final backupData = {
        'timestamp': DateTime.now().toIso8601String(),
        'appVersion': '1.0.0',
        'passwords': passwordMaps,
        'userId': await AuthService().getUserId(),
      };
      await _saveLocalBackup(backupData, customName: customName);
      
      // Always upload to SIA node (both SecureSphere and Self-hosted use SIA now)
      await _uploadToSiaNode(backupData, customName: customName);
      
      
      // Call the refresh callback if provided
      if (onBackupComplete != null) {
        onBackupComplete();
      }
      
    } catch (e) {
      rethrow;
    }
  }
  
  /// Upload backup to SIA node using bucket-based approach (same as vault)
  Future<void> _uploadToSiaNode(Map<String, dynamic> jsonData, {String? customName}) async {
    File? tempFile;
    try {
      if (kIsWeb) {
        throw Exception('SIA backup upload not supported on web platform');
      }
      
      if (_renterdUploader == null) {
        
        // Force re-initialization by resetting the flag
        _isInitialized = false;
        
        try {
          await init(); // Try to initialize again
          
          if (_renterdUploader == null) {
            // Try manual initialization as last resort
            try {
              final settingsService = Get.find<SettingsService>();
              final encryptionService = Get.find<EncryptionService>();
              _renterdUploader = RenterdUploader(settingsService, encryptionService);
            } catch (manualError) {
              throw Exception('RenterdUploader not initialized after all attempts. Last error: $manualError');
            }
          } else {
          }
        } catch (initError) {
          throw Exception('RenterdUploader re-initialization failed: $initError');
        }
      }
      
      
      // Step 1: Ensure all services are available
      if (!_isInitialized) {
        await init();
      }
      
      // Step 2: Double-check EncryptionService availability
      if (_encryptionService == null) {
        try {
          _encryptionService = Get.find<EncryptionService>();
        } catch (e) {
          throw Exception('EncryptionService not available. Ensure user is authenticated and service is initialized.');
        }
      }
      
      // Step 3: Validate user authentication for encryption
      final canEncrypt = await _encryptionService!.validateEncryptionKeys();
      if (!canEncrypt) {
        throw Exception('User authentication required for backup encryption. Please login again.');
      }
      
      // Step 4: Encrypt the backup data
      final encryptedBackup = await _encryptionService!.encryptBackupData(jsonData);
      
      // Step 5: Create encrypted backup file structure
      // Format: [IV][metadata_length:4bytes][metadata][encrypted_data]
      final metadataJson = jsonEncode(encryptedBackup.metadata);
      final metadataBytes = utf8.encode(metadataJson);
      final metadataLength = metadataBytes.length;
      
      final lengthBytes = ByteData(4)..setUint32(0, metadataLength, Endian.big);
      
      final encryptedFileBytes = Uint8List.fromList([
        ...encryptedBackup.iv,
        ...lengthBytes.buffer.asUint8List(),
        ...metadataBytes,
        ...encryptedBackup.encryptedBytes,
      ]);
      
      // Step 6: Create temp file with encrypted backup data
      final fileName = customName ?? 'backup_${DateTime.now().millisecondsSinceEpoch}.encrypted';
      final tempPath = '${Directory.systemTemp.path}/$fileName';
      tempFile = File(tempPath);
      
      // Step 7: Write encrypted data to temp file  
      await tempFile.writeAsBytes(encryptedFileBytes);
      
      // Step 8: Get backup bucket name
      final bucketName = await _getBackupBucketName();
      
      // Step 9: Create backup bucket if needed
      final siaConfig = await _settingsService!.getSiaConfig();
      if (siaConfig == null) {
        throw Exception('SIA configuration not found. Please configure SIA settings first.');
      }
      
      await _ensureBackupBucketExists(siaConfig, bucketName);
      
      // Step 10: Upload using RenterdUploader with backup bucket
      await _uploadBackupToSpecificBucket(tempFile, fileName, siaConfig, bucketName);
      
      
    } catch (e) {
      rethrow;
    } finally {
      // Clean up temp file
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Ensures the backup bucket exists in SIA using the correct API
  Future<void> _ensureBackupBucketExists(dynamic siaConfig, String bucketName) async {
    try {
      // Skip bucket creation for default vault/securesphere-backup bucket if they exist
      if (bucketName == 'vault' || bucketName == 'securesphere-backup') {
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
          .timeout(const Duration(seconds: 600));
      
      client.close();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Small delay to ensure bucket propagation
        await Future.delayed(const Duration(milliseconds: 500));
      } else if (response.statusCode == 409) {
      } else {
        throw Exception('Failed to create backup bucket "$bucketName": ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      throw Exception('Failed to create backup bucket "$bucketName": $e');
    }
  }

  /// Upload backup file to specific SIA bucket
  Future<void> _uploadBackupToSpecificBucket(File file, String filename, dynamic siaConfig, String bucketName) async {
    try {
      final bytes = await file.readAsBytes();
      
      final client = http.Client();
      
      final headers = {
        'Content-Type': 'application/octet-stream',
        'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
      };
      
      final cleanFilename = filename.startsWith('/') ? filename.substring(1) : filename;
      final uploadUrl = '${siaConfig.renterdUrl}/api/worker/object/$cleanFilename?bucket=$bucketName';
      
      
      final response = await client
          .put(
            Uri.parse(uploadUrl),
            headers: headers,
            body: bytes,
          )
          .timeout(const Duration(seconds: 600));
      
      client.close();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
      } else {
        throw Exception('Upload failed with status ${response.statusCode}: ${response.body}');
      }
      
    } catch (e) {
      throw Exception('Failed to upload backup to SIA: $e');
    }
  }

  Future<void> _saveLocalBackup(Map<String, dynamic> jsonData, {String? customName}) async {
    try {
      if (_backupBox == null) {
        throw Exception('BackupBox is not initialized');
      }
      
      final fileName = customName ?? 'backup_${DateTime.now().millisecondsSinceEpoch}.json';
      await _backupBox!.put(fileName, jsonEncode(jsonData));
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getBackups() async {
    try {
      // Ensure service is initialized
      if (!_isInitialized) {
        await init();
      }
      
      
      // Both SecureSphere and Self-hosted now use SIA bucket approach
      return await _getBackupsFromSiaBucket();
      
    } catch (e) {
      rethrow;
    }
  }

  /// Get backups from SIA bucket using the new bucket-based approach
  Future<List<Map<String, dynamic>>> _getBackupsFromSiaBucket() async {
    try {
      if (_renterdUploader == null) {
        await init();
        if (_renterdUploader == null) {
          throw Exception('RenterdUploader not initialized');
        }
      }
      
      // Get backup bucket name
      final bucketName = await _getBackupBucketName();
      
      // Get SIA configuration
      final siaConfig = await _settingsService!.getSiaConfig();
      if (siaConfig == null) {
        throw Exception('SIA configuration not found. Please configure SIA settings first.');
      }
      
      // List backup files from SIA bucket
      final backupFiles = await _listBackupFilesFromBucket(siaConfig, bucketName);
      
      return backupFiles;
      
    } catch (e) {
      rethrow;
    }
  }

  /// List backup files from specific SIA bucket
  Future<List<Map<String, dynamic>>> _listBackupFilesFromBucket(dynamic siaConfig, String bucketName) async {
    try {
      
      final client = http.Client();
      
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
      };
      
      final response = await client
          .get(
            Uri.parse('${siaConfig.renterdUrl}/api/bus/objects/?bucket=$bucketName'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 600));
      
      client.close();
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        if (responseData is! Map<String, dynamic> || !responseData.containsKey('objects')) {
          return [];
        }
        
        final objects = responseData['objects'] as List<dynamic>? ?? [];
        
        // Filter for backup files (.json and .encrypted files)
        final backupFiles = objects.where((obj) {
          final key = obj['key'] as String? ?? '';
          final cleanKey = key.startsWith('/') ? key.substring(1) : key;
          return cleanKey.endsWith('.json') || cleanKey.endsWith('.encrypted');
        }).map((obj) {
          final key = obj['key'] as String? ?? '';
          final cleanKey = key.startsWith('/') ? key.substring(1) : key;
          final size = obj['size'] ?? 0;
          final modTime = obj['modTime'] as String? ?? '';
          
          // Parse date
          DateTime? parsedDate;
          try {
            parsedDate = DateTime.parse(modTime);
          } catch (e) {
            parsedDate = DateTime.now();
          }
          
          // Determine if this is an encrypted backup
          final isEncrypted = cleanKey.endsWith('.encrypted');
          
          // Create display name (remove .encrypted extension for cleaner display)
          final displayName = isEncrypted ? 
            cleanKey.replaceAll('.encrypted', '.json') : cleanKey;
          
          return {
            'name': displayName,
            'originalName': cleanKey, // Keep original name for download operations
            'date': parsedDate.toString(),
            'path': cleanKey,
            'size': size,
            'bucket': bucketName,
            'isEncrypted': isEncrypted,
          };
        }).toList();
        
        // Sort by date (newest first)
        backupFiles.sort((a, b) {
          final dateA = DateTime.tryParse(a['date'] ?? '') ?? DateTime.now();
          final dateB = DateTime.tryParse(b['date'] ?? '') ?? DateTime.now();
          return dateB.compareTo(dateA);
        });
        
        return backupFiles;
        
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception('Failed to list backup files: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      throw Exception('Failed to list backup files from SIA: $e');
    }
  }

  Future<Map<String, dynamic>> restoreBackup(String backupKey) async {
    try {
      // Ensure service is initialized
      if (!_isInitialized) {
        await init();
      }
      
      
      // First get the list of backups to find the actual filename
      final backups = await getBackups();
      String actualFilename = backupKey;
      
      // Find the backup entry and get the original filename
      for (final backup in backups) {
        if (backup['name'] == backupKey || backup['path'] == backupKey) {
          actualFilename = backup['originalName'] ?? backup['path'] ?? backupKey;
          break;
        }
      }
      
      // Both SecureSphere and Self-hosted now use SIA with different buckets
      await _downloadBackupFromSia(actualFilename);
      
      final backupData = _lastDownloadedBackup;
      if (backupData == null) {
        throw Exception('[SIA] Backup data is null');
      }
      if (backupData is! Map) {
        throw Exception('[SIA] Backup data is not a Map');
      }
      if (_passwordRepository == null) {
        throw Exception('PasswordRepository is not initialized');
      }
      if (backupData.containsKey('passwords')) {
        await _passwordRepository!.restorePasswords(backupData['passwords']);
      }
      return Map<String, dynamic>.from(backupData);
    } catch (e) {
      rethrow;
    }
  }

  /// Download backup from SIA using bucket-based approach
  Future<void> _downloadBackupFromSia(String filename) async {
    try {
      if (_renterdUploader == null) {
        
        // Force re-initialization by resetting the flag
        _isInitialized = false;
        
        try {
          await init(); // Try to initialize again
          
          if (_renterdUploader == null) {
            // Try manual initialization as last resort
            try {
              final settingsService = Get.find<SettingsService>();
              final encryptionService = Get.find<EncryptionService>();
              _renterdUploader = RenterdUploader(settingsService, encryptionService);
            } catch (manualError) {
              throw Exception('RenterdUploader not initialized after all attempts. Last error: $manualError');
            }
          } else {
          }
        } catch (initError) {
          throw Exception('RenterdUploader re-initialization failed: $initError');
        }
      }
      
      
      // Get backup bucket name
      final bucketName = await _getBackupBucketName();
      
      // Get SIA configuration
      final siaConfig = await _settingsService!.getSiaConfig();
      if (siaConfig == null) {
        throw Exception('SIA configuration not found. Please configure SIA settings first.');
      }
      
      // Download backup file from SIA bucket
      final backupData = await _downloadBackupFromSpecificBucket(filename, siaConfig, bucketName);
      
      _lastDownloadedBackup = backupData;
      
      
    } catch (e) {
      rethrow;
    }
  }

  /// Download backup file from specific SIA bucket and decrypt it
  Future<Map<String, dynamic>> _downloadBackupFromSpecificBucket(String filename, dynamic siaConfig, String bucketName) async {
    try {
      
      final client = http.Client();
      
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode(':${siaConfig.apiPassword}'))}',
      };
      
      final cleanFilename = filename.startsWith('/') ? filename.substring(1) : filename;
      final downloadUrl = '${siaConfig.renterdUrl}/api/worker/object/$cleanFilename?bucket=$bucketName';
      
      
      final response = await client
          .get(
            Uri.parse(downloadUrl),
            headers: headers,
          )
          .timeout(const Duration(seconds: 600));
      
      client.close();
      
      if (response.statusCode == 200) {
        
        final responseBytes = response.bodyBytes;
        
        // Try to decrypt if it looks like an encrypted backup
        if (_isEncryptedBackup(responseBytes)) {
          return await _decryptBackupData(responseBytes);
        } else {
          // Legacy plain backup - try to parse as JSON
          try {
            final backupData = jsonDecode(response.body);
            return Map<String, dynamic>.from(backupData);
          } catch (e) {
            throw Exception('Failed to parse legacy backup: $e');
          }
        }
      } else {
        throw Exception('Download failed with status ${response.statusCode}: ${response.body}');
      }
      
    } catch (e) {
      throw Exception('Failed to download backup from SIA: $e');
    }
  }

  /// Checks if downloaded data is an encrypted backup
  bool _isEncryptedBackup(Uint8List data) {
    // Encrypted backups have: [IV:16bytes][metadata_length:4bytes][metadata][encrypted_data]
    return data.length >= 20; // 16 bytes for IV + 4 bytes for metadata length
  }

  /// Decrypts downloaded backup data
  Future<Map<String, dynamic>> _decryptBackupData(Uint8List encryptedData) async {
    try {
      // Ensure EncryptionService is available
      if (_encryptionService == null) {
        try {
          _encryptionService = Get.find<EncryptionService>();
        } catch (e) {
          throw Exception('EncryptionService not available for decryption. Ensure user is authenticated.');
        }
      }
      
      
      // Parse encrypted backup structure: [IV:16bytes][metadata_length:4bytes][metadata][encrypted_data]
      if (encryptedData.length < 20) {
        throw Exception('Invalid encrypted backup format: too short');
      }
      
      // Extract IV (first 16 bytes)
      final iv = Uint8List.sublistView(encryptedData, 0, 16);
      
      // Extract metadata length (next 4 bytes)
      final metadataLength = ByteData.view(encryptedData.buffer, 16, 4).getUint32(0, Endian.big);
      
      
      // Calculate positions
      final metadataStart = 20; // 16 + 4
      final metadataEnd = metadataStart + metadataLength;
      final encryptedDataStart = metadataEnd;
      
      if (encryptedData.length < encryptedDataStart) {
        throw Exception('Invalid encrypted backup format: insufficient data');
      }
      
      // Extract metadata
      final metadataBytes = encryptedData.sublist(metadataStart, metadataEnd);
      final metadataJson = utf8.decode(metadataBytes);
      final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
      
      
      // Extract encrypted backup data
      final encryptedBackupBytes = encryptedData.sublist(encryptedDataStart);
      
      
      // Get original size from metadata
      final originalSize = metadata['originalSize'] as int? ?? 0;
      
      // Decrypt the backup data
      final decryptedData = await _encryptionService!.decryptBackupData(
        encryptedBackupBytes,
        iv,
        originalSize,
      );
      
      return decryptedData;
    } catch (e) {
      throw Exception('Failed to decrypt backup: $e');
    }
  }

  Future<void> deleteBackup(String backupKey) async {
    try {
      // Ensure service is initialized
      if (!_isInitialized) {
        await init();
      }
      if (_backupBox == null) {
        throw Exception('BackupBox is not initialized');
      }
      if (await _backupBox!.containsKey(backupKey)) {
        await _backupBox!.delete(backupKey);
      } else {
        throw Exception('Backup not found');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Debug method to check service initialization status
  Map<String, dynamic> getServiceStatus() {
    return {
      'isInitialized': _isInitialized,
      'hasBackupBox': _backupBox != null,
      'hasPasswordRepository': _passwordRepository != null,
      'hasRenterdUploader': _renterdUploader != null,
      'hasSettingsService': _settingsService != null,
      'hasEncryptionService': _encryptionService != null,
      'lastDownloadedBackup': _lastDownloadedBackup != null,
    };
  }
}

// Helper function to create PasswordModel from Map
PasswordModel _passwordModelFromMap(Map<String, dynamic> map) {
  return PasswordModel(
    id: map['id'] as String,
    title: map['title'] as String,
    username: map['username'] as String,
    encryptedPassword: map['encryptedPassword'] as String,
    category: map['category'] ?? 'Other',
    notes: map['notes'] ?? '',
    createdAt: DateTime.parse(map['createdAt'] as String),
    updatedAt: DateTime.parse(map['updatedAt'] as String),
  );
}

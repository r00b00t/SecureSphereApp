import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:securesphere/features/password/repositories/password_repository.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:securesphere/features/auth/services/auth_service.dart';
import 'package:securesphere/config/api_config.dart';

class BackupService extends GetxService {
  Box? _backupBox;
  PasswordRepository? _passwordRepository;
  bool _isInitialized = false;
  
  Future<void> init() async {
    if (_isInitialized) return;
    
    _backupBox = await Hive.openBox('backups');
    try {
      _passwordRepository = Get.find<PasswordRepository>();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize PasswordRepository: ${e.toString()}');
      rethrow;
    }
  }
  
  Future<void> triggerBackup({String? customName}) async {
    try {
      // Ensure service is initialized
      if (!_isInitialized) {
        await init();
      }
      
      if (_passwordRepository == null) {
        throw Exception('PasswordRepository is not initialized');
      }
      
      // Get passwords from repository (this will include the actual passwords from secure storage)
      List<PasswordModel> passwords = [];
      try {
        passwords = await _passwordRepository!.getAllPasswords();
        debugPrint('Successfully retrieved ${passwords.length} passwords for backup');
      } catch (e) {
        debugPrint('Error retrieving passwords for backup: ${e.toString()}');
        // Continue with empty passwords list rather than failing the entire backup
        // This allows backing up other data even if passwords can't be retrieved
      }
      final passwordMaps = passwords.map((p) => p.toMap()).toList();
      
      // Create backup data including passwords
      final backupData = {
        'timestamp': DateTime.now().toIso8601String(),
        'appVersion': '1.0.0',
        'passwords': passwordMaps,
      };
      
      // Save backup locally
      await _saveLocalBackup(backupData, customName: customName);
      
      // Upload to S5 node
      await _uploadToS5Node(backupData, customName: customName);
      
      debugPrint('Backup completed successfully');
    } catch (e) {
      debugPrint('Backup trigger error: ${e.toString()}');
      rethrow;
    }
  }
  
  Future<void> _uploadToS5Node(Map<String, dynamic> jsonData, {String? customName}) async {
    File? tempFile;
    try {
      debugPrint('Starting S5 upload process...');
      
      if (kIsWeb) {
        debugPrint('S5 upload skipped: Not supported on web platform');
        throw Exception('S5 upload not supported on web platform');
      }
      
      // Step 1: Create temp file
      final fileName = customName ?? 'backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final tempPath = '${Directory.systemTemp.path}/$fileName';
      tempFile = File(tempPath);
      debugPrint('Creating temporary file at: $tempPath');
      
      // Step 2: Write data to temp file
      debugPrint('Writing ${jsonEncode(jsonData).length} bytes to temporary file');
      await tempFile.writeAsString(jsonEncode(jsonData));
      debugPrint('Temporary file created successfully: ${await tempFile.length()} bytes');
      
      // Step 3: Prepare upload request
      final uploadUrl = ApiConfig.s5UploadUrl;
      debugPrint('Preparing upload request to: $uploadUrl');
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.headers['Accept'] = 'application/json';
      request.headers['Authorization'] = ApiConfig.s5AuthToken;
      
      // Step 4: Add file to request
      debugPrint('Adding file to upload request: ${tempFile.path}');
      request.files.add(await http.MultipartFile.fromPath('file', tempFile.path));
      
      // Step 5: Send request
      debugPrint('Sending upload request to S5 node...');
      final response = await request.send();
      debugPrint('Received response with status code: ${response.statusCode}');
      
      // Step 6: Process response
      if (response.statusCode != 200) {
        // Get response body for more detailed error information
        final responseBody = await http.Response.fromStream(response).then((res) => res.body);
        debugPrint('S5 upload response body: $responseBody');
        
        try {
          final errorData = jsonDecode(responseBody);
          final errorMessage = errorData['error'] ?? errorData['message'] ?? 'Unknown error';
          throw Exception('S5 upload failed (${response.statusCode}): $errorMessage');
        } catch (_) {
          throw Exception('Failed to upload to S5 node: ${response.statusCode}, Response: $responseBody');
        }
      }
      
      // Step 7: Parse successful response
      final responseBody = await http.Response.fromStream(response).then((res) => res.body);
      debugPrint('S5 upload response: $responseBody');
      
      try {
        final responseData = jsonDecode(responseBody);
        final cid = responseData['cid'] ?? 'Unknown';
        debugPrint('Backup uploaded to S5 node successfully with CID: $cid');
        
        // Add backup CID to user profile
        final authService = Get.find<AuthService>();
        final userId = authService.currentUser?.id;
        if (userId != null) {
          try {
            final response = await http.post(
              Uri.parse('http://164.92.143.228:3001/user/$userId/addBackup'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'backupCid': cid}),
            );
            
            if (response.statusCode == 200) {
              final responseData = jsonDecode(response.body);
              if (responseData['success'] == true) {
                debugPrint('Backup CID added to user profile: $cid');
              } else {
                debugPrint('Failed to add backup CID to user profile: ${responseData['message'] ?? 'Unknown error'}');
                throw Exception('Failed to add backup CID: ${responseData['message'] ?? 'Unknown error'}');
              }
            } else {
              debugPrint('Failed to add backup CID to user profile: ${response.statusCode}');
              final responseBody = response.body;
              debugPrint('Failed to add backup CID response body: $responseBody');
              throw Exception('Failed to add backup CID: ${response.statusCode}');
            }
          } catch (e) {
            debugPrint('Error adding backup CID to user profile: ${e.toString()}');
            rethrow;
          }
        }
      } catch (parseError) {
        debugPrint('Could not parse S5 response JSON: $parseError');
        debugPrint('Backup uploaded to S5 node successfully, but response parsing failed');
      }
    } catch (e) {
      debugPrint('S5 upload failed: ${e.toString()}');
      rethrow;
    } finally {
      // Step 8: Clean up temporary file
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          debugPrint('Temporary file deleted successfully');
        } catch (e) {
          debugPrint('Failed to delete temporary file: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _saveLocalBackup(Map<String, dynamic> jsonData, {String? customName}) async {
    try {
      if (_backupBox == null) {
        throw Exception('BackupBox is not initialized');
      }
      
      final fileName = customName ?? 'backup_${DateTime.now().millisecondsSinceEpoch}.json';
      await _backupBox!.put(fileName, jsonEncode(jsonData));
      debugPrint('Backup saved locally as: $fileName');
    } catch (e) {
      debugPrint('Local backup failed: ${e.toString()}');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getBackups() async {
    try {
      // Ensure service is initialized
      if (!_isInitialized) {
        await init();
      }
      
      if (_backupBox == null) {
        throw Exception('BackupBox is not initialized');
      }
      
      final backups = <Map<String, dynamic>>[];
      for (var key in _backupBox!.keys) {
        final backupJson = _backupBox!.get(key);
        if (backupJson != null) {
          final backupData = jsonDecode(backupJson);
          backups.add({
            'name': key,
            'date': DateTime.parse(backupData['timestamp']).toString(),
            'path': key,
          });
        }
      }
      return backups;
    } catch (e) {
      debugPrint('Error fetching backups: ${e.toString()}');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> restoreBackup(String backupKey) async {
    try {
      // Ensure service is initialized
      if (!_isInitialized) {
        await init();
      }
      
      if (_backupBox == null) {
        throw Exception('BackupBox is not initialized');
      }
      
      if (_passwordRepository == null) {
        throw Exception('PasswordRepository is not initialized');
      }
      
      final backupJson = _backupBox!.get(backupKey);
      if (backupJson == null) {
        throw Exception('Backup not found');
      }
      
      final backupData = jsonDecode(backupJson);
      
      // Restore passwords if they exist in the backup
      if (backupData.containsKey('passwords')) {
        await _passwordRepository!.restorePasswords(backupData['passwords']);
        debugPrint('Successfully restored passwords from backup');
      }
      
      debugPrint('Successfully restored backup: $backupKey');
      return backupData;
    } catch (e) {
      debugPrint('Backup restoration failed: ${e.toString()}');
      rethrow;
    }
  }
}

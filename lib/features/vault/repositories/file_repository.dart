import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:get/get.dart';
import '../models/file_model.dart';
import '../services/renterd_uploader.dart';
import 'package:decvault/features/subscription/services/storage_service.dart';
import 'package:decvault/services/notification_service.dart';

class FileRepository {
  final Box<FileModel> _box = Hive.box<FileModel>('files');
  final Uuid _uuid = const Uuid();
  final RenterdUploader? _renterdUploader;

  FileRepository([this._renterdUploader]);

  Future<void> saveFile(FileModel file) async {
    // Check if this is a new file or an update
    final existingFile = _box.get(file.id);
    final isNewFile = existingFile == null;
    
    await _box.put(file.id, file);
    
    // Update storage tracking only for new files
    if (isNewFile) {
      try {
        final storageService = Get.find<StorageService>();
        await storageService.addFileSize(
          file.size,
          fileId: file.id,
          fileName: file.name,
        );
      } catch (e) {
        // StorageService not available, continue without tracking
      }
    }
  }

  Future<void> deleteFile(String id) async {
    final file = await getFileById(id);
    if (file != null) {
      // Check if file exists in SIA vault and delete it
      if (file.tags.contains('sia-vault') || file.tags.contains('sia-uploaded') || file.tags.contains('sia-synced')) {
        if (_renterdUploader != null) {
          try {
            final filenameForSia = file.siaFilename ?? file.name;
            await _renterdUploader!.deleteFile(filenameForSia);
          } catch (e) {
            // Continue with local deletion even if SIA deletion fails
          }
        }
      }
      
      // Delete the actual local file from storage
      if (file.path.isNotEmpty) {
        final filePath = file.path;
        final fileToDelete = File(filePath);
        if (await fileToDelete.exists()) {
          await fileToDelete.delete();
        }
      }
      
      await _box.delete(id);
      
      // Update storage tracking
      try {
        final storageService = Get.find<StorageService>();
        await storageService.removeFileSize(file.size, fileId: file.id);
      } catch (e) {
        // StorageService not available, continue without tracking
      }
    }
  }

  Future<String> copyFileToVault(File sourceFile, String originalName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory('${appDir.path}/vault');
    
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    final fileName = '${_uuid.v4()}_${DateTime.now().millisecondsSinceEpoch}';
    final extension = originalName.split('.').last;
    final newFileName = '$fileName.$extension';
    final newPath = '${vaultDir.path}/$newFileName';

    await sourceFile.copy(newPath);
    return newPath;
  }

  Future<FileModel> addFile({
    required File file,
    required String originalName,
    String? description,
    List<String> tags = const [],
    Function(double progress)? onProgress,
  }) async {
    try {
      debugPrint('[FileRepository] Starting file upload: $originalName');
      onProgress?.call(5.0);
      
      // Check file size and storage limit
      final size = await file.length();
      
      // Check storage limit with StorageService
      try {
        final storageService = Get.find<StorageService>();
        
        if (!storageService.canUploadFile(size)) {
          await storageService.showStorageLimitDialog();
          throw Exception('Storage limit exceeded');
        }
      } catch (e) {
        if (e.toString().contains('Storage limit exceeded')) {
          rethrow;
        }
        // StorageService not available, continue without check
      }
      
      final id = _uuid.v4();
      onProgress?.call(15.0);
      
      final path = await copyFileToVault(file, originalName);
      onProgress?.call(40.0);
      
      onProgress?.call(50.0);
      
      final fileModel = FileModel(
        id: id,
        name: originalName,
        originalName: originalName,
        path: path,
        size: size,
        mimeType: _getMimeType(originalName),
        uploadedAt: DateTime.now(),
        description: description,
        tags: tags,
        isEncrypted: true, // Files are now encrypted by default
      );

      onProgress?.call(60.0);
      await saveFile(fileModel);
      onProgress?.call(70.0);
      
      debugPrint('[FileRepository] File saved locally, checking SIA availability');
      
      // Check if SIA upload is available and upload automatically
      if (isSiaUploadAvailable) {
        debugPrint('[FileRepository] Starting SIA upload');
        try {
          onProgress?.call(75.0);
          
          await uploadToSia(
            fileModel,
            onProgress: (siaProgress) {
              final totalProgress = 75.0 + (siaProgress * 0.25);
              onProgress?.call(totalProgress);
            },
          );
          
          fileModel.tags = [...fileModel.tags, 'sia-uploaded'];
          await saveFile(fileModel);
          
          debugPrint('[FileRepository] SIA upload successful');
          
        } catch (e) {
          // SIA upload failed, but local upload succeeded
          debugPrint('[FileRepository] SIA upload failed: $e');
          
          // Still save the file locally even if SIA upload failed
          fileModel.tags = [...fileModel.tags, 'sia-upload-failed'];
          await saveFile(fileModel);
          
          // Re-throw the error so the UI can show it
          throw Exception('File uploaded locally but SIA upload failed: $e');
        }
      } else {
      }
      
      onProgress?.call(100.0);
      debugPrint('[FileRepository] Upload complete');
      return fileModel;
      
    } catch (e) {
      debugPrint('[FileRepository] Upload error: $e');
      rethrow;
    }
  }

  Future<List<FileModel>> getAllFiles() async {
    return _box.values.toList();
  }

  Future<FileModel?> getFileById(String id) async {
    return _box.get(id);
  }

  Future<void> uploadToSia(FileModel file, {Function(double progress)? onProgress}) async {
    if (_renterdUploader == null) {
      throw Exception('RenterdUploader not configured');
    }
    
    try {
      final fileToUpload = File(file.path);
      
      if (!await fileToUpload.exists()) {
        throw Exception('File not found: ${file.path}');
      }
      
      final siaFilename = await _renterdUploader!.uploadFile(
        fileToUpload,
        file.name,
        onProgress: onProgress,
      );
      
      // Store the size-embedded SIA filename for downloads
      file.siaFilename = siaFilename;
      await saveFile(file);
      
    } catch (e) {
      throw Exception('Failed to upload to SIA: $e');
    }
  }

  /// Downloads and decrypts a file from SIA renterd v2
  Future<void> downloadFromSia(FileModel file, {Function(double progress)? onProgress}) async {
    if (_renterdUploader == null) {
      throw Exception('RenterdUploader not configured');
    }

    try {
      // Check if file is too large for this device before starting download
      final isMobile = Platform.isAndroid || Platform.isIOS;
      final maxDownloadSize = isMobile ? 200 * 1024 * 1024 : 1024 * 1024 * 1024;
      
      if (file.size > maxDownloadSize) {
        final sizeMB = (file.size / 1024 / 1024).toStringAsFixed(0);
        final maxSizeMB = (maxDownloadSize / 1024 / 1024).toStringAsFixed(0);
        throw Exception(
          'File is ${sizeMB}MB. Maximum download size on ${isMobile ? "mobile" : "desktop"} is ${maxSizeMB}MB. '
          '${isMobile ? "Please download this file on desktop instead." : "Try compressing the file first."}'
        );
      }
      
      final filenameForSia = file.siaFilename ?? file.name;
      
      // Request storage permissions first
      await _requestStoragePermissions();
      
      // Try multiple approaches to save the file
      Directory? downloadDir;
      String approach = '';
      
      // Approach 1: Try Downloads/DecVault directory (cross-platform)
      try {
        Directory? baseDownloadsDir;
        
        if (Platform.isAndroid) {
          baseDownloadsDir = Directory('/storage/emulated/0/Download');
        } else if (Platform.isIOS) {
          // On iOS, use the app's Documents directory since we can't access Downloads directly
          final documentsDir = await getApplicationDocumentsDirectory();
          baseDownloadsDir = Directory('${documentsDir.path}/Downloads');
        } else if (Platform.isWindows) {
          final userProfile = Platform.environment['USERPROFILE'] ?? '';
          if (userProfile.isNotEmpty) {
            baseDownloadsDir = Directory('$userProfile\\Downloads');
          }
        } else if (Platform.isMacOS || Platform.isLinux) {
          final home = Platform.environment['HOME'] ?? '';
          if (home.isNotEmpty) {
            baseDownloadsDir = Directory('$home/Downloads');
          }
        }
        
        if (baseDownloadsDir != null && await baseDownloadsDir.exists()) {
          final secureSphereDownloadDir = Directory('${baseDownloadsDir.path}${Platform.pathSeparator}DecVault');
          if (!await secureSphereDownloadDir.exists()) {
            await secureSphereDownloadDir.create(recursive: true);
          }
          downloadDir = secureSphereDownloadDir;
          approach = 'Downloads/DecVault';
        }
      } catch (e) {
      }
      
      // Approach 2: Try standard Downloads directory (cross-platform)
      if (downloadDir == null) {
        try {
          Directory? baseDownloadsDir;
          
          if (Platform.isAndroid) {
            baseDownloadsDir = Directory('/storage/emulated/0/Download');
          } else if (Platform.isIOS) {
            // On iOS, use the app's Documents directory since we can't access Downloads directly
            final documentsDir = await getApplicationDocumentsDirectory();
            baseDownloadsDir = Directory('${documentsDir.path}/Downloads');
          } else if (Platform.isWindows) {
            final userProfile = Platform.environment['USERPROFILE'] ?? '';
            if (userProfile.isNotEmpty) {
              baseDownloadsDir = Directory('$userProfile\\Downloads');
            }
          } else if (Platform.isMacOS || Platform.isLinux) {
            final home = Platform.environment['HOME'] ?? '';
            if (home.isNotEmpty) {
              baseDownloadsDir = Directory('$home/Downloads');
            }
          }
          
          if (baseDownloadsDir != null && await baseDownloadsDir.exists()) {
            downloadDir = baseDownloadsDir;
            approach = 'Downloads';
          }
        } catch (e) {
        }
      }
      
      // Approach 3: Use app's external files directory
      if (downloadDir == null) {
        try {
          final appDir = await getExternalStorageDirectory();
          if (appDir != null) {
            downloadDir = Directory('${appDir.path}/DecVault');
            if (!await downloadDir.exists()) {
              await downloadDir.create(recursive: true);
            }
            approach = 'External App Directory';
          }
        } catch (e) {
        }
      }
      
      // Approach 4: Fallback to app's internal directory
      if (downloadDir == null) {
        final appDir = await getApplicationDocumentsDirectory();
        downloadDir = Directory('${appDir.path}/downloads');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        approach = 'Internal App Directory';
      }
      
      final downloadPath = '${downloadDir.path}/${file.name}';
      
      final downloadedFile = await _renterdUploader!.downloadFileWithSize(
        filenameForSia,
        downloadPath,
        file.size,
        onProgress: onProgress,
      );
      
      // Verify the file was actually created and has content
      if (await downloadedFile.exists()) {
        final fileSize = await downloadedFile.length();
        
        if (fileSize == 0) {
          throw Exception('Downloaded file is empty');
        }
        
        // For external storage files, try to make them visible via MediaStore (Android only)
        if (approach == 'Downloads/DecVault' || approach == 'Downloads' || approach == 'External App Directory') {
          try {
            // Only call MediaScanner on Android - it's not available on desktop platforms
            if (Platform.isAndroid) {
              await MediaScanner.loadMedia(path: downloadedFile.path);
            } else {
            }
          } catch (e) {
          }
        }
        
        // Show download notification
        try {
          await NotificationService().showDownloadComplete(
            fileName: file.name,
            filePath: downloadedFile.path,
          );
        } catch (e) {
          // Notification failure should not stop the download flow
        }
        
      } else {
        throw Exception('File was not created at expected location: $downloadPath');
      }
      
    } catch (e) {
      // Show error notification
      try {
        await NotificationService().showDownloadError(
          fileName: file.name,
          error: e.toString(),
        );
      } catch (notifError) {
        // Notification failure should not stop the error flow
      }
      throw Exception('Failed to download and save file: $e');
    }
  }
  
  /// Request storage permissions
  Future<void> _requestStoragePermissions() async {
    try {
      // Only request permissions on Android - iOS/macOS/Windows don't need explicit storage permissions
      if (Platform.isAndroid) {
        // Try to get storage permission
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        
        // Also try manage external storage for broader access
        var manageStatus = await Permission.manageExternalStorage.status;
        if (!manageStatus.isGranted) {
          // Note: This will open settings, user needs to manually grant
          manageStatus = await Permission.manageExternalStorage.request();
        }
              } else {
        }
    } catch (e) {
      // Continue anyway, we have fallback options
    }
  }

  bool get isSiaUploadAvailable => _renterdUploader != null;

  /// Test SIA connection
  Future<bool> testSiaConnection() async {
    if (_renterdUploader == null) {
      return false;
    }
    
    try {
      return await _renterdUploader!.testConnection();
    } catch (e) {
      return false;
    }
  }

  /// Get files directly from SIA vault bucket (actual vault contents)
  /// 
  /// IMPORTANT: When files are uploaded, their original size is embedded in the filename
  /// as a .origXXXXX suffix (e.g., "file_timestamp.ext.orig12345"). This is critical for
  /// cross-device decryption to work correctly, as the encryption key is derived from
  /// the original file size. Without extracting this size, decryption will fail when
  /// downloading files that were uploaded from other devices.
  Future<List<FileModel>> getSiaVaultFiles() async {
    if (_renterdUploader == null) {
      throw Exception('RenterdUploader not configured');
    }
    
    try {
      final siaFiles = await _renterdUploader!.listVaultFiles();
      final vaultFiles = <FileModel>[];
      
      for (final siaFile in siaFiles) {
        final siaFileName = siaFile['name'] as String;
        
        // Check if we have local metadata for this file using siaFilename
        final localFiles = await getAllFiles();
        final existingFile = localFiles.firstWhere(
          (f) => f.siaFilename == siaFileName,
          orElse: () {
            // Extract original file size from .origXXXXX suffix if present
            int originalSize = siaFile['size'] as int? ?? 0;
            final origSizeMatch = RegExp(r'\.orig(\d+)$').firstMatch(siaFileName);
            if (origSizeMatch != null) {
              originalSize = int.parse(origSizeMatch.group(1)!);
            } else {
            }
            
            // Try to extract original name from unique filename
            String displayName = siaFileName;
            // Remove .origXXXXX suffix first
            displayName = displayName.replaceAll(RegExp(r'\.orig\d+$'), '');
            
            if (displayName.contains('_') && displayName.split('_').length >= 2) {
              final parts = displayName.split('_');
              final timestampAndExt = parts.last;
              final originalParts = parts.sublist(0, parts.length - 1);
              final originalName = originalParts.join('_');
              
              if (timestampAndExt.contains('.')) {
                final extension = timestampAndExt.split('.').last;
                displayName = '$originalName.$extension';
              }
            }
            
            return FileModel(
              id: _uuid.v4(),
              name: displayName,
              originalName: displayName,
              path: '',
              size: originalSize, // Use extracted original size instead of encrypted size
              mimeType: _getMimeType(displayName),
              uploadedAt: DateTime.tryParse(siaFile['modTime'] as String? ?? '') ?? DateTime.now(),
              description: 'File in SIA vault',
              tags: ['sia-vault'],
              isEncrypted: true,
              siaFilename: siaFileName,
            );
          },
        );
        
        // Extract original size from filename if available, otherwise use existing file size
        int fileSize = existingFile.size;
        final origSizeMatch = RegExp(r'\.orig(\d+)$').firstMatch(siaFileName);
        if (origSizeMatch != null) {
          fileSize = int.parse(origSizeMatch.group(1)!);
        }
        
        final fileModel = FileModel(
          id: existingFile.id,
          name: existingFile.name,
          originalName: existingFile.originalName.isNotEmpty ? existingFile.originalName : existingFile.name,
          path: existingFile.path,
          size: fileSize, // Use extracted original size or existing size
          mimeType: existingFile.mimeType.isNotEmpty ? existingFile.mimeType : _getMimeType(existingFile.name),
          uploadedAt: DateTime.tryParse(siaFile['modTime'] as String? ?? '') ?? existingFile.uploadedAt,
          description: existingFile.description ?? 'File in SIA vault',
          tags: ['sia-vault'],
          isEncrypted: true,
          siaFilename: siaFileName,
        );
        
        vaultFiles.add(fileModel);
      }
      
      return vaultFiles;
    } catch (e) {
      throw Exception('Failed to get SIA vault files: $e');
    }
  }

  /// Syncs files from SIA vault bucket to local storage
  /// 
  /// IMPORTANT: Extracts original file size from .origXXXXX suffix in SIA filename
  /// to ensure correct decryption across devices. The encryption key depends on this size.
  Future<List<FileModel>> syncFromSiaBucket() async {
    if (_renterdUploader == null) {
      throw Exception('RenterdUploader not configured');
    }
    
    try {
      final isConnected = await testSiaConnection();
      if (!isConnected) {
        throw Exception('SIA connection failed. Please check your SIA configuration.');
      }
      
      final siaFiles = await _renterdUploader!.listVaultFiles();
      final localFiles = await getAllFiles();
      final localFileNames = localFiles.map((f) => f.name).toSet();
      
      final newFiles = <FileModel>[];
      
      for (final siaFile in siaFiles) {
        final siaFileName = siaFile['name'] as String;
        
        // Extract original file size from .origXXXXX suffix if present
        int originalSize = siaFile['size'] as int? ?? 0;
        final origSizeMatch = RegExp(r'\.orig(\d+)$').firstMatch(siaFileName);
        if (origSizeMatch != null) {
          originalSize = int.parse(origSizeMatch.group(1)!);
        } else {
        }
        
        // Extract original filename from unique SIA filename
        String displayName = siaFileName;
        // Remove .origXXXXX suffix first
        displayName = displayName.replaceAll(RegExp(r'\.orig\d+$'), '');
        
        // Remove timestamp from filename (format: basename_timestamp.ext)
        if (displayName.contains('_') && displayName.split('_').length >= 2) {
          final parts = displayName.split('_');
          final timestampAndExt = parts.last;
          final originalParts = parts.sublist(0, parts.length - 1);
          final originalName = originalParts.join('_');
          
          if (timestampAndExt.contains('.')) {
            final extension = timestampAndExt.split('.').last;
            displayName = '$originalName.$extension';
          }
        }
        
        if (localFileNames.contains(displayName)) {
          continue;
        }
        
        final fileModel = FileModel(
          id: _uuid.v4(),
          name: displayName,
          originalName: displayName,
          path: '',
          size: originalSize, // Use extracted original size instead of encrypted size
          mimeType: _getMimeType(displayName),
          uploadedAt: DateTime.tryParse(siaFile['modTime'] as String? ?? '') ?? DateTime.now(),
          description: 'Synced from SIA vault',
          tags: ['sia-synced'],
          isEncrypted: true,
          siaFilename: siaFileName, // Store the actual SIA filename for download
        );
        
        newFiles.add(fileModel);
      }
      
      for (final file in newFiles) {
        await saveFile(file);
      }
      
      return newFiles;
    } catch (e) {
      throw Exception('Failed to sync from SIA bucket: $e');
    }
  }

  /// Downloads a file from SIA and updates its local path
  Future<File> downloadAndUpdatePath(FileModel file) async {
    if (_renterdUploader == null) {
      throw Exception('RenterdUploader not configured');
    }
    
    try {
      await downloadFromSia(file);
      
      Directory downloadDir;
      if (Platform.isAndroid) {
        if (file.mimeType.startsWith('image/')) {
          downloadDir = Directory('/storage/emulated/0/Pictures');
        } else if (file.mimeType.startsWith('video/')) {
          downloadDir = Directory('/storage/emulated/0/Movies');
        } else {
          downloadDir = Directory('/storage/emulated/0/Download');
        }
      } else if (Platform.isIOS) {
        // On iOS, use the app's Documents directory with type-specific subdirectories
        final documentsDir = await getApplicationDocumentsDirectory();
        if (file.mimeType.startsWith('image/')) {
          downloadDir = Directory('${documentsDir.path}/Images');
        } else if (file.mimeType.startsWith('video/')) {
          downloadDir = Directory('${documentsDir.path}/Videos');
        } else {
          downloadDir = Directory('${documentsDir.path}/Downloads');
        }
      } else {
        // For desktop platforms (macOS, Windows, Linux), use Downloads
        final documentsDir = await getApplicationDocumentsDirectory();
        downloadDir = Directory('${documentsDir.path}/Downloads');
      }
      
      final downloadPath = '${downloadDir.path}/${file.name}';
      final downloadedFile = File(downloadPath);
      
      file.path = downloadPath;
      await saveFile(file);
      
      return downloadedFile;
    } catch (e) {
      throw Exception('Failed to download and update path: $e');
    }
  }

  /// Deletes a file from SIA vault only (keeps local record)
  Future<void> deleteFromSia(FileModel file) async {
    if (_renterdUploader == null) {
      throw Exception('RenterdUploader not configured');
    }
    
    try {
      final filenameForSia = file.siaFilename ?? file.name;
      await _renterdUploader!.deleteFile(filenameForSia);
    } catch (e) {
      throw Exception('Failed to delete from SIA: $e');
    }
  }

  String _getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'txt':
        return 'text/plain';
      case 'mp4':
        return 'video/mp4';
      case 'avi':
        return 'video/avi';
      default:
        return 'application/octet-stream';
    }
  }
} 

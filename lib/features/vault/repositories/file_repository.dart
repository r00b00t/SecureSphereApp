import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/file_model.dart';
import '../services/renterd_uploader.dart';

class FileRepository {
  final Box<FileModel> _box = Hive.box<FileModel>('files');
  final Uuid _uuid = const Uuid();
  final RenterdUploader? _renterdUploader;

  FileRepository([this._renterdUploader]);

  Future<void> saveFile(FileModel file) async {
    await _box.put(file.id, file);
  }

  Future<void> deleteFile(String id) async {
    final file = await getFileById(id);
    if (file != null) {
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
      
      onProgress?.call(5.0);
      
      final id = _uuid.v4();
      onProgress?.call(15.0);
      
      final path = await copyFileToVault(file, originalName);
      onProgress?.call(40.0);
      
      final size = await file.length();
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
      
      
      if (isSiaUploadAvailable) {
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
          
          
        } catch (e) {
          // SIA upload failed, but local upload succeeded
        }
      } else {
      }
      
      onProgress?.call(100.0);
      return fileModel;
      
    } catch (e) {
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
      final filenameForSia = file.siaFilename ?? file.name;
      
      // Request storage permissions first
      await _requestStoragePermissions();
      
      // Try multiple approaches to save the file
      Directory? downloadDir;
      String approach = '';
      
      // Approach 1: Try Downloads/SecureSphere directory (cross-platform)
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
          final secureSphereDownloadDir = Directory('${baseDownloadsDir.path}${Platform.pathSeparator}SecureSphere');
          if (!await secureSphereDownloadDir.exists()) {
            await secureSphereDownloadDir.create(recursive: true);
          }
          downloadDir = secureSphereDownloadDir;
          approach = 'Downloads/SecureSphere';
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
            downloadDir = Directory('${appDir.path}/SecureSphere');
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
        if (approach == 'Downloads/SecureSphere' || approach == 'Downloads' || approach == 'External App Directory') {
          try {
            // Only call MediaScanner on Android - it's not available on desktop platforms
            if (Platform.isAndroid) {
              await MediaScanner.loadMedia(path: downloadedFile.path);
            } else {
            }
          } catch (e) {
          }
        }
        
        
      } else {
        throw Exception('File was not created at expected location: $downloadPath');
      }
      
    } catch (e) {
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
  Future<List<FileModel>> getSiaVaultFiles() async {
    if (_renterdUploader == null) {
      throw Exception('RenterdUploader not configured');
    }
    
    try {
      final siaFiles = await _renterdUploader!.listVaultFiles();
      final vaultFiles = <FileModel>[];
      
      for (final siaFile in siaFiles) {
        final siaFileName = siaFile['name'] as String;
        
        final localFiles = await getAllFiles();
        final existingFile = localFiles.firstWhere(
          (f) => f.siaFilename == siaFileName,
          orElse: () {
            // Try to extract original name from unique filename
            String displayName = siaFileName;
            if (siaFileName.contains('_') && siaFileName.split('_').length >= 2) {
              final parts = siaFileName.split('_');
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
              size: siaFile['size'] as int? ?? 0,
              mimeType: _getMimeType(displayName),
              uploadedAt: DateTime.tryParse(siaFile['modTime'] as String? ?? '') ?? DateTime.now(),
              description: 'File in SIA vault',
              tags: ['sia-vault'],
              isEncrypted: true,
              siaFilename: siaFileName,
            );
          },
        );
        
        final fileModel = FileModel(
          id: existingFile.id,
          name: existingFile.name,
          originalName: existingFile.originalName.isNotEmpty ? existingFile.originalName : existingFile.name,
          path: existingFile.path,
          size: siaFile['size'] as int? ?? 0,
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
        
        // Extract clean filename for display (remove .origXXXXX suffix)
        final cleanFileName = siaFileName.replaceAll(RegExp(r'\.orig\d+$'), '');
        
        if (localFileNames.contains(cleanFileName)) {
          continue;
        }
        
        final fileModel = FileModel(
          id: _uuid.v4(),
          name: cleanFileName,
          originalName: cleanFileName,
          path: '',
          size: siaFile['size'] as int? ?? 0,
          mimeType: _getMimeType(cleanFileName),
          uploadedAt: DateTime.tryParse(siaFile['modTime'] as String? ?? '') ?? DateTime.now(),
          description: 'Synced from SIA vault',
          tags: ['sia-synced'],
          isEncrypted: true,
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
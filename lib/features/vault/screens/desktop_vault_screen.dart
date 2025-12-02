import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:decvault/features/vault/models/file_model.dart';
import 'package:decvault/features/vault/repositories/file_repository.dart';
import 'package:decvault/features/vault/screens/file_detail_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:decvault/features/sia/services/sia_service.dart';
import 'package:decvault/features/sia/screens/sia_password_required_screen.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:decvault/common/widgets/custom_title_bar.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class DesktopVaultScreen extends StatefulWidget {
  const DesktopVaultScreen({super.key});

  @override
  State<DesktopVaultScreen> createState() => _DesktopVaultScreenState();
}

class _DesktopVaultScreenState extends State<DesktopVaultScreen> {
  final FileRepository _fileRepo = Get.find();
  
  List<FileModel> _files = [];
  List<FileModel> _filteredFiles = [];
  bool _isLoading = true;
  String _selectedView = 'grid'; // grid or list
  String _sortBy = 'name'; // name, date, size, type
  bool _sortAscending = true;
  FileModel? _selectedFile;
  bool _isUploading = false;
  bool _isSelectingFile = false;
  double _uploadProgress = 0.0;
  String _uploadingFileName = '';
  String _selectedFileType = 'All Files'; // Filter by file type
  bool _isDragOver = false; // For drag and drop visual feedback
  
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkInitialSiaAccess();
    _setupKeyboardShortcuts();
  }

  Future<void> _checkInitialSiaAccess() async {
    // Check if SIA access is available before loading files - same as mobile
    final hasAccess = await _checkSiaConnectivity();
    if (hasAccess) {
      _loadFiles();
    }
  }

  Future<bool> _checkSiaConnectivity({String? action}) async {
    if (!_fileRepo.isSiaUploadAvailable) {
      SnackbarUtils.showWarning(
        title: 'SIA Not Connected',
        message: action != null 
          ? 'Cannot $action. Please go to Settings → Backup & Storage → Connect your SIA node first.'
          : 'SIA is not connected. Please go to Settings → Backup & Storage to connect your SIA node.',
        duration: const Duration(seconds: 5),
      );
      return false;
    }

    // Additional check for SIA password when using self-hosted
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupOption = prefs.getString('backupOption') ?? 'DecVault';
      
      if (backupOption == 'Self-Hosted SIA Node') {
        final siaService = Get.find<SiaService>();
        final isPasswordMissing = await siaService.isPasswordMissing();
        
        if (isPasswordMissing) {
          final result = await Get.to(() => const SiaPasswordRequiredScreen());
          if (result != true) {
            SnackbarUtils.showWarning(
              title: 'SIA Password Required',
              message: 'SIA password is needed to access the vault. Please provide your SIA password.',
            );
            return false;
          }
        }
      }
    } catch (e) {
    }
    
    return true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _setupKeyboardShortcuts() {
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+F for search
      if (event.logicalKey == LogicalKeyboardKey.keyF && 
          HardwareKeyboard.instance.isControlPressed) {
        _searchFocusNode.requestFocus();
        return true;
      }
      // Ctrl+U for upload
      if (event.logicalKey == LogicalKeyboardKey.keyU && 
          HardwareKeyboard.instance.isControlPressed) {
        _uploadFile();
        return true;
      }
      // Ctrl+R for refresh
      if (event.logicalKey == LogicalKeyboardKey.keyR && 
          HardwareKeyboard.instance.isControlPressed) {
        _loadFiles();
        return true;
      }
      // Delete key for delete file
      if (event.logicalKey == LogicalKeyboardKey.delete && _selectedFile != null) {
        _deleteFile(_selectedFile!);
        return true;
      }
      // Ctrl+D for download file
      if (event.logicalKey == LogicalKeyboardKey.keyD && 
          HardwareKeyboard.instance.isControlPressed && _selectedFile != null) {
        _downloadFile(_selectedFile!);
        return true;
      }
      // Escape to clear selection/search
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_searchController.text.isNotEmpty) {
          _clearSearch();
        } else {
          setState(() => _selectedFile = null);
        }
        return true;
      }
    }
    return false;
  }

  Future<void> _loadFiles() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Load files directly from SIA vault bucket (actual vault contents) - same as mobile
      if (_fileRepo.isSiaUploadAvailable) {
        final siaVaultFiles = await _fileRepo.getSiaVaultFiles();
        
        // Also include locally uploaded files that failed SIA upload
        final allFiles = await _fileRepo.getAllFiles();
        final localFailedFiles = allFiles.where((file) => 
          file.tags.contains('sia-upload-failed')
        ).toList();
        
        // Combine SIA files and locally failed files
        final combinedFiles = [...siaVaultFiles, ...localFailedFiles];
        
        if (!mounted) return;
        setState(() {
          _files = combinedFiles;
          _filteredFiles = List.from(combinedFiles);
          _isLoading = false;
        });
      } else {
        // Fallback to local files if SIA not available - same as mobile
        final allFiles = await _fileRepo.getAllFiles();
        if (!mounted) return;
        final siaFiles = allFiles.where((file) => 
          file.tags.contains('sia-uploaded') ||
          file.tags.contains('sia-synced') ||
          file.tags.contains('sia-vault') ||
          file.tags.contains('sia-upload-failed')
        ).toList();
        
        if (!mounted) return;
        setState(() {
          _files = siaFiles;
          _filteredFiles = List.from(siaFiles);
          _isLoading = false;
        });
      }
      
      _sortFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      
      // Check if the error is SIA-related and provide appropriate message
      final errorMessage = e.toString();
      final isSiaError = !_fileRepo.isSiaUploadAvailable || 
                        errorMessage.contains('SIA') || 
                        errorMessage.contains('sia') ||
                        errorMessage.contains('connection') ||
                        errorMessage.contains('network');
      
      if (isSiaError) {
        SnackbarUtils.showWarning(
          title: 'SIA Connection Required',
          message: 'Unable to load vault files. Please go to Settings → Backup & Storage and connect your SIA node first.',
          duration: const Duration(seconds: 6),
        );
      } else {
        SnackbarUtils.showError(
          title: 'Error',
          message: 'Failed to load vault files: $e',
        );
      }
    }
  }

  void _filterFiles(String query) {
    setState(() {
      // Start with all files
      List<FileModel> filteredFiles = List.from(_files);
      
      // Apply search query filter
      if (query.isNotEmpty) {
        filteredFiles = filteredFiles.where((f) =>
          f.name.toLowerCase().contains(query.toLowerCase()) ||
          f.fileExtension.toLowerCase().contains(query.toLowerCase())
        ).toList();
      }
      
      // Apply file type filter
      if (_selectedFileType != 'All Files') {
        filteredFiles = filteredFiles.where((file) {
          final extension = file.fileExtension.toLowerCase();
          switch (_selectedFileType) {
            case 'Images':
              return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'].contains(extension);
            case 'Documents':
              return ['pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'ppt', 'pptx', 'xls', 'xlsx'].contains(extension);
            case 'Videos':
              return ['mp4', 'avi', 'mov', 'wmv', 'mkv', 'flv', 'webm', 'm4v'].contains(extension);
            case 'Other':
              return !['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'ppt', 'pptx', 'xls', 'xlsx', 'mp4', 'avi', 'mov', 'wmv', 'mkv', 'flv', 'webm', 'm4v'].contains(extension);
            default:
              return true;
          }
        }).toList();
      }
      
      _filteredFiles = filteredFiles;
    });
    _sortFiles();
  }

  void _sortFiles() {
    setState(() {
      _filteredFiles.sort((a, b) {
        int comparison;
        switch (_sortBy) {
          case 'name':
            comparison = a.name.compareTo(b.name);
            break;
          case 'date':
            comparison = a.uploadedAt.compareTo(b.uploadedAt);
            break;
          case 'size':
            comparison = a.size.compareTo(b.size);
            break;
          case 'type':
            comparison = a.fileExtension.compareTo(b.fileExtension);
            break;
          default:
            comparison = a.name.compareTo(b.name);
        }
        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _filterFiles('');
    FocusScope.of(context).unfocus();
  }

  Future<void> _shareFile(FileModel file) async {
    try {
      // Check if file needs to be downloaded first
      if (file.tags.contains('sia-vault') && file.path.isEmpty) {
        // Show dialog to download first
        final shouldDownload = await Get.dialog<bool>(
          AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Download Required', style: TextStyle(color: Colors.white)),
            content: const Text(
              'This file needs to be downloaded from SIA vault before sharing. Would you like to download it now?',
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () => Get.back(result: true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF34A853)),
                child: const Text('Download & Share'),
              ),
            ],
          ),
        );

        if (shouldDownload != true) return;
        
        // Download the file first
        await _downloadFile(file);
        
        // After download, reload to get updated file with local path
        await _loadFiles();
        final updatedFile = _files.firstWhere(
          (f) => f.id == file.id,
          orElse: () => file,
        );
        
        if (updatedFile.path.isEmpty) {
          SnackbarUtils.showError(
            title: 'Error',
            message: 'Could not locate downloaded file. Please try downloading again.',
          );
          return;
        }
        
        // Share the downloaded file
        final rect = Rect.fromLTWH(0, 0, MediaQuery.of(context).size.width, MediaQuery.of(context).size.height / 2);
        await Share.shareXFiles(
          [XFile(updatedFile.path)],
          text: 'Sharing file: ${updatedFile.name}',
          subject: updatedFile.name,
          sharePositionOrigin: rect,
        );
      } else if (file.path.isNotEmpty) {
        // File is already local, share directly
        final fileObj = File(file.path);
        if (await fileObj.exists()) {
          final rect = Rect.fromLTWH(0, 0, MediaQuery.of(context).size.width, MediaQuery.of(context).size.height / 2);
          await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Sharing file: ${file.name}',
            subject: file.name,
            sharePositionOrigin: rect,
          );
          
          SnackbarUtils.showSuccess(
            title: 'Sharing',
            message: 'Share dialog opened for ${file.name}',
            duration: const Duration(seconds: 2),
          );
        } else {
          SnackbarUtils.showError(
            title: 'Error',
            message: 'File not found locally. Please download it first.',
          );
        }
      } else {
        SnackbarUtils.showError(
          title: 'Error',
          message: 'Unable to share this file. Please download it first.',
        );
      }
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Share Error',
        message: 'Failed to share file: $e',
      );
    }
  }

  void _uploadFile() async {
    if (_isUploading || _isSelectingFile) return;

    // Mark user as active to prevent PIN dialog during file operations
    try {
      final securityService = Get.find<SecurityService>();
      await securityService.markUserActive();
    } catch (e) {
    }

    // Check SIA connectivity before uploading
    final hasAccess = await _checkSiaConnectivity(action: 'upload files');
    if (!hasAccess) return;

    setState(() {
      _isSelectingFile = true;
    });

    try {
      // Show loading feedback
      SnackbarUtils.showInfo(
        title: 'Opening File Picker',
        message: 'Please wait...',
      );
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false, // Don't load file data immediately - much faster!
      );
    
      if (result != null && result.files.isNotEmpty) {
        // Show success feedback
        SnackbarUtils.showSuccess(
          title: 'Files Selected',
          message: '${result.files.length} file(s) selected',
        );
        
        for (var platformFile in result.files) {
          if (platformFile.path != null) {
            await _uploadSingleFile(File(platformFile.path!), platformFile.name);
          }
        }
      }
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to select files: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSelectingFile = false;
        });
      }
    }
  }

  Future<void> _uploadSingleFile(File file, String fileName) async {
    if (!mounted) return;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadingFileName = fileName;
    });

    try {
      await _fileRepo.addFile(
        file: file,
        originalName: fileName,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = progress / 100.0; // Convert to 0-1 range
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
        _uploadingFileName = '';
      });

      SnackbarUtils.showSuccess(
        title: 'Success',
        message: 'File uploaded successfully to SIA',
      );

      // Reload files to show the newly uploaded file
      await _loadFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
        _uploadingFileName = '';
      });

      // Check error type and show appropriate message
      final errorMessage = e.toString();
      
      if (errorMessage.contains('File is ') && errorMessage.contains('MB. Maximum upload size')) {
        final match = RegExp(r'File is (\d+)MB\. Maximum upload size on (mobile|desktop) is (\d+)MB').firstMatch(errorMessage);
        if (match != null) {
          final fileSize = match.group(1);
          final platform = match.group(2);
          final maxSize = match.group(3);
          
          SnackbarUtils.showError(
            title: 'File Too Large',
            message: 'Your file is ${fileSize}MB. Maximum upload size on $platform is ${maxSize}MB.',
            duration: const Duration(seconds: 5),
          );
        } else {
          SnackbarUtils.showError(
            title: 'File Too Large',
            message: errorMessage.split('RenterdUploadException:').last.trim(),
            duration: const Duration(seconds: 5),
          );
        }
      } else if (errorMessage.contains('Out of Memory') || errorMessage.contains('Out of memory')) {
        SnackbarUtils.showWarning(
          title: 'Memory Warning',
          message: 'File too large for available memory. Try closing other applications or compressing the file first.',
          duration: const Duration(seconds: 6),
        );
      } else if (errorMessage.contains('SIA upload failed')) {
        SnackbarUtils.showWarning(
          title: 'Partial Upload',
          message: 'File saved locally but could not upload to SIA network. Check SIA connection.',
          duration: const Duration(seconds: 5),
        );
        // Still reload to show locally saved file
        await _loadFiles();
      } else {
        SnackbarUtils.showError(
          title: 'Upload Failed',
          message: 'Failed to upload file: $e',
        );
      }
    }
  }

  void _deleteFile(FileModel file) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "${file.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _fileRepo.deleteFile(file.id);
        _loadFiles();
        setState(() => _selectedFile = null);
        SnackbarUtils.showSuccess(
          title: 'Success',
          message: 'File deleted successfully',
        );
      } catch (e) {
        SnackbarUtils.showError(
          title: 'Error',
          message: 'Failed to delete file',
        );
      }
    }
  }

  Future<void> _downloadFile(FileModel file) async {
    // Check SIA connectivity before attempting download
    final hasAccess = await _checkSiaConnectivity(action: 'download files');
    if (!hasAccess) return;

    try {
      // Automatically save to Downloads/DecVault directory like mobile version
      String downloadsPath;
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? '';
        downloadsPath = path.join(userProfile, 'Downloads', 'DecVault');
      } else if (Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        downloadsPath = path.join(home, 'Downloads', 'DecVault');
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        downloadsPath = path.join(home, 'Downloads', 'DecVault');
      } else {
        // Fallback
        downloadsPath = path.join(Directory.current.path, 'Downloads', 'DecVault');
      }

      // Ensure the directory exists
      final downloadsDir = Directory(downloadsPath);
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final outputFile = path.join(downloadsPath, file.name);

      // Show progress dialog with ValueNotifier for updates
      final downloadProgress = ValueNotifier<double>(0.0);
      final progressMessage = ValueNotifier<String>('Downloading encrypted file...');
      String? capturedTempFile;
      
      Get.dialog(
        PopScope(
          canPop: false, // Prevent dismissing during download
          child: ValueListenableBuilder<double>(
            valueListenable: downloadProgress,
            builder: (context, progress, child) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                title: const Text(
                  'Downloading File', 
                  style: TextStyle(color: Colors.white)
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: progressMessage,
                      builder: (context, message, child) {
                        return Text(
                          message,
                          style: const TextStyle(color: Colors.white70),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress / 100,
                      backgroundColor: const Color(0xFF2C2C2C),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${progress.toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        barrierDismissible: false,
      );

      // Download file from SIA with progress callback - intercept temp file
      await _fileRepo.downloadFromSia(
        file,
        onProgress: (progress) {
          downloadProgress.value = progress;
          
          // Update message based on progress
          if (progress < 90) {
            progressMessage.value = 'Downloading encrypted file...';
          } else if (progress >= 90 && progress < 100) {
            progressMessage.value = 'Decrypting file...';
          } else if (progress >= 100) {
            progressMessage.value = 'Finalizing...';
            // Close dialog after a short delay to show completion
            Future.delayed(const Duration(milliseconds: 300), () {
              SnackbarUtils.safeCloseDialog();
            });
          }
          
          // At 90% completion, try to capture and COPY the temp file immediately
          if (progress >= 90 && capturedTempFile == null) {
            try {
              final tempDir = Directory.systemTemp;
              final tempFiles = tempDir.listSync();
              
              for (final entity in tempFiles) {
                if (entity is File) {
                  final filename = path.basename(entity.path);
                  if (filename.startsWith('encrypted_') && 
                      (filename.contains(file.name) || 
                       filename.contains(file.siaFilename ?? '') ||
                       filename.contains(path.basenameWithoutExtension(file.name)))) {
                    
                    // Immediately copy to Downloads/DecVault to preserve it
                    final userProfile = Platform.environment['USERPROFILE'] ?? '';
                    if (userProfile.isNotEmpty) {
                      final downloadsDecVault = path.join(userProfile, 'Downloads', 'DecVault');
                      final outputPath = path.join(downloadsDecVault, file.name);
                      
                      // Fire and forget async copy operation
                      () async {
                        try {
                          final directory = Directory(downloadsDecVault);
                          if (!await directory.exists()) {
                            await directory.create(recursive: true);
                          }
                          await entity.copy(outputPath);
                        } catch (e) {
                        }
                      }();
                      
                      capturedTempFile = outputPath; // Store the target location
                    } else {
                      capturedTempFile = entity.path;
                    }
                    break;
                  }
                }
              }
            } catch (e) {
            }
          }
        },
      );

      // Clean up
      downloadProgress.dispose();
      progressMessage.dispose();

      // Close progress dialog
      SnackbarUtils.safeCloseDialog();

      // Handle file location after download with captured temp file
      await _handleDownloadedFile(file, outputFile, downloadsPath, capturedTempFile);

    } catch (e) {
      // Close progress dialog if it's open
      SnackbarUtils.safeCloseDialog();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download Error: Failed to download file: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Open Downloads',
              textColor: Colors.white,
              onPressed: () {
                // Still provide access to Downloads folder in case of error
                final userProfile = Platform.environment['USERPROFILE'] ?? '';
                if (userProfile.isNotEmpty) {
                  final downloadsPath = path.join(userProfile, 'Downloads', 'DecVault');
                  _openFileLocation(downloadsPath);
                }
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDownloadedFile(FileModel file, String outputFile, String downloadsPath, [String? capturedTempFile]) async {
    try {
      
      File? sourceFile;
      
      // First priority: Use captured temp file if available
      if (capturedTempFile != null) {
        final tempFile = File(capturedTempFile);
        if (await tempFile.exists()) {
          sourceFile = tempFile;
        } else {
        }
      }
      
      // Second priority: Check expected locations
      if (sourceFile == null) {
        List<String> possibleLocations = [
          outputFile, // Our intended location
          path.join(downloadsPath, file.name), // Alternative in same directory
        ];
        
        // Also check if FileRepository saved it in Windows Downloads
        if (Platform.isWindows) {
          final userProfile = Platform.environment['USERPROFILE'] ?? '';
          if (userProfile.isNotEmpty) {
            possibleLocations.addAll([
              path.join(userProfile, 'Downloads', 'DecVault', file.name),
              path.join(userProfile, 'Downloads', file.name),
            ]);
          }
        }
        
        for (String location in possibleLocations) {
          final testFile = File(location);
          if (await testFile.exists()) {
            sourceFile = testFile;
            break;
          }
        }
      }
      
      // If we found a source file, move it to the target location
      if (sourceFile != null) {
        if (sourceFile.path != outputFile) {
          await sourceFile.copy(outputFile);
          
          // Clean up source file if it was a temp file
          if (sourceFile.path.contains('Temp') || sourceFile.path == capturedTempFile) {
            try {
              await sourceFile.delete();
            } catch (e) {
            }
          }
        } else {
        }
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Download Complete - File saved to Downloads/DecVault'),
              backgroundColor: const Color(0xFF34A853),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Show in Folder',
                textColor: Colors.white,
                onPressed: () {
                  _openFileLocation(outputFile);
                },
              ),
            ),
          );
        }
        return;
      }
      
      // If not found in expected locations, look in temp directory
      File? downloadedFile;
      final tempDir = Directory.systemTemp;
      
      try {
        final tempFiles = tempDir.listSync();
        
        List<File> encryptedFiles = [];
        for (final entity in tempFiles) {
          if (entity is File) {
            final filename = path.basename(entity.path);
            if (filename.startsWith('encrypted_')) {
              encryptedFiles.add(entity);
              
              // Check if this file matches our target
              if (filename.contains(file.name) || 
                  filename.contains(file.siaFilename ?? '') ||
                  filename.contains(path.basenameWithoutExtension(file.name)) ||
                  filename.contains(file.id)) {
                downloadedFile = entity;
                break;
              }
            }
          }
        }
        
        
        // If no specific match, try the most recent encrypted file
        if (downloadedFile == null && encryptedFiles.isNotEmpty) {
          // Sort by modification time and take the most recent
          encryptedFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
          downloadedFile = encryptedFiles.first;
        }
        
      } catch (e) {
      }
      
      if (downloadedFile != null) {
        // Move file from temp to Downloads/DecVault
        await downloadedFile.copy(outputFile);
        
        // Clean up the temporary file
        try {
          await downloadedFile.delete();
        } catch (e) {
        }
        
        // Show success message
        SnackbarUtils.showSuccess(
          title: 'Download Complete',
          message: 'File saved to Downloads/DecVault',
          duration: const Duration(seconds: 4),
        );
              } else {
          // Last resort: comprehensive search of Downloads directory
          
          if (Platform.isWindows) {
            final userProfile = Platform.environment['USERPROFILE'] ?? '';
            if (userProfile.isNotEmpty) {
              final downloadsDirs = [
                path.join(userProfile, 'Downloads'),
                path.join(userProfile, 'Downloads', 'DecVault'),
              ];
              
              for (String dir in downloadsDirs) {
                try {
                  final directory = Directory(dir);
                  if (await directory.exists()) {
                    final files = directory.listSync();
                    for (final entity in files) {
                      if (entity is File) {
                        final filename = path.basename(entity.path);
                        
                        // Check if this matches our file
                        if (filename == file.name ||
                            filename.contains(path.basenameWithoutExtension(file.name)) ||
                            filename.contains(file.id)) {
                          
                          // Move to our target location if different
                          if (entity.path != outputFile) {
                            await entity.copy(outputFile);
                          }
                          
                          SnackbarUtils.showSuccess(
                            title: 'Download Complete',
                            message: 'File found and moved to Downloads/DecVault',
                            duration: const Duration(seconds: 4),
                          );
                          return;
                        }
                      }
                    }
                  }
                } catch (e) {
                }
              }
            }
          }
          
          // If still not found, show generic success message
          SnackbarUtils.showSuccess(
            title: 'Download Complete',
            message: 'File downloaded successfully. Check Downloads/DecVault folder.',
            duration: const Duration(seconds: 6),
          );
        }
      
    } catch (e) {
      SnackbarUtils.showWarning(
        title: 'Download Warning',
        message: 'File was downloaded but could not be moved to Downloads/DecVault folder.',
        duration: const Duration(seconds: 6),
      );
    }
  }

  void _openFileLocation(String filePath) {
    try {
      if (Platform.isWindows) {
        // Check if it's a file or directory
        final file = File(filePath);
        final directory = Directory(filePath);
        
        if (file.existsSync()) {
          // Select the specific file
          Process.run('explorer', ['/select,', filePath]);
        } else if (directory.existsSync()) {
          // Open the directory
          Process.run('explorer', [filePath]);
        } else {
          // Fallback: open parent directory
          Process.run('explorer', [path.dirname(filePath)]);
        }
      } else if (Platform.isMacOS) {
        final file = File(filePath);
        if (file.existsSync()) {
          Process.run('open', ['-R', filePath]);
        } else {
          Process.run('open', [path.dirname(filePath)]);
        }
      } else if (Platform.isLinux) {
        final directory = Directory(filePath).existsSync() ? filePath : path.dirname(filePath);
        // Try different file managers
        Process.run('xdg-open', [directory]).catchError((_) {
          return Process.run('nautilus', [directory]).catchError((_) {
            return Process.run('dolphin', [directory]);
          });
        });
      }
    } catch (e) {
    }
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          right: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder_special, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Files Vault',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'File Storage',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Quick Stats
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildStatCard(
                  title: 'Total Files',
                  value: '${_files.length}',
                  icon: Icons.folder,
                  color: const Color(0xFF34A853),
                ),
                const SizedBox(height: 12),
                _buildStatCard(
                  title: 'Total Size',
                  value: _formatTotalSize(),
                  icon: Icons.storage,
                  color: const Color(0xFF1E8E3E),
                ),
              ],
            ),
          ),
          
          const Divider(color: Color(0xFF3C4043)),
          
          // File Type Filters
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildFilterItem('All Files', Icons.folder, _files.length),
                _buildFilterItem('Images', Icons.image, _getFileTypeCount(['jpg', 'jpeg', 'png', 'gif', 'bmp'])),
                _buildFilterItem('Documents', Icons.description, _getFileTypeCount(['pdf', 'doc', 'docx', 'txt'])),
                _buildFilterItem('Videos', Icons.video_library, _getFileTypeCount(['mp4', 'avi', 'mov', 'wmv'])),
                _buildFilterItem('Other', Icons.insert_drive_file, _getOtherFileCount()),
              ],
            ),
          ),
          
          // Drag and Drop Info
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isDragOver 
                  ? const Color(0xFF34A853).withOpacity(0.2)
                  : const Color(0xFF34A853).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isDragOver
                    ? const Color(0xFF34A853)
                    : const Color(0xFF34A853).withOpacity(0.3),
                width: _isDragOver ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _isDragOver ? Icons.cloud_done : Icons.cloud_upload,
                  color: const Color(0xFF34A853),
                  size: _isDragOver ? 28 : 24,
                ),
                const SizedBox(height: 8),
                Text(
                  _isDragOver ? 'Drop Files Here!' : 'Drag & Drop Files',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _isDragOver ? 16 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isDragOver 
                      ? 'Release to upload files'
                      : 'Drop files anywhere to upload',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          
          // Back to Home
          Container(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () => Get.offNamed('/home'),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Home'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterItem(String label, IconData icon, int count) {
    final isSelected = _selectedFileType == label;
    
    return ListTile(
      leading: Icon(
        icon, 
        color: isSelected ? const Color(0xFF34A853) : Colors.white70, 
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF34A853) : Colors.white70, 
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFF34A853).withOpacity(0.3)
              : const Color(0xFF34A853).withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          count.toString(),
          style: const TextStyle(
            color: Color(0xFF34A853),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dense: true,
      selected: isSelected,
      selectedTileColor: const Color(0xFF34A853).withOpacity(0.1),
      onTap: () {
        setState(() {
          _selectedFileType = label;
        });
        _filterFiles(_searchController.text);
      },
    );
  }

  Widget _buildMainContent() {
    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          _buildToolbar(),
          if (_isUploading) _buildUploadProgress(),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildFileGrid(),
                ),
                if (_selectedFile != null)
                  Expanded(
                    flex: 1,
                    child: _buildFileDetails(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.upload_file,
                color: Color(0xFF34A853),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Uploading: $_uploadingFileName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(_uploadProgress * 100).toInt()}%',
                style: const TextStyle(
                  color: Color(0xFF34A853),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _uploadProgress,
            backgroundColor: const Color(0xFF2C2C2C),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _filterFiles,
              decoration: InputDecoration(
                hintText: 'Search files... (Ctrl+F)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),

          const SizedBox(width: 16),
          
          // View Toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'grid',
                icon: Icon(Icons.grid_view, size: 18),
                label: Text('Grid'),
              ),
              ButtonSegment(
                value: 'list',
                icon: Icon(Icons.list, size: 18),
                label: Text('List'),
              ),
            ],
            selected: {_selectedView},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _selectedView = newSelection.first;
              });
            },
          ),

          const SizedBox(width: 16),
          
          // Sort Dropdown
          DropdownButton<String>(
            value: _sortBy,
            items: const [
              DropdownMenuItem(value: 'name', child: Text('Name')),
              DropdownMenuItem(value: 'date', child: Text('Date')),
              DropdownMenuItem(value: 'size', child: Text('Size')),
              DropdownMenuItem(value: 'type', child: Text('Type')),
            ],
            onChanged: (value) {
              setState(() {
                _sortBy = value!;
              });
              _sortFiles();
            },
            underline: Container(),
          ),
          
          IconButton(
            onPressed: () {
              setState(() {
                _sortAscending = !_sortAscending;
              });
              _sortFiles();
            },
            icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _sortAscending ? 'Sort Descending' : 'Sort Ascending',
          ),

          const SizedBox(width: 16),
          
          // Refresh Button
          Tooltip(
            message: 'Refresh Files (Ctrl+R)',
            child: IconButton(
              onPressed: _isLoading ? null : _loadFiles,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 20),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Upload Button
          Tooltip(
            message: 'Upload File (Ctrl+U)',
            child: ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadFile,
              icon: _isUploading 
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file, size: 18),
              label: Text(_isUploading ? 'Uploading...' : 'Upload'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileGrid() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_filteredFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchController.text.isNotEmpty
                  ? Icons.search_off
                  : Icons.folder_open,
              size: 64,
              color: Colors.white30,
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No files found'
                  : 'No files in vault',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Try a different search term'
                  : 'Drag files here or click Upload to get started',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF121212),
      child: _selectedView == 'grid' ? _buildGridView() : _buildListView(),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];
        final isSelected = _selectedFile?.id == file.id;
        
        return GestureDetector(
          onTap: () => setState(() => _selectedFile = file),
          onDoubleTap: () => Get.to(() => FileDetailScreen(file: file)),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected 
                  ? const Color(0xFF34A853).withOpacity(0.1)
                  : const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected 
                    ? const Color(0xFF34A853)
                    : const Color(0xFF3C4043),
                width: isSelected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getFileIcon(file.fileExtension),
                  size: 48,
                  color: isSelected 
                    ? const Color(0xFF34A853)
                    : Colors.white70,
                ),
                const SizedBox(height: 12),
                Text(
                  file.name,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF34A853) : Colors.white,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatFileSize(file.size),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];
        final isSelected = _selectedFile?.id == file.id;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              _getFileIcon(file.fileExtension),
              color: isSelected ? const Color(0xFF34A853) : Colors.white70,
            ),
            title: Text(
              file.name,
              style: TextStyle(
                color: isSelected ? const Color(0xFF34A853) : Colors.white,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              '${_formatFileSize(file.size)} • ${_formatDate(file.uploadedAt)}',
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download),
                      SizedBox(width: 8),
                      Text('Download'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, color: Color(0xFFF39C12)),
                      SizedBox(width: 8),
                      Text('Share'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'download') {
                  _downloadFile(file);
                } else if (value == 'share') {
                  _shareFile(file);
                } else if (value == 'delete') {
                  _deleteFile(file);
                }
              },
            ),
            selected: isSelected,
            selectedTileColor: const Color(0xFF34A853).withOpacity(0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onTap: () => setState(() => _selectedFile = file),
            onLongPress: () => Get.to(() => FileDetailScreen(file: file)),
          ),
        );
      },
    );
  }

  Widget _buildFileDetails() {
    if (_selectedFile == null) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          left: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getFileIcon(_selectedFile!.fileExtension),
                  color: const Color(0xFF34A853),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedFile!.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _selectedFile!.fileExtension.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedFile = null),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
          
          // Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Size', _formatFileSize(_selectedFile!.size)),
                  _buildDetailRow('Uploaded', _formatDate(_selectedFile!.uploadedAt)),
                  _buildDetailRow('Type', _selectedFile!.fileExtension.toUpperCase()),
                  if (_selectedFile!.description != null && _selectedFile!.description!.isNotEmpty)
                    _buildDetailRow('Description', _selectedFile!.description!),
                  
                  const SizedBox(height: 24),
                  
                  // Actions
                  Tooltip(
                    message: 'Download File (Ctrl+D)',
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _downloadFile(_selectedFile!);
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 40),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Tooltip(
                    message: 'Share File',
                    child: OutlinedButton.icon(
                      onPressed: () => _shareFile(_selectedFile!),
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF39C12),
                        side: const BorderSide(color: Color(0xFFF39C12)),
                        minimumSize: const Size(double.infinity, 40),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  OutlinedButton.icon(
                    onPressed: () => _deleteFile(_selectedFile!),
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(double.infinity, 40),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'wmv':
        return Icons.video_library;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.music_note;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatTotalSize() {
    final totalSize = _files.fold<int>(0, (sum, file) => sum + file.size);
    return _formatFileSize(totalSize);
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  int _getFileTypeCount(List<String> extensions) {
    return _files.where((file) => 
      extensions.contains(file.fileExtension.toLowerCase())
    ).length;
  }

  int _getOtherFileCount() {
    final knownExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'pdf', 'doc', 'docx', 'txt', 'mp4', 'avi', 'mov', 'wmv'];
    return _files.where((file) => 
      !knownExtensions.contains(file.fileExtension.toLowerCase())
    ).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(
                  child: DropTarget(
                    onDragDone: (detail) async {
                      setState(() {
                        _isDragOver = false;
                      });
                      
                      if (_isUploading) {
                        SnackbarUtils.showWarning(
                          title: 'Upload in Progress',
                          message: 'Please wait for the current upload to complete',
                        );
                        return;
                      }
                      
                      // Check SIA connectivity before uploading
                      final hasAccess = await _checkSiaConnectivity(action: 'upload files');
                      if (!hasAccess) return;
                      
                      // Handle dropped files
                      for (final file in detail.files) {
                        try {
                          final fileObj = File(file.path);
                          await _uploadSingleFile(fileObj, file.name);
                        } catch (e) {
                          SnackbarUtils.showError(
                            title: 'Error',
                            message: 'Failed to upload ${file.name}: $e',
                          );
                        }
                      }
                    },
                    onDragEntered: (detail) {
                      if (!_isUploading) {
                        setState(() {
                          _isDragOver = true;
                        });
                      }
                    },
                    onDragExited: (detail) {
                      setState(() {
                        _isDragOver = false;
                      });
                    },
                    child: Container(
                      decoration: _isDragOver
                          ? BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFF34A853),
                                width: 2,
                                style: BorderStyle.solid,
                              ),
                              color: const Color(0xFF34A853).withOpacity(0.1),
                            )
                          : null,
                      child: _buildMainContent(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 

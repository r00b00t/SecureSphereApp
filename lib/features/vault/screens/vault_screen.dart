import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../models/file_model.dart';
import '../repositories/file_repository.dart';
import '../utils/file_utils.dart';
import 'file_detail_screen.dart';
import 'upload_file_screen.dart';
import 'package:decvault/features/sia/services/sia_service.dart';
import 'package:decvault/features/sia/screens/sia_password_required_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decvault/common/widgets/app_drawer.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final FileRepository _fileRepo = Get.find<FileRepository>();
  List<FileModel> _files = [];
  List<FileModel> _filteredFiles = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isPasswordMissing = false;
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = 'date';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _checkInitialSiaAccess();
  }

  /// Safely shows a snackbar using ScaffoldMessenger
  void _safeShowSnackbar({
    required String title,
    required String message,
    Color? backgroundColor,
    Color? colorText,
    Duration? duration,
  }) {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        
        try {
          // Use ScaffoldMessenger which is more reliable than Get.snackbar
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorText ?? Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorText ?? Colors.white,
                      ),
                    ),
                  ],
                ),
                backgroundColor: backgroundColor ?? const Color(0xFF34A853).withValues(alpha: 0.8),
                duration: duration ?? const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } catch (e) {
          // Silent fail - better than crashing the app
        }
      });
    }
  }

  Future<void> _checkInitialSiaAccess() async {
    // Check if SIA password is missing for display purposes
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupOption = prefs.getString('backupOption') ?? 'DecVault';
      
      if (backupOption == 'Self-Hosted SIA Node') {
        final siaService = Get.find<SiaService>();
        final isPasswordMissing = await siaService.isPasswordMissing();
        
        setState(() {
          _isPasswordMissing = isPasswordMissing;
        });
      } else {
        setState(() {
          _isPasswordMissing = false;
        });
      }
    } catch (e) {
      setState(() {
        _isPasswordMissing = false;
      });
    }
    
    // Check if SIA access is available before loading files
    final hasAccess = await _checkSiaConnectivity();
    if (hasAccess) {
      _loadFiles();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _checkSiaConnectivity({String? action}) async {
    if (!_fileRepo.isSiaUploadAvailable) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action != null 
              ? 'Cannot $action. Please go to Settings → Backup & Storage → Connect your SIA node first.'
              : 'SIA is not connected. Please go to Settings → Backup & Storage to connect your SIA node.'),
            backgroundColor: Colors.orange.withValues(alpha: 0.8),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () {
                Get.offAllNamed('/settings');
              },
            ),
          ),
        );
      }
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
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(action != null 
                  ? 'Cannot $action. Your self-hosted SIA node requires a password.'
                  : 'Access denied. Your self-hosted SIA node requires a password.'),
                backgroundColor: Colors.red.withValues(alpha: 0.8),
                duration: const Duration(seconds: 6),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Add Password',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SiaPasswordRequiredScreen(),
                      ),
                    );
                  },
                ),
              ),
            );
          }
          return false;
        }
      }
    } catch (e) {
    }
    
    return true;
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load files directly from SIA vault bucket (actual vault contents)
      if (_fileRepo.isSiaUploadAvailable) {
        final siaVaultFiles = await _fileRepo.getSiaVaultFiles();
        
        // Also include locally uploaded files that failed SIA upload
        final allFiles = await _fileRepo.getAllFiles();
        final localFailedFiles = allFiles.where((file) => 
          file.tags.contains('sia-upload-failed')
        ).toList();
        
        // Combine SIA files and locally failed files
        final combinedFiles = [...siaVaultFiles, ...localFailedFiles];
        
        setState(() {
          _files = combinedFiles;
          _filteredFiles = List.from(combinedFiles);
          _isLoading = false;
        });
      } else {
        // Fallback to local files if SIA not available
        final allFiles = await _fileRepo.getAllFiles();
        final siaFiles = allFiles.where((file) => 
          file.tags.contains('sia-uploaded') ||
          file.tags.contains('sia-synced') ||
          file.tags.contains('sia-vault') ||
          file.tags.contains('sia-upload-failed')
        ).toList();
        
        setState(() {
          _files = siaFiles;
          _filteredFiles = List.from(siaFiles);
          _isLoading = false;
        });
      }
      
      _sortFiles();
    } catch (e) {
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
        _safeShowSnackbar(
          title: 'SIA Connection Required',
          message: 'Unable to load vault files. Please go to Settings → Backup & Storage and connect your SIA node first.',
          backgroundColor: Colors.orange.withValues(alpha: 0.8),
          colorText: Colors.white,
          duration: const Duration(seconds: 6),
        );
      } else {
        _safeShowSnackbar(
          title: 'Error',
          message: 'Failed to load vault files: $e',
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          colorText: Colors.white,
        );
      }
    }
  }

  void _filterFiles(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredFiles = List.from(_files);
      } else {
        _filteredFiles = _files.where((file) {
          return file.name.toLowerCase().contains(query.toLowerCase()) ||
                 file.mimeType.toLowerCase().contains(query.toLowerCase()) ||
                 (file.description?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
      _sortFiles();
    });
  }

  void _sortFiles() {
    setState(() {
      _filteredFiles.sort((a, b) {
        int result = 0;
        switch (_sortBy) {
          case 'name':
            result = a.name.compareTo(b.name);
            break;
          case 'size':
            result = a.size.compareTo(b.size);
            break;
          case 'date':
          default:
            result = a.uploadedAt.compareTo(b.uploadedAt);
            break;
        }
        return _sortAscending ? result : -result;
      });
    });
  }

  Future<void> _syncWithSia() async {
    if (!await _checkSiaConnectivity(action: 'sync with SIA')) {
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      await _fileRepo.syncFromSiaBucket();
      await _loadFiles();
      
      _safeShowSnackbar(
        title: 'Success',
        message: 'Vault synced with SIA successfully',
        backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    } catch (e) {
      _safeShowSnackbar(
        title: 'Error',
        message: 'Error syncing from SIA: $e',
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  Future<void> _downloadFromSia(FileModel file) async {
    // Check SIA connectivity before attempting download
    if (!await _checkSiaConnectivity(action: 'download files')) {
      return;
    }
    
    double downloadProgress = 0.0;
    String progressMessage = 'Downloading file...';
    StateSetter? dialogSetState;
    
    try {
      final isLargeFile = file.size > (5 * 1024 * 1024); // > 5MB
      if (isLargeFile) {
        progressMessage = 'This may take a moment for large files...';
      }
      
      // Show progress dialog that can be updated
      Get.dialog(
        StatefulBuilder(
          builder: (context, setDialogState) {
            dialogSetState = setDialogState; // Store the setState function
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text('Downloading File', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    progressMessage,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: downloadProgress / 100,
                    backgroundColor: Colors.grey[700],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${downloadProgress.toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            );
          }
        ),
        barrierDismissible: false,
      );

      // Download file from SIA with progress callback
      final stopwatch = Stopwatch()..start();
      await _fileRepo.downloadFromSia(
        file, 
        onProgress: (progress) {
          downloadProgress = progress;
          
          // Update message based on progress
          if (progress < 90) {
            progressMessage = 'Downloading encrypted file...';
          } else if (progress >= 90 && progress < 100) {
            progressMessage = 'Decrypting file...';
          } else {
            progressMessage = 'Download complete!';
          }
          
          // Update the dialog without recreating it
          if (dialogSetState != null) {
            dialogSetState!(() {});
          }
        },
      );
      stopwatch.stop();
      
      // Files are downloaded to DecVault folder in Downloads
      final downloadPath = '/storage/emulated/0/Download/DecVault';
      
      // For small files, ensure dialog is visible for at least 500ms
      final minDisplayTime = 500;
      final elapsed = stopwatch.elapsedMilliseconds;

      if (elapsed < minDisplayTime) {
        await Future.delayed(Duration(milliseconds: minDisplayTime - elapsed));
      }
      
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      
      await Future.delayed(const Duration(milliseconds: 100));
      await _loadFiles();
      
      _safeShowSnackbar(
        title: 'Download Complete',
        message: _getDownloadSuccessMessage(file.name, downloadPath),
        backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
        colorText: Colors.white,
        duration: const Duration(seconds: 8),
      );
    } catch (e) {
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      
      // Check error type and show appropriate message
      final errorMessage = e.toString();
      String title = 'Download Failed';
      String message = 'Error downloading file: $e';
      
      if (errorMessage.contains('Out of Memory') || errorMessage.contains('Out of memory')) {
        title = 'Memory Error';
        message = 'File too large for available memory. Try: 1) Close other apps, 2) Restart device, 3) Download on desktop, 4) Free up storage.';
      } else if (errorMessage.contains('No space left')) {
        title = 'Storage Full';
        message = 'Not enough storage space. Free up some space and try again.';
      }
      
      _safeShowSnackbar(
        title: title,
        message: message,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
      );
    }
  }

  String _getDownloadSuccessMessage(String fileName, String filePath) {
    if (fileName.toLowerCase().endsWith('.jpg') || 
        fileName.toLowerCase().endsWith('.jpeg') || 
        fileName.toLowerCase().endsWith('.png') ||
        fileName.toLowerCase().endsWith('.gif') ||
        fileName.toLowerCase().endsWith('.mp4') ||
        fileName.toLowerCase().endsWith('.avi')) {
      return 'File saved successfully! Check Downloads/DecVault folder or Gallery for "$fileName".';
    }
    return 'File saved successfully! Check Downloads/DecVault folder or file manager for "$fileName".';
  }

  void _showUploadSuccessNotification(String fileName) {
    _safeShowSnackbar(
      title: 'Upload Complete',
      message: 'File "$fileName" has been uploaded and encrypted successfully.',
      backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
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
        await _downloadFromSia(file);
        
        // After download, reload to get updated file with local path
        await _loadFiles();
        final updatedFile = _files.firstWhere(
          (f) => f.id == file.id,
          orElse: () => file,
        );
        
        if (updatedFile.path.isEmpty) {
          _safeShowSnackbar(
            title: 'Error',
            message: 'Could not locate downloaded file. Please try downloading again.',
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            colorText: Colors.white,
          );
          return;
        }
        
        // Share the downloaded file
        await Share.shareXFiles(
          [XFile(updatedFile.path)],
          text: 'Sharing file: ${updatedFile.name}',
          subject: updatedFile.name,
        );
      } else if (file.path.isNotEmpty) {
        // File is already local, share directly
        final fileObj = File(file.path);
        if (await fileObj.exists()) {
          await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Sharing file: ${file.name}',
            subject: file.name,
          );
          
          _safeShowSnackbar(
            title: 'Sharing',
            message: 'Share dialog opened for ${file.name}',
            backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        } else {
          _safeShowSnackbar(
            title: 'Error',
            message: 'File not found locally. Please download it first.',
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            colorText: Colors.white,
          );
        }
      } else {
        _safeShowSnackbar(
          title: 'Error',
          message: 'Unable to share this file. Please download it first.',
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          colorText: Colors.white,
        );
      }
    } catch (e) {
      _safeShowSnackbar(
        title: 'Share Error',
        message: 'Failed to share file: $e',
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        elevation: 0,
        title: const Text('Files Vault', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_fileRepo.isSiaUploadAvailable)
            IconButton(
              icon: _isSyncing 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
                    ),
                  )
                : const Icon(Icons.sync, color: Color(0xFF34A853)),
              onPressed: _isSyncing ? null : _syncWithSia,
              tooltip: 'Sync with SIA',
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Colors.white),
            color: const Color(0xFF1E1E1E),
            onSelected: (value) {
              setState(() {
                if (_sortBy == value) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = value;
                  _sortAscending = false;
                }
              });
              _sortFiles();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    const Icon(Icons.date_range, color: Color(0xFF34A853)),
                    const SizedBox(width: 8),
                    Text('Sort by Date', style: TextStyle(color: Colors.white)),
                    if (_sortBy == 'date') Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, color: Color(0xFF34A853), size: 16),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    const Icon(Icons.abc, color: Color(0xFF34A853)),
                    const SizedBox(width: 8),
                    Text('Sort by Name', style: TextStyle(color: Colors.white)),
                    if (_sortBy == 'name') Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, color: Color(0xFF34A853), size: 16),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'size',
                child: Row(
                  children: [
                    const Icon(Icons.storage, color: Color(0xFF34A853)),
                    const SizedBox(width: 8),
                    Text('Sort by Size', style: TextStyle(color: Colors.white)),
                    if (_sortBy == 'size') Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, color: Color(0xFF34A853), size: 16),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF121212),
              const Color(0xFF1E1E1E),
              Theme.of(context).primaryColor.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: Column(
          children: [
            Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E1E1E),
            child: TextField(
              controller: _searchController,
              onChanged: _filterFiles,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search files...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF34A853)),
                suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        _filterFiles('');
                      },
                    )
                  : null,
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF34A853), width: 2),
                ),
              ),
            ),
          ),
          // SIA Connection Notice
          if (!_fileRepo.isSiaUploadAvailable)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SIA Not Connected',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Showing cached files only. Connect to SIA in Settings to upload/download files.',
                          style: TextStyle(color: Colors.orange.withValues(alpha: 0.8), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Get.offAllNamed('/settings');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Settings'),
                  ),
                ],
              ),
            ),
          // SIA Password Notice
          if (_isPasswordMissing && _fileRepo.isSiaUploadAvailable)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SIA Password Required',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your self-hosted SIA node requires a password to access the vault.',
                          style: TextStyle(color: Colors.red.withValues(alpha: 0.8), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      try {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SiaPasswordRequiredScreen(),
                          ),
                        );
                      } catch (e) {
                        // Last resort - use Get.to with widget
                        try {
                          Get.to(() => const SiaPasswordRequiredScreen());
                        } catch (e2) {
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Add Password'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading vault files...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : _filteredFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'No files in SIA vault',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Upload files to see them here',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadFiles,
                    color: const Color(0xFF34A853),
                    backgroundColor: const Color(0xFF1E1E1E),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredFiles.length,
                      itemBuilder: (context, index) {
                        final file = _filteredFiles[index];
                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.2),
                              child: Icon(
                                FileUtils.getFileIcon(file.mimeType),
                                color: const Color(0xFF34A853),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    file.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (file.tags.contains('sia-uploaded'))
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF34A853).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'SIA Backup',
                                      style: TextStyle(
                                        color: Color(0xFF34A853),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (file.tags.contains('sia-synced'))
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2196F3).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'SIA Only',
                                      style: TextStyle(
                                        color: Color(0xFF2196F3),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '${file.formattedSize} • ${DateFormat('MMM dd, yyyy').format(file.uploadedAt)}',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                                if (file.description != null && file.description!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    file.description!,
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white),
                              color: const Color(0xFF1E1E1E),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'view',
                                  child: Row(
                                    children: [
                                      Icon(Icons.visibility, color: Color(0xFF34A853)),
                                      SizedBox(width: 8),
                                      Text('View Details', style: TextStyle(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                if (file.tags.contains('sia-vault'))
                                  const PopupMenuItem(
                                    value: 'download',
                                    child: Row(
                                      children: [
                                        Icon(Icons.download, color: Color(0xFF2196F3)),
                                        SizedBox(width: 8),
                                        Text('Download', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'share',
                                  child: Row(
                                    children: [
                                      Icon(Icons.share, color: Color(0xFFF39C12)),
                                      SizedBox(width: 8),
                                      Text('Share', style: TextStyle(color: Colors.white)),
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
                              onSelected: (value) async {
                                if (value == 'view') {
                                  final result = await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => FileDetailScreen(file: file),
                                    ),
                                  );
                                  if (result == true) {
                                    _loadFiles();
                                  }
                                } else if (value == 'download') {
                                  await _downloadFromSia(file);
                                } else if (value == 'share') {
                                  await _shareFile(file);
                                } else if (value == 'delete') {
                                  _showDeleteDialog(file);
                                }
                              },
                            ),
                            onTap: () async {
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => FileDetailScreen(file: file),
                                ),
                              );
                              if (result == true) {
                                _loadFiles();
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Check SIA connectivity before allowing upload
          if (!await _checkSiaConnectivity(action: 'upload files')) {
            return;
          }
          
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const UploadFileScreen(),
            ),
          );
          if (result != null && result is String) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.sync, color: Colors.white),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Upload Processing', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('File uploaded! Syncing vault to show updated contents...', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: const Color(0xFF2196F3).withValues(alpha: 0.9),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            
            await Future.delayed(const Duration(seconds: 2));
            await _loadFiles();
            
            _showUploadSuccessNotification(result);
          }
        },
        backgroundColor: const Color(0xFF34A853),
        label: const Text('Upload File', style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showDeleteDialog(FileModel file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete File', style: TextStyle(color: Colors.white)),
        content: Text(
          _fileRepo.isSiaUploadAvailable
            ? 'Are you sure you want to delete "${file.name}"?\n\nThis will remove the file from both your local storage and SIA vault. This action cannot be undone.'
            : 'Are you sure you want to delete "${file.name}"?\n\nThis will remove the file from your local storage only (SIA not connected). This action cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF34A853))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _fileRepo.deleteFile(file.id);
                _loadFiles();
                _safeShowSnackbar(
                  title: 'Success',
                  message: _fileRepo.isSiaUploadAvailable
                    ? 'File deleted successfully from local storage and SIA vault'
                    : 'File deleted successfully from local storage (SIA not connected)',
                  backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
                  colorText: Colors.white,
                );
              } catch (e) {
                _safeShowSnackbar(
                  title: 'Error',
                  message: 'Failed to delete file: $e',
                  backgroundColor: Colors.red.withValues(alpha: 0.8),
                  colorText: Colors.white,
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
} 

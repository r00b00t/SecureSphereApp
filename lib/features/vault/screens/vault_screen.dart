import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
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
  String? _nodeNotConfiguredMessage;
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = 'date';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _checkInitialSiaAccess();
  }

  Future<void> _checkInitialSiaAccess() async {
    // Check if SIA password is missing for display purposes
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupOption = prefs.getString('backupOption') ?? 'SecureSphere';
      
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
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _checkSiaConnectivity({String? action}) async {
    if (!_fileRepo.isSiaUploadAvailable) {
      Get.snackbar(
        'SIA Not Connected',
        action != null 
          ? 'Cannot $action. Please go to Settings → Backup & Storage → Connect your SIA node first.'
          : 'SIA is not connected. Please go to Settings → Backup & Storage to connect your SIA node.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.withValues(alpha: 0.8),
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
        mainButton: TextButton(
          onPressed: () {
            Get.back(); // Close snackbar
            Get.offAllNamed('/settings');
          },
          child: const Text('Go to Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
      return false;
    }

    // Additional check for SIA password when using self-hosted
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupOption = prefs.getString('backupOption') ?? 'SecureSphere';
      
      if (backupOption == 'Self-Hosted SIA Node') {
        final siaService = Get.find<SiaService>();
        final isPasswordMissing = await siaService.isPasswordMissing();
        
        if (isPasswordMissing) {
          Get.snackbar(
            'SIA Password Required',
            action != null 
              ? 'Cannot $action. Your self-hosted SIA node requires a password.'
              : 'Access denied. Your self-hosted SIA node requires a password.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            colorText: Colors.white,
            duration: const Duration(seconds: 6),
            mainButton: TextButton(
              onPressed: () {
                Get.back(); // Close snackbar
                if (!mounted) return;
                try {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SiaPasswordRequiredScreen(),
                    ),
                  );
                } catch (e) {
                  try {
                    Get.to(() => const SiaPasswordRequiredScreen());
                  } catch (e2) {
                    // ignore
                  }
                }
              },
              child: const Text('Add Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          );
          return false;
        }
      }
    } catch (e) {
      // ignore
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
        
        setState(() {
          _files = siaVaultFiles;
          _filteredFiles = List.from(siaVaultFiles);
          _isLoading = false;
        });
      } else {
        // Fallback to local files if SIA not available
        final allFiles = await _fileRepo.getAllFiles();
        final siaFiles = allFiles.where((file) => 
          file.tags.contains('sia-uploaded') ||
          file.tags.contains('sia-synced') ||
          file.tags.contains('sia-vault')
        ).toList();
        
        setState(() {
          _files = siaFiles;
          _filteredFiles = List.from(siaFiles);
          _isLoading = false;
        });
      }
      
      _sortFiles();
    } catch (e) {
      setState(() => _isLoading = false);

      final errorMessage = e.toString();

      // "not configured" means the node host is blank — show persistent banner.
      if (errorMessage.contains('not configured') || errorMessage.contains('No Sia node assigned')) {
        final prefs = await SharedPreferences.getInstance();
        final appMode = prefs.getString('app_mode') ?? 'managed';
        final msg = appMode == 'decentralized'
            ? 'Go to Settings to connect your Sia node.'
            : 'No Sia node assigned yet. Please contact support or add a node in Settings.';
        setState(() => _nodeNotConfiguredMessage = msg);
        return;
      }

      final isSiaError = !_fileRepo.isSiaUploadAvailable ||
          errorMessage.contains('SIA') ||
          errorMessage.contains('sia') ||
          errorMessage.contains('connection') ||
          errorMessage.contains('network');

      if (isSiaError) {
        Get.snackbar(
          'SIA Connection Required',
          'Unable to load vault files. Please go to Settings → Backup & Storage and connect your SIA node first.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange.withValues(alpha: 0.8),
          colorText: Colors.white,
          duration: const Duration(seconds: 6),
          mainButton: TextButton(
            onPressed: () {
              Get.back();
              Get.offAllNamed('/settings');
            },
            child: const Text('Go to Settings',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        );
      } else {
        Get.snackbar(
          'Error',
          'Failed to load vault files: $e',
          snackPosition: SnackPosition.BOTTOM,
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
      
      Get.snackbar(
        'Success',
        'Vault synced with SIA successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Error syncing from SIA: $e',
        snackPosition: SnackPosition.BOTTOM,
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
      
      // Files are downloaded to SecureSphere folder in Downloads
      final downloadPath = '/storage/emulated/0/Download/SecureSphere';
      
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
      
      Get.snackbar(
        'Download Complete',
        _getDownloadSuccessMessage(file.name, downloadPath),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
        colorText: Colors.white,
        duration: const Duration(seconds: 8),
      );
    } catch (e) {
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      
      Get.snackbar(
        'Download Error', 
        'Failed to download file: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
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
      return 'File saved successfully! Check Downloads/DecVault folder or Gallery for "$fileName". Check console logs for exact location.';
    }
    return 'File saved successfully! Check Downloads/DecVault folder or file manager for "$fileName". Check console logs for exact location.';
  }

  void _showUploadSuccessNotification(String fileName) {
    Get.snackbar(
      'Upload Complete',
      'File "$fileName" has been uploaded and encrypted successfully.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      icon: const Icon(Icons.check_circle, color: Colors.white),
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
          Get.snackbar(
            'Error',
            'Could not locate downloaded file. Please try downloading again.',
            snackPosition: SnackPosition.BOTTOM,
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
          
          Get.snackbar(
            'Sharing',
            'Share dialog opened for ${file.name}',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        } else {
          Get.snackbar(
            'Error',
            'File not found locally. Please download it first.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            colorText: Colors.white,
          );
        }
      } else {
        Get.snackbar(
          'Error',
          'Unable to share this file. Please download it first.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Share Error',
        'Failed to share file: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text('Secure Vault', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      body: Column(
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
          // Node-not-configured notice (host is blank — new managed user or missing setup)
          if (_nodeNotConfiguredMessage != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings_ethernet,
                      color: Colors.blue, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Vault Unavailable',
                            style: TextStyle(
                                color: Colors.blue,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(_nodeNotConfiguredMessage!,
                            style:
                                const TextStyle(color: Colors.blue, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Get.offAllNamed('/settings'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white),
                    child: const Text('Settings'),
                  ),
                ],
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
                        try {
                          Get.to(() => const SiaPasswordRequiredScreen());
                        } catch (e2) {
                          // ignore
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
            Get.snackbar(
              'Upload Processing',
              'File uploaded! Syncing vault to show updated contents...',
              snackPosition: SnackPosition.TOP,
              backgroundColor: const Color(0xFF2196F3).withValues(alpha: 0.9),
              colorText: Colors.white,
              duration: const Duration(seconds: 2),
              icon: const Icon(Icons.sync, color: Colors.white),
            );
            
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
                Get.snackbar(
                  'Success',
                  _fileRepo.isSiaUploadAvailable
                    ? 'File deleted successfully from local storage and SIA vault'
                    : 'File deleted successfully from local storage (SIA not connected)',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: const Color(0xFF34A853).withValues(alpha: 0.8),
                  colorText: Colors.white,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  'Failed to delete file: $e',
                  snackPosition: SnackPosition.BOTTOM,
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
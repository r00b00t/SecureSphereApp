import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get/get.dart';
import '../repositories/file_repository.dart';
import 'package:decvault/core/utils/snackbar_utils.dart';

class UploadFileScreen extends StatefulWidget {
  const UploadFileScreen({super.key});

  @override
  State<UploadFileScreen> createState() => _UploadFileScreenState();
}

class _UploadFileScreenState extends State<UploadFileScreen> {
  final FileRepository _fileRepo = Get.find<FileRepository>();
  File? _selectedFile;
  String _fileName = '';
  String _description = '';
  bool _isUploading = false;
  bool _isSelectingFile = false;

  Future<void> _pickFile() async {
    setState(() {
      _isSelectingFile = true;
    });
    
    try {
      // Show loading feedback
      SnackbarUtils.showInfo(
        title: 'Loading File',
        message: 'Please wait',
      );
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false, // Don't load file data immediately - much faster!
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _fileName = result.files.single.name;
        });
        
        // Show success feedback
        SnackbarUtils.showSuccess(
          title: 'File Selected',
          message: _fileName,
        );
      }
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to pick file: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSelectingFile = false;
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() {
      _isSelectingFile = true;
    });
    
    try {
      final ImagePicker picker = ImagePicker();
      
      // Show options for photos or videos
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: const Color(0xFF1E1E1E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Color(0xFF34A853)),
                  title: const Text('Photo Library', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Color(0xFF34A853)),
                  title: const Text('Camera', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ],
            ),
          );
        },
      );

      if (source == null) return;

      final XFile? pickedFile = await picker.pickImage(source: source);
      
      if (pickedFile != null) {
        setState(() {
          _selectedFile = File(pickedFile.path);
          _fileName = pickedFile.name;
        });
        
        SnackbarUtils.showSuccess(
          title: 'File Selected',
          message: _fileName,
        );
      }
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to pick from gallery: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSelectingFile = false;
        });
      }
    }
  }

  Future<void> _pickVideo() async {
    setState(() {
      _isSelectingFile = true;
    });
    
    try {
      final ImagePicker picker = ImagePicker();
      
      // Show options for video source
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: const Color(0xFF1E1E1E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.video_library, color: Color(0xFF34A853)),
                  title: const Text('Video Library', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam, color: Color(0xFF34A853)),
                  title: const Text('Record Video', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ],
            ),
          );
        },
      );

      if (source == null) return;

      final XFile? pickedFile = await picker.pickVideo(source: source);
      
      if (pickedFile != null) {
        setState(() {
          _selectedFile = File(pickedFile.path);
          _fileName = pickedFile.name;
        });
        
        SnackbarUtils.showSuccess(
          title: 'File Selected',
          message: _fileName,
        );
      }
    } catch (e) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Failed to pick video: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSelectingFile = false;
        });
      }
    }
  }

  Future<void> _uploadFile() async {
    
    if (_selectedFile == null || _fileName.isEmpty) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Please select a file first',
      );
      return;
    }

    // Check if file exists
    if (!await _selectedFile!.exists()) {
      SnackbarUtils.showError(
        title: 'Error',
        message: 'Selected file no longer exists',
      );
      return;
    }

    // Show upload progress dialog
    double dialogProgress = 0.0;
    String dialogStage = 'Preparing file...';
    StateSetter? dialogSetState;
    
    Get.dialog(
      StatefulBuilder(
        builder: (context, setDialogState) {
          dialogSetState = setDialogState;
          return WillPopScope(
            onWillPop: () async => false, // Prevent dismissing during upload
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text(
                'Uploading File',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dialogStage,
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: dialogProgress / 100),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    builder: (context, double value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.grey[700],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: dialogProgress),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    builder: (context, double value, child) {
                      return Text(
                        '${value.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      barrierDismissible: false,
    );

    try {
      final fileModel = await _fileRepo.addFile(
        file: _selectedFile!,
        originalName: _fileName,
        description: _description.isEmpty ? null : _description,
        onProgress: (progress) {
          dialogProgress = progress;
          
          // Update stage message for smoother UX
          if (progress < 10) {
            dialogStage = 'Preparing file...';
          } else if (progress < 40) {
            dialogStage = 'Encrypting file...';
          } else if (progress < 75) {
            dialogStage = 'Saving locally...';
          } else if (progress < 100) {
            dialogStage = 'Uploading to SIA network...';
          } else {
            dialogStage = 'Upload complete!';
          }
          
          // Update the dialog
          if (dialogSetState != null) {
            dialogSetState!(() {});
          }
        },
      );

      // Close progress dialog
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      
      // Check if upload was successful
      
      if (fileModel.id.isNotEmpty) {
        // Check if file has sia-uploaded tag to confirm SIA upload
        if (fileModel.tags.contains('sia-uploaded')) {
          SnackbarUtils.showSuccess(
            title: 'Upload Complete',
            message: 'File uploaded successfully to SIA network',
          );
        } else if (fileModel.tags.contains('sia-upload-failed')) {
          SnackbarUtils.showWarning(
            title: 'Partial Upload',
            message: 'File saved locally but SIA upload failed. Check SIA connection.',
            duration: const Duration(seconds: 5),
          );
        }
        Get.back(result: _fileName);
      } else {
        throw Exception('Upload failed - no file model returned');
      }
    } catch (e) {
      // Close progress dialog on error
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      
      // Check error type and show appropriate message
      final errorMessage = e.toString();
      
      if (errorMessage.contains('File is ') && errorMessage.contains('MB. Maximum upload size')) {
        // Extract clean file size limit message
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
          title: 'Memory Error',
          message: 'File too large for available memory. Try: 1) Close other apps, 2) Restart device, 3) Compress the file, or 4) Use desktop version.',
          duration: const Duration(seconds: 7),
        );
      } else if (errorMessage.contains('SIA upload failed')) {
        SnackbarUtils.showWarning(
          title: 'Partial Upload',
          message: 'File saved locally but could not upload to SIA. Check logs for details.',
          duration: const Duration(seconds: 5),
        );
        // Still return success so vault reloads
        Get.back(result: _fileName);
      } else {
        SnackbarUtils.showError(
          title: 'Upload Failed',
          message: 'Failed to upload file: $e',
        );
      }
    } finally {
      // Ensure dialog is closed
      if (Get.isDialogOpen == true) {
        Get.back();
      }
      
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Widget _buildSelectionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool fullWidth = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 36,
              color: onTap != null ? const Color(0xFF34A853) : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? Colors.white : Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text('Upload File', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File size limit banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF34A853).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF34A853).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF34A853),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      Platform.isAndroid || Platform.isIOS
                          ? 'Maximum upload size: 200 MB'
                          : 'Maximum upload size: 1 GB (1024 MB)',
                      style: const TextStyle(
                        color: Color(0xFF34A853),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Text(
              'Select File',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Loading indicator during file selection
            if (_isSelectingFile) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Loading File',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please wait',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
            // Selected file display (if any)
            if (_selectedFile != null && !_isSelectingFile) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF34A853),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 48,
                      color: Color(0xFF34A853),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _fileName,
                      style: const TextStyle(
                        color: Color(0xFF34A853),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<int>(
                      future: _selectedFile!.length(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final size = snapshot.data!;
                          String sizeText;
                          if (size < 1024) {
                            sizeText = '$size B';
                          } else if (size < 1024 * 1024) {
                            sizeText = '${(size / 1024).toStringAsFixed(1)} KB';
                          } else if (size < 1024 * 1024 * 1024) {
                            sizeText = '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
                          } else {
                            sizeText = '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
                          }
                          return Text(
                            'Size: $sizeText',
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Selection buttons
            Row(
              children: [
                Expanded(
                  child: _buildSelectionButton(
                    icon: Icons.photo_library,
                    label: 'Photos',
                    onTap: (_isUploading || _isSelectingFile) ? null : _pickFromGallery,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSelectionButton(
                    icon: Icons.videocam,
                    label: 'Videos',
                    onTap: (_isUploading || _isSelectingFile) ? null : _pickVideo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSelectionButton(
              icon: Icons.insert_drive_file,
              label: 'Browse Files',
              onTap: (_isUploading || _isSelectingFile) ? null : _pickFile,
              fullWidth: true,
            ),
            const SizedBox(height: 32),
            const Text(
              'File Name',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              enabled: !_isUploading,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter file name',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF34A853), width: 2),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _fileName = value;
                });
              },
              controller: TextEditingController(text: _fileName)..selection = TextSelection.fromPosition(TextPosition(offset: _fileName.length)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Description (Optional)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              enabled: !_isUploading,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter file description',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF34A853), width: 2),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _description = value;
                });
              },
            ),
            const SizedBox(height: 32),
            // Upload button (progress shown in popup dialog)
            if (!_isUploading) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedFile != null && _fileName.isNotEmpty ? _uploadFile : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34A853),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Upload to Vault',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF34A853), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Files are automatically encrypted and stored securely on the SIA network.',
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} 
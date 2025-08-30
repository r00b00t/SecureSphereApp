import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import '../repositories/file_repository.dart';

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
  double _uploadProgress = 0.0;

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _fileName = result.files.single.name;
        });
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to pick file: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null || _fileName.isEmpty) {
      Get.snackbar(
        'Error',
        'Please select a file first',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final fileModel = await _fileRepo.addFile(
        file: _selectedFile!,
        originalName: _fileName,
        description: _description.isEmpty ? null : _description,
        onProgress: (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      if (fileModel.id.isNotEmpty) {
        Get.back(result: _fileName);
      } else {
        throw Exception('Upload failed - no file model returned');
      }
    } catch (e) {
      Get.snackbar(
        'Upload Failed',
        'Failed to upload file: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
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
            const Text(
              'Select File',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _isUploading ? null : _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedFile != null 
                        ? const Color(0xFF34A853) 
                        : Colors.grey.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFile != null ? Icons.check_circle : Icons.cloud_upload,
                      size: 48,
                      color: _selectedFile != null 
                          ? const Color(0xFF34A853) 
                          : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _selectedFile != null 
                          ? 'File Selected: $_fileName'
                          : 'Tap to select a file',
                      style: TextStyle(
                        color: _selectedFile != null 
                            ? const Color(0xFF34A853)
                            : Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_selectedFile != null) ...[
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
                  ],
                ),
              ),
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
            if (_isUploading) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Uploading and Encrypting...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your file is being securely uploaded to SIA network',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _uploadProgress / 100,
                      backgroundColor: Colors.grey[700],
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34A853)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_uploadProgress.toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ] else ...[
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
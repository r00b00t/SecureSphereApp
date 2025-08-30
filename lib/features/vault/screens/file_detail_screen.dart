import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/file_model.dart';
import '../repositories/file_repository.dart';
import '../utils/file_utils.dart';

class FileDetailScreen extends StatefulWidget {
  final FileModel file;

  const FileDetailScreen({super.key, required this.file});

  @override
  State<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends State<FileDetailScreen> {
  final FileRepository _fileRepo = Get.find<FileRepository>();
  late FileModel _file;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text('File Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_file.path.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: () => _shareFile(context),
            ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _showDeleteDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File preview/icon section
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  FileUtils.getFileIcon(_file.mimeType),
                  size: 60,
                  color: const Color(0xFF34A853),
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            // File information cards
            _buildInfoCard('File Name', _file.name),
            const SizedBox(height: 16),
            
            _buildInfoCard('Original Name', _file.originalName),
            const SizedBox(height: 16),
            
            _buildInfoCard('File Size', _file.formattedSize),
            const SizedBox(height: 16),
            
            _buildInfoCard('File Type', _getMimeTypeDescription(_file.mimeType)),
            const SizedBox(height: 16),
            
            _buildInfoCard('Upload Date', DateFormat('MMMM dd, yyyy \'at\' HH:mm').format(_file.uploadedAt)),
            const SizedBox(height: 16),
            
            if (_file.description != null && _file.description!.isNotEmpty) ...[
              _buildInfoCard('Description', _file.description!),
              const SizedBox(height: 16),
            ],
            
            _buildInfoCard('Encryption', _file.isEncrypted ? 'AES-256 Encrypted' : 'Not Encrypted'),
            const SizedBox(height: 16),
            
            // Storage location
            _buildInfoCard('Storage Location', _getStorageLocation()),
            const SizedBox(height: 16),
            
            // Tags section
            if (_file.tags.isNotEmpty) ...[
              const Text(
                'Tags',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _file.tags.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getTagColor(tag).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getTagColor(tag), width: 1),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: _getTagColor(tag),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 32),
            ],
            
            // File path information
            if (_file.path.isNotEmpty) ...[
              _buildInfoCard('Local Path', _file.path),
              const SizedBox(height: 16),
            ],
            
            // SIA filename information
            if (_file.siaFilename != null && _file.siaFilename!.isNotEmpty) ...[
              _buildInfoCard('SIA Filename', _file.siaFilename!),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  String _getMimeTypeDescription(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'JPEG Image';
      case 'image/png':
        return 'PNG Image';
      case 'image/gif':
        return 'GIF Image';
      case 'application/pdf':
        return 'PDF Document';
      case 'application/msword':
        return 'Word Document';
      case 'text/plain':
        return 'Text File';
      case 'video/mp4':
        return 'MP4 Video';
      case 'video/avi':
        return 'AVI Video';
      default:
        return mimeType.split('/').last.toUpperCase();
    }
  }

  String _getStorageLocation() {
    if (_file.tags.contains('sia-vault')) {
      return 'SIA Decentralized Network';
    } else if (_file.tags.contains('sia-uploaded')) {
      return 'Local Storage + SIA Backup';
    } else if (_file.tags.contains('sia-synced')) {
      return 'SIA Network Only';
    } else {
      return 'Local Storage Only';
    }
  }

  Color _getTagColor(String tag) {
    switch (tag.toLowerCase()) {
      case 'sia-uploaded':
      case 'sia-vault':
        return const Color(0xFF34A853);
      case 'sia-synced':
        return const Color(0xFF2196F3);
      case 'encrypted':
        return const Color(0xFFF39C12);
      default:
        return Colors.grey;
    }
  }

  void _shareFile(BuildContext context) {
    try {
      Share.shareXFiles([XFile(_file.path)], text: 'Sharing file: ${_file.name}');
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to share file: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withOpacity(0.8),
        colorText: Colors.white,
      );
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete File', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${widget.file.name}"?\n\nThis will remove the file from both your local storage and SIA vault. This action cannot be undone.',
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
                await _fileRepo.deleteFile(widget.file.id);
                if (mounted) {
                  Navigator.pop(context, true);
                }
              } catch (e) {
                Get.snackbar(
                  'Error',
                  'Failed to delete file: $e',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.red.withOpacity(0.8),
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
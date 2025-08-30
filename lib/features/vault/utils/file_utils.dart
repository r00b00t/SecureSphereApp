import 'package:flutter/material.dart';

class FileUtils {
  static IconData getFileIcon(String mimeType) {
    // Extract file type from mimeType or treat as file extension
    String fileType = mimeType.toLowerCase();
    
    // Handle mimeType format (e.g., "image/jpeg" -> "jpeg")
    if (fileType.contains('/')) {
      fileType = fileType.split('/').last;
      // Handle compound types
      if (fileType.contains('vnd.openxmlformats-officedocument.wordprocessingml.document')) {
        fileType = 'docx';
      } else if (fileType.contains('vnd.openxmlformats-officedocument.spreadsheetml.sheet')) {
        fileType = 'xlsx';
      } else if (fileType.contains('vnd.openxmlformats-officedocument.presentationml.presentation')) {
        fileType = 'pptx';
      } else if (fileType.contains('msword')) {
        fileType = 'doc';
      } else if (fileType.contains('pdf')) {
        fileType = 'pdf';
      } else if (fileType.contains('plain')) {
        fileType = 'txt';
      }
    }
    
    switch (fileType) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'svg':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
      case 'wmv':
      case 'flv':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.archive;
      case 'txt':
      case 'md':
      case 'rtf':
        return Icons.text_snippet;
      case 'json':
      case 'xml':
      case 'csv':
        return Icons.code;
      case 'exe':
      case 'msi':
      case 'dmg':
      case 'deb':
        return Icons.computer;
      default:
        return Icons.insert_drive_file;
    }
  }

  static Color getFileIconColor(String mimeType) {
    // Extract file type from mimeType or treat as file extension
    String fileType = mimeType.toLowerCase();
    
    // Handle mimeType format (e.g., "image/jpeg" -> "jpeg")
    if (fileType.contains('/')) {
      fileType = fileType.split('/').last;
      if (fileType.contains('vnd.openxmlformats-officedocument.wordprocessingml.document')) {
        fileType = 'docx';
      } else if (fileType.contains('vnd.openxmlformats-officedocument.spreadsheetml.sheet')) {
        fileType = 'xlsx';
      } else if (fileType.contains('vnd.openxmlformats-officedocument.presentationml.presentation')) {
        fileType = 'pptx';
      } else if (fileType.contains('msword')) {
        fileType = 'doc';
      } else if (fileType.contains('pdf')) {
        fileType = 'pdf';
      } else if (fileType.contains('plain')) {
        fileType = 'txt';
      }
    }
    
    switch (fileType) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'svg':
      case 'webp':
        return Colors.purple;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
      case 'wmv':
      case 'flv':
        return Colors.red;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return Colors.orange;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Colors.amber;
      case 'txt':
      case 'md':
      case 'rtf':
        return Colors.grey;
      case 'json':
      case 'xml':
      case 'csv':
        return Colors.teal;
      case 'exe':
      case 'msi':
      case 'dmg':
      case 'deb':
        return Colors.indigo;
      default:
        return const Color(0xFF34A853);
    }
  }
  
  /// Get file extension from filename
  static String getFileExtension(String filename) {
    if (filename.contains('.')) {
      return filename.split('.').last.toLowerCase();
    }
    return '';
  }
  
  /// Get file icon by filename extension
  static IconData getFileIconByExtension(String filename) {
    final extension = getFileExtension(filename);
    return getFileIcon(extension);
  }
} 
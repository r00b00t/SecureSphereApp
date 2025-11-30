import 'package:hive/hive.dart';

part 'file_model.g.dart';

@HiveType(typeId: 2)
class FileModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String originalName;

  @HiveField(3)
  String path;

  @HiveField(4)
  int size;

  @HiveField(5)
  String mimeType;

  @HiveField(6)
  DateTime uploadedAt;

  @HiveField(7)
  String? description;

  @HiveField(8)
  List<String> tags;

  @HiveField(9)
  bool isEncrypted;

  @HiveField(10)
  String? siaFilename;

  FileModel({
    required this.id,
    required this.name,
    required this.originalName,
    required this.path,
    required this.size,
    required this.mimeType,
    required this.uploadedAt,
    this.description,
    this.tags = const [],
    this.isEncrypted = true,
    this.siaFilename,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get fileExtension {
    final parts = originalName.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }
} 
import 'package:hive/hive.dart';

part 'password_model.g.dart';

@HiveType(typeId: 0)
class PasswordModel extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String title;
  
  @HiveField(2)
  final String username;
  
  @HiveField(3)
  final String encryptedPassword;
  
  @HiveField(4)
  final String category;
  
  @HiveField(5)
  final String notes;
  
  @HiveField(6)
  final DateTime createdAt;
  
  @HiveField(7)
  final DateTime updatedAt;
  
  PasswordModel({
    required this.id,
    required this.title,
    required this.username,
    required this.encryptedPassword,
    this.category = 'Other',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'username': username,
      'encryptedPassword': encryptedPassword,
      'category': category,
      'notes': notes,
      'createdAt': createdAt.toString(),
      'updatedAt': updatedAt.toString(),
    };
  }

  static PasswordModel fromMap(Map<String, dynamic> map) {
    return PasswordModel(
      id: map['id'] as String,
      title: map['title'] as String,
      username: map['username'] as String,
      encryptedPassword: map['encryptedPassword'] as String,
      category: map['category'] ?? 'Other',
      notes: map['notes'] ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
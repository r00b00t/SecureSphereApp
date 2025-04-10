import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:securesphere/features/auth/services/auth_service.dart';
import 'package:securesphere/features/password/models/password_model.dart';
import 'package:crypto/crypto.dart';

class PasswordRepository {
  late Box<PasswordModel> _passwordBox;
  final _secureStorage = const FlutterSecureStorage();
  static const _secureStoragePrefix = 'password_';
  final String _userId;

  final AuthService _authService = Get.find<AuthService>();
  
  PasswordRepository(this._userId);
  
  Future<void> init() async {
    _passwordBox = await Hive.openBox<PasswordModel>('passwords');
  }
  
  Future<void> addPassword(PasswordModel password) async {
    // Store the actual password in secure storage with user-specific key
    await _secureStorage.write(key: '${_userId}_${_secureStoragePrefix}${password.id}', value: password.encryptedPassword);
    
    // Store a reference in Hive (without the actual password)
    final passwordModel = PasswordModel(
      id: password.id,
      title: password.title,
      username: password.username,
      encryptedPassword: 'secure_storage_reference',  // Just a placeholder
      category: password.category,
      notes: password.notes,
      createdAt: password.createdAt,
      updatedAt: password.updatedAt,
    );
    await _passwordBox.put(password.id, passwordModel);
  }
  
  Future<void> clearAllPasswords() async {
    try {
      // Clear all password references from Hive
      await _passwordBox.clear();
      
      // Clear all actual passwords from secure storage
      final allKeys = await _secureStorage.readAll();
      final passwordKeys = allKeys.keys.where((key) => key.startsWith('${_userId}_${_secureStoragePrefix}'));
      
      for (final key in passwordKeys) {
        await _secureStorage.delete(key: key);
      }
      
      debugPrint('Successfully cleared all passwords');
    } catch (e) {
      debugPrint('Error clearing passwords: $e');
      rethrow;
    }
  }
  
  Future<List<PasswordModel>> getAllPasswords() async {
    try {
      final passwords = _passwordBox.values.toList();
      final result = <PasswordModel>[];
      
      for (var p in passwords) {
        try {
          // Retrieve the actual password from secure storage with user-specific key
          final actualPassword = await _secureStorage.read(key: '${_userId}_${_secureStoragePrefix}${p.id}');
          
          result.add(PasswordModel(
            id: p.id,
            title: p.title,
            username: p.username,
            encryptedPassword: actualPassword ?? '',  // Use empty string if not found
            category: p.category,
            notes: p.notes,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
          ));
        } catch (e) {
          // Log the error for this specific password
          debugPrint('⚠️ Failed to retrieve password ${p.id} from secure storage: ${e.toString()}');
          // Still add the password with empty encrypted password to avoid breaking the UI
          result.add(PasswordModel(
            id: p.id,
            title: p.title,
            username: p.username,
            encryptedPassword: '',  // Empty string since retrieval failed
            category: p.category,
            notes: p.notes,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
          ));
        }
      }
      
      return result;
    } catch (e) {
      debugPrint('⚠️ Failed to load passwords: ${e.toString()}');
      // Rethrow to let the UI handle the error
      rethrow;
    }
  }
  
  Future<void> deletePassword(String id) async {
    // Delete from Hive
    await _passwordBox.delete(id);
    
    // Delete from secure storage with user-specific key
    await _secureStorage.delete(key: '${_userId}_${_secureStoragePrefix}$id');
  }

  Future<void> restorePasswords(List<dynamic> passwordMaps) async {
    // Clear existing data
    await _passwordBox.clear();
    
    // Get all secure storage keys that start with our prefix
    final allKeys = await _secureStorage.readAll();
    final passwordKeys = allKeys.keys.where((k) => k.startsWith('${_userId}_${_secureStoragePrefix}'));
    
    // Delete all existing password entries from secure storage
    for (final key in passwordKeys) {
      await _secureStorage.delete(key: key);
    }
    
    // Restore passwords
    for (final map in passwordMaps) {
      final id = map['id'];
      final actualPassword = map['encryptedPassword'];
      
      // Store the actual password in secure storage with user-specific key
      await _secureStorage.write(key: '${_userId}_${_secureStoragePrefix}$id', value: actualPassword);
      
      // Store metadata in Hive
      final password = PasswordModel(
        id: id,
        title: map['title'],
        username: map['username'],
        encryptedPassword: 'secure_storage_reference',
        category: map['category'],
        notes: map['notes'],
        createdAt: DateTime.parse(map['createdAt']),
        updatedAt: DateTime.parse(map['updatedAt']),
      );
      await _passwordBox.put(id, password);
    }
  }
  
  Future<PasswordModel?> getPassword(String id) async {
    try {
      final password = _passwordBox.get(id);
      if (password == null) return null;
      
      // Retrieve the actual password from secure storage with user-specific key
      String? actualPassword;
      try {
        actualPassword = await _secureStorage.read(key: '${_userId}_${_secureStoragePrefix}$id');
      } catch (e) {
        debugPrint('⚠️ Failed to retrieve password $id from secure storage: ${e.toString()}');
        // Continue with empty password
        actualPassword = null;
      }
      
      return PasswordModel(
        id: password.id,
        title: password.title,
        username: password.username,
        encryptedPassword: actualPassword ?? '',
        category: password.category,
        notes: password.notes,
        createdAt: password.createdAt,
        updatedAt: password.updatedAt,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to get password $id: ${e.toString()}');
      rethrow;
    }
  }
  
  Future<void> updatePassword(PasswordModel password) async {
    // Update the password in secure storage with user-specific key
    await _secureStorage.write(key: '${_userId}_${_secureStoragePrefix}${password.id}', value: password.encryptedPassword);
    
    // Update metadata in Hive
    final updatedPassword = PasswordModel(
      id: password.id,
      title: password.title,
      username: password.username,
      encryptedPassword: 'secure_storage_reference',
      category: password.category,
      notes: password.notes,
      createdAt: password.createdAt,
      updatedAt: DateTime.now(),
    );
    await _passwordBox.put(password.id, updatedPassword);
  }
}
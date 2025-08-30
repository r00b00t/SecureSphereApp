import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:securesphere/features/password/models/password_model.dart';

class PasswordRepository {
  late Box<PasswordModel> _passwordBox;
  final _secureStorage = const FlutterSecureStorage();
  static const _secureStoragePrefix = 'password_';
  final String _userId;

  
  PasswordRepository(this._userId);
  
  Future<void> init() async {
    _passwordBox = await Hive.openBox<PasswordModel>('passwords');
  }
  
  Future<void> addPassword(PasswordModel password) async {
    await _secureStorage.write(key: '${_userId}_${_secureStoragePrefix}${password.id}', value: password.encryptedPassword);
    
    final passwordModel = PasswordModel(
      id: password.id,
      title: password.title,
      username: password.username,
      encryptedPassword: 'secure_storage_reference',  
      category: password.category,
      notes: password.notes,
      createdAt: password.createdAt,
      updatedAt: password.updatedAt,
    );
    await _passwordBox.put(password.id, passwordModel);
  }
  
  Future<void> clearAllPasswords() async {
    try {

      await _passwordBox.clear();
      

      final allKeys = await _secureStorage.readAll();
      final passwordKeys = allKeys.keys.where((key) => key.startsWith('${_userId}_${_secureStoragePrefix}'));
      
      for (final key in passwordKeys) {
        await _secureStorage.delete(key: key);
      }
      

    } catch (e) {
      rethrow;
    }
  }
  
  Future<List<PasswordModel>> getAllPasswords() async {
    try {
      final passwords = _passwordBox.values.toList();
      final result = <PasswordModel>[];
      
      for (var p in passwords) {
        try {

          final actualPassword = await _secureStorage.read(key: '${_userId}_${_secureStoragePrefix}${p.id}');
          
          result.add(PasswordModel(
            id: p.id,
            title: p.title,
            username: p.username,
            encryptedPassword: actualPassword ?? '',  
            category: p.category,
            notes: p.notes,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
          ));
        } catch (e) {


          result.add(PasswordModel(
            id: p.id,
            title: p.title,
            username: p.username,
            encryptedPassword: '',  
            category: p.category,
            notes: p.notes,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
          ));
        }
      }
      
      return result;
    } catch (e) {
      rethrow;
    }
  }
  
  Future<void> deletePassword(String id) async {

    await _passwordBox.delete(id);
    

    await _secureStorage.delete(key: '${_userId}_${_secureStoragePrefix}$id');
  }

  Future<void> restorePasswords(List<dynamic> passwordMaps) async {

    final existingPasswords = _passwordBox.values.cast<PasswordModel>().toList();
    final existingIds = existingPasswords.map((p) => p.id).toSet();
  
  
    final List<dynamic> nonDuplicateMaps = passwordMaps.where((map) => !existingIds.contains(map['id'])).toList();

    for (final map in nonDuplicateMaps) {
      final id = map['id'];
      final actualPassword = map['encryptedPassword'];
  

      await _secureStorage.write(key: '${_userId}_${_secureStoragePrefix}$id', value: actualPassword);
  

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
      

      String? actualPassword;
      try {
        actualPassword = await _secureStorage.read(key: '${_userId}_${_secureStoragePrefix}$id');
      } catch (e) {

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
      rethrow;
    }
  }
  
  Future<void> updatePassword(PasswordModel password) async {

    await _secureStorage.write(key: '${_userId}_${_secureStoragePrefix}${password.id}', value: password.encryptedPassword);
    

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
  
  Future<List<PasswordModel>> getPasswords() async {
    return await getAllPasswords();
  }
  
  Future<void> addPasswords(List<PasswordModel> passwords) async {
    for (final password in passwords) {

      await _secureStorage.write(key: '${_userId}_${_secureStoragePrefix}${password.id}', value: password.encryptedPassword);

      final passwordMeta = PasswordModel(
        id: password.id,
        title: password.title,
        username: password.username,
        encryptedPassword: 'secure_storage_reference',
        category: password.category,
        notes: password.notes,
        createdAt: password.createdAt,
        updatedAt: password.updatedAt,
      );
      await _passwordBox.put(password.id, passwordMeta);
    }
  }
}
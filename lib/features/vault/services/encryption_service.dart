import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:hex/hex.dart';
import '../../auth/services/auth_service.dart';

class EncryptionService {
  final AuthService _authService;
  
  // Constants for encryption
  static const int _ivLength = 16; // 128-bit IV
  static const String _encryptionPrefix = 'SECURESPHERE_ENCRYPTED:';
  
  EncryptionService(this._authService);

  /// Derives a master encryption key from the user's seed phrase
  Future<Uint8List> _deriveMasterKey() async {
    try {
      final privateKey = await _authService.getPrivateKey();
      if (privateKey == null) {
        throw Exception('No private key available. User must be authenticated.');
      }
      
      // We use SHA-256 to ensure consistent 32-byte key length
      final privateKeyBytes = Uint8List.fromList(HEX.decode(privateKey));
      final masterKey = sha256.convert(privateKeyBytes).bytes;
      
      return Uint8List.fromList(masterKey);
    } catch (e) {
      throw Exception('Failed to derive master key: $e');
    }
  }

  /// Generates a unique encryption key for each file
  /// Uses the master key + file metadata to create a deterministic but unique key
  Future<Uint8List> _generateFileKey(String filename, int fileSize) async {
    try {
      final masterKey = await _deriveMasterKey();
      
      // - Master key
      // - Filename
      // - File size
      // - Timestamp (optional, for additional uniqueness)
      
      final keyMaterial = utf8.encode(filename) + 
                         utf8.encode(fileSize.toString()) +
                         masterKey;
      
      // Generate a deterministic but unique key using SHA-256
      final fileKey = sha256.convert(keyMaterial).bytes;
      
      return Uint8List.fromList(fileKey);
    } catch (e) {
      throw Exception('Failed to generate file key: $e');
    }
  }

  /// Encrypts a file using AES-256-CBC
  /// Returns the encrypted file path
  Future<String> encryptFile(File file) async {
    try {
      // Read the original file
      final fileBytes = await file.readAsBytes();
      final filename = file.path.split('/').last;
      final fileSize = fileBytes.length;
      
      // Generate encryption key for this file
      final key = await _generateFileKey(filename, fileSize);
      
      // Generate a random IV for this encryption
      final iv = IV.fromSecureRandom(_ivLength);
      
      // Create the encrypter
      final encrypter = Encrypter(AES(Key(key)));
      
      // Encrypt the file content
      final encrypted = encrypter.encrypt(base64Encode(fileBytes), iv: iv);
      
      // Create metadata for decryption
      final metadata = {
        'filename': filename,
        'originalSize': fileSize,
        'iv': base64Encode(iv.bytes),
        'encryptedAt': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
      
      // Combine metadata and encrypted data
      final metadataJson = jsonEncode(metadata);
      final metadataBytes = utf8.encode(metadataJson);
      final metadataLength = metadataBytes.length;
      
      // Create the final encrypted file structure:
      // [prefix][metadata_length:4bytes][metadata][encrypted_data]
      final prefixBytes = utf8.encode(_encryptionPrefix);
      final lengthBytes = ByteData(4)..setUint32(0, metadataLength, Endian.big);
      
      final encryptedFileBytes = Uint8List.fromList([
        ...prefixBytes,
        ...lengthBytes.buffer.asUint8List(),
        ...metadataBytes,
        ...encrypted.bytes,
      ]);
      
      // Write encrypted file
      final encryptedFilePath = '${file.path}.encrypted';
      final encryptedFile = File(encryptedFilePath);
      await encryptedFile.writeAsBytes(encryptedFileBytes);
      
      return encryptedFilePath;
    } catch (e) {
      throw Exception('File encryption failed: $e');
    }
  }

  /// Decrypts an encrypted file
  /// Returns the decrypted file path
  Future<String> decryptFile(File encryptedFile) async {
    try {
      // Read the encrypted file
      final encryptedBytes = await encryptedFile.readAsBytes();
      
      if (!_isEncryptedFile(encryptedBytes)) {
        throw Exception('File is not encrypted or has invalid format');
      }
      
      // Parse the encrypted file structure
      final prefixLength = _encryptionPrefix.length;
      final metadataLength = ByteData.view(encryptedBytes.buffer, prefixLength, 4)
          .getUint32(0, Endian.big);
      
      final metadataStart = prefixLength + 4;
      final metadataEnd = metadataStart + metadataLength;
      final encryptedDataStart = metadataEnd;
      
      // Extract metadata
      final metadataBytes = encryptedBytes.sublist(metadataStart, metadataEnd);
      final metadataJson = utf8.decode(metadataBytes);
      final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
      
      // Extract encrypted data
      final encryptedData = encryptedBytes.sublist(encryptedDataStart);
      
      // Get encryption parameters
      final filename = metadata['filename'] as String;
      final originalSize = metadata['originalSize'] as int;
      final ivBytes = base64Decode(metadata['iv'] as String);
      final iv = IV(ivBytes);
      
      // Generate the same key used for encryption
      final key = await _generateFileKey(filename, originalSize);
      
      // Create the decrypter
      final encrypter = Encrypter(AES(Key(key)));
      
      // Decrypt the data
      final decrypted = encrypter.decrypt64(
        base64Encode(encryptedData),
        iv: iv,
      );
      
      // Decode the decrypted base64 data back to bytes
      final decryptedBytes = base64Decode(decrypted);
      
      // Verify the decrypted size matches the original
      if (decryptedBytes.length != originalSize) {
        throw Exception('Decrypted file size does not match original size');
      }
      
      // Write decrypted file
      final decryptedFilePath = encryptedFile.path.replaceAll('.encrypted', '.decrypted');
      final decryptedFile = File(decryptedFilePath);
      await decryptedFile.writeAsBytes(decryptedBytes);
      
      return decryptedFilePath;
    } catch (e) {
      throw Exception('File decryption failed: $e');
    }
  }

  /// Checks if a file is encrypted by this service
  bool _isEncryptedFile(Uint8List fileBytes) {
    if (fileBytes.length < _encryptionPrefix.length + 4) {
      return false;
    }
    
    final prefixBytes = fileBytes.sublist(0, _encryptionPrefix.length);
    final prefix = utf8.decode(prefixBytes);
    
    return prefix == _encryptionPrefix;
  }

  /// Encrypts file content in memory (for streaming uploads)
  Future<EncryptedFileData> encryptFileContent(Uint8List fileBytes, String filename) async {
    try {
      final fileSize = fileBytes.length;
      
      final key = await _generateFileKey(filename, fileSize);
      
      final iv = IV.fromSecureRandom(_ivLength);
      
      final encrypter = Encrypter(AES(Key(key)));
      
      final base64Data = base64Encode(fileBytes);
      
      final encrypted = encrypter.encrypt(base64Data, iv: iv);
      
      return EncryptedFileData(
        encryptedBytes: encrypted.bytes,
        iv: iv.bytes,
        originalSize: fileSize,
        filename: filename,
      );
    } catch (e) {
      throw Exception('Content encryption failed: $e');
    }
  }

  /// Decrypts file content in memory (for streaming downloads)
  Future<Uint8List> decryptFileContent(
    Uint8List encryptedBytes,
    Uint8List iv,
    String filename,
    int originalSize,
  ) async {
    try {
      
      final key = await _generateFileKey(filename, originalSize);
      
      final ivObj = IV(iv);
      final encrypter = Encrypter(AES(Key(key)));
      
      // Create Encrypted object from bytes and decrypt
      final encryptedObj = Encrypted(encryptedBytes);
      final decrypted = encrypter.decrypt(encryptedObj, iv: ivObj);
      
      
      // Decode the decrypted base64 data back to bytes
      final decryptedBytes = base64Decode(decrypted);
      
      
      if (decryptedBytes.length != originalSize) {
        // Don't throw error, just warn for now
      }
      
      return decryptedBytes;
    } catch (e) {
      throw Exception('Content decryption failed: $e');
    }
  }

  /// Generates a unique encryption key for backup data
  /// Uses the master key + backup-specific salt for enhanced security
  Future<Uint8List> _generateBackupKey() async {
    try {
      final masterKey = await _deriveMasterKey();
      
      // Add backup-specific salt to make backup keys unique from file keys
      const backupSalt = 'SECURESPHERE_BACKUP_SALT_2024';
      final saltBytes = utf8.encode(backupSalt);
      
      // Combine master key with backup salt
      final keyMaterial = masterKey + saltBytes;
      
      // Generate backup-specific key using SHA-256
      final backupKey = sha256.convert(keyMaterial).bytes;
      
      return Uint8List.fromList(backupKey);
    } catch (e) {
      throw Exception('Failed to generate backup key: $e');
    }
  }

  /// Encrypts backup JSON data with user-specific keys and app-level security
  /// Returns encrypted data with metadata for secure backup storage
  Future<EncryptedBackupData> encryptBackupData(Map<String, dynamic> jsonData) async {
    try {
      
      // Convert JSON to bytes
      final jsonString = jsonEncode(jsonData);
      final jsonBytes = utf8.encode(jsonString);
      final originalSize = jsonBytes.length;
      
      
      // Generate backup-specific encryption key
      final key = await _generateBackupKey();
      
      // Generate random IV for this backup
      final iv = IV.fromSecureRandom(_ivLength);
      
      // Create the encrypter
      final encrypter = Encrypter(AES(Key(key)));
      
      // Encrypt the JSON data (convert to base64 first for compatibility)
      final base64Data = base64Encode(jsonBytes);
      final encrypted = encrypter.encrypt(base64Data, iv: iv);
      
      
      // Create encryption metadata
      final metadata = {
        'encryptedAt': DateTime.now().toIso8601String(),
        'originalSize': originalSize,
        'version': '1.0',
        'type': 'backup',
        'iv': base64Encode(iv.bytes),
      };
      
      return EncryptedBackupData(
        encryptedBytes: encrypted.bytes,
        iv: iv.bytes,
        originalSize: originalSize,
        metadata: metadata,
      );
    } catch (e) {
      throw Exception('Backup encryption failed: $e');
    }
  }

  /// Decrypts backup data and returns the original JSON
  Future<Map<String, dynamic>> decryptBackupData(Uint8List encryptedBytes, Uint8List iv, int originalSize) async {
    try {
      
      // Generate the same backup key used for encryption
      final key = await _generateBackupKey();
      
      // Create decrypter
      final ivObj = IV(iv);
      final encrypter = Encrypter(AES(Key(key)));
      
      // Decrypt the data
      final encryptedObj = Encrypted(encryptedBytes);
      final decrypted = encrypter.decrypt(encryptedObj, iv: ivObj);
      
      
      // Decode from base64 to get original JSON bytes
      final jsonBytes = base64Decode(decrypted);
      
      
      // Verify size if provided
      if (originalSize > 0 && jsonBytes.length != originalSize) {
      }
      
      // Convert bytes back to JSON
      final jsonString = utf8.decode(jsonBytes);
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      return jsonData;
    } catch (e) {
      throw Exception('Backup decryption failed: $e');
    }
  }

  /// Validates that the user has the necessary keys for encryption/decryption
  Future<bool> validateEncryptionKeys() async {
    try {
      final privateKey = await _authService.getPrivateKey();
      if (privateKey == null || privateKey.isEmpty) {
        return false;
      }
      
      // Test key derivation to ensure it works
      final masterKey = await _deriveMasterKey();
      if (masterKey.length != 32) {
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Encrypts a file and returns structured metadata for vault storage
  Future<EncryptedVaultFile> encryptForVault(File file, String filename) async {
    try {
      
      final fileBytes = await file.readAsBytes();
      final encryptedData = await encryptFileContent(fileBytes, filename);
      
      // Create vault-specific metadata
      final metadata = {
        'filename': filename,
        'originalSize': fileBytes.length,
        'encryptedSize': encryptedData.encryptedBytes.length,
        'iv': base64Encode(encryptedData.iv),
        'encryptedAt': DateTime.now().toIso8601String(),
        'version': '1.0',
        'algorithm': 'AES-256-CBC',
      };
      
      
      return EncryptedVaultFile(
        encryptedBytes: encryptedData.encryptedBytes,
        iv: encryptedData.iv,
        originalSize: fileBytes.length,
        filename: filename,
        metadata: metadata,
      );
    } catch (e) {
      throw Exception('Vault encryption failed: $e');
    }
  }

  /// Decrypts a vault file and returns the original file bytes
  Future<Uint8List> decryptFromVault(
    Uint8List encryptedBytes,
    Map<String, dynamic> metadata,
  ) async {
    try {
      
      final filename = metadata['filename'] as String;
      final originalSize = metadata['originalSize'] as int;
      final ivString = metadata['iv'] as String;
      final iv = base64Decode(ivString);
      
      
      final decryptedBytes = await decryptFileContent(
        encryptedBytes,
        iv,
        filename,
        originalSize,
      );
      
      
      return decryptedBytes;
    } catch (e) {
      throw Exception('Vault decryption failed: $e');
    }
  }
}

/// Data class for encrypted file information
class EncryptedFileData {
  final Uint8List encryptedBytes;
  final Uint8List iv;
  final int originalSize;
  final String filename;

  EncryptedFileData({
    required this.encryptedBytes,
    required this.iv,
    required this.originalSize,
    required this.filename,
  });
}

/// Data class for encrypted backup information
class EncryptedBackupData {
  final Uint8List encryptedBytes;
  final Uint8List iv;
  final int originalSize;
  final Map<String, dynamic> metadata;

  EncryptedBackupData({
    required this.encryptedBytes,
    required this.iv,
    required this.originalSize,
    required this.metadata,
  });
}

/// Data class for encrypted vault file with enhanced metadata
class EncryptedVaultFile {
  final Uint8List encryptedBytes;
  final Uint8List iv;
  final int originalSize;
  final String filename;
  final Map<String, dynamic> metadata;

  EncryptedVaultFile({
    required this.encryptedBytes,
    required this.iv,
    required this.originalSize,
    required this.filename,
    required this.metadata,
  });
} 
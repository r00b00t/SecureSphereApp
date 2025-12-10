import 'dart:convert';
import 'package:crypto/crypto.dart';

class BucketUtils {
 
  static const String _bucketSalt = 'decvault-secure-storage';
  

  static String getVaultBucketName(String userId) {
    return _generateSecureBucketName(userId, 'vault');
  }
  

  static String getBackupBucketName(String userId) {
    return _generateSecureBucketName(userId, 'backup');
  }
  

  static String _generateSecureBucketName(String userId, String type) {
 
    final input = '$userId-$type-$_bucketSalt';
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);
    

    final shortHash = hash.toString().substring(0, 16);
    

    return 'dv-$type-$shortHash';
  }
  

  static bool isValidBucketName(String bucketName) {
 
    final regex = RegExp(r'^dv-(vault|backup)-[a-f0-9]{16}$');
    return regex.hasMatch(bucketName);
  }
  

  static String? getBucketType(String bucketName) {
    if (bucketName.startsWith('dv-vault-')) return 'vault';
    if (bucketName.startsWith('dv-backup-')) return 'backup';
    return null;
  }
}


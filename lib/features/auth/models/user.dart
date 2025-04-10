import 'package:flutter/foundation.dart';

class User {
  final String id;
  final String? publicKey;
  final String? privateKey;
  final String? seedPhrase;

  User({
    required this.id,
    this.publicKey,
    this.privateKey,
    this.seedPhrase,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is User &&
      other.id == id &&
      other.publicKey == publicKey &&
      other.privateKey == privateKey &&
      other.seedPhrase == seedPhrase;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      publicKey.hashCode ^
      privateKey.hashCode ^
      seedPhrase.hashCode;
  }

  @override
  String toString() {
    return 'User(id: $id, publicKey: $publicKey, privateKey: $privateKey)';
  }
}
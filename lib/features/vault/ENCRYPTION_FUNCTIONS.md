# File Vault Encryption Functions

This document describes the encryption and decryption functions implemented for the SecureSphere file vault.

## Overview

The file vault now provides comprehensive encryption/decryption functionality for secure file uploads and downloads. All files are automatically encrypted using AES-256-CBC encryption before being uploaded to the SIA network.

## Key Features

### Security **Automatic Encryption**
- All files are encrypted using AES-256-CBC before upload
- Each file gets a unique encryption key derived from the user's master key
- Random IV (Initialization Vector) generated for each file
- Secure key derivation using the user's private key from their seed phrase

### 🛡️ **Enhanced Security**
- Master key derivation from user's seed phrase
- Deterministic file keys for consistent encryption/decryption
- IV prepended to encrypted files for proper decryption
- Comprehensive validation of encryption keys before operations

### Performance **Robust Error Handling**
- File validation before upload/download
- Encryption key validation
- File integrity checks
- Detailed logging for debugging

## Core Components

### 1. EncryptionService (`encryption_service.dart`)

#### Key Methods:

**`encryptFileContent(Uint8List fileBytes, String filename)`**
- Encrypts file content in memory
- Returns `EncryptedFileData` with encrypted bytes and IV
- Used for streaming uploads

**`decryptFileContent(Uint8List encryptedBytes, Uint8List iv, String filename, int originalSize)`**
- Decrypts file content in memory
- Returns original file bytes
- Used for streaming downloads

**`encryptForVault(File file, String filename)`**
- Enhanced vault-specific encryption with metadata
- Returns `EncryptedVaultFile` with comprehensive metadata
- Includes encryption algorithm, timestamps, and sizes

**`decryptFromVault(Uint8List encryptedBytes, Map<String, dynamic> metadata)`**
- Vault-specific decryption using metadata
- Validates metadata before decryption
- Returns original file bytes

**`validateEncryptionKeys()`**
- Validates encryption keys are available and functional
- Tests key derivation process
- Returns true if keys are valid

### 2. RenterdUploader (`renterd_uploader.dart`)

#### Upload Process:

1. **File Validation** - Validates file exists, is readable, and has valid filename
2. **Key Validation** - Ensures encryption keys are available
3. **Encryption** - Encrypts file using `EncryptionService`
4. **Upload** - Uploads encrypted file to SIA network
5. **Cleanup** - Removes temporary encrypted file

#### Download Process:

1. **Key Validation** - Ensures decryption keys are available
2. **Download** - Downloads encrypted file from SIA network
3. **Decryption** - Decrypts file using `EncryptionService`
4. **Verification** - Validates decrypted file integrity
5. **Cleanup** - Removes temporary encrypted file

## Usage Examples

### Upload a File with Encryption

```dart
final renterdUploader = Get.find<RenterdUploader>();

try {
  final siaFilename = await renterdUploader.uploadFile(
    file,           // File to upload
    'document.pdf', // Original filename
    onProgress: (progress) {
      print('Upload progress: ${progress.toStringAsFixed(1)}%');
    },
  );
  
  print('File uploaded successfully: $siaFilename');
} catch (e) {
  print('Upload failed: $e');
}
```

### Download and Decrypt a File

```dart
try {
  final downloadedFile = await renterdUploader.downloadFileWithSize(
    siaFilename,       // SIA filename
    '/path/to/save',   // Local save path
    originalFileSize,  // Original file size for validation
    onProgress: (progress) {
      print('Download progress: ${progress.toStringAsFixed(1)}%');
    },
  );
  
  print('File downloaded and decrypted: ${downloadedFile.path}');
} catch (e) {
  print('Download failed: $e');
}
```

### Direct Encryption/Decryption

```dart
final encryptionService = Get.find<EncryptionService>();

// Encrypt file content
final fileBytes = await file.readAsBytes();
final encryptedData = await encryptionService.encryptFileContent(
  fileBytes, 
  'filename.pdf'
);

// Decrypt file content
final decryptedBytes = await encryptionService.decryptFileContent(
  encryptedData.encryptedBytes,
  encryptedData.iv,
  'filename.pdf',
  fileBytes.length,
);
```

## Security Implementation

### Key Derivation
- Master key derived from user's private key (from seed phrase)
- File-specific keys generated using: master key + filename + file size
- SHA-256 used for all key derivation operations

### Encryption Details
- **Algorithm**: AES-256-CBC
- **Key Size**: 256 bits (32 bytes)
- **IV Size**: 128 bits (16 bytes)
- **IV Generation**: Cryptographically secure random
- **Data Format**: IV + Encrypted Content

### File Structure
```
[16-byte IV][Encrypted File Content]
```

## Error Handling

### Upload Errors
- `RenterdUploadException` for all upload-related errors
- File validation errors (empty files, invalid filenames)
- Encryption key validation errors
- Network/SIA connection errors

### Download Errors
- `RenterdUploadException` for all download-related errors
- Decryption key validation errors
- File format validation errors (invalid IV, corrupted data)
- File integrity verification errors

## File Validation

### Upload Validation
- File existence and readability
- Non-empty file size
- Valid filename (no special characters)
- Encryption key availability

### Download Validation
- Encrypted file format validation
- IV validation (non-zero IV)
- File integrity after decryption
- Size verification after write

## Performance Considerations

### Memory Usage
- Files are processed in memory for encryption/decryption
- Temporary files used for upload/download operations
- Automatic cleanup of temporary files

### Progress Tracking
- Upload progress: 5% validation → 10% encryption → 90% upload → 100% complete
- Download progress: 5% validation → 85% download → 95% decryption → 100% complete

## Configuration

### Requirements
- User must be authenticated (valid seed phrase)
- SIA configuration must be available
- Network connectivity to SIA renterd

### Bucket Management
- SecureSphere: User-specific buckets (`user-vault-{userId}`)
- Self-hosted: Shared `vault` bucket
- Automatic bucket creation for SecureSphere users

## Troubleshooting

### Common Issues

**Encryption Key Not Available**
- Ensure user is logged in with valid seed phrase
- Check `AuthService.getPrivateKey()` returns valid key

**Upload/Download Fails**
- Verify SIA configuration is correct
- Check network connectivity
- Ensure sufficient storage space

**Decryption Fails**
- Verify file was encrypted with current user's keys
- Check file hasn't been corrupted during transfer
- Ensure original file size is correct

## Migration Notes

This implementation replaces the previous non-encrypted file storage. All new files will be automatically encrypted. Existing unencrypted files will need to be re-uploaded to benefit from encryption.

### Important: App Rebuild Required

After implementing these encryption functions, you **must rebuild the app** for the changes to take effect:

```bash
flutter clean
flutter pub get
flutter build apk  # for Android
# or
flutter build ios  # for iOS
```

### Backward Compatibility

The download function includes backward compatibility for files that were uploaded before encryption was enabled:

- **Encrypted files**: Automatically detected and decrypted
- **Unencrypted files**: Handled gracefully without decryption attempt
- **Size validation**: Files are checked to determine if they're encrypted based on size comparison

### Debugging Upload/Download Issues

The enhanced logging will show:

**During Upload:**
```
[SIA Upload] Encrypting file...
[SIA Upload] Original file size: X bytes
[SIA Upload] Encrypted file size: Y bytes (should be > X)
[SIA Upload]  Encryption verified - uploading encrypted file
```

**During Download:**
```
[SIA Download] Expected original size: X
[SIA Download] Combined bytes length: Y
[SIA Download]  File successfully decrypted and saved
```

If you see warnings about file sizes, it indicates the file wasn't encrypted during upload.

### Common Issues After Implementation

**"Invalid or corrupted pad block" Error:**
- Usually indicates trying to decrypt an unencrypted file
- The new backward compatibility feature handles this automatically
- Rebuild the app to ensure encryption is working for new uploads

**File Size Mismatch:**
- Encrypted files should be larger than originals due to encryption overhead
- If sizes are equal, the file wasn't encrypted during upload
- Check that the app was rebuilt after implementing encryption functions
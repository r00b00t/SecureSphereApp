# DecVault

A decentralized, privacy-focused password manager with seed phrase authentication and encrypted file storage.

## Overview

DecVault is a cross-platform password management application that prioritizes user privacy and security through decentralized architecture. The application uses seed phrase-based authentication, eliminating the need for traditional passwords while providing secure access to your credentials and files.

## Features

### Security
- Seed phrase authentication using BIP39/BIP32 standards
- AES-256-CBC encryption for all stored data
- Zero-knowledge architecture - server never sees encryption keys or plaintext
- Deterministic key derivation for cross-device compatibility
- Local biometric authentication support

### Password Management
- Secure password storage with encryption
- Password generator with customizable options
- Breach monitoring and password health checks
- Cross-device synchronization

### File Vault
- Encrypted file storage on decentralized SIA network
- Automatic encryption before upload
- Cross-device file access and decryption
- Storage management with tiered limits

### Platform Support
- iOS
- Android
- macOS
- Windows
- Linux
- Web

### Additional Features
- QR code-based login and authentication
- Subscription management with RevenueCat integration
- Backup and restore functionality
- Desktop-optimized UI for larger screens
- Notification support

## Technology Stack

- **Framework:** Flutter
- **State Management:** GetX
- **Storage:** Hive (local), SIA Network (decentralized)
- **Encryption:** AES-256-CBC with deterministic key derivation
- **Authentication:** BIP39 seed phrases, BIP32 key derivation
- **Subscriptions:** RevenueCat

## Project Structure

```
lib/
├── features/
│   ├── auth/          # Authentication and seed phrase management
│   ├── password/      # Password management features
│   ├── vault/         # File vault and encryption
│   ├── backup/        # Backup and restore functionality
│   ├── settings/      # Application settings
│   ├── subscription/  # Subscription management
│   └── sia/           # SIA network integration
├── common/            # Shared widgets and utilities
└── services/          # Core services
```

## Configuration

The application requires configuration of backend endpoints and API keys. These should be set through environment variables or configuration files as appropriate for your deployment.

## License

Copyright (c) 2025 DecVault. All rights reserved.

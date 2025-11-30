class SiaNodeConfig {
  final String host;
  final String port;
  final String password;
  final bool isDecVaultManagedNode;

  const SiaNodeConfig({
    required this.host,
    required this.port,
    required this.password,
    required this.isDecVaultManagedNode,
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'password': password,
      'isDecVaultManagedNode': isDecVaultManagedNode,
    };
  }

  factory SiaNodeConfig.fromJson(Map<String, dynamic> json) {
    return SiaNodeConfig(
      host: json['host'] as String,
      port: json['port'] as String,
      password: json['password'] as String,
      isDecVaultManagedNode: json['isDecVaultManagedNode'] as bool? ?? false,
    );
  }

  static SiaNodeConfig get secureSphereManagedNode => SiaNodeConfig(
    host: const String.fromEnvironment('SIA_NODE_IP', defaultValue: ''),
    port: const String.fromEnvironment('SIA_NODE_PORT', defaultValue: '9980'),
    password: const String.fromEnvironment('SIA_NODE_PASSWORD', defaultValue: ''),
    isDecVaultManagedNode: true,
  );
}
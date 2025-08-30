class SiaNodeConfig {
  final String host;
  final String port;
  final String password;
  final bool isSecureSphereManagedNode;

  const SiaNodeConfig({
    required this.host,
    required this.port,
    required this.password,
    required this.isSecureSphereManagedNode,
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'password': password,
      'isSecureSphereManagedNode': isSecureSphereManagedNode,
    };
  }

  factory SiaNodeConfig.fromJson(Map<String, dynamic> json) {
    return SiaNodeConfig(
      host: json['host'] as String,
      port: json['port'] as String,
      password: json['password'] as String,
      isSecureSphereManagedNode: json['isSecureSphereManagedNode'] as bool? ?? false,
    );
  }

  static const SiaNodeConfig secureSphereManagedNode = SiaNodeConfig(
    host: '',
    port: '',
    password: '',
    isSecureSphereManagedNode: true,
  );
}
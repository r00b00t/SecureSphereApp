class ApiConfig {
  // PSQL Backend
  static const String psqlBaseUrl = '';
  
  // Authentication endpoints (Using PSQL Backend)
  static const String loginEndpoint = '$psqlBaseUrl/login'; 
  static const String registerEndpoint = '$psqlBaseUrl/signup';
  
  // SIA Node endpoints (Using PSQL Backend)
  static const String siaNodeEndpoint = '$psqlBaseUrl/sia-node';
  static String getSiaNodeEndpoint(String uuid) => '$psqlBaseUrl/sia-node/$uuid';
  static const String managedNodeEndpoint = '$psqlBaseUrl/managed-node';
  
  // SIA Proxy Endpoints
  static const String siaProxyBaseUrl = '$psqlBaseUrl/api/sia';
  static String siaProxyObjectsPath(String filename) => '$siaProxyBaseUrl/objects/$filename';
  static const String siaProxyList = '$siaProxyBaseUrl/list';
  static const String siaProxyState = '$siaProxyBaseUrl/state';
  static const String siaProxyBuckets = '$siaProxyBaseUrl/buckets';
  static const String siaProxyHealth = '$siaProxyBaseUrl/health';

  // Backup endpoints (Using PSQL Backend)
  static const String uploadBackupUrl = '$psqlBaseUrl/upload-backup';
  static const String getBackupsBaseUrl = '$psqlBaseUrl/backups';

  // Breach Check API (Using PSQL Backend)
  static const String checkEmailBreachEndpoint = '$psqlBaseUrl/breach/check-email';
  static const String checkPasswordBreachEndpoint = '$psqlBaseUrl/breach/check-password';

  // Breach monitoring API
  static const String breachApiBaseUrl = '$psqlBaseUrl/breach';
  static const String breachAnalyticsPath = '/analytics';
  static const String breachesPath = '/breaches';

  // Password API
  static const String passwordApiBaseUrl = '$psqlBaseUrl/api/passwords';
  static const String passwordAnonPath = '/anon';

  // Self-hosted Sia node (direct connection, decentralized mode)
  static const String SSip = '';
  static const String SSport = '';
  static const String SSpass = '';
  static const String siaWorkerStatePath = '/api/bus/state';
}
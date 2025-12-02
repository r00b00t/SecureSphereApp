import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../backup_service.dart';
import 'package:decvault/common/widgets/app_drawer.dart';

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  late Future<List<Map<String, dynamic>>> _backupsFuture;
  final BackupService backupService = Get.find<BackupService>();

  @override
  void initState() {
    super.initState();
    _refreshBackups();
  }

  void _refreshBackups() {
    setState(() {
      _backupsFuture = backupService.getBackups();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Snapshots'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () async {
              try {
                await backupService.triggerBackup(
                  onBackupComplete: () {
                    _refreshBackups();
                  },
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Snapshot created and synced successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to create snapshot: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF121212),
              const Color(0xFF1E1E1E),
              Theme.of(context).primaryColor.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _backupsFuture,
          builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF34A853).withValues(alpha: 0.2),
                          const Color(0xFF34A853).withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.backup_outlined,
                      size: 80,
                      color: Color(0xFF34A853),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No Snapshots Yet',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Protect your data by creating\nyour first snapshot',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[400],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await backupService.triggerBackup(
                          onBackupComplete: () {
                            _refreshBackups();
                          },
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Snapshot created and synced successfully')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to create snapshot: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.add, size: 24),
                    label: const Text(
                      'Create Your First Snapshot',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final backup = snapshot.data![index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: backup['isEncrypted'] == true ? 
                      const Color(0xFF1E8E3E) : const Color(0xFF666666),
                    child: Icon(
                      backup['isEncrypted'] == true ? Icons.lock : Icons.backup, 
                      color: Colors.white
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          backup['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (backup['isEncrypted'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E8E3E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'ENCRYPTED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backup['date'],
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      if (backup['isEncrypted'] == true)
                        Text(
                          'Secured with user-specific encryption',
                          style: TextStyle(
                            color: const Color(0xFF1E8E3E),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore, color: Color(0xFF34A853)),
                        onPressed: () async {
                          final backupPath = backup['path'];
                         
                          if (backupPath == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Restore failed: snapshot path is null')),
                            );
                            return;
                          }
                          try {
                            await backupService.restoreBackup(backupPath);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Snapshot restored successfully')),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Restore failed: $e')),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Confirm Delete'),
                              content: const Text('Are you sure you want to delete this snapshot?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            try {
                              await backupService.deleteBackup(backup['path']);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Snapshot deleted successfully')),
                              );
                              _refreshBackups();
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Delete failed: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                )
              );
            },
          );
          },
        ),
      ),
    );
  }
}

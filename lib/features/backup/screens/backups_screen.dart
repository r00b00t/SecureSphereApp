import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../backup_service.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';

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
        title: const Text('Backups'),
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
                  SnackBar(content: Text('Backup created and synced successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to create backup: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
                  const Icon(Icons.backup_outlined, size: 80, color: Color(0xFF34A853)),
                  const SizedBox(height: 24),
                  Text(
                    'No backups available',
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await backupService.triggerBackup(
                          onBackupComplete: () {
                            _refreshBackups();
                          },
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Backup created and synced successfully')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to create backup: $e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create Your First Backup'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                              SnackBar(content: Text('Restore failed: backup path is null')),
                            );
                            return;
                          }
                          try {
                            await backupService.restoreBackup(backupPath);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Backup restored successfully')),
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
                              content: const Text('Are you sure you want to delete this backup?'),
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
                                SnackBar(content: Text('Backup deleted successfully')),
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
    );
  }
}
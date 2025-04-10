import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../backup_service.dart';
import 'package:securesphere/common/widgets/app_drawer.dart';

class BackupsScreen extends StatelessWidget {
  const BackupsScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    final BackupService backupService = Get.find<BackupService>();
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
                await backupService.triggerBackup();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Backup created successfully')),
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
        future: backupService.getBackups(),
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
                        await backupService.triggerBackup();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Backup created successfully')),
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
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF1E8E3E),
                    child: Icon(Icons.backup, color: Colors.white),
                  ),
                  title: Text(
                    backup['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    backup['date'],
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore, color: Color(0xFF34A853)),
                    onPressed: () async {
                      try {
                        await backupService.restoreBackup(backup['path']);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Backup restored successfully')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Restore failed: $e')),
                        );
                      }
                    },
                  )
                )
              );
            },
          );
        },
      ),
    );
  }
}
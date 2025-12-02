import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../backup_service.dart';
import 'package:decvault/common/widgets/custom_title_bar.dart';

class DesktopBackupsScreen extends StatefulWidget {
  const DesktopBackupsScreen({super.key});

  @override
  State<DesktopBackupsScreen> createState() => _DesktopBackupsScreenState();
}

class _DesktopBackupsScreenState extends State<DesktopBackupsScreen> {
  late Future<List<Map<String, dynamic>>> _backupsFuture;
  final BackupService _backupService = Get.find<BackupService>();
  
  List<Map<String, dynamic>> _backups = [];
  List<Map<String, dynamic>> _filteredBackups = [];
  bool _isLoading = true;
  bool _isCreatingBackup = false;
  Map<String, dynamic>? _selectedBackup;
  
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _sortBy = 'date'; // date, name, size
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _setupKeyboardShortcuts();
    _loadBackups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _setupKeyboardShortcuts() {
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+F for search
      if (event.logicalKey == LogicalKeyboardKey.keyF && 
          HardwareKeyboard.instance.isControlPressed) {
        _searchFocusNode.requestFocus();
        return true;
      }
      // Ctrl+N for new backup
      if (event.logicalKey == LogicalKeyboardKey.keyN && 
          HardwareKeyboard.instance.isControlPressed) {
        _createBackup();
        return true;
      }
      // Ctrl+R for refresh
      if (event.logicalKey == LogicalKeyboardKey.keyR && 
          HardwareKeyboard.instance.isControlPressed) {
        _loadBackups();
        return true;
      }
      // Delete key for delete backup
      if (event.logicalKey == LogicalKeyboardKey.delete && _selectedBackup != null) {
        _confirmDeleteBackup(_selectedBackup!);
        return true;
      }
      // Escape to clear selection/search
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_searchController.text.isNotEmpty) {
          _clearSearch();
        } else {
          setState(() => _selectedBackup = null);
        }
        return true;
      }
    }
    return false;
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final backups = await _backupService.getBackups();
      setState(() {
        _backups = backups;
        _filteredBackups = List.from(backups);
        _isLoading = false;
      });
      _sortBackups();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Failed to load backups: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _filterBackups(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredBackups = List.from(_backups);
      } else {
        _filteredBackups = _backups.where((backup) {
          final name = backup['name']?.toString().toLowerCase() ?? '';
          final originalName = backup['originalName']?.toString().toLowerCase() ?? '';
          final lowerQuery = query.toLowerCase();
          
          return name.contains(lowerQuery) || originalName.contains(lowerQuery);
        }).toList();
      }
      _sortBackups();
    });
  }

  void _sortBackups() {
    setState(() {
      _filteredBackups.sort((a, b) {
        int comparison;
        switch (_sortBy) {
          case 'name':
            final aName = a['originalName'] ?? a['name'] ?? '';
            final bName = b['originalName'] ?? b['name'] ?? '';
            comparison = aName.toString().compareTo(bName.toString());
            break;
          case 'size':
            final aSize = a['size'] ?? 0;
            final bSize = b['size'] ?? 0;
            comparison = aSize.compareTo(bSize);
            break;
          case 'date':
          default:
            final aDate = a['createdAt'] ?? a['timestamp'] ?? '';
            final bDate = b['createdAt'] ?? b['timestamp'] ?? '';
            comparison = aDate.toString().compareTo(bDate.toString());
            break;
        }
        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _filterBackups('');
    FocusScope.of(context).unfocus();
  }

  Future<void> _createBackup() async {
    if (_isCreatingBackup) return;

    setState(() {
      _isCreatingBackup = true;
    });

    try {
      await _backupService.triggerBackup(
        onBackupComplete: () {
          _loadBackups();
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Success: Snapshot created and synced successfully'),
            backgroundColor: const Color(0xFF34A853),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Failed to create snapshot: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() {
        _isCreatingBackup = false;
      });
    }
  }

  Future<void> _restoreBackup(Map<String, dynamic> backup) async {
    final backupPath = backup['path'];
    
    if (backupPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error: Restore failed - snapshot path is null'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Restore Snapshot', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will replace all current data with the snapshot data. This action cannot be undone.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Text(
              'Snapshot: ${backup['originalName'] ?? backup['name']}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            Text(
              'Created: ${_formatDate(backup['createdAt'] ?? backup['timestamp'])}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34A853),
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _backupService.restoreBackup(backupPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Success: Snapshot restored successfully'),
            backgroundColor: const Color(0xFF34A853),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      _loadBackups();
      
      // Navigate back to home to refresh password list
      Get.offAllNamed('/home');
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString();
        String userFriendlyMessage = 'Restore failed: $e';
        
        // Check if it's a decryption error
        if (errorMessage.contains('pad block') || 
            errorMessage.contains('decrypt') || 
            errorMessage.contains('Invalid argument')) {
          userFriendlyMessage = 'Cannot restore this snapshot - it was created with a different account or seed phrase. '
              'Snapshots can only be restored on the same account that created them.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $userFriendlyMessage'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 7),
          ),
        );
      }
    }
  }

  void _confirmDeleteBackup(Map<String, dynamic> backup) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Snapshot', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Are you sure you want to delete this snapshot? This action cannot be undone.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Text(
              backup['originalName'] ?? backup['name'] ?? 'Unknown snapshot',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteBackup(backup);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBackup(Map<String, dynamic> backup) async {
    // Note: Implement delete functionality in BackupService if needed
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Info: Delete functionality not yet implemented'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _formatDate(dynamic dateString) {
    if (dateString == null || dateString.toString().isEmpty) {
      return 'Unknown';
    }
    
    try {
      final date = DateTime.parse(dateString.toString());
      return DateFormat('MMM dd, yyyy HH:mm').format(date);
    } catch (e) {
      return dateString.toString();
    }
  }

  String _formatFileSize(dynamic size) {
    if (size == null) return 'Unknown size';
    
    try {
      final bytes = int.parse(size.toString());
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } catch (e) {
      return size.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          right: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.backup, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Snapshots',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Data Management',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Create Snapshot Button
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton.icon(
              onPressed: _isCreatingBackup ? null : _createBackup,
              icon: _isCreatingBackup 
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 18),
              label: Text(_isCreatingBackup ? 'Creating...' : 'Create Snapshot'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: const Color(0xFF34A853),
              ),
            ),
          ),
          
          const Divider(color: Color(0xFF3C4043)),
          
          // Statistics
          if (_backups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Statistics',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatItem('Total Snapshots', _backups.length.toString()),
                  _buildStatItem('Encrypted', _backups.where((b) => b['isEncrypted'] == true).length.toString()),
                  _buildStatItem('Latest', _getLatestBackupDate()),
                ],
              ),
            ),
            
            const Divider(color: Color(0xFF3C4043)),
          ],
          
          const Spacer(),
          
          // Keyboard shortcuts info
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Ctrl+N • Create\nCtrl+R • Refresh\nCtrl+F • Search\nDel • Delete',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          
          // Back to Home
          Container(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () {
                try {
                  Get.back();
                } catch (e) {
                  // Already on the correct page or navigation failed
                }
              },
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Home'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF34A853),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getLatestBackupDate() {
    if (_backups.isEmpty) return 'None';
    
    try {
      final latest = _backups.reduce((a, b) {
        final aDate = a['createdAt'] ?? a['timestamp'] ?? '';
        final bDate = b['createdAt'] ?? b['timestamp'] ?? '';
        return aDate.toString().compareTo(bDate.toString()) > 0 ? a : b;
      });
      
      final dateStr = latest['createdAt'] ?? latest['timestamp'];
      if (dateStr != null) {
        final date = DateTime.parse(dateStr.toString());
        final now = DateTime.now();
        final difference = now.difference(date);
        
        if (difference.inDays > 0) {
          return '${difference.inDays}d ago';
        } else if (difference.inHours > 0) {
          return '${difference.inHours}h ago';
        } else {
          return '${difference.inMinutes}m ago';
        }
      }
    } catch (e) {
      // Fall back to a simple format
    }
    
    return 'Unknown';
  }

  Widget _buildMainContent() {
    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildBackupsList(),
                ),
                if (_selectedBackup != null)
                  Expanded(
                    flex: 1,
                    child: _buildBackupDetails(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Snapshot Management',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          
          // Search
          SizedBox(
            width: 300,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _filterBackups,
              decoration: InputDecoration(
                hintText: 'Search snapshots... (Ctrl+F)',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.clear, size: 20),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Sort Dropdown
          DropdownButton<String>(
            value: _sortBy,
            items: const [
              DropdownMenuItem(value: 'date', child: Text('Date')),
              DropdownMenuItem(value: 'name', child: Text('Name')),
              DropdownMenuItem(value: 'size', child: Text('Size')),
            ],
            onChanged: (value) {
              setState(() {
                _sortBy = value!;
              });
              _sortBackups();
            },
            underline: Container(),
          ),
          
          IconButton(
            onPressed: () {
              setState(() {
                _sortAscending = !_sortAscending;
              });
              _sortBackups();
            },
            icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _sortAscending ? 'Sort Descending' : 'Sort Ascending',
          ),
          
          const SizedBox(width: 16),
          
          // Refresh Button
          Tooltip(
            message: 'Refresh Snapshots (Ctrl+R)',
            child: IconButton(
              onPressed: _isLoading ? null : _loadBackups,
              icon: _isLoading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 20),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Create Snapshot Button
          Tooltip(
            message: 'Create Snapshot (Ctrl+N)',
            child: ElevatedButton.icon(
              onPressed: _isCreatingBackup ? null : _createBackup,
              icon: _isCreatingBackup 
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 18),
              label: Text(_isCreatingBackup ? 'Creating...' : 'Create'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredBackups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchController.text.isNotEmpty
                  ? Icons.search_off
                  : Icons.backup_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No snapshots found'
                  : 'No snapshots available',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Try a different search term'
                  : 'Create your first snapshot to get started',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
            if (_searchController.text.isEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _createBackup,
                icon: const Icon(Icons.add),
                label: const Text('Create Your First Snapshot'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF34A853),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredBackups.length,
      itemBuilder: (context, index) {
        final backup = _filteredBackups[index];
        return _buildBackupCard(backup);
      },
    );
  }

  Widget _buildBackupCard(Map<String, dynamic> backup) {
    final isSelected = _selectedBackup == backup;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: isSelected 
            ? const Color(0xFF34A853).withOpacity(0.1)
            : const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected 
                ? const Color(0xFF34A853)
                : const Color(0xFF3C4043),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => setState(() => _selectedBackup = backup),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: backup['isEncrypted'] == true 
                        ? const Color(0xFF34A853).withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    backup['isEncrypted'] == true ? Icons.lock : Icons.backup,
                    color: backup['isEncrypted'] == true 
                        ? const Color(0xFF34A853)
                        : Colors.grey,
                    size: 24,
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backup['originalName'] ?? backup['name'] ?? 'Unknown snapshot',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? const Color(0xFF34A853) : Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _formatDate(backup['createdAt'] ?? backup['timestamp']),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const Text(' • ', style: TextStyle(color: Colors.white54)),
                          Text(
                            _formatFileSize(backup['size']),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          if (backup['isEncrypted'] == true) ...[
                            const Text(' • ', style: TextStyle(color: Colors.white54)),
                            const Text(
                              'Encrypted',
                              style: TextStyle(
                                color: Color(0xFF34A853),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Actions
                PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'restore',
                      child: Row(
                        children: [
                          Icon(Icons.restore, color: Color(0xFF34A853)),
                          SizedBox(width: 8),
                          Text('Restore'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'restore') {
                      _restoreBackup(backup);
                    } else if (value == 'delete') {
                      _confirmDeleteBackup(backup);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackupDetails() {
    if (_selectedBackup == null) return const SizedBox.shrink();

    final backup = _selectedBackup!;
    
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          left: BorderSide(color: Color(0xFF3C4043), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3C4043), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  backup['isEncrypted'] == true ? Icons.lock : Icons.backup,
                  color: backup['isEncrypted'] == true 
                      ? const Color(0xFF34A853)
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backup['originalName'] ?? backup['name'] ?? 'Unknown snapshot',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (backup['isEncrypted'] == true)
                        const Text(
                          'Encrypted',
                          style: TextStyle(
                            color: Color(0xFF34A853),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedBackup = null),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          
          // Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Created', _formatDate(backup['createdAt'] ?? backup['timestamp'])),
                  _buildDetailRow('Size', _formatFileSize(backup['size'])),
                  _buildDetailRow('Type', backup['isEncrypted'] == true ? 'Encrypted Snapshot' : 'Standard Snapshot'),
                  if (backup['path'] != null)
                    _buildDetailRow('Path', backup['path'].toString()),
                  
                  const SizedBox(height: 24),
                  
                  // Actions
                  ElevatedButton.icon(
                    onPressed: () => _restoreBackup(backup),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore Snapshot'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34A853),
                      minimumSize: const Size(double.infinity, 40),
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  OutlinedButton.icon(
                    onPressed: () => _confirmDeleteBackup(backup),
                    icon: const Icon(Icons.delete),
                    label: const Text('Delete Snapshot'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(double.infinity, 40),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
} 

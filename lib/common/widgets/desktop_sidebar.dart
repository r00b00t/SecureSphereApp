import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DesktopSidebar extends StatelessWidget {
  final String currentRoute;
  final String title;
  final String subtitle;
  final IconData headerIcon;
  final List<DesktopSidebarItem> items;
  final List<Widget>? bottomWidgets;

  const DesktopSidebar({
    super.key,
    required this.currentRoute,
    required this.title,
    required this.subtitle,
    required this.headerIcon,
    required this.items,
    this.bottomWidgets,
  });

  @override
  Widget build(BuildContext context) {
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
                  child: Icon(headerIcon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
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
          
          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: items.map((item) => _buildNavItem(item)).toList(),
            ),
          ),
          
          // Bottom widgets
          if (bottomWidgets != null)
            ...bottomWidgets!,
        ],
      ),
    );
  }

  Widget _buildNavItem(DesktopSidebarItem item) {
    final isSelected = currentRoute == item.route;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isSelected ? const Color(0xFF34A853) : Colors.white70,
          size: 20,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF34A853) : Colors.white70,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        trailing: item.badge != null 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF34A853).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.badge!,
                  style: const TextStyle(
                    color: Color(0xFF34A853),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right, color: Colors.white54),
        selected: isSelected,
        selectedTileColor: const Color(0xFF34A853).withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: item.onTap ?? () => Get.offNamed(item.route),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

class DesktopSidebarItem {
  final String route;
  final String label;
  final IconData icon;
  final String? badge;
  final VoidCallback? onTap;

  const DesktopSidebarItem({
    required this.route,
    required this.label,
    required this.icon,
    this.badge,
    this.onTap,
  });
} 
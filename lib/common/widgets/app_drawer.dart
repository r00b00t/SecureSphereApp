import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:securesphere/features/auth/services/auth_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: const Color(0xFF121212), // Dark background
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF1E8E3E), // Green header
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.security,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'SecureSphere',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Secure Password Manager',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(
              icon: Icons.password,
              title: 'Passwords',
              onTap: () {
                Navigator.pop(context);
                Get.offNamed('/home');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.backup,
              title: 'Backups',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/backups');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.password_rounded,
              title: 'Password Generator',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/password-generator');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.settings,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/settings');
              },
              context: context,
            ),
            const Divider(color: Color(0xFF3C4043)),
            _buildDrawerItem(
              icon: Icons.logout,
              title: 'Sign Out',
              onTap: () async {
                Navigator.pop(context);
                // Get the auth service and log out the user
                final authService = Get.find<AuthService>();
                await authService.logoutUser();
                // Navigate to login screen
                Get.offAllNamed('/login');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.info_outline,
              title: 'About',
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement about screen
              },
              context: context,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: const Color(0xFF34A853), // Green icon
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white,
            ),
      ),
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.comfortable,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      hoverColor: const Color(0xFF1E8E3E).withOpacity(0.1),
    );
  }
}
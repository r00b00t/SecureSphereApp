import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/auth/services/security_service.dart';
import 'package:decvault/features/auth/screens/pin_unlock_screen.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: const Color(0xFF121212), 
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF1E8E3E),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E8E3E), Color(0xFF34A853)],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Image.asset(
                      'assets/logo/white.png',
                      width: 48,
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Welcome!',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withOpacity(0.8),
                              ),
                        ),
                        Text(
                          'DecVault',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Secure Password Manager',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withOpacity(0.7),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF3C4043), thickness: 1, height: 0),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Text('Main', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            _buildDrawerItem(
              icon: Icons.password,
              iconColor: Color(0xFF34A853),
              title: 'Passwords',
              onTap: () {
                Navigator.pop(context);
                Get.offNamed('/home');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.security,
              iconColor: Color(0xFF1E8E3E),
              title: 'Breach Monitoring',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/breach-monitoring');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.password_rounded,
              iconColor: Color(0xFFF9AB00),
              title: 'Password Generator',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/password-generator');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.backup,
              iconColor: Color(0xFF4285F4),
              title: 'Backups',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/backups');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.folder,
              iconColor: Color(0xFF9C27B0),
              title: 'File Vault',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/vault');
              },
              context: context,
            ),
            
           
            const Divider(color: Color(0xFF3C4043), thickness: 1, height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Text('Advanced', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            _buildSubscriptionItem(context),
             _buildDrawerItem(
              icon: Icons.settings,
              iconColor: Color(0xFFDB4437),
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/settings');
              },
              context: context,
            ),

            _buildDrawerItem(
              icon: Icons.logout,
              iconColor: Color(0xFF8E24AA),
              title: 'Sign Out',
              onTap: () async {
                Navigator.pop(context);
                await _showLogoutConfirmation();
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.info_outline,
              iconColor: Color(0xFF00ACC1),
              title: 'About',
              onTap: () {
                Navigator.pop(context);
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
    Color iconColor = const Color(0xFF34A853),
    required String title,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor,
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
      hoverColor: Colors.white.withOpacity(0.04),
      splashColor: Colors.white.withOpacity(0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      minLeadingWidth: 32,
    );
  }

  Widget _buildSubscriptionItem(BuildContext context) {
    try {
      final revenueCatService = Get.find<RevenueCatService>();
      
      return Obx(() {
        final isPro = revenueCatService.isPro.value;
        
        return ListTile(
          leading: Icon(
            isPro ? Icons.workspace_premium : Icons.star_outline,
            color: const Color(0xFFF9AB00),
          ),
          title: Row(
            children: [
              Text(
                isPro ? 'DecVault Pro' : 'Upgrade to Pro',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
              ),
              if (isPro) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E8E3E),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          onTap: () {
            Navigator.pop(context);
            if (isPro) {
              // If already Pro, show subscription details
              Get.toNamed('/subscription');
            } else {
              // If not Pro, show paywall directly
              revenueCatService.presentPaywall();
            }
          },
          dense: true,
          visualDensity: VisualDensity.comfortable,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          hoverColor: Colors.white.withOpacity(0.04),
          splashColor: Colors.white.withOpacity(0.08),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          minLeadingWidth: 32,
        );
      });
    } catch (e) {
      // RevenueCat service not initialized
      return _buildDrawerItem(
        icon: Icons.star_outline,
        iconColor: const Color(0xFFF9AB00),
        title: 'Upgrade to Pro',
        onTap: () {
          Navigator.pop(context);
          Get.toNamed('/subscription');
        },
        context: context,
      );
    }
  }

  Future<void> _showLogoutConfirmation() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.logout, color: Color(0xFF8E24AA)),
            const SizedBox(width: 8),
            const Text('Sign Out'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to sign out?',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'You will need your recovery phrase to sign back in.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E24AA),
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final authService = Get.find<AuthService>();
        await authService.logoutUser();
        Get.offAllNamed('/auth');
      } catch (e) {
        // Use context to show snackbar safely
        final scaffoldContext = Get.context;
        if (scaffoldContext != null && scaffoldContext.mounted) {
          ScaffoldMessenger.of(scaffoldContext).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.info, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Notice',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          'Sign out could not be completed.',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange.withOpacity(0.8),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      }
    }
  }
}
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:decvault/features/auth/services/auth_service.dart';
import 'package:decvault/features/subscription/services/revenuecat_service.dart';
import 'package:decvault/features/decentralized/services/decentralized_service.dart';

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
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
              child: Text(
                'Main',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
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
              icon: Icons.folder_special,
              title: 'File Vault',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/vault');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.vpn_key,
              title: 'Password Generator',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/password-generator');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.security,
              title: 'Breach Monitoring',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/breach-monitoring');
              },
              context: context,
            ),
            const Divider(color: Color(0xFF3C4043), thickness: 1, height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
              child: Text(
                'Advanced',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            _buildDrawerItem(
              icon: Icons.backup,
              title: 'Snapshots',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/backups');
              },
              context: context,
            ),
            _buildSubscriptionItem(context),
            _buildDrawerItem(
              icon: Icons.settings,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/settings');
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.logout,
              title: 'Sign Out',
              onTap: () async {
                Navigator.pop(context);
                await _showLogoutConfirmation();
              },
              context: context,
            ),
            _buildDrawerItem(
              icon: Icons.info_outline,
              title: 'About',
              onTap: () {
                Navigator.pop(context);
                Get.toNamed('/about');
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
    Color iconColor = Colors.white70,
    required String title,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          icon,
          color: iconColor,
          size: 22,
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
        ),
        onTap: onTap,
        dense: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        hoverColor: Colors.white.withOpacity(0.05),
        splashColor: Colors.white.withOpacity(0.08),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        minLeadingWidth: 40,
        minVerticalPadding: 8,
      ),
    );
  }

  Widget _buildSubscriptionItem(BuildContext context) {
    // Path A: no subscription needed
    try {
      final decSvc = Get.find<DecentralizedService>();
      if (decSvc.isDecentralized) return const SizedBox.shrink();
    } catch (_) {}

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
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          minLeadingWidth: 40,
          minVerticalPadding: 8,
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
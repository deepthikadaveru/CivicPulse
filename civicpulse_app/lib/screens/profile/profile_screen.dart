import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../auth/phone_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          // Avatar
          Center(
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  (user?['name'] ?? 'U').substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(user?['name'] ?? 'User',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          Center(child: Text(user?['phone_number'] ?? '',
            style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(height: 6),
          Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(20)),
            child: Text((user?['role'] ?? 'citizen').replaceAll('_', ' '),
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
          )),
          const SizedBox(height: 32),

          // Settings tiles
          Card(child: Column(children: [
            ListTile(
              leading: const Icon(Icons.location_city_outlined, color: AppColors.primary),
              title: const Text('My City'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {},
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.notifications_outlined, color: AppColors.primary),
              title: const Text('Notifications'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {},
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.info_outline, color: AppColors.primary),
              title: const Text('About CivicPulse'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {},
            ),
          ])),
          const SizedBox(height: 16),

          // Logout
          OutlinedButton.icon(
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (_) => const PhoneScreen()), (_) => false);
              }
            },
            icon: const Icon(Icons.logout, color: AppColors.critical),
            label: const Text('Log out', style: TextStyle(color: AppColors.critical)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.critical),
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ],
      ),
    );
  }
}

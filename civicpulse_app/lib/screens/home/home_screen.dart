import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/api/api_client.dart';
import '../../providers/issues_provider.dart';
import '../map/map_screen.dart';
import '../report/report_screen.dart';
import 'issues_list_screen.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    IssuesListScreen(),
    MapScreen(),
    ReportScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _setupCity();
  }

  Future<void> _setupCity() async {
    final prefs = await SharedPreferences.getInstance();
    // If city not set, fetch first available city and store it
    if (prefs.getString(AppConstants.cityKey) == null) {
      try {
        final cities = await ApiClient().getCities();
        if (cities.isNotEmpty) {
          await prefs.setString(AppConstants.cityKey, cities[0]['id']);
        }
      } catch (_) {}
    }
    if (mounted) {
      context.read<IssuesProvider>().loadIssues(refresh: true);
      context.read<IssuesProvider>().loadCategories();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primaryLight,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Issues'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Report'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

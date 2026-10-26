import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/partner_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/export_data.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _noticeShown = false;

  static const _screens = <Widget>[
    HomeScreen(),
    CalendarScreen(),
    InsightsScreen(),
    PartnerScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Once per account, after the quiz: her logs live only on this phone.
    if (ref.watch(dataNoticeProvider).valueOrNull == false && !_noticeShown) {
      _noticeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showDataNotice(context, ref);
      });
    }
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.brightness_3_outlined),
            selectedIcon: Icon(Icons.brightness_3),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Patterns',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Partner',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

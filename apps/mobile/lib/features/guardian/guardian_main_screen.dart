import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'guardian_home_screen.dart';
import 'family_link_screen.dart';
import 'guardian_stats_screen.dart';
import 'guardian_calendar_screen.dart';

class GuardianMainScreen extends StatefulWidget {
  const GuardianMainScreen({super.key});

  @override
  State<GuardianMainScreen> createState() => _GuardianMainScreenState();
}

class _GuardianMainScreenState extends State<GuardianMainScreen> {
  int _currentIndex = 0;
  final _calendarKey = GlobalKey<GuardianCalendarScreenState>();

  Future<bool> _onWillPop() async => false;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            const GuardianHomeScreen(),
            const GuardianStatsScreen(),
            GuardianCalendarScreen(key: _calendarKey),
            const FamilyLinkScreen(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            if (i == 2 && _currentIndex == 2) {
              _calendarKey.currentState?.load();
            }
            setState(() => _currentIndex = i);
          },
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textSecondary,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: '통계',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              activeIcon: Icon(Icons.calendar_month),
              label: '달력',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: '가족 연동',
            ),
          ],
        ),
      ),
    );
  }
}

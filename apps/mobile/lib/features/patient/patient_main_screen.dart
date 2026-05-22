import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'patient_home_screen.dart';
import 'medicine_list_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';

class PatientMainScreen extends StatefulWidget {
  const PatientMainScreen({super.key});

  @override
  State<PatientMainScreen> createState() => _PatientMainScreenState();
}

class _PatientMainScreenState extends State<PatientMainScreen> {
  int _currentIndex = 0;

  final _homeKey = GlobalKey<PatientHomeScreenState>();
  final _historyKey = GlobalKey<HistoryScreenState>();
  final _statsKey = GlobalKey<StatsScreenState>();

  Future<bool> _onWillPop() async => false;

  void _onTabTap(int i) {
    if (i == _currentIndex) return;
    setState(() => _currentIndex = i);
    // 프레임 렌더링 완료 후 새로고침 (currentState null 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (i == 0) _homeKey.currentState?.load();
      if (i == 2) _historyKey.currentState?.load();
      if (i == 3) _statsKey.currentState?.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            PatientHomeScreen(key: _homeKey),
            const MedicineListScreen(),
            HistoryScreen(key: _historyKey),
            StatsScreen(key: _statsKey),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTap,
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
              icon: Icon(Icons.medication_outlined),
              activeIcon: Icon(Icons.medication),
              label: '내 약',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: '기록',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: '통계',
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class GuardianStatsScreen extends StatefulWidget {
  const GuardianStatsScreen({super.key});

  @override
  State<GuardianStatsScreen> createState() => _GuardianStatsScreenState();
}

class _GuardianStatsScreenState extends State<GuardianStatsScreen>
    with SingleTickerProviderStateMixin {
  int? _guardianId;
  String? _token;
  List<dynamic> _patients = [];
  Map<int, Map<String, dynamic>> _statsMap7 = {};
  Map<int, Map<String, dynamic>> _statsMap30 = {};
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _guardianId = await Storage.getUserId();
    _token = await Storage.getToken();
    await _load();
  }

  Future<void> _load() async {
    if (_guardianId == null || _token == null) return;
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/family-map/$_guardianId/patients', token: _token);
      final patients = res['data'] as List<dynamic>? ?? [];

      final statsMap7 = <int, Map<String, dynamic>>{};
      final statsMap30 = <int, Map<String, dynamic>>{};

      for (final p in patients) {
        final pid = p['user_id'] as int;
        try {
          final r7 = await ApiClient.get('/statistics/adherence', token: _token,
              queryParams: {'patient_id': pid.toString(), 'period': '7'});
          statsMap7[pid] = r7['data'] as Map<String, dynamic>? ?? {};

          final r30 = await ApiClient.get('/statistics/adherence', token: _token,
              queryParams: {'patient_id': pid.toString(), 'period': '30'});
          statsMap30[pid] = r30['data'] as Map<String, dynamic>? ?? {};
        } catch (_) {
          statsMap7[pid] = {};
          statsMap30[pid] = {};
        }
      }

      if (mounted) {
        setState(() {
          _patients = patients;
          _statsMap7 = statsMap7;
          _statsMap30 = statsMap30;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('가족 통계'),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: '최근 7일'),
            Tab(text: '최근 30일'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_statsMap7, 7),
                _buildList(_statsMap30, 30),
              ],
            ),
    );
  }

  Widget _buildList(Map<int, Map<String, dynamic>> statsMap, int period) {
    if (_patients.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary),
            SizedBox(height: 16),
            Text('연동된 가족이 없어요', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _patients.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => _buildPatientStats(_patients[i], statsMap, period),
      ),
    );
  }

  Widget _buildPatientStats(dynamic patient, Map<int, Map<String, dynamic>> statsMap, int period) {
    final pid = patient['user_id'] as int;
    final stats = statsMap[pid] ?? {};
    final daily = stats['daily_adherence'] as List<dynamic>? ?? [];
    final weeklyPoints = (stats['weekly_points'] as num?)?.toInt() ?? 0;
    final totalPoints = (stats['total_points'] as num?)?.toInt() ?? 0;
    final grade = stats['grade'] as String? ?? 'C';
    final totalTaken = (stats['total_taken'] as num?)?.toInt() ?? 0;

    final gradeColor = {
      'S': Colors.purple,
      'A': Colors.orange,
      'B': Colors.blue,
      'C': Colors.grey,
    }[grade] ?? Colors.grey;

    // 날짜 생성
    final today = DateTime.now();
    final days = List.generate(period, (i) => today.subtract(Duration(days: period - 1 - i)));
    final countMap = <String, int>{};
    for (final d in daily) {
      final date = (d['date'] as String).substring(0, 10);
      countMap[date] = (d['taken_count'] as num).toInt();
    }
    final maxCount = countMap.values.isEmpty ? 1 : countMap.values.reduce((a, b) => a > b ? a : b);

    // 30일은 주별로 묶어서 표시
    final showWeekly = period == 30;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    patient['name'] as String? ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(12)),
                  child: Text('등급 $grade', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 요약 칩
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chip('이번주 ${weeklyPoints}P', Icons.star, Colors.amber),
                    _chip('누적 ${totalPoints}P', Icons.emoji_events, Colors.orange),
                    _chip('총 ${totalTaken}회 복약', Icons.medication, AppTheme.primary),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  showWeekly ? '주별 복약 현황' : '최근 7일 복약',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 10),

                showWeekly
                    ? _buildWeeklyBars(days, countMap, maxCount)
                    : _buildDailyBars(days, countMap, maxCount, today),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 7일 일별 바 차트
  Widget _buildDailyBars(List<DateTime> days, Map<String, int> countMap, int maxCount, DateTime today) {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: days.map((day) {
        final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final count = countMap[key] ?? 0;
        final ratio = maxCount > 0 ? count / maxCount : 0.0;
        final label = weekdays[day.weekday - 1];
        final isToday = day.day == today.day && day.month == today.month;

        return Column(
          children: [
            Text('$count', style: TextStyle(fontSize: 10, color: count > 0 ? AppTheme.primary : AppTheme.textSecondary)),
            const SizedBox(height: 3),
            Container(
              width: 28,
              height: 70,
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 28,
                height: ratio * 70 < 4 ? (count > 0 ? 4 : 0) : ratio * 70,
                decoration: BoxDecoration(
                  color: count > 0 ? AppTheme.primary : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              fontSize: 11,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
              color: isToday ? AppTheme.primary : AppTheme.textSecondary,
            )),
          ],
        );
      }).toList(),
    );
  }

  // 30일 주별 바 차트 (4~5주)
  Widget _buildWeeklyBars(List<DateTime> days, Map<String, int> countMap, int maxCount) {
    // 주별로 묶기
    final weekTotals = <String, int>{};
    for (final day in days) {
      final monday = day.subtract(Duration(days: day.weekday - 1));
      final weekKey = DateFormat('M/d').format(monday);
      final dayKey = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      weekTotals[weekKey] = (weekTotals[weekKey] ?? 0) + (countMap[dayKey] ?? 0);
    }
    final weeks = weekTotals.keys.toList();
    final maxWeek = weekTotals.values.isEmpty ? 1 : weekTotals.values.reduce((a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: weeks.map((w) {
        final count = weekTotals[w] ?? 0;
        final ratio = maxWeek > 0 ? count / maxWeek : 0.0;
        return Column(
          children: [
            Text('$count', style: TextStyle(fontSize: 10, color: count > 0 ? AppTheme.primary : AppTheme.textSecondary)),
            const SizedBox(height: 3),
            Container(
              width: 36,
              height: 70,
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 36,
                height: ratio * 70 < 4 ? (count > 0 ? 4 : 0) : ratio * 70,
                decoration: BoxDecoration(
                  color: count > 0 ? AppTheme.primary : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(w, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
          ],
        );
      }).toList(),
    );
  }

  Widget _chip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => StatsScreenState();
}

class StatsScreenState extends State<StatsScreen> {
  int? _userId;
  String? _token;
  bool _loading = true;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _userId = await Storage.getUserId();
    _token = await Storage.getToken();
    await _load();
  }

  // 외부(PatientMainScreen)에서 탭 전환 시 호출
  Future<void> load() => _load();

  Future<void> _load() async {
    if (_userId == null || _token == null) return;
    try {
      final res = await ApiClient.get(
        '/statistics/adherence',
        token: _token,
        queryParams: {'patient_id': _userId.toString(), 'period': '7'},
      );
      if (mounted) {
        setState(() {
          _stats = res['data'] as Map<String, dynamic>?;
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
        title: const Text('내 통계'),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPointsCard(),
                    const SizedBox(height: 16),
                    _buildWeeklyChart(),
                    const SizedBox(height: 16),
                    _buildBadges(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPointsCard() {
    final totalPoints = _stats?['total_points'] as num? ?? 0;
    final weeklyPoints = _stats?['weekly_points'] as num? ?? 0;
    final grade = _stats?['grade'] as String? ?? 'C';
    final totalTaken = _stats?['total_taken'] as num? ?? 0;

    final gradeColor = {
      'S': Colors.purple,
      'A': Colors.orange,
      'B': Colors.blue,
      'C': Colors.grey,
    }[grade] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('내 포인트', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: gradeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '등급 $grade',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${totalPoints.toInt()} P',
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statChip('이번주 +${weeklyPoints.toInt()}P', Icons.trending_up),
              const SizedBox(width: 12),
              _statChip('총 ${totalTaken.toInt()}회 복약', Icons.medication),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart() {
    final daily = _stats?['daily_adherence'] as List<dynamic>? ?? [];

    // 최근 7일 날짜 생성
    final today = DateTime.now();
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));

    // 날짜별 복약 횟수 맵
    final countMap = <String, int>{};
    for (final d in daily) {
      final date = d['date'] as String;
      countMap[date.substring(0, 10)] = (d['taken_count'] as num).toInt();
    }

    final maxCount = countMap.values.isEmpty ? 1 : countMap.values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('최근 7일 복약 기록', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: days.map((day) {
              final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
              final count = countMap[key] ?? 0;
              final ratio = maxCount > 0 ? count / maxCount : 0.0;
              final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
              final label = weekdays[day.weekday - 1];
              final isToday = day.day == today.day && day.month == today.month;

              return Column(
                children: [
                  Text('$count', style: TextStyle(fontSize: 11, color: count > 0 ? AppTheme.primary : AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Container(
                    width: 28,
                    height: 80,
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 28,
                      height: ratio * 80 < 6 ? (count > 0 ? 6 : 0) : ratio * 80,
                      decoration: BoxDecoration(
                        color: count > 0 ? AppTheme.primary : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                      color: isToday ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBadges() {
    final badges = _stats?['badges'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('획득한 배지', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (badges.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('아직 배지가 없어요\n복약을 시작해보세요!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: badges.map((b) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Center(
                        child: Text(b['icon'] as String, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(b['label'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  int? _userId;
  String? _token;
  List<dynamic> _history = [];
  bool _loading = true;

  final _timeSlotLabels = {
    'morning': '아침',
    'lunch': '점심',
    'dinner': '저녁',
    'bedtime': '취침',
  };

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
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get(
        '/intake-logs/history',
        token: _token,
        queryParams: {'patient_id': _userId.toString(), 'limit': '50'},
      );
      if (mounted) {
        setState(() {
          _history = res['data'] as List<dynamic>? ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelIntake(int logId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('복약 취소'),
        content: const Text('이 복약 기록을 취소할까요?\n포인트 100점이 차감됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니요'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiClient.delete('/intake-logs/$logId', token: _token);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복약 기록이 취소되었습니다.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('복약 기록'),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _history.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.35),
                        const Column(
                          children: [
                            Icon(Icons.history, size: 64, color: AppTheme.textSecondary),
                            SizedBox(height: 16),
                            Text('복약 기록이 없어요', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                          ],
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildCard(_history[i]),
                    ),
            ),
    );
  }

  Widget _buildCard(dynamic log) {
    // 백엔드가 KST(UTC+9)로 변환해서 내려줌
    final takenAt = DateTime.tryParse(log['taken_at'] as String? ?? '');
    final dateStr = takenAt != null
        ? DateFormat('M월 d일 (E)', 'ko').format(takenAt)
        : '';
    final timeStr = takenAt != null ? DateFormat('HH:mm').format(takenAt) : '';
    final slot = _timeSlotLabels[log['time_slot']] ?? log['time_slot'] as String? ?? '';
    final logId = log['log_id'] as int;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log['medicine_name'] as String? ?? '',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${log['dose']}  $slot',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(dateStr, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              Text(timeStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _cancelIntake(logId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    '취소',
                    style: TextStyle(fontSize: 11, color: Colors.red.shade600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

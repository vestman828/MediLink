import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';
import 'daily_note_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  int? _userId;
  String? _token;
  List<dynamic> _history = [];
  // 월별 메모 캐시: 'yyyy-MM' -> list
  Map<String, List<dynamic>> _monthlyNotes = {};
  bool _loading = true;
  bool _showCalendar = false;

  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;

  final _timeSlotLabels = {
    'morning': '아침',
    'lunch': '점심',
    'dinner': '저녁',
    'bedtime': '취침',
    'custom': '직접설정',
  };
  final _conditionEmojis = ['😞', '😕', '😐', '🙂', '😊'];

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

  Future<void> load() => _load();

  Future<void> _load() async {
    if (_userId == null || _token == null) return;
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get(
        '/intake-logs/history',
        token: _token,
        queryParams: {'patient_id': _userId.toString(), 'limit': '200'},
      );
      if (mounted) {
        setState(() {
          _history = res['data'] as List<dynamic>? ?? [];
          _loading = false;
        });
      }
      // 현재 달 메모도 같이 로드
      await _loadMonthlyNotes(_focusedMonth);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMonthlyNotes(DateTime month) async {
    final key = DateFormat('yyyy-MM').format(month);
    if (_monthlyNotes.containsKey(key)) return;
    try {
      final res = await ApiClient.get(
        '/daily-notes/monthly',
        token: _token,
        queryParams: {'year': month.year.toString(), 'month': month.month.toString()},
      );
      final notes = res['data'] as List<dynamic>? ?? [];
      if (mounted) setState(() => _monthlyNotes[key] = notes);
    } catch (_) {}
  }

  Map<String, List<dynamic>> get _groupedByDate {
    final map = <String, List<dynamic>>{};
    for (final log in _history) {
      final takenAt = DateTime.tryParse(log['taken_at'] as String? ?? '');
      if (takenAt == null) continue;
      final key = DateFormat('yyyy-MM-dd').format(takenAt);
      map.putIfAbsent(key, () => []).add(log);
    }
    return map;
  }

  List<dynamic> get _selectedDayLogs {
    if (_selectedDay == null) return [];
    final key = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    return _groupedByDate[key] ?? [];
  }

  Map<String, dynamic>? _getNoteForDate(DateTime day) {
    final monthKey = DateFormat('yyyy-MM').format(day);
    final dateKey = DateFormat('yyyy-MM-dd').format(day);
    final notes = _monthlyNotes[monthKey] ?? [];
    try {
      return notes.firstWhere(
        (n) => (n['note_date'] as String).startsWith(dateKey),
      ) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  bool _hasLogs(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    return _groupedByDate.containsKey(key);
  }

  bool _hasNote(DateTime day) {
    return _getNoteForDate(day) != null;
  }

  Future<void> _cancelIntake(int logId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('복약 취소'),
        content: const Text('이 복약 기록을 취소할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니요')),
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
        actions: [
          IconButton(
            icon: Icon(_showCalendar ? Icons.list : Icons.calendar_month),
            tooltip: _showCalendar ? '목록 보기' : '달력 보기',
            onPressed: () => setState(() {
              _showCalendar = !_showCalendar;
              _selectedDay = null;
            }),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _showCalendar
              ? _buildCalendarView()
              : _buildListView(),
    );
  }

  // ── 달력 뷰 ──────────────────────────────────────────
  Widget _buildCalendarView() {
    return Column(
      children: [
        _buildCalendarHeader(),
        _buildCalendarGrid(),
        const Divider(height: 1),
        if (_selectedDay != null)
          Expanded(child: _buildSelectedDayDetail())
        else
          Expanded(
            child: Center(
              child: Text('날짜를 선택하면 기록을 볼 수 있어요',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            ),
          ),
      ],
    );
  }

  Widget _buildCalendarHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              final newMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
              setState(() {
                _focusedMonth = newMonth;
                _selectedDay = null;
              });
              _loadMonthlyNotes(newMonth);
            },
          ),
          Text(
            DateFormat('yyyy년 M월').format(_focusedMonth),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              final newMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
              setState(() {
                _focusedMonth = newMonth;
                _selectedDay = null;
              });
              _loadMonthlyNotes(newMonth);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    int startWeekday = firstDay.weekday % 7;

    final days = <DateTime?>[];
    for (int i = 0; i < startWeekday; i++) days.add(null);
    for (int d = 1; d <= lastDay.day; d++) {
      days.add(DateTime(_focusedMonth.year, _focusedMonth.month, d));
    }
    while (days.length % 7 != 0) days.add(null);

    const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: weekdays.map((w) => Expanded(
              child: Center(
                child: Text(w, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: w == '일' ? Colors.red.shade300 : w == '토' ? Colors.blue.shade300 : AppTheme.textSecondary,
                )),
              ),
            )).toList(),
          ),
          const SizedBox(height: 4),
          ...List.generate(days.length ~/ 7, (week) {
            return Row(
              children: List.generate(7, (wd) {
                final day = days[week * 7 + wd];
                if (day == null) return const Expanded(child: SizedBox(height: 50));
                final isSelected = _selectedDay != null &&
                    DateFormat('yyyy-MM-dd').format(day) == DateFormat('yyyy-MM-dd').format(_selectedDay!);
                final isToday = DateFormat('yyyy-MM-dd').format(day) == DateFormat('yyyy-MM-dd').format(DateTime.now());
                final hasLog = _hasLogs(day);
                final hasNote = _hasNote(day);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDay = day),
                    child: Container(
                      height: 50,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : isToday ? AppTheme.primary.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${day.day}', style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.normal,
                            color: isSelected ? Colors.white : wd == 0 ? Colors.red.shade400 : wd == 6 ? Colors.blue.shade400 : null,
                          )),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasLog) Container(width: 5, height: 5, decoration: BoxDecoration(
                                color: isSelected ? Colors.white : Colors.green, shape: BoxShape.circle)),
                              if (hasLog && hasNote) const SizedBox(width: 2),
                              if (hasNote) Container(width: 5, height: 5, decoration: BoxDecoration(
                                color: isSelected ? Colors.white70 : Colors.orange, shape: BoxShape.circle)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
          const SizedBox(height: 8),
          // 범례
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              const Text('복약', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(width: 12),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              const Text('메모', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSelectedDayDetail() {
    final logs = _selectedDayLogs;
    final note = _getNoteForDate(_selectedDay!);
    final dateStr = DateFormat('M월 d일 (E)', 'ko').format(_selectedDay!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 메모 섹션
        if (note != null) ...[
          Row(
            children: [
              const Icon(Icons.edit_note, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              Text('$dateStr 메모', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _conditionEmojis[(note['condition_score'] as int) - 1],
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '컨디션 ${note['condition_score']}점',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ],
                ),
                if ((note['memo'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(note['memo'] as String, style: const TextStyle(fontSize: 14)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 메모 수정 버튼
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => DailyNoteScreen(date: _selectedDay!)));
                if (result == true) {
                  final key = DateFormat('yyyy-MM').format(_selectedDay!);
                  setState(() => _monthlyNotes.remove(key));
                  await _loadMonthlyNotes(_selectedDay!);
                }
              },
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('수정', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 8),
        ] else ...[
          // 메모 없으면 추가 버튼
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push(context,
                MaterialPageRoute(builder: (_) => DailyNoteScreen(date: _selectedDay!)));
              if (result == true) {
                final key = DateFormat('yyyy-MM').format(_selectedDay!);
                setState(() => _monthlyNotes.remove(key));
                await _loadMonthlyNotes(_selectedDay!);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.add, color: Colors.orange.shade600, size: 18),
                  const SizedBox(width: 6),
                  Text('$dateStr 메모 추가하기',
                      style: TextStyle(color: Colors.orange.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 복약 기록 섹션
        Row(
          children: [
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
            const SizedBox(width: 4),
            Text('복약 기록 ${logs.length}건',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        if (logs.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
            child: const Text('이 날은 복약 기록이 없어요', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          )
        else
          ...logs.map((log) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildCard(log),
          )),
      ],
    );
  }

  // ── 리스트 뷰 ─────────────────────────────────────────
  Widget _buildListView() {
    if (_history.isEmpty) {
      return ListView(children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.35),
        const Column(children: [
          Icon(Icons.history, size: 64, color: AppTheme.textSecondary),
          SizedBox(height: 16),
          Text('복약 기록이 없어요', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
        ]),
      ]);
    }

    final grouped = _groupedByDate;
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: sortedDates.length,
        itemBuilder: (_, i) {
          final dateKey = sortedDates[i];
          final dt = DateTime.parse(dateKey);
          final logs = grouped[dateKey]!;
          final note = _getNoteForDate(dt);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 8, top: i == 0 ? 0 : 16),
                child: Row(
                  children: [
                    Text(DateFormat('M월 d일 (E)', 'ko').format(dt),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                    if (note != null) ...[
                      const SizedBox(width: 8),
                      Text(_conditionEmojis[(note['condition_score'] as int) - 1],
                          style: const TextStyle(fontSize: 14)),
                    ],
                  ],
                ),
              ),
              ...logs.map((log) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildCard(log),
              )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(dynamic log) {
    final takenAt = DateTime.tryParse(log['taken_at'] as String? ?? '');
    final timeStr = takenAt != null ? DateFormat('HH:mm').format(takenAt) : '';
    final slot = _timeSlotLabels[log['time_slot']] ?? log['time_slot'] as String? ?? '';
    final logId = log['log_id'] as int;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log['medicine_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${log['dose']}  $slot',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(timeStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _cancelIntake(logId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text('취소', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

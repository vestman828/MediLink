import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class GuardianCalendarScreen extends StatefulWidget {
  const GuardianCalendarScreen({super.key});

  @override
  State<GuardianCalendarScreen> createState() => GuardianCalendarScreenState();
}

class GuardianCalendarScreenState extends State<GuardianCalendarScreen> {
  int? _userId;
  String? _token;
  List<dynamic> _patients = [];
  int? _selectedPatientId;
  String _selectedPatientName = '';

  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;

  // 날짜별 복약 기록: 'yyyy-MM-dd' -> list
  Map<String, List<dynamic>> _intakeLogs = {};
  // 날짜별 메모: 'yyyy-MM-dd' -> map
  Map<String, Map<String, dynamic>> _notes = {};

  bool _loading = true;
  bool _dataLoading = false;

  final _conditionEmojis = ['😞', '😕', '😐', '🙂', '😊'];
  final _timeSlotLabels = {'morning': '아침', 'lunch': '점심', 'dinner': '저녁', 'bedtime': '취침'};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> load() => _init();

  Future<void> _init() async {
    _userId = await Storage.getUserId();
    _token = await Storage.getToken();
    await _loadPatients();
  }

  Future<void> _loadPatients() async {
    if (_userId == null || _token == null) return;
    try {
      final res = await ApiClient.get(
        '/family-map/$_userId/patients',
        token: _token,
      );
      final patients = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _patients = patients;
          _loading = false;
          if (patients.isNotEmpty && _selectedPatientId == null) {
            final first = patients[0];
            _selectedPatientId = (first['patient_id'] ?? first['user_id']) as int?;
            _selectedPatientName = first['name'] as String? ?? '';
          }
        });
        if (_selectedPatientId != null) await _loadMonthData();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMonthData() async {
    if (_selectedPatientId == null || _token == null) return;
    setState(() => _dataLoading = true);
    try {
      final year = _focusedMonth.year.toString();
      final month = _focusedMonth.month.toString();
      final patientId = _selectedPatientId.toString();

      // 복약 기록 (월별 전용 API)
      final logRes = await ApiClient.get(
        '/intake-logs/patient-history',
        token: _token,
        queryParams: {
          'patient_id': patientId,
          'year': year,
          'month': month,
        },
      );
      final logs = logRes['data'] as List<dynamic>? ?? [];
      final logMap = <String, List<dynamic>>{};
      for (final log in logs) {
        final takenAt = DateTime.tryParse(log['taken_at'] as String? ?? '');
        if (takenAt == null) continue;
        final key = DateFormat('yyyy-MM-dd').format(takenAt);
        logMap.putIfAbsent(key, () => []).add(log);
      }

      // 메모 (월별)
      final noteRes = await ApiClient.get(
        '/daily-notes/patient-monthly',
        token: _token,
        queryParams: {
          'patient_id': patientId,
          'year': year,
          'month': month,
        },
      );
      final noteList = noteRes['data'] as List<dynamic>? ?? [];
      final noteMap = <String, Map<String, dynamic>>{};
      for (final n in noteList) {
        final dateStr = (n['note_date'] as String).substring(0, 10);
        noteMap[dateStr] = n as Map<String, dynamic>;
      }

      if (mounted) {
        setState(() {
          _intakeLogs = logMap;
          _notes = noteMap;
          _dataLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _dataLoading = false);
    }
  }

  bool _hasLog(DateTime day) => _intakeLogs.containsKey(DateFormat('yyyy-MM-dd').format(day));
  bool _hasNote(DateTime day) => _notes.containsKey(DateFormat('yyyy-MM-dd').format(day));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('복약 달력'),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _patients.isEmpty
              ? _buildNoPatientsState()
              : Column(
                  children: [
                    _buildPatientSelector(),
                    _buildCalendarHeader(),
                    _buildCalendarGrid(),
                    const Divider(height: 1),
                    if (_dataLoading)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      )
                    else if (_selectedDay != null)
                      Expanded(child: _buildSelectedDayDetail())
                    else
                      Expanded(
                        child: Center(
                          child: Text('날짜를 선택하면 기록을 볼 수 있어요',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildNoPatientsState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary),
          SizedBox(height: 16),
          Text('연동된 환자가 없어요', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 8),
          Text('가족 연동 탭에서 환자를 연동해주세요',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPatientSelector() {
    if (_patients.length <= 1) {
      // 환자 1명이어도 이름 표시
      return Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.person, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              _selectedPatientName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(width: 6),
            const Text('님의 기록', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.person, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _selectedPatientId,
            underline: const SizedBox.shrink(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Colors.black87,
            ),
            items: _patients.map((p) => DropdownMenuItem<int>(
              value: (p['patient_id'] ?? p['user_id']) as int,
              child: Text('${p['name']}님'),
            )).toList(),
            onChanged: (id) {
              if (id == null) return;
              final patient = _patients.firstWhere(
                (p) => (p['patient_id'] ?? p['user_id']) == id);
              setState(() {
                _selectedPatientId = id;
                _selectedPatientName = patient['name'] as String? ?? '';
                _selectedDay = null;
                _intakeLogs = {};
                _notes = {};
              });
              _loadMonthData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                _selectedDay = null;
                _intakeLogs = {};
                _notes = {};
              });
              _loadMonthData();
            },
          ),
          Text(DateFormat('yyyy년 M월').format(_focusedMonth),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                _selectedDay = null;
                _intakeLogs = {};
                _notes = {};
              });
              _loadMonthData();
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
                final hasLog = _hasLog(day);
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
          const SizedBox(height: 6),
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
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    final dateStr = DateFormat('M월 d일 (E)', 'ko').format(_selectedDay!);
    final logs = _intakeLogs[dateKey] ?? [];
    final note = _notes[dateKey];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 환자 이름 + 날짜 헤더
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_selectedPatientName님',
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
              ),
            ),
            const SizedBox(width: 8),
            Text(dateStr,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 12),

        // 메모 섹션
        if (note != null) ...[
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
                    const Icon(Icons.edit_note, color: Colors.orange, size: 18),
                    const SizedBox(width: 6),
                    Text('$_selectedPatientName님 메모',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const Spacer(),
                    Text(_conditionEmojis[(note['condition_score'] as int) - 1],
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 4),
                    Text('컨디션 ${note['condition_score']}점',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
                if ((note['memo'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(note['memo'] as String, style: const TextStyle(fontSize: 14)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note, color: AppTheme.textSecondary, size: 16),
                const SizedBox(width: 6),
                Text('$_selectedPatientName님이 이 날 메모를 남기지 않았어요',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 복약 기록 섹션
        Row(
          children: [
            const Icon(Icons.medication, size: 16, color: Colors.green),
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
            child: Text('$_selectedPatientName님의 복약 기록이 없어요',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          )
        else
          ...logs.map((log) {
            final takenAt = DateTime.tryParse(log['taken_at'] as String? ?? '');
            final timeStr = takenAt != null ? DateFormat('HH:mm').format(takenAt) : '';
            final slot = _timeSlotLabels[log['time_slot']] ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.check_circle, color: Colors.green, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(log['medicine_name'] as String? ?? '',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text('${log['dose']}  $slot',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(timeStr,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                ],
              ),
            );
          }),
      ],
    );
  }
}

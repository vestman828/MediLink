import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _medicineNameCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  int? _selectedMedicineId;
  String? _selectedMedicineName;
  List<dynamic> _searchResults = [];
  bool _searching = false;
  bool _saving = false;

  // 복용 시간대 선택
  final Map<String, bool> _timeSlots = {
    'morning': false,
    'lunch': false,
    'dinner': false,
    'bedtime': false,
  };

  // 요일 선택
  final Map<int, bool> _days = {
    0: true, 1: true, 2: true, 3: true, 4: true, 5: false, 6: false,
  };

  final _timeSlotTimes = {
    'morning': '08:00:00',
    'lunch': '12:00:00',
    'dinner': '18:00:00',
    'bedtime': '22:00:00',
  };

  final _timeSlotLabels = {
    'morning': '아침',
    'lunch': '점심',
    'dinner': '저녁',
    'bedtime': '취침',
  };

  final _dayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  DateTime? _endDate;

  int? _userId;
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    _userId = await Storage.getUserId();
    _token = await Storage.getToken();
  }

  Future<void> _searchMedicine(String q) async {
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await ApiClient.get('/medicines/search', token: _token, queryParams: {'q': q});
      setState(() {
        _searchResults = res['data'] as List<dynamic>? ?? [];
        _searching = false;
      });
    } catch (_) {
      setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    if (_selectedMedicineId == null) {
      _showSnack('약을 선택해주세요', isError: true);
      return;
    }
    if (_doseCtrl.text.trim().isEmpty) {
      _showSnack('용량을 입력해주세요', isError: true);
      return;
    }
    if (!_timeSlots.values.any((v) => v)) {
      _showSnack('복용 시간대를 하나 이상 선택해주세요', isError: true);
      return;
    }
    if (!_days.values.any((v) => v)) {
      _showSnack('복용 요일을 하나 이상 선택해주세요', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      // 1. patient_medicine 등록
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final pmRes = await ApiClient.post('/patient-medicines', {
        'patient_id': _userId,
        'medicine_id': _selectedMedicineId,
        'dose': _doseCtrl.text.trim(),
        'start_date': today,
        if (_endDate != null) 'end_date': _endDate!.toIso8601String().substring(0, 10),
      }, token: _token);
      final pmId = pmRes['patient_medicine_id'] as int;

      // 2. 선택한 요일 × 시간대로 스케줄 등록
      final selectedSlots = _timeSlots.entries.where((e) => e.value).map((e) => e.key).toList();
      final selectedDays = _days.entries.where((e) => e.value).map((e) => e.key).toList();

      for (final day in selectedDays) {
        for (final slot in selectedSlots) {
          await ApiClient.post('/schedules', {
            'patient_medicine_id': pmId,
            'day_of_week': day,
            'time_slot': slot,
            'scheduled_time': _timeSlotTimes[slot],
          }, token: _token);
        }
      }

      if (mounted) {
        _showSnack('약이 등록되었어요!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showSnack(e.toString(), isError: true);
        setState(() => _saving = false);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('약 추가')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 약 검색
            _sectionTitle('약 이름 검색'),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '약 이름을 입력하세요',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _searching ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))) : null,
              ),
              onChanged: _searchMedicine,
            ),

            // 검색 결과
            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                ),
                child: Column(
                  children: _searchResults.map((m) => ListTile(
                    title: Text(m['name'] as String),
                    subtitle: Text(m['unit'] as String? ?? 'mg'),
                    onTap: () async {
                      final name = m['name'] as String;
                      final existingId = m['medicine_id'];
                      if (existingId != null) {
                        // DB에 있는 약
                        setState(() {
                          _selectedMedicineId = existingId as int;
                          _selectedMedicineName = name;
                          _searchResults = [];
                          _searchCtrl.text = name;
                        });
                      } else {
                        // e약은요 API에서 온 약 → DB에 먼저 등록
                        try {
                          final res = await ApiClient.post(
                            '/medicines',
                            {'name': name, 'unit': m['unit'] as String? ?? '정'},
                            token: _token,
                          );
                          setState(() {
                            _selectedMedicineId = res['medicine_id'] as int;
                            _selectedMedicineName = name;
                            _searchResults = [];
                            _searchCtrl.text = name;
                          });
                        } catch (e) {
                          _showSnack(e.toString(), isError: true);
                        }
                      }
                    },
                  )).toList(),
                ),
              ),

            // 직접 입력 버튼
            if (_selectedMedicineId == null && _searchCtrl.text.isNotEmpty && _searchResults.isEmpty && !_searching)
              TextButton.icon(
                onPressed: () => _registerNewMedicine(_searchCtrl.text.trim()),
                icon: const Icon(Icons.add),
                label: Text('"${_searchCtrl.text}" 새로 등록하기'),
              ),

            if (_selectedMedicineId != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(_selectedMedicineName ?? '', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // 용량
            _sectionTitle('1회 용량'),
            TextField(
              controller: _doseCtrl,
              decoration: InputDecoration(
                hintText: '예: 1정, 500mg',
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 복용 시간대
            _sectionTitle('복용 시간대'),
            Wrap(
              spacing: 8,
              children: _timeSlots.keys.map((slot) {
                final selected = _timeSlots[slot]!;
                return FilterChip(
                  label: Text(_timeSlotLabels[slot]!),
                  selected: selected,
                  onSelected: (v) => setState(() => _timeSlots[slot] = v),
                  selectedColor: AppTheme.primary.withOpacity(0.2),
                  checkmarkColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // 복용 요일
            _sectionTitle('복용 요일'),
            Wrap(
              spacing: 8,
              children: _days.keys.map((day) {
                final selected = _days[day]!;
                return FilterChip(
                  label: Text(_dayLabels[day]),
                  selected: selected,
                  onSelected: (v) => setState(() => _days[day] = v),
                  selectedColor: AppTheme.primary.withOpacity(0.2),
                  checkmarkColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // 복용 종료일 (선택)
            _sectionTitle('복용 종료일 (선택)'),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  helpText: '복용 종료일 선택',
                  confirmText: '확인',
                  cancelText: '취소',
                );
                if (picked != null) setState(() => _endDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: _endDate != null ? AppTheme.primary : AppTheme.textSecondary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _endDate != null
                            ? '${_endDate!.year}년 ${_endDate!.month}월 ${_endDate!.day}일까지'
                            : '종료일 없음 (무기한)',
                        style: TextStyle(
                          color: _endDate != null ? Colors.black87 : AppTheme.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (_endDate != null)
                      GestureDetector(
                        onTap: () => setState(() => _endDate = null),
                        child: const Icon(Icons.close, size: 18, color: AppTheme.textSecondary),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 36),

            // 저장 버튼
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('등록하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _registerNewMedicine(String name) async {
    if (name.isEmpty) return;
    try {
      final res = await ApiClient.post('/medicines', {'name': name, 'unit': '정'}, token: _token);
      setState(() {
        _selectedMedicineId = res['medicine_id'] as int;
        _selectedMedicineName = name;
        _searchResults = [];
      });
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

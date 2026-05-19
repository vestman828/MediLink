import 'package:flutter/material.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';

class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _medicineNameCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();

  bool _saving = false;
  int? _userId;
  String? _token;
  DateTime? _endDate;

  final Map<String, bool> _timeSlots = {
    'morning': false,
    'lunch': false,
    'dinner': false,
    'bedtime': false,
  };

  final Map<int, bool> _days = {
    0: true,
    1: true,
    2: true,
    3: true,
    4: true,
    5: false,
    6: false,
  };

  final Map<String, String> _timeSlotTimes = const {
    'morning': '08:00:00',
    'lunch': '12:00:00',
    'dinner': '18:00:00',
    'bedtime': '22:00:00',
  };

  final Map<String, String> _timeSlotLabels = const {
    'morning': '아침',
    'lunch': '점심',
    'dinner': '저녁',
    'bedtime': '취침',
  };

  final List<String> _dayLabels = const ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _medicineNameCtrl.dispose();
    _doseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final userId = await Storage.getUserId();
    final token = await Storage.getToken();
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _token = token;
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _save() async {
    final name = _medicineNameCtrl.text.trim();
    final dose = _doseCtrl.text.trim();

    if (_token == null || _userId == null) {
      _showSnack('로그인 정보가 없습니다. 다시 로그인해주세요.', isError: true);
      return;
    }
    if (name.isEmpty) {
      _showSnack('약 이름을 입력해주세요.', isError: true);
      return;
    }
    if (dose.isEmpty) {
      _showSnack('1회 용량을 입력해주세요.', isError: true);
      return;
    }
    if (!_timeSlots.values.any((v) => v)) {
      _showSnack('복용 시간대를 하나 이상 선택해주세요.', isError: true);
      return;
    }
    if (!_days.values.any((v) => v)) {
      _showSnack('복용 요일을 하나 이상 선택해주세요.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final medicineRes = await ApiClient.post(
        '/medicines',
        {'name': name, 'unit': '정'},
        token: _token,
      );
      final medicineId = medicineRes['medicine_id'] as int?;
      if (medicineId == null) {
        throw const ApiException('약 등록에 실패했습니다.', 500);
      }

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final pmRes = await ApiClient.post(
        '/patient-medicines',
        {
          'patient_id': _userId,
          'medicine_id': medicineId,
          'dose': dose,
          'start_date': today,
          if (_endDate != null)
            'end_date': _endDate!.toIso8601String().substring(0, 10),
        },
        token: _token,
      );

      final patientMedicineId = pmRes['patient_medicine_id'] as int?;
      if (patientMedicineId == null) {
        throw const ApiException('복용약 생성에 실패했습니다.', 500);
      }

      final selectedSlots =
          _timeSlots.entries.where((e) => e.value).map((e) => e.key).toList();
      final selectedDays =
          _days.entries.where((e) => e.value).map((e) => e.key).toList();

      final schedules = <Map<String, dynamic>>[];
      for (final day in selectedDays) {
        for (final slot in selectedSlots) {
          schedules.add({
            'day_of_week': day,
            'time_slot': slot,
            'scheduled_time': _timeSlotTimes[slot],
          });
        }
      }

      await ApiClient.put(
        '/schedules/by-medicine/$patientMedicineId',
        {'schedules': schedules},
        token: _token,
      );

      _showSnack('약을 추가했습니다.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('약 추가 중 오류가 발생했습니다.', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: '복용 종료일 선택',
      confirmText: '확인',
      cancelText: '취소',
    );
    if (picked != null && mounted) {
      setState(() => _endDate = picked);
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
            _sectionTitle('약 이름'),
            TextField(
              controller: _medicineNameCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: '예) 타이레놀',
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('1회 용량'),
            TextField(
              controller: _doseCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: '예) 1정, 500mg',
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
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
            _sectionTitle('복용 종료일 (선택)'),
            GestureDetector(
              onTap: _pickEndDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      color: _endDate != null
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _endDate != null
                            ? '${_endDate!.year}년 ${_endDate!.month}월 ${_endDate!.day}일까지'
                            : '종료일 없음 (무기한)',
                        style: TextStyle(
                          color: _endDate != null
                              ? Colors.black87
                              : AppTheme.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (_endDate != null)
                      GestureDetector(
                        onTap: () => setState(() => _endDate = null),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        '등록하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

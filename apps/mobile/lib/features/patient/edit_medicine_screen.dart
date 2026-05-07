import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class EditMedicineScreen extends StatefulWidget {
  final int patientMedicineId;
  final String medicineName;
  final String currentDose;

  const EditMedicineScreen({
    super.key,
    required this.patientMedicineId,
    required this.medicineName,
    required this.currentDose,
  });

  @override
  State<EditMedicineScreen> createState() => _EditMedicineScreenState();
}

class _EditMedicineScreenState extends State<EditMedicineScreen> {
  final _doseCtrl = TextEditingController();
  String? _token;
  bool _loading = true;
  bool _saving = false;

  final Map<String, bool> _timeSlots = {
    'morning': false,
    'lunch': false,
    'dinner': false,
    'bedtime': false,
  };

  final Map<int, bool> _days = {
    0: false, 1: false, 2: false, 3: false, 4: false, 5: false, 6: false,
  };

  final _timeSlotTimes = {
    'morning': '08:00:00',
    'lunch':   '12:00:00',
    'dinner':  '18:00:00',
    'bedtime': '22:00:00',
  };

  final _timeSlotLabels = {
    'morning': '아침',
    'lunch':   '점심',
    'dinner':  '저녁',
    'bedtime': '취침',
  };

  final _dayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _doseCtrl.text = widget.currentDose;
    _init();
  }

  @override
  void dispose() {
    _doseCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _token = await Storage.getToken();
    await _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    try {
      final res = await ApiClient.get(
        '/schedules/by-medicine/${widget.patientMedicineId}',
        token: _token,
      );
      final schedules = res['data'] as List<dynamic>? ?? [];

      // 기존 스케줄에서 시간대/요일 체크
      for (final s in schedules) {
        final slot = s['time_slot'] as String? ?? '';
        final day = s['day_of_week'] as int? ?? 0;
        if (_timeSlots.containsKey(slot)) _timeSlots[slot] = true;
        if (_days.containsKey(day)) _days[day] = true;
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
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

    final selectedSlots = _timeSlots.entries.where((e) => e.value).map((e) => e.key).toList();
    final selectedDays = _days.entries.where((e) => e.value).map((e) => e.key).toList();

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

    try {
      await ApiClient.put(
        '/schedules/by-medicine/${widget.patientMedicineId}',
        token: _token,
        body: {
          'dose': _doseCtrl.text.trim(),
          'schedules': schedules,
        },
      );
      if (mounted) {
        _showSnack('수정되었어요!');
        Navigator.pop(context, true);
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
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text('${widget.medicineName} 수정')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 약 이름 (수정 불가)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.medication, color: AppTheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          widget.medicineName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primary),
                        ),
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
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700, size: 16),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '수정 시 기존 복약 기록은 유지되지만\n오늘 이후 스케줄은 새로 적용돼요.',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
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
                          : const Text('수정하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

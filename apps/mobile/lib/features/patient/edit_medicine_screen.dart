import 'package:flutter/material.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
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

  final List<TimeOfDay> _customTimes = [];

  final Map<String, bool> _timeSlots = {
    'morning': false,
    'lunch': false,
    'dinner': false,
    'bedtime': false,
    'custom': false,
  };

  final Map<int, bool> _days = {
    0: false,
    1: false,
    2: false,
    3: false,
    4: false,
    5: false,
    6: false,
  };

  final Map<String, String> _fixedSlotTimes = const {
    'morning': '08:00:00',
    'lunch': '12:00:00',
    'dinner': '18:00:00',
    'bedtime': '22:00:00',
  };

  static const int _maxCustomTimes = 4;
  static const Set<String> _reservedFixedTimes = {
    '08:00:00',
    '12:00:00',
    '18:00:00',
    '22:00:00',
  };

  final Map<String, String> _timeSlotLabels = const {
    'morning': '아침',
    'lunch': '점심',
    'dinner': '저녁',
    'bedtime': '취침',
    'custom': '직접 설정',
  };

  final List<String> _dayLabels = const ['월', '화', '수', '목', '금', '토', '일'];

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

      for (final s in schedules) {
        final slot = (s['time_slot'] ?? '').toString();
        final day = s['day_of_week'] as int? ?? 0;
        if (_days.containsKey(day)) _days[day] = true;

        if (_fixedSlotTimes.containsKey(slot)) {
          _timeSlots[slot] = true;
          continue;
        }

        final parsed = _parseServerTime(s['scheduled_time'] as String?);
        if (parsed != null) {
          final key = _formatServerTime(parsed);
          final exists = _customTimes.any((t) => _formatServerTime(t) == key);
          if (!exists) {
            _customTimes.add(parsed);
          }
        }
      }

      _timeSlots['custom'] = _customTimes.isNotEmpty;

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatServerTime(TimeOfDay time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  String _formatCustomTimeLabel(TimeOfDay time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  TimeOfDay? _parseServerTime(String? raw) {
    final value = (raw ?? '').toString().trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return null;

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  bool _isReservedFixedTime(TimeOfDay time) {
    return _reservedFixedTimes.contains(_formatServerTime(time));
  }

  bool _containsCustomTime(TimeOfDay time) {
    final key = _formatServerTime(time);
    return _customTimes.any((t) => _formatServerTime(t) == key);
  }

  List<TimeOfDay> _sortedCustomTimes() {
    final copied = List<TimeOfDay>.from(_customTimes);
    copied.sort((a, b) {
      if (a.hour != b.hour) return a.hour - b.hour;
      return a.minute - b.minute;
    });
    return copied;
  }

  bool _hasDuplicateScheduleTime(List<Map<String, dynamic>> schedules) {
    final keys = <String>{};
    for (final s in schedules) {
      final key = '${s['day_of_week']}_${s['scheduled_time']}';
      if (!keys.add(key)) return true;
    }
    return false;
  }

  void _removeCustomTime(TimeOfDay time) {
    final key = _formatServerTime(time);
    setState(() {
      _customTimes.removeWhere((t) => _formatServerTime(t) == key);
      if (_customTimes.isEmpty) {
        _timeSlots['custom'] = false;
      }
    });
  }

  bool _validateCustomTimeSelection() {
    if (_timeSlots['custom'] != true) return true;

    if (_customTimes.isEmpty) {
      _showSnack('직접 설정 시간을 최소 1개 선택해주세요.', isError: true);
      return false;
    }

    if (_customTimes.length > _maxCustomTimes) {
      _showSnack('직접 설정 시간은 최대 4개까지 가능합니다.', isError: true);
      return false;
    }

    final keys = <String>{};
    for (final t in _customTimes) {
      final key = _formatServerTime(t);
      if (_reservedFixedTimes.contains(key)) {
        _showSnack('직접 설정 시간은 아침/점심/저녁/취침 기본 시간과 겹칠 수 없습니다.', isError: true);
        return false;
      }
      if (!keys.add(key)) {
        _showSnack('직접 설정 시간끼리는 중복될 수 없습니다.', isError: true);
        return false;
      }
    }

    return true;
  }

  Future<void> _toggleTimeSlot(String slot, bool selected) async {
    if (slot != 'custom') {
      setState(() => _timeSlots[slot] = selected);
      return;
    }

    if (!selected) {
      setState(() {
        _timeSlots[slot] = false;
        _customTimes.clear();
      });
      return;
    }

    await _pickCustomTime();
  }

  Future<void> _pickCustomTime() async {
    if (_customTimes.length >= _maxCustomTimes) {
      _showSnack('직접 설정 시간은 최대 4개까지 가능합니다.', isError: true);
      return;
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: _customTimes.isEmpty
          ? const TimeOfDay(hour: 9, minute: 0)
          : _sortedCustomTimes().last,
      helpText: '직접 설정 시간',
      confirmText: '확인',
      cancelText: '취소',
    );

    if (picked == null) return;

    if (_isReservedFixedTime(picked)) {
      _showSnack('직접 설정 시간은 아침/점심/저녁/취침 기본 시간과 겹칠 수 없습니다.', isError: true);
      return;
    }

    if (_containsCustomTime(picked)) {
      _showSnack('이미 추가된 직접 설정 시간입니다.', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() {
      _customTimes.add(picked);
      _timeSlots['custom'] = true;
    });
  }

  Future<void> _save() async {
    if (_token == null) {
      _showSnack('로그인 정보가 없습니다. 다시 로그인해주세요.', isError: true);
      return;
    }

    if (_doseCtrl.text.trim().isEmpty) {
      _showSnack('복용량을 입력해주세요.', isError: true);
      return;
    }

    if (!_timeSlots.values.any((v) => v)) {
      _showSnack('복용 시간대를 하나 이상 선택해주세요.', isError: true);
      return;
    }

    if (!_validateCustomTimeSelection()) return;

    if (!_days.values.any((v) => v)) {
      _showSnack('복용 요일을 하나 이상 선택해주세요.', isError: true);
      return;
    }

    final selectedFixedSlots = _timeSlots.entries
        .where((e) => e.value && e.key != 'custom')
        .map((e) => e.key)
        .toList();

    final selectedDays =
        _days.entries.where((e) => e.value).map((e) => e.key).toList();

    final schedules = <Map<String, dynamic>>[];
    for (final day in selectedDays) {
      for (final slot in selectedFixedSlots) {
        final scheduledTime = _fixedSlotTimes[slot];
        if (scheduledTime == null) continue;
        schedules.add({
          'day_of_week': day,
          'time_slot': slot,
          'scheduled_time': scheduledTime,
        });
      }

      if (_timeSlots['custom'] == true) {
        for (final customTime in _customTimes) {
          schedules.add({
            'day_of_week': day,
            'time_slot': 'custom',
            'scheduled_time': _formatServerTime(customTime),
          });
        }
      }
    }

    if (_hasDuplicateScheduleTime(schedules)) {
      _showSnack('같은 요일에서 복약 시간이 겹칠 수 없습니다.', isError: true);
      return;
    }

    setState(() => _saving = true);

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
        _showSnack('수정되었습니다.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      _showSnack('수정 중 오류가 발생했습니다.', isError: true);
      if (mounted) setState(() => _saving = false);
    }
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
      appBar: AppBar(title: Text('${widget.medicineName} 수정')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('1회 복용량'),
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
                  _sectionTitle('복용 시간대'),
                  Wrap(
                    spacing: 8,
                    children: _timeSlots.keys.map((slot) {
                      final selected = _timeSlots[slot]!;
                      return FilterChip(
                        label: Text(_timeSlotLabels[slot]!),
                        selected: selected,
                        onSelected: (v) => _toggleTimeSlot(slot, v),
                        selectedColor: AppTheme.primary.withOpacity(0.2),
                        checkmarkColor: AppTheme.primary,
                        labelStyle: TextStyle(
                          color:
                              selected ? AppTheme.primary : AppTheme.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                  if (_timeSlots['custom'] == true) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '직접 설정 시간 (${_customTimes.length}/$_maxCustomTimes)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _customTimes.length >= _maxCustomTimes
                              ? null
                              : _pickCustomTime,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('시간 추가'),
                        ),
                      ],
                    ),
                    if (_customTimes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '직접 설정 시간을 추가해주세요.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _sortedCustomTimes().map((time) {
                          return InputChip(
                            label: Text(_formatCustomTimeLabel(time)),
                            onDeleted: () => _removeCustomTime(time),
                            deleteIcon: const Icon(Icons.close, size: 16),
                          );
                        }).toList(),
                      ),
                  ],
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
                          color:
                              selected ? AppTheme.primary : AppTheme.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.normal,
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
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '수정 후 기존 복약 기록은 유지되며, 오늘 이후 스케줄부터 적용됩니다.',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
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
                              '수정하기',
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

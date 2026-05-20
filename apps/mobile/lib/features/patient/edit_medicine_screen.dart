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
  final List<TimeOfDay> _customTimes = [];

  final Map<String, bool> _timeSlots = {
    'morning': false,
    'lunch': false,
    'dinner': false,
    'bedtime': false,
    'custom': false,
  };

  final Map<int, bool> _days = {
    0: false, 1: false, 2: false, 3: false, 4: false, 5: false, 6: false,
  };

  final _fixedSlotTimes = {
    'morning': '08:00:00',
    'lunch':   '12:00:00',
    'dinner':  '18:00:00',
    'bedtime': '22:00:00',
  };
  static const int _maxCustomTimes = 4;
  static const Set<String> _reservedFixedTimes = {
    '08:00:00',
    '12:00:00',
    '18:00:00',
    '22:00:00',
  };

  final _timeSlotLabels = {
    'morning': '?꾩묠',
    'lunch':   '?먯떖',
    'dinner':  '???,
    'bedtime': '痍⑥묠',
    'custom': '吏곸젒 ?ㅼ젙',
  };

  final _dayLabels = ['??, '??, '??, '紐?, '湲?, '??, '??];

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

      // 湲곗〈 ?ㅼ?以꾩뿉???쒓컙?/?붿씪 泥댄겕
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
    } catch (e) {
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
    if (_doseCtrl.text.trim().isEmpty) {
      _showSnack('?⑸웾???낅젰?댁＜?몄슂', isError: true);
      return;
    }
    if (!_timeSlots.values.any((v) => v)) {
      _showSnack('蹂듭슜 ?쒓컙?瑜??섎굹 ?댁긽 ?좏깮?댁＜?몄슂', isError: true);
      return;
    }
    if (!_validateCustomTimeSelection()) return;
    if (!_days.values.any((v) => v)) {
      _showSnack('蹂듭슜 ?붿씪???섎굹 ?댁긽 ?좏깮?댁＜?몄슂', isError: true);
      return;
    }

    final selectedFixedSlots = _timeSlots.entries
        .where((e) => e.value && e.key != 'custom')
        .map((e) => e.key)
        .toList();
    final selectedDays = _days.entries.where((e) => e.value).map((e) => e.key).toList();

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
      _showSnack('媛숈? ?쎈Ъ?먯꽌 蹂듭슜 ?쒓컙??寃뱀튌 ???놁뒿?덈떎.', isError: true);
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
        _showSnack('?섏젙?섏뿀?댁슂!');
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
      appBar: AppBar(title: Text('${widget.medicineName} ?섏젙')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ???대쫫 (?섏젙 遺덇?)
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

                  // ?⑸웾
                  _sectionTitle('1???⑸웾'),
                  TextField(
                    controller: _doseCtrl,
                    decoration: InputDecoration(
                      hintText: '?? 1?? 500mg',
                      filled: true,
                      fillColor: AppTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 蹂듭슜 ?쒓컙?
                  _sectionTitle('蹂듭슜 ?쒓컙?'),
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
                          color: selected ? AppTheme.primary : AppTheme.textSecondary,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
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
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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

                  // 蹂듭슜 ?붿씪
                  _sectionTitle('蹂듭슜 ?붿씪'),
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
                            '?섏젙 ??湲곗〈 蹂듭빟 湲곕줉? ?좎??섏?留?n?ㅻ뒛 ?댄썑 ?ㅼ?以꾩? ?덈줈 ?곸슜?쇱슂.',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ???踰꾪듉
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
                          : const Text('?섏젙?섍린', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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






import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import 'drug_detail_screen.dart';

class AddMedicineScreen extends StatefulWidget {
  final int? patientId;
  final String? patientName;

  const AddMedicineScreen({super.key, this.patientId, this.patientName});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _medicineNameCtrl = TextEditingController();
  final _doseCtrl = TextEditingController();
  Timer? _searchDebounce;

  bool _saving = false;
  bool _searching = false;
  bool _suppressSearchOnce = false;
  int? _patientId;
  String? _token;
  DateTime? _endDate;
  final List<TimeOfDay> _customTimes = [];
  Map<String, dynamic>? _selectedMedicine;
  List<Map<String, dynamic>> _searchResults = [];

  final Map<String, bool> _timeSlots = {
    'morning': false,
    'lunch': false,
    'dinner': false,
    'bedtime': false,
    'custom': false,
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
    'morning': '?꾩묠',
    'lunch': '?먯떖',
    'dinner': '???,
    'bedtime': '痍⑥묠',
    'custom': '吏곸젒 ?ㅼ젙',
  };

  final List<String> _dayLabels = const ['??, '??, '??, '紐?, '湲?, '??, '??];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _medicineNameCtrl.dispose();
    _doseCtrl.dispose();
    super.dispose();
  }

  Future<void> _onMedicineNameChanged(String value) async {
    if (_suppressSearchOnce) {
      _suppressSearchOnce = false;
      return;
    }

    final query = value.trim();
    _selectedMedicine = null;
    _searchDebounce?.cancel();

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      await _searchMedicines(query);
    });
  }

  Future<void> _searchMedicines(String query) async {
    if (_token == null || query.isEmpty) return;
    try {
      final res = await ApiClient.get(
        '/medicines/search',
        token: _token,
        queryParams: {'q': query},
      );

      if (!mounted || _medicineNameCtrl.text.trim() != query) return;
      final raw = res['data'] as List<dynamic>? ?? [];
      final results =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searching = false;
      });
    }
  }

  void _selectMedicine(Map<String, dynamic> medicine) {
    final selectedName = (medicine['name'] ?? '').toString().trim();
    if (selectedName.isEmpty) return;

    _suppressSearchOnce = true;
    _medicineNameCtrl.text = selectedName;
    _medicineNameCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _medicineNameCtrl.text.length),
    );

    setState(() {
      _selectedMedicine = medicine;
      _searchResults = [];
      _searching = false;
    });

    FocusScope.of(context).unfocus();
  }

  Future<void> _loadUser() async {
    final userId = await Storage.getUserId();
    final token = await Storage.getToken();
    if (!mounted) return;
    setState(() {
      _patientId = widget.patientId ?? userId;
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
    final name = _medicineNameCtrl.text.trim();
    final dose = _doseCtrl.text.trim();

    if (_token == null || _patientId == null) {
      _showSnack('濡쒓렇???뺣낫媛 ?놁뒿?덈떎. ?ㅼ떆 濡쒓렇?명빐二쇱꽭??', isError: true);
      return;
    }
    if (name.isEmpty) {
      _showSnack('???대쫫???낅젰?댁＜?몄슂.', isError: true);
      return;
    }
    if (dose.isEmpty) {
      _showSnack('1???⑸웾???낅젰?댁＜?몄슂.', isError: true);
      return;
    }
    if (!_timeSlots.values.any((v) => v)) {
      _showSnack('蹂듭슜 ?쒓컙?瑜??섎굹 ?댁긽 ?좏깮?댁＜?몄슂.', isError: true);
      return;
    }
    if (!_validateCustomTimeSelection()) return;
    if (!_days.values.any((v) => v)) {
      _showSnack('蹂듭슜 ?붿씪???섎굹 ?댁긽 ?좏깮?댁＜?몄슂.', isError: true);
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
      _showSnack('媛숈? ?쎈Ъ?먯꽌 蹂듭슜 ?쒓컙??寃뱀튌 ???놁뒿?덈떎.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final selectedUnit =
          (_selectedMedicine?['unit'] ?? '??).toString().trim().isEmpty
              ? '??
              : (_selectedMedicine?['unit'] ?? '??).toString().trim();
      final selectedDescription =
          (_selectedMedicine?['description'] ?? '').toString().trim();

      final medicineRes = await ApiClient.post(
        '/medicines',
        {
          'name': name,
          'unit': selectedUnit,
          if (selectedDescription.isNotEmpty) 'description': selectedDescription,
        },
        token: _token,
      );
      final medicineId = medicineRes['medicine_id'] as int?;
      if (medicineId == null) {
        throw const ApiException('???깅줉???ㅽ뙣?덉뒿?덈떎.', 500);
      }

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final pmRes = await ApiClient.post(
        '/patient-medicines',
        {
          'patient_id': _patientId,
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
        throw const ApiException('蹂듭슜???앹꽦???ㅽ뙣?덉뒿?덈떎.', 500);
      }

      await ApiClient.put(
        '/schedules/by-medicine/$patientMedicineId',
        body: {'schedules': schedules},
        token: _token,
      );

      _showSnack('?쎌쓣 異붽??덉뒿?덈떎.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('??異붽? 以??ㅻ쪟媛 諛쒖깮?덉뒿?덈떎.', isError: true);
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
      helpText: '蹂듭슜 醫낅즺???좏깮',
      confirmText: '?뺤씤',
      cancelText: '痍⑥냼',
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
      appBar: AppBar(
        title: Text(
          widget.patientName == null ? '??異붽?' : '${widget.patientName}????異붽?',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('???대쫫'),
            TextField(
              controller: _medicineNameCtrl,
              onChanged: _onMedicineNameChanged,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: '???대쫫???낅젰?섎㈃ 寃?됰맗?덈떎. ?? ??대젅?',
                filled: true,
                fillColor: AppTheme.surface,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _medicineNameCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _medicineNameCtrl.clear();
                          setState(() {
                            _selectedMedicine = null;
                            _searchResults = [];
                            _searching = false;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (_, i) {
                    final medicine = _searchResults[i];
                    final source =
                        (medicine['source'] ?? '').toString().toLowerCase();
                    final name = (medicine['name'] ?? '').toString();
                    final unit = (medicine['unit'] ?? '??).toString();
                    return ListTile(
                      dense: true,
                      title: Text(name, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        unit,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      trailing: source.isEmpty
                          ? null
                          : Text(
                              source == 'api' ? 'API' : 'DB',
                              style: TextStyle(
                                color: source == 'api'
                                    ? Colors.orange.shade700
                                    : Colors.green.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      onTap: () => _selectMedicine(medicine),
                    );
                  },
                ),
              ),
            ],
            if (_selectedMedicine != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    final name =
                        (_selectedMedicine?['name'] ?? '').toString().trim();
                    if (name.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DrugDetailScreen(medicineName: name),
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('???곸꽭?뺣낫 蹂닿린'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _sectionTitle('1???⑸웾'),
            TextField(
              controller: _doseCtrl,
              textInputAction: TextInputAction.next,
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
            const SizedBox(height: 24),
            _sectionTitle('蹂듭슜 醫낅즺??(?좏깮)'),
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
                            ? '${_endDate!.year}??${_endDate!.month}??${_endDate!.day}?쇨퉴吏'
                            : '醫낅즺???놁쓬 (臾닿린??',
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
                        '?깅줉?섍린',
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



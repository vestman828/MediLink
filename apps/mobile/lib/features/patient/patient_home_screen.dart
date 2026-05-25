import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/fcm_service.dart';
import '../../core/notification_service.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/auth_repository.dart';
import 'daily_note_screen.dart';
import 'family_request_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => PatientHomeScreenState();
}

class PatientHomeScreenState extends State<PatientHomeScreen>
    with WidgetsBindingObserver {
  final _authRepo = AuthRepository();

  String? _name;
  int? _userId;
  String? _token;
  List<dynamic> _schedules = [];
  bool _loading = true;

  // 연동 요청 중복 팝업 방지용 쿨다운
  // lifecycle resume: 5초 (앱 전환 시 즉시 재확인)
  // tab switch(load): 60초 (탭 이동 시 과도한 호출 방지)
  DateTime? _lastFamilyCheckLifecycle;
  DateTime? _lastFamilyCheckLoad;
  bool _familyCheckInProgress = false;

  DateTime _nowKst() => DateTime.now().toUtc().add(const Duration(hours: 9));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // FCM family_request 메시지 수신 시 즉시 팝업 표시
    FcmService.onFamilyRequest = () {
      if (mounted) _checkFamilyRequests();
    };
    _init();
  }

  @override
  void dispose() {
    FcmService.onFamilyRequest = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 앱이 포그라운드로 돌아올 때 연동 요청 재확인 (쿨다운 5초)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastFamilyCheckLifecycle == null ||
          now.difference(_lastFamilyCheckLifecycle!).inSeconds >= 5) {
        _lastFamilyCheckLifecycle = now;
        _checkFamilyRequests();
      }
    }
  }

  Future<void> _init() async {
    _name = await Storage.getUserName();
    _userId = await Storage.getUserId();
    _token = await Storage.getToken();
    await _loadSchedules();
    await _checkFamilyRequests();
  }

  Future<void> _checkFamilyRequests() async {
    if (_token == null) return;
    if (_familyCheckInProgress) return; // 중복 실행 방지
    _familyCheckInProgress = true;

    try {
      final res =
          await ApiClient.get('/family-requests/pending', token: _token);
      final requests = res['data'] as List<dynamic>? ?? [];
      if (requests.isNotEmpty && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  FamilyRequestScreen(requests: requests, token: _token!)),
        );
        await _init();
      }
    } catch (_) {
      // ignore
    } finally {
      _familyCheckInProgress = false;
    }
  }

  // 탭 전환 시 호출: 스케줄 새로고침 + 연동 요청 확인 (60초 쿨다운)
  Future<void> load() async {
    await _loadSchedules();
    final now = DateTime.now();
    if (_lastFamilyCheckLoad == null ||
        now.difference(_lastFamilyCheckLoad!).inSeconds >= 60) {
      _lastFamilyCheckLoad = now;
      _checkFamilyRequests();
    }
  }

  Future<void> _loadSchedules() async {
    if (_userId == null || _token == null) return;

    try {
      final today = DateFormat('yyyy-MM-dd').format(_nowKst());
      final res = await ApiClient.get(
        '/schedules/today',
        token: _token,
        queryParams: {'patient_id': _userId.toString(), 'date': today},
      );

      if (mounted) {
        setState(() {
          _schedules = res['data'] as List<dynamic>? ?? [];
          _loading = false;
        });

        if (_schedules.isNotEmpty) {
          await NotificationService.scheduleFromSchedules(
            _schedules
                .map((s) => Map<String, dynamic>.from(s as Map))
                .toList(),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkIntake(int scheduleId) async {
    try {
      await ApiClient.post(
        '/intake-logs',
        {
          'schedule_id': scheduleId,
          'patient_id': _userId,
          'auth_method': 'button'
        },
        token: _token,
      );

      await _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('복약 완료! +100 포인트'), backgroundColor: Colors.green),
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

  String _imageContentType(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.png')) return 'image/png';
    if (lowerPath.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _checkIntakeWithPhoto(int scheduleId) async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('사진 확인',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(picked.path),
                    height: 200, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('다시 촬영'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('등록'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final bytes = await File(picked.path).readAsBytes();

      await ApiClient.postBytes(
        '/intake-logs/photo',
        bytes,
        token: _token,
        contentType: _imageContentType(picked.path),
        queryParams: {
          'schedule_id': scheduleId.toString(),
          'patient_id': _userId.toString(),
        },
      );

      await _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('사진 인증 완료! +100 포인트'),
              backgroundColor: Colors.green),
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

  Future<void> _logout() async {
    try {
      if (_token != null) {
        await _authRepo.logout(token: _token!);
      }
    } catch (_) {
      // ignore and continue local logout
    }

    await NotificationService.cancelAll();
    await Storage.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  int get _takenCount => _schedules.where((s) => s['log_id'] != null).length;
  int get _totalCount => _schedules.length;

  String _timeSlotLabel(String slot) {
    switch (slot) {
      case 'morning':
        return '아침';
      case 'lunch':
        return '점심';
      case 'dinner':
        return '저녁';
      case 'bedtime':
        return '취침';
      case 'custom':
        return '직접설정';
      default:
        return slot;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('복약 모드'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '내 정보',
            onPressed: () async {
              await Navigator.pushNamed(context, '/profile');
              await _loadSchedules();
            },
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSchedules,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '안녕하세요, ${_name ?? ''}님',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('yyyy년 M월 d일 (E)', 'ko')
                          .format(_nowKst()),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    _buildProgressCard(),
                    const SizedBox(height: 12),
                    _buildNextDoseCard(),
                    const SizedBox(height: 12),
                    _buildMemoButton(),
                    const SizedBox(height: 20),
                    if (_schedules.isEmpty)
                      _buildEmptyState()
                    else
                      ..._buildScheduleList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProgressCard() {
    final progress = _totalCount > 0 ? _takenCount / _totalCount : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘 복약 현황  $_takenCount / $_totalCount',
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.white30,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _takenCount == _totalCount && _totalCount > 0
                ? '오늘 복약을 모두 완료했어요!'
                : '${_totalCount - _takenCount}개 남았어요',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNextDoseCard() {
    final slotLabels = {
      'morning': '아침',
      'lunch': '점심',
      'dinner': '저녁',
      'bedtime': '취침',
      'custom': '직접설정',
    };

    final nowKst = _nowKst();
    final nowMinutes = nowKst.hour * 60 + nowKst.minute;

    dynamic nextSchedule;
    int minDiff = 24 * 60 + 1;

    for (final schedule in _schedules.where((s) => s['log_id'] == null)) {
      final scheduleMinutes =
          _parseTimeToMinutes(schedule['scheduled_time'] as String?);
      if (scheduleMinutes == null) continue;

      var diff = scheduleMinutes - nowMinutes;
      if (diff < 0) diff += 24 * 60;

      if (diff < minDiff) {
        minDiff = diff;
        nextSchedule = schedule;
      }
    }

    if (nextSchedule == null) return const SizedBox.shrink();
    final nextSlot = nextSchedule['time_slot'] as String? ?? '';
    final nextTime = _displayTime(nextSchedule['scheduled_time'] as String?);

    // custom 슬롯은 시간만, 표준 슬롯은 '아침(08:00)' 형식
    final label = nextSlot == 'custom'
        ? nextTime
        : '${slotLabels[nextSlot] ?? nextSlot}($nextTime)';

    final hours = minDiff ~/ 60;
    final minutes = minDiff % 60;
    final timeStr = hours > 0 ? '$hours시간 $minutes분' : '$minutes분';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time, color: Colors.orange.shade600, size: 20),
          const SizedBox(width: 10),
          Text(
            '$label 복약까지 $timeStr',
            style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => DailyNoteScreen(date: _nowKst())),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_note, color: AppTheme.primary, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('오늘 컨디션 메모 기록하기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.medication_outlined,
              size: 48, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text('오늘 복약 스케줄이 없어요',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  List<Widget> _buildScheduleList() {
    // custom 슬롯은 scheduled_time별로 독립 그룹으로 분리
    // → 03:00(custom), 아침(08:00), 점심(12:00), 19:00(custom) 순으로 인터리브
    final grouped = <String, List<dynamic>>{};

    for (final s in _schedules) {
      final slot = s['time_slot'] as String;
      String key;
      if (slot == 'custom') {
        final t = (s['scheduled_time'] ?? '').toString();
        key = 'custom_$t'; // 시간별 독립 그룹
      } else {
        key = slot;
      }
      grouped.putIfAbsent(key, () => []).add(s);
    }

    // 각 그룹 내 약도 scheduled_time 기준 정렬
    for (final group in grouped.values) {
      group.sort((a, b) {
        final aMin = _parseTimeToMinutes(a['scheduled_time'] as String?) ?? 9999;
        final bMin = _parseTimeToMinutes(b['scheduled_time'] as String?) ?? 9999;
        return aMin.compareTo(bMin);
      });
    }

    // 그룹을 실제 시간순으로 정렬
    final orderedKeys = grouped.keys.toList()
      ..sort((a, b) =>
          _slotSortMinutes(grouped[a]!).compareTo(_slotSortMinutes(grouped[b]!)));

    final widgets = <Widget>[];

    for (final key in orderedKeys) {
      final schedules = grouped[key] ?? <dynamic>[];

      // 헤더 레이블: custom_HH:MM:SS → HH:MM, 표준 슬롯 → 아침/점심/...
      final headerLabel = key.startsWith('custom_')
          ? _displayTime(schedules.first['scheduled_time'] as String?)
          : _timeSlotLabel(key);

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(headerLabel,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );

      for (final s in schedules) {
        widgets.add(_buildMedicineCard(s));
        widgets.add(const SizedBox(height: 10));
      }

      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }

  int _slotSortMinutes(List<dynamic> schedules) {
    int minValue = 24 * 60 + 1;
    for (final s in schedules) {
      final minutes = _parseTimeToMinutes(s['scheduled_time'] as String?);
      if (minutes != null && minutes < minValue) {
        minValue = minutes;
      }
    }
    return minValue;
  }

  Widget _buildMedicineCard(dynamic schedule) {
    final isTaken = schedule['log_id'] != null;
    final scheduleId = schedule['schedule_id'] as int;
    final isEarly = !isTaken && _isBeforeScheduledTime(schedule);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isTaken ? Colors.green.shade50 : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTaken ? Colors.green.shade200 : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isTaken
                  ? Colors.green.shade100
                  : isEarly
                      ? Colors.grey.shade100
                      : AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isTaken ? Icons.check_circle : Icons.medication,
              color: isTaken
                  ? Colors.green
                  : isEarly
                      ? Colors.grey.shade400
                      : AppTheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule['medicine_name'] as String? ?? '',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${schedule['dose']}  ${_displayTime(schedule['scheduled_time'] as String?)}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                if (isEarly)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '복약 시간이 되면 활성화됩니다',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ),
              ],
            ),
          ),
          if (!isTaken)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 먹었어요 버튼: 시간 전이면 비활성화
                ElevatedButton(
                  onPressed: isEarly ? null : () => _checkIntake(scheduleId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isEarly ? Colors.grey.shade300 : AppTheme.primary,
                    foregroundColor:
                        isEarly ? Colors.grey.shade500 : Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    disabledBackgroundColor: Colors.grey.shade200,
                    disabledForegroundColor: Colors.grey.shade400,
                  ),
                  child: const Text('먹었어요', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 4),
                // 사진 버튼: 시간 전이면 비활성화
                GestureDetector(
                  onTap: isEarly ? null : () => _checkIntakeWithPhoto(scheduleId),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isEarly
                          ? Colors.grey.shade100
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isEarly
                              ? Colors.grey.shade300
                              : Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt,
                            size: 13,
                            color: isEarly
                                ? Colors.grey.shade400
                                : Colors.orange.shade700),
                        const SizedBox(width: 3),
                        Text('사진',
                            style: TextStyle(
                                fontSize: 12,
                                color: isEarly
                                    ? Colors.grey.shade400
                                    : Colors.orange.shade700)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            const Text('완료',
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // scheduled_time이 아직 지나지 않았으면 true (복약 버튼 비활성화용)
  bool _isBeforeScheduledTime(dynamic schedule) {
    final nowMin = _nowKst().hour * 60 + _nowKst().minute;
    final schedMin = _parseTimeToMinutes(schedule['scheduled_time'] as String?);
    if (schedMin == null) return false;
    return nowMin < schedMin;
  }

  int? _parseTimeToMinutes(String? raw) {
    final value = (raw ?? '').toString().trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  String _displayTime(String? raw) {
    final minutes = _parseTimeToMinutes(raw);
    if (minutes == null) return '--:--';
    final hh = (minutes ~/ 60).toString().padLeft(2, '0');
    final mm = (minutes % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

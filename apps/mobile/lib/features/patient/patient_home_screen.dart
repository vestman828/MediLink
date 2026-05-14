import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../core/notification_service.dart';
import '../../data/api_client.dart';
import 'daily_note_screen.dart';
import 'family_request_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => PatientHomeScreenState();
}

class PatientHomeScreenState extends State<PatientHomeScreen> {
  String? _name;
  int? _userId;
  String? _token;
  List<dynamic> _schedules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
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
    try {
      final res = await ApiClient.get('/family-requests/pending', token: _token);
      final requests = res['data'] as List<dynamic>? ?? [];
      if (requests.isNotEmpty && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FamilyRequestScreen(requests: requests, token: _token!),
          ),
        ).then((_) => _init());
      }
    } catch (_) {}
  }

  // 외부(PatientMainScreen)에서 탭 전환 시 호출
  Future<void> load() => _loadSchedules();

  Future<void> _loadSchedules() async {
    if (_userId == null || _token == null) return;
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
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
        // 알림 자동 등록
        if (_schedules.isNotEmpty) {
          await NotificationService.scheduleFromSlots(
            _schedules.map((s) => {'time_slot': s['time_slot'] as String}).toList(),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkIntake(int scheduleId) async {
    try {
      await ApiClient.post(
        '/intake-logs',
        {'schedule_id': scheduleId, 'patient_id': _userId, 'auth_method': 'button'},
        token: _token,
      );
      // 복약 완료 시 해당 슬롯 재알림 취소
      final slot = _schedules.firstWhere(
        (s) => s['schedule_id'] == scheduleId,
        orElse: () => {},
      );
      if (slot['time_slot'] != null) {
        await NotificationService.cancelReminderForSlot(slot['time_slot'] as String);
      }
      await _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 복약 완료! +100 포인트'), backgroundColor: Colors.green),
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

  Future<void> _checkIntakeWithPhoto(int scheduleId) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;

    // 사진 미리보기 + 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('사진 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(picked.path), height: 200, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('다시 찍기'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
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
      // 사진을 Base64로 인코딩해서 서버에 전송 → 보호자도 볼 수 있음
      final bytes = await File(picked.path).readAsBytes();
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      await ApiClient.post(
        '/intake-logs',
        {
          'schedule_id': scheduleId,
          'patient_id': _userId,
          'auth_method': 'photo',
          'photo_url': base64Image,
        },
        token: _token,
      );
      // 복약 완료 시 해당 슬롯 재알림 취소
      final slot = _schedules.firstWhere(
        (s) => s['schedule_id'] == scheduleId,
        orElse: () => {},
      );
      if (slot['time_slot'] != null) {
        await NotificationService.cancelReminderForSlot(slot['time_slot'] as String);
      }
      await _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📸 사진 인증 완료! +100 포인트'), backgroundColor: Colors.green),
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

  // 개발용: 미복약 알림 즉시 테스트
  Future<void> _testMissedNotification() async {
    final missed = _schedules.where((s) => s['log_id'] == null).toList();
    if (missed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 약을 복약했어요! 미복약 없음'), backgroundColor: Colors.green),
        );
      }
      return;
    }
    final slotLabels = {'morning': '아침', 'lunch': '점심', 'dinner': '저녁', 'bedtime': '취침'};
    int id = 300;
    for (final s in missed) {
      final label = slotLabels[s['time_slot']] ?? s['time_slot'];
      final medicine = s['medicine_name'] as String? ?? '약';
      await NotificationService.showNow(
        id: id++,
        title: '⚠️ $label 복약을 아직 안 하셨어요!',
        body: '$medicine 복약을 잊으셨나요? 지금 바로 복약해주세요.',
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('테스트 알림 ${missed.length}개 발송됨'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _logout() async {
    await NotificationService.cancelAll();
    await Storage.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  int get _takenCount => _schedules.where((s) => s['log_id'] != null).length;
  int get _totalCount => _schedules.length;

  String _timeSlotLabel(String slot) {
    switch (slot) {
      case 'morning': return '아침';
      case 'lunch': return '점심';
      case 'dinner': return '저녁';
      case 'bedtime': return '취침';
      default: return slot;
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
            onPressed: () => Navigator.pushNamed(context, '/profile'),
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
                      '안녕하세요, ${_name ?? ''}님 👋',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('yyyy년 M월 d일 (E)', 'ko').format(DateTime.now()),
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
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
                ? '오늘 복약을 모두 완료했어요! 🎉'
                : '${_totalCount - _takenCount}개 남았어요',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // 다음 복약까지 남은 시간
  Widget _buildNextDoseCard() {
    final slotTimes = {
      'morning': const TimeOfDay(hour: 8, minute: 0),
      'lunch': const TimeOfDay(hour: 12, minute: 0),
      'dinner': const TimeOfDay(hour: 18, minute: 0),
      'bedtime': const TimeOfDay(hour: 22, minute: 0),
    };
    final slotLabels = {'morning': '아침', 'lunch': '점심', 'dinner': '저녁', 'bedtime': '취침'};

    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;

    // 아직 안 먹은 슬롯 중 가장 가까운 것 찾기
    final pendingSlots = _schedules
        .where((s) => s['log_id'] == null)
        .map((s) => s['time_slot'] as String)
        .toSet()
        .toList();

    if (pendingSlots.isEmpty) return const SizedBox.shrink();

    String? nextSlot;
    int minDiff = 9999;
    for (final slot in pendingSlots) {
      final t = slotTimes[slot];
      if (t == null) continue;
      final slotMinutes = t.hour * 60 + t.minute;
      final diff = slotMinutes - nowMinutes;
      if (diff > 0 && diff < minDiff) {
        minDiff = diff;
        nextSlot = slot;
      }
    }

    if (nextSlot == null) return const SizedBox.shrink();

    final hours = minDiff ~/ 60;
    final minutes = minDiff % 60;
    final timeStr = hours > 0 ? '$hours시간 $minutes분 후' : '$minutes분 후';

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
            '${slotLabels[nextSlot]}약 복용까지 $timeStr',
            style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // 오늘 메모 버튼
  Widget _buildMemoButton() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DailyNoteScreen(date: DateTime.now())),
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
              child: Text('오늘 컨디션/메모 기록하기',
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
          Icon(Icons.medication_outlined, size: 48, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text('오늘 복약 스케줄이 없어요', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  List<Widget> _buildScheduleList() {
    final grouped = <String, List<dynamic>>{};
    for (final s in _schedules) {
      final slot = s['time_slot'] as String;
      grouped.putIfAbsent(slot, () => []).add(s);
    }

    final slotOrder = ['morning', 'lunch', 'dinner', 'bedtime'];
    final widgets = <Widget>[];

    for (final slot in slotOrder) {
      if (!grouped.containsKey(slot)) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _timeSlotLabel(slot),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      );
      for (final s in grouped[slot]!) {
        widgets.add(_buildMedicineCard(s));
        widgets.add(const SizedBox(height: 10));
      }
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }

  Widget _buildMedicineCard(dynamic schedule) {
    final isTaken = schedule['log_id'] != null;
    final scheduleId = schedule['schedule_id'] as int;

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
              color: isTaken ? Colors.green.shade100 : AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isTaken ? Icons.check_circle : Icons.medication,
              color: isTaken ? Colors.green : AppTheme.primary,
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${schedule['dose']}  ${schedule['scheduled_time']}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          if (!isTaken)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () => _checkIntake(scheduleId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('먹었어요', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _checkIntakeWithPhoto(scheduleId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt, size: 13, color: Colors.orange.shade700),
                        const SizedBox(width: 3),
                        Text('사진', style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            const Text('완료 ✅', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

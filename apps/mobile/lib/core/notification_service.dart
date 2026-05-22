import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'medilink_channel';
  static const _channelName = 'MediLink 알림';
  static const _reminderChannelId = 'medilink_reminder';
  static const _reminderChannelName = 'MediLink 재알림';

  // scheduled_time 파싱 실패 시 사용할 기본 시간
  static final _defaultSlotTimes = {
    'morning':  [8,  0],
    'lunch':    [12, 0],
    'dinner':   [18, 0],
    'bedtime':  [22, 0],
  };

  static final _slotLabels = {
    'morning':  '아침',
    'lunch':    '점심',
    'dinner':   '저녁',
    'bedtime':  '취침',
    'custom':   '직접설정',
  };

  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // 즉시 알림
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    final android = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: '복약 알림',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(id, title, body, NotificationDetails(android: android));
  }

  // 매일 반복 알림 예약
  static Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String channelId = _channelId,
    String channelName = _channelName,
  }) async {
    final android = AndroidNotificationDetails(
      channelId, channelName,
      channelDescription: '복약 알림',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOfTime(hour, minute),
      NotificationDetails(android: android),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // 특정 알림 취소
  static Future<void> cancel(int id) async => _plugin.cancel(id);

  // 모든 알림 취소
  static Future<void> cancelAll() async => _plugin.cancelAll();

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static List<int>? _resolveScheduleTime(Map<String, dynamic> schedule) {
    final raw = (schedule['scheduled_time'] ?? '').toString().trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match != null) {
      final hour = int.tryParse(match.group(1)!);
      final minute = int.tryParse(match.group(2)!);
      if (hour != null &&
          minute != null &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        return [hour, minute];
      }
    }

    final slot = schedule['time_slot'] as String?;
    if (slot == null) return null;
    return _defaultSlotTimes[slot];
  }

  // 시간 포맷: HH:mm
  static String _formatHHmm(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  // 복약 스케줄 기반으로 알림 + 30분 후 재알림 일괄 등록
  // - 같은 시간대의 여러 약은 하나의 알림으로 통합
  // - custom 슬롯은 실제 시간(HH:mm)을 레이블로 표시
  static Future<void> scheduleFromSchedules(
    List<Map<String, dynamic>> schedules,
  ) async {
    await cancelAll();

    // 시간 키(HH:mm)별로 미복약 스케줄 묶기
    final timeGroups = <String, List<Map<String, dynamic>>>{};
    final timeToHM = <String, List<int>>{};

    for (final schedule in schedules) {
      if (schedule['log_id'] != null || schedule['status'] == 'taken') continue;
      final times = _resolveScheduleTime(schedule);
      if (times == null) continue;

      final key = _formatHHmm(times[0], times[1]);
      timeGroups.putIfAbsent(key, () => []).add(schedule);
      timeToHM[key] = times;
    }

    int id = 100;

    for (final entry in timeGroups.entries) {
      final timeKey = entry.key; // 'HH:mm'
      final group = entry.value;
      final times = timeToHM[timeKey]!;
      final hour = times[0];
      final minute = times[1];

      // 시간 레이블 결정: 모두 같은 표준 슬롯이면 그 이름, 아니면 HH:mm
      final slots = group.map((s) => s['time_slot'] as String? ?? '').toSet();
      String label;
      if (slots.length == 1 && slots.first != 'custom') {
        label = _slotLabels[slots.first] ?? timeKey;
      } else {
        label = timeKey; // custom 또는 혼합 → 시간으로 표시
      }

      // 약 이름 목록 (최대 3개, 초과 시 '외 N개')
      final names = group
          .map((s) => (s['medicine_name'] as String? ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      String medicineText;
      if (names.isEmpty) {
        medicineText = '복약';
      } else if (names.length <= 2) {
        medicineText = names.join(', ');
      } else {
        medicineText = '${names.take(2).join(', ')} 외 ${names.length - 2}개';
      }

      // 1차 알림: 복약 시간
      await scheduleDailyNotification(
        id: id++,
        title: '💊 복약 시간이에요! ($label)',
        body: '$medicineText 복약을 잊지 마세요',
        hour: hour,
        minute: minute,
      );

      // 2차 알림: 30분 후 재알림
      final totalMinutes = hour * 60 + minute + 30;
      final reminderHour = (totalMinutes ~/ 60) % 24;
      final finalMinute = totalMinutes % 60;

      await scheduleDailyNotification(
        id: id++,
        title: '⚠️ 아직 복약 안 하셨나요? ($label)',
        body: '$medicineText 아직 복약하지 않으셨어요. 지금 바로 확인해주세요!',
        hour: reminderHour,
        minute: finalMinute,
        channelId: _reminderChannelId,
        channelName: _reminderChannelName,
      );
    }
  }
}

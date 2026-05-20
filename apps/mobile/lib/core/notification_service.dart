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

  // 복약 스케줄 기반으로 알림 + 30분 후 재알림 일괄 등록
  static Future<void> scheduleFromSchedules(
    List<Map<String, dynamic>> schedules,
  ) async {
    await cancelAll();

    final registered = <String>{};
    int id = 100;

    for (final schedule in schedules) {
      if (schedule['log_id'] != null || schedule['status'] == 'taken') continue;

      final timeSlot = schedule['time_slot'] as String? ?? '';
      final times = _resolveScheduleTime(schedule);
      if (times == null) continue;

      final key = '$timeSlot-${times[0]}:${times[1]}';
      if (registered.contains(key)) continue;
      registered.add(key);

      final label = _slotLabels[timeSlot] ?? timeSlot;
      final hour = times[0];
      final minute = times[1];

      // 1차 알림: 복약 시간
      await scheduleDailyNotification(
        id: id++,
        title: '💊 복약 시간이에요!',
        body: '$label 복약을 잊지 마세요',
        hour: hour,
        minute: minute,
      );

      // 2차 알림: 30분 후 재알림
      final totalMinutes = hour * 60 + minute + 30;
      final reminderHour = (totalMinutes ~/ 60) % 24;
      final finalMinute = totalMinutes % 60;

      await scheduleDailyNotification(
        id: id++,
        title: '⚠️ 아직 복약 안 하셨나요?',
        body: '$label 약을 아직 드시지 않으셨어요. 지금 바로 복약해주세요!',
        hour: reminderHour,
        minute: finalMinute,
        channelId: _reminderChannelId,
        channelName: _reminderChannelName,
      );
    }
  }
}

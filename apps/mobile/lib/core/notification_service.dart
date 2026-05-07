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

  static final _slotTimes = {
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

  // 복약 스케줄 기반으로 알림 + 30분 후 재알림 일괄 등록
  static Future<void> scheduleFromSlots(List<Map<String, dynamic>> slots) async {
    await cancelAll();

    final registered = <String>{};
    int id = 100;

    for (final slot in slots) {
      final timeSlot = slot['time_slot'] as String;
      if (registered.contains(timeSlot)) continue;
      registered.add(timeSlot);

      final times = _slotTimes[timeSlot];
      if (times == null) continue;

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
      final reminderMinute = minute + 30;
      final reminderHour = hour + (reminderMinute ~/ 60);
      final finalMinute = reminderMinute % 60;

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

  // 특정 슬롯 재알림 취소 (복약 완료 시 호출)
  static Future<void> cancelReminderForSlot(String timeSlot) async {
    // 재알림 ID는 슬롯 순서 기반으로 계산 (id=101, 103, 105, 107)
    final slots = ['morning', 'lunch', 'dinner', 'bedtime'];
    final idx = slots.indexOf(timeSlot);
    if (idx < 0) return;
    final reminderId = 100 + (idx * 2) + 1;
    await cancel(reminderId);
  }
}

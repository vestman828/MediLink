import '../data/api_client.dart';
import 'storage.dart';
import 'notification_service.dart';

class GuardianAlertService {
  static const _slotLabels = {
    'morning': '아침',
    'lunch': '점심',
    'dinner': '저녁',
    'bedtime': '취침',
  };

  // 복용 시간 + 2시간 기준
  static const _slotCutoffHour = {
    'morning': 10,
    'lunch': 14,
    'dinner': 20,
    'bedtime': 0,
  };

  /// 로그인 직후 딱 한 번 호출
  /// 오늘 미복약 슬롯이 있으면 환자별로 알림 1개씩 띄움
  static Future<void> checkAndNotify(String token) async {
    try {
      final userId = await Storage.getUserId();
      if (userId == null) return;

      final res = await ApiClient.get(
        '/guardian/dashboard',
        token: token,
        queryParams: {'guardian_id': userId.toString()},
      );
      final patients = res['data'] as List<dynamic>? ?? [];
      if (patients.isEmpty) return;

      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;

      final List<String> missedLines = [];

      for (final patient in patients) {
        final name = patient['patient_name'] as String;
        final schedules = patient['today_schedules'] as List<dynamic>? ?? [];

        final List<String> missedSlots = [];
        for (final s in schedules) {
          if (s['status'] == 'taken') continue;
          final slot = s['time_slot'] as String;
          final cutoffHour = _slotCutoffHour[slot];
          if (cutoffHour == null) continue;
          final cutoffMinutes = cutoffHour == 0 ? 24 * 60 : cutoffHour * 60;
          if (currentMinutes >= cutoffMinutes) {
            missedSlots.add(_slotLabels[slot] ?? slot);
          }
        }

        if (missedSlots.isNotEmpty) {
          missedLines.add('$name님: ${missedSlots.join(', ')}');
        }
      }

      if (missedLines.isEmpty) return;

      // 알림 하나로 묶어서 띄우기
      await NotificationService.showNow(
        id: 500,
        title: '💊 미복약 알림',
        body: missedLines.join('\n'),
      );
    } catch (_) {
      // 실패 시 조용히 무시
    }
  }
}

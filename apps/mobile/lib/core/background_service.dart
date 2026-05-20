import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'notification_service.dart';
import '../data/api_client.dart';

const _taskName = 'medilink.checkMissedDose';
const _taskUniqueName = 'medilink_missed_dose_check';

// 백그라운드 isolate에서 실행되는 진입점 - 반드시 최상위 함수여야 함
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _taskName) {
      await _checkAndNotifyMissed();
    }
    return true;
  });
}

Future<void> _checkAndNotifyMissed() async {
  try {
    await NotificationService.init();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final userId = prefs.getInt('user_id');
    final role = prefs.getString('user_role');

    // 환자만 체크
    if (token == null || userId == null || role != 'patient') return;

    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final uri = Uri.parse(
      '${ApiClient.baseUrl}/schedules/today?patient_id=$userId&date=$dateStr',
    );
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    }).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final schedules = data['data'] as List<dynamic>? ?? [];

    final slotLabels = {
      'morning': '아침',
      'lunch': '점심',
      'dinner': '저녁',
      'bedtime': '취침',
      'custom': '직접설정',
    };

    final nowMinutes = today.hour * 60 + today.minute;

    int notifId = 200;
    for (final s in schedules) {
      // 이미 복약 완료된 것은 건너뜀
      if (s['log_id'] != null) continue;

      // 스케줄 시간 파싱 (HH:mm:ss)
      final timeParts =
          (s['scheduled_time'] as String? ?? '00:00:00').split(':');
      final schedHour = int.tryParse(timeParts[0]) ?? 0;
      final schedMin = int.tryParse(timeParts[1]) ?? 0;

      // 예약 시간 + 30분이 지났는지 확인
      final schedMinutes = schedHour * 60 + schedMin;
      if (nowMinutes >= schedMinutes + 30) {
        final slot = s['time_slot'] as String? ?? '';
        final label = slotLabels[slot] ?? slot;
        final medicine = s['medicine_name'] as String? ?? '약';

        await NotificationService.showNow(
          id: notifId++,
          title: '⚠️ $label 복약을 아직 안 하셨어요!',
          body: '$medicine 복약을 잊으셨나요? 지금 바로 복약해주세요.',
        );
      }
    }
  } catch (e) {
    // 백그라운드 에러는 무시 (앱에 영향 없음)
  }
}

class BackgroundService {
  // 앱 시작 시 초기화 + 주기적 태스크 등록
  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  // 30분마다 미복약 체크 태스크 등록
  static Future<void> registerPeriodicTask() async {
    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      _taskName,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  // 태스크 취소 (로그아웃 시)
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'storage.dart';
import '../data/api_client.dart';
import 'notification_service.dart';

class FcmService {
  static final _messaging = FirebaseMessaging.instance;

  // 가족 연동 요청 FCM 수신 시 호출할 콜백 (PatientHomeScreenState에서 등록)
  static VoidCallback? onFamilyRequest;

  static Future<void> init() async {
    // 알림 권한 요청
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 포그라운드 메시지 수신
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // 가족 연동 요청 데이터 메시지
      if (message.data['type'] == 'family_request') {
        onFamilyRequest?.call();
        return;
      }
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      if (title.isNotEmpty) {
        NotificationService.showNow(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: title,
          body: body,
        );
      }
    });

    // 백그라운드 상태에서 알림 탭해서 앱 열었을 때
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['type'] == 'family_request') {
        onFamilyRequest?.call();
      }
    });
  }

  // 로그인 후 FCM 토큰 서버에 저장
  static Future<void> uploadToken(String authToken) async {
    try {
      final fcmToken = await _messaging.getToken();
      if (fcmToken == null) return;
      await ApiClient.patch(
        '/users/me/fcm-token',
        token: authToken,
        body: {'fcm_token': fcmToken},
      );
      // 토큰 갱신 시 자동 업로드
      _messaging.onTokenRefresh.listen((newToken) async {
        final storedToken = await Storage.getToken();
        if (storedToken != null) {
          await ApiClient.patch(
            '/users/me/fcm-token',
            token: storedToken,
            body: {'fcm_token': newToken},
          );
        }
      });
    } catch (e) {
      debugPrint('[FCM] 토큰 업로드 실패: $e');
    }
  }
}

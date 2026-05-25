import 'dart:async';

import '../data/auth_repository.dart';
import 'notification_service.dart';
import 'storage.dart';

class LogoutService {
  static final AuthRepository _authRepo = AuthRepository();

  static Future<void> logout({
    required String? token,
    bool cancelNotifications = false,
  }) async {
    if (token != null && token.isNotEmpty) {
      unawaited(_authRepo.logout(token: token).catchError((_) {}));
    }

    if (cancelNotifications) {
      try {
        await NotificationService.cancelAll();
      } catch (_) {
        // Local session cleanup must still complete even if notification cleanup fails.
      }
    }
    await Storage.clear();
  }
}

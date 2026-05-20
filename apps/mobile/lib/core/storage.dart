import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static const _tokenKey = 'access_token';
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';
  static const _userRoleKey = 'user_role';

  // 알림 시간 기본값: 아침 8:00, 점심 12:00, 저녁 18:00, 취침 22:00
  static const _defaultSlotTimes = {
    'morning': [8, 0],
    'lunch': [12, 0],
    'dinner': [18, 0],
    'bedtime': [22, 0],
  };

  static Future<Map<String, List<int>>> getSlotTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, List<int>>{};
    for (final entry in _defaultSlotTimes.entries) {
      final h = prefs.getInt('slot_${entry.key}_h') ?? entry.value[0];
      final m = prefs.getInt('slot_${entry.key}_m') ?? entry.value[1];
      result[entry.key] = [h, m];
    }
    return result;
  }

  static Future<void> saveSlotTime(String slot, int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('slot_${slot}_h', hour);
    await prefs.setInt('slot_${slot}_m', minute);
  }

  static Future<void> saveSession({
    required String token,
    required int userId,
    required String name,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_tokenKey, token),
      prefs.setInt(_userIdKey, userId),
      prefs.setString(_userNameKey, name),
      prefs.setString(_userRoleKey, role),
    ]);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  static Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userRoleKey);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    // 알림 시간 설정은 로그아웃해도 유지
    await Future.wait([
      prefs.remove(_tokenKey),
      prefs.remove(_userIdKey),
      prefs.remove(_userNameKey),
      prefs.remove(_userRoleKey),
    ]);
  }
}

import 'api_client.dart';

class AuthResult {
  final String accessToken;
  final int userId;
  final String name;
  final String role;

  const AuthResult({
    required this.accessToken,
    required this.userId,
    required this.name,
    required this.role,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthResult(
      accessToken: json['accessToken'] as String,
      userId: user['user_id'] as int,
      name: user['name'] as String,
      role: user['role'] as String,
    );
  }
}

class OtpSendResult {
  final int expiresIn;
  final String? debugCode;

  const OtpSendResult({required this.expiresIn, required this.debugCode});
}

class AuthRepository {
  Future<AuthResult> login({
    required String phone,
    required String password,
  }) async {
    final data = await ApiClient.post('/auth/login', {
      'phone': phone,
      'password': password,
    });
    return AuthResult.fromJson(data);
  }

  Future<OtpSendResult> sendSignupOtp({required String phone}) async {
    final data = await ApiClient.post(
        '/auth/otp/send',
        {
          'phone': phone,
          'purpose': 'signup',
        },
        timeout: const Duration(seconds: 30));

    return OtpSendResult(
      expiresIn: data['expires_in'] as int? ?? 300,
      debugCode: data['debug_code'] as String?,
    );
  }

  Future<String> verifySignupOtp({
    required String phone,
    required String code,
  }) async {
    final data = await ApiClient.post(
        '/auth/otp/verify',
        {
          'phone': phone,
          'code': code,
          'purpose': 'signup',
        },
        timeout: const Duration(seconds: 20));

    final token = data['verify_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const ApiException('인증 토큰이 비어 있습니다.', 500);
    }

    return token;
  }

  Future<int> signup({
    required String name,
    required String phone,
    required String password,
    required String role,
    required String verifyToken,
  }) async {
    final data = await ApiClient.post('/auth/signup', {
      'name': name,
      'phone': phone,
      'password': password,
      'role': role,
      'verify_token': verifyToken,
    });
    return data['user_id'] as int;
  }

  Future<void> logout({required String token}) async {
    await ApiClient.post('/auth/logout', {}, token: token);
  }

  Future<bool> phoneExists(String phone) async {
    final data = await ApiClient.get('/auth/phone-exists',
        queryParams: {'phone': phone});
    return data['exists'] == true;
  }
}

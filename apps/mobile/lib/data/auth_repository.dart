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

  Future<int> signup({
    required String name,
    required String phone,
    required String password,
    required String role,
  }) async {
    final data = await ApiClient.post('/auth/signup', {
      'name': name,
      'phone': phone,
      'password': password,
      'role': role,
    });
    return data['user_id'] as int;
  }
}

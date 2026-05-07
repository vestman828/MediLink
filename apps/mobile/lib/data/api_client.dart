import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

class ApiClient {
  // ⚠️ 개발 환경에 따라 아래 IP를 변경해야 합니다:
  // - 안드로이드 에뮬레이터: 'http://10.0.2.2:4000/api'
  // - 실기기 (USB/핫스팟): 'http://<본인PC의_로컬IP>:4000/api'
  //   → Windows: ipconfig | findstr IPv4
  //   → Mac/Linux: ifconfig | grep inet
  static const String _baseUrl = 'http://192.168.137.1:4000/api';

  static Map<String, String> _headers({String? token}) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(token: token),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw ApiException(data['message'] as String? ?? '요청에 실패했습니다.', response.statusCode);
  }

  static Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);
    final response = await http
        .get(uri, headers: _headers(token: token))
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw ApiException(data['message'] as String? ?? '요청에 실패했습니다.', response.statusCode);
  }

  static Future<Map<String, dynamic>> patch(
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final response = await http
        .patch(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(token: token),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw ApiException(data['message'] as String? ?? '요청에 실패했습니다.', response.statusCode);
  }

  static Future<Map<String, dynamic>> put(
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final response = await http
        .put(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(token: token),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw ApiException(data['message'] as String? ?? '요청에 실패했습니다.', response.statusCode);
  }

  static Future<Map<String, dynamic>> delete(
    String path, {
    String? token,
  }) async {
    final response = await http
        .delete(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(token: token),
        )
        .timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw ApiException(data['message'] as String? ?? '요청에 실패했습니다.', response.statusCode);
  }
}

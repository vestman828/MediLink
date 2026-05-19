import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

class ApiClient {
  // HTTPS default.
  // Override with: --dart-define=MEDILINK_API_BASE_URL=https://your-host/api
  static const String _baseUrl = String.fromEnvironment(
    'MEDILINK_API_BASE_URL',
    defaultValue: 'https://10.0.2.2:4000/api',
  );

  static const Duration _defaultTimeout = Duration(seconds: 20);

  static String get baseUrl => _baseUrl;

  static Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Map<String, dynamic> _parseBody(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{'message': response.body};
    }
  }

  static void _throwIfError(http.Response response, Map<String, dynamic> data) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw ApiException(
      data['message'] as String? ?? '요청에 실패했습니다.',
      response.statusCode,
    );
  }

  static Future<http.Response> _runWithNetworkGuard(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    try {
      return await request().timeout(timeout ?? _defaultTimeout);
    } on TimeoutException {
      throw const ApiException('요청 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.', 408);
    } on HandshakeException {
      throw const ApiException('HTTPS 인증서 연결에 실패했습니다. 앱을 재실행해주세요.', 495);
    } on SocketException {
      throw const ApiException('서버에 연결할 수 없습니다. 네트워크/서버 상태를 확인해주세요.', 503);
    } on HttpException {
      throw const ApiException('HTTP 통신 중 오류가 발생했습니다.', 500);
    }
  }

  static Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async {
    final response = await _runWithNetworkGuard(
      () => http.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(token: token),
        body: jsonEncode(body),
      ),
      timeout: timeout,
    );

    final data = _parseBody(response);
    _throwIfError(response, data);
    return data;
  }

  static Future<Map<String, dynamic>> get(
    String path, {
    String? token,
    Map<String, String>? queryParams,
    Duration? timeout,
  }) async {
    final uri =
        Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);
    final response = await _runWithNetworkGuard(
      () => http.get(uri, headers: _headers(token: token)),
      timeout: timeout,
    );

    final data = _parseBody(response);
    _throwIfError(response, data);
    return data;
  }

  static Future<Map<String, dynamic>> patch(
    String path, {
    String? token,
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final response = await _runWithNetworkGuard(
      () => http.patch(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(token: token),
        body: body != null ? jsonEncode(body) : null,
      ),
      timeout: timeout,
    );

    final data = _parseBody(response);
    _throwIfError(response, data);
    return data;
  }

  static Future<Map<String, dynamic>> put(
    String path, {
    String? token,
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final response = await _runWithNetworkGuard(
      () => http.put(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(token: token),
        body: body != null ? jsonEncode(body) : null,
      ),
      timeout: timeout,
    );

    final data = _parseBody(response);
    _throwIfError(response, data);
    return data;
  }

  static Future<Map<String, dynamic>> delete(
    String path, {
    String? token,
    Duration? timeout,
  }) async {
    final response = await _runWithNetworkGuard(
      () => http.delete(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(token: token),
      ),
      timeout: timeout,
    );

    final data = _parseBody(response);
    _throwIfError(response, data);
    return data;
  }
}

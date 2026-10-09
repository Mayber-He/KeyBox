import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:synchronized/synchronized.dart';
import '../core/crypto_box.dart';

abstract class SessionStorage {
  Future<String?> read();
  Future<void> write(String? value);
}

class SecureSessionStorage implements SessionStorage {
  final _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: 'keybox_sync_session');
  @override
  Future<void> write(String? value) => value == null
      ? _storage.delete(key: 'keybox_sync_session')
      : _storage.write(key: 'keybox_sync_session', value: value);
}

class MemorySessionStorage implements SessionStorage {
  String? _value;
  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String? value) async {
    _value = value;
  }
}

class ApiError implements Exception {
  ApiError(this.status, this.code, {this.current});
  final int status;
  final String code;
  final Json? current;
  @override
  String toString() => '服务器请求失败 ($status/$code)';
}

class ApiClient {
  ApiClient(
    this.base,
    this.storage, {
    http.Client? client,
    bool allowLocalHttp = false,
  }) : _client = client ?? http.Client() {
    if (base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.scheme != 'https' &&
            !(allowLocalHttp &&
                !kReleaseMode &&
                base.scheme == 'http' &&
                ['127.0.0.1', 'localhost', '10.0.2.2'].contains(base.host))) ||
        (base.path.isNotEmpty && base.path != '/')) {
      throw const FormatException('请使用完整的 HTTPS 服务器地址（不含路径、账号或参数）');
    }
  }
  final Uri base;
  final SessionStorage storage;
  final http.Client _client;
  final _mutex = Lock();
  String? _access, _refresh;
  String? deviceId;
  bool get authenticated => _refresh != null;

  Future<void> restore() async {
    final raw = await storage.read();
    if (raw == null) return;
    final data = Json.from(jsonDecode(raw) as Map);
    if (data['url'] != base.toString()) return;
    _refresh = data['refresh_token'] as String;
    deviceId = data['device_id'] as String;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Json? body,
    String? access,
  }) async {
    final request = http.Request(method, base.resolve('/api/v1$path'))
      ..followRedirects = false;
    request.headers['Content-Type'] = 'application/json';
    if (access != null) request.headers['Authorization'] = 'Bearer $access';
    if (body != null) request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw ApiError(response.statusCode, 'invalid_response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw ApiError(
        response.statusCode,
        detail is Map
            ? detail['code'] as String? ?? 'request_failed'
            : 'request_failed',
        current: detail is Map && detail['current'] is Map
            ? Json.from(detail['current'] as Map)
            : null,
      );
    }
    return decoded;
  }

  Future<void> _accept(dynamic response) async {
    final data = Json.from(response as Map);
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String;
    final device = data['device_id'] as String;
    await storage.write(
      jsonEncode({
        'url': base.toString(),
        'refresh_token': refresh,
        'device_id': device,
      }),
    );
    _access = access;
    _refresh = refresh;
    deviceId = device;
  }

  Future<void> login(String username, String password) =>
      _mutex.synchronized(() async {
        await _accept(
          await _send(
            'POST',
            '/auth/login',
            body: {
              'username': username,
              'password': password,
              'device_name': 'KeyBox 手机',
            },
          ),
        );
      });

  Future<void> _renew() async {
    final previous = _refresh;
    if (previous == null) throw ApiError(401, 'login_required');
    // Remove before sending: a lost response must never cause refresh replay.
    _access = null;
    _refresh = null;
    await storage.write(null);
    await _accept(
      await _send('POST', '/auth/refresh', body: {'refresh_token': previous}),
    );
  }

  Future<dynamic> request(String method, String path, {Json? body}) =>
      _mutex.synchronized(() async {
        if (_access == null) await _renew();
        try {
          return await _send(method, path, body: body, access: _access);
        } on ApiError catch (error) {
          if (error.status != 401) rethrow;
          await _renew();
          try {
            return await _send(method, path, body: body, access: _access);
          } on ApiError catch (retryError) {
            if (retryError.status == 401) {
              _access = null;
              _refresh = null;
              await storage.write(null);
            }
            rethrow;
          }
        }
      });
  Future<void> logout() async {
    try {
      if (authenticated) await request('POST', '/auth/logout');
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() async {
    _access = null;
    _refresh = null;
    deviceId = null;
    await storage.write(null);
  }

  void close() => _client.close();
}

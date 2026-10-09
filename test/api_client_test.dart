import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keybox/sync/api_client.dart';

void main() {
  test('串行刷新会话，不重试已消耗令牌，拒绝凭据重定向', () async {
    final storage = MemorySessionStorage();
    var refreshes = 0;
    final client = ApiClient(
      Uri.parse('https://vault.example.com'),
      storage,
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        if (request.url.path.endsWith('/login')) {
          return http.Response(
            jsonEncode({
              'access_token': 'old',
              'refresh_token': 'refresh-old',
              'device_id': 'device',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/refresh')) {
          refreshes++;
          expect(await storage.read(), isNull);
          return http.Response(
            jsonEncode({
              'access_token': 'new',
              'refresh_token': 'refresh-new',
              'device_id': 'device',
            }),
            200,
          );
        }
        return request.headers['Authorization'] == 'Bearer old'
            ? http.Response('{"detail":{"code":"unauthorized"}}', 401)
            : http.Response('[]', 200);
      }),
    );
    await client.login('user', 'separate-sync-password');
    await Future.wait([
      client.request('GET', '/devices'),
      client.request('GET', '/devices'),
    ]);
    expect(refreshes, 1);
    expect(await storage.read(), contains('refresh-new'));
    final redirect = ApiClient(
      Uri.parse('https://vault.example.com'),
      MemorySessionStorage(),
      client: MockClient(
        (request) async => http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example'},
        ),
      ),
    );
    await expectLater(
      redirect.login('user', 'password'),
      throwsA(isA<ApiError>()),
    );
    expect(
      () => ApiClient(Uri.parse('http://example.com'), MemorySessionStorage()),
      throwsFormatException,
    );
  });
  test('刷新响应丢失后必须重新登录，不能重放旧刷新令牌', () async {
    final storage = MemorySessionStorage();
    await storage.write(
      jsonEncode({
        'url': 'https://vault.example.com',
        'refresh_token': 'refresh-old',
        'device_id': 'device',
      }),
    );
    var calls = 0;
    final client = ApiClient(
      Uri.parse('https://vault.example.com'),
      storage,
      client: MockClient((request) async {
        calls++;
        throw http.ClientException('offline');
      }),
    );
    await client.restore();
    await expectLater(
      client.request('GET', '/vault'),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      client.request('GET', '/vault'),
      throwsA(isA<ApiError>()),
    );
    expect(calls, 1);
    expect(await storage.read(), isNull);
  });
}

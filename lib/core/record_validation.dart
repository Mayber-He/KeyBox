import 'crypto_box.dart';
import '../otp/totp.dart';

void validateRecord(Json data) {
  if (data['name'] is! String || (data['name'] as String).trim().isEmpty) {
    throw const FormatException('条目缺少名称');
  }
  for (final field in [
    'username',
    'account',
    'password',
    'secret',
    'website',
    'notes',
    'category',
  ]) {
    if (data[field] != null && data[field] is! String) {
      throw const FormatException('条目字段格式错误');
    }
  }
  if (data['color'] != null &&
      (data['color'] is! int ||
          data['color'] < 0 ||
          data['color'] > 0xFFFFFFFF)) {
    throw const FormatException('无效头像颜色');
  }
  switch (data['kind']) {
    case 'password':
      if (data['password'] is! String || (data['password'] as String).isEmpty) {
        throw const FormatException('条目缺少密码');
      }
    case 'otp':
      if (data['account'] is! String || (data['account'] as String).isEmpty) {
        throw const FormatException('条目缺少账号');
      }
      normalizeSecret(data['secret'] as String? ?? '');
      validateOtp(
        data['algorithm'] as String? ?? 'SHA1',
        data['digits'] as int? ?? 6,
        data['period'] as int? ?? 30,
      );
    default:
      throw const FormatException('不支持的条目类型');
  }
}

import 'package:base32/base32.dart';
import 'package:otp/otp.dart';
import '../core/crypto_box.dart';

String normalizeSecret(String value) {
  final secret = value
      .toUpperCase()
      .replaceAll(RegExp(r'\s'), '')
      .replaceFirst(RegExp(r'=+$'), '');
  if (secret.isEmpty ||
      secret.length > 512 ||
      !RegExp(r'^[A-Z2-7]+$').hasMatch(secret)) {
    throw const FormatException('请填写有效的 Base32 密钥');
  }
  try {
    final decoded = base32.decode(
      secret.padRight(((secret.length + 7) ~/ 8) * 8, '='),
    );
    if (decoded.isEmpty ||
        base32.encode(decoded).replaceAll('=', '') != secret) {
      throw const FormatException('无效 Base32 密钥');
    }
  } catch (_) {
    throw const FormatException('请填写有效的 Base32 密钥');
  }
  return secret;
}

void validateOtp(String algorithm, int digits, int period) {
  if (!['SHA1', 'SHA256', 'SHA512'].contains(algorithm) ||
      ![6, 8].contains(digits) ||
      period < 1 ||
      period > 300) {
    throw const FormatException('不支持的验证码参数');
  }
}

String totp(
  String secret,
  DateTime time, {
  String algorithm = 'SHA1',
  int digits = 6,
  int period = 30,
}) {
  validateOtp(algorithm, digits, period);
  return OTP.generateTOTPCodeString(
    normalizeSecret(secret),
    time.millisecondsSinceEpoch,
    length: digits,
    interval: period,
    isGoogle: true,
    algorithm: switch (algorithm) {
      'SHA256' => Algorithm.SHA256,
      'SHA512' => Algorithm.SHA512,
      _ => Algorithm.SHA1,
    },
  );
}

Json parseOtpUri(String raw) {
  try {
    final uri = Uri.parse(raw);
    if (uri.scheme != 'otpauth' ||
        uri.host != 'totp' ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      throw const FormatException('仅支持 TOTP 二维码');
    }
    final label = Uri.decodeComponent(uri.path.substring(1));
    if (label.isEmpty) throw const FormatException('缺少账号');
    final separator = label.indexOf(':');
    final issuer =
        (uri.queryParameters['issuer'] ??
                (separator < 0 ? '' : label.substring(0, separator)))
            .trim();
    final account = (separator < 0 ? label : label.substring(separator + 1))
        .trim();
    if (account.isEmpty) throw const FormatException('缺少账号');
    final algorithm = (uri.queryParameters['algorithm'] ?? 'SHA1')
        .toUpperCase();
    final digits = int.parse(uri.queryParameters['digits'] ?? '6');
    final period = int.parse(uri.queryParameters['period'] ?? '30');
    validateOtp(algorithm, digits, period);
    return {
      'name': issuer.isEmpty ? account : issuer,
      'account': account,
      'secret': normalizeSecret(uri.queryParameters['secret'] ?? ''),
      'algorithm': algorithm,
      'digits': digits,
      'period': period,
    };
  } catch (_) {
    throw const FormatException('二维码不是有效的 TOTP 配置，请手动输入');
  }
}

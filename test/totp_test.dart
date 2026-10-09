import 'dart:convert';
import 'dart:typed_data';
import 'package:base32/base32.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keybox/otp/totp.dart';

void main() {
  test('RFC6238 全部算法与时间测试向量', () {
    final times = [
      59,
      1111111109,
      1111111111,
      1234567890,
      2000000000,
      20000000000,
    ];
    final vectors = {
      'SHA1': [
        '94287082',
        '07081804',
        '14050471',
        '89005924',
        '69279037',
        '65353130',
      ],
      'SHA256': [
        '46119246',
        '68084774',
        '67062674',
        '91819424',
        '90698825',
        '77737706',
      ],
      'SHA512': [
        '90693936',
        '25091201',
        '99943326',
        '93441116',
        '38618901',
        '47863826',
      ],
    };
    final lengths = {'SHA1': 20, 'SHA256': 32, 'SHA512': 64};
    for (final algorithm in vectors.keys) {
      final secret = List.generate(
        lengths[algorithm]!,
        (i) => '1234567890'[i % 10],
      ).join();
      for (var i = 0; i < times.length; i++) {
        expect(
          totp(
            base32.encode(Uint8List.fromList(utf8.encode(secret))),
            DateTime.fromMillisecondsSinceEpoch(times[i] * 1000),
            algorithm: algorithm,
            digits: 8,
          ),
          vectors[algorithm]![i],
        );
      }
    }
  });
  test('扫码参数解析、默认值与错误格式拒绝', () {
    final parsed = parseOtpUri(
      'otpauth://totp/GitHub%3Atest%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub',
    );
    expect(parsed['name'], 'GitHub');
    expect(parsed['account'], 'test@example.com');
    expect(parsed['period'], 30);
    for (final uri in [
      'otpauth://hotp/test?secret=JBSWY3DPEHPK3PXP',
      'otpauth://totp/test?secret=invalid!',
      'otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&period=0',
      'otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&digits=7',
      'otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&algorithm=MD5',
    ]) {
      expect(() => parseOtpUri(uri), throwsFormatException);
    }
  });
}

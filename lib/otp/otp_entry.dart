import 'package:flutter/material.dart';
import 'totp.dart';

class OtpEntry {
  const OtpEntry({
    required this.id,
    required this.name,
    required this.account,
    this.secret = 'DEMO_SECRET_ONLY',
    this.color = const Color(0xFF2C806A),
    this.algorithm = 'SHA1',
    this.digits = 6,
    this.period = 30,
  });
  final String id, name, account, secret;
  final Color color;
  final String algorithm;
  final int digits, period;
  String code(DateTime now) =>
      totp(secret, now, algorithm: algorithm, digits: digits, period: period);
  Map<String, dynamic> toData() => {
    'name': name,
    'account': account,
    'secret': secret,
    'algorithm': algorithm,
    'digits': digits,
    'period': period,
    'color': color.toARGB32(),
  };
  factory OtpEntry.fromData(Map<String, dynamic> data) => OtpEntry(
    id: data['id'] as String,
    name: data['name'] as String,
    account: data['account'] as String,
    secret: data['secret'] as String,
    algorithm: data['algorithm'] as String? ?? 'SHA1',
    digits: data['digits'] as int? ?? 6,
    period: data['period'] as int? ?? 30,
    color: Color(data['color'] as int? ?? 0xFF2C806A),
  );

  String demoCode(int round) {
    const codes = ['482193', '761408', '295637', '830251'];
    final offset = id.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return codes[(round + offset) % codes.length];
  }
}

List<OtpEntry> demoTokens() => [
  OtpEntry(
    id: 'github',
    name: 'GitHub',
    account: 'keybox-demo',
    color: Color(0xFF53616C),
  ),
  OtpEntry(
    id: 'google',
    name: 'Google',
    account: 'hello@example.com',
    color: Color(0xFFBF715B),
  ),
  OtpEntry(
    id: 'aliyun',
    name: '阿里云',
    account: 'cloud@example.com',
    color: Color(0xFFC5894E),
  ),
];

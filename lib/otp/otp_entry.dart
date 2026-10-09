import 'package:flutter/material.dart';

class OtpEntry {
  const OtpEntry({
    required this.id,
    required this.name,
    required this.account,
    this.secret = 'DEMO_SECRET_ONLY',
    this.color = const Color(0xFF2C806A),
  });
  final String id, name, account, secret;
  final Color color;

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

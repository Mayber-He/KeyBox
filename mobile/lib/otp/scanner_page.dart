import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/crypto_box.dart';
import 'totp.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _done = false;
  String? _error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描验证码二维码')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              if (_done) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw == null) continue;
                try {
                  final Json result = parseOtpUri(raw);
                  _done = true;
                  Navigator.pop(context, result);
                  return;
                } catch (_) {
                  if (_error == null) {
                    setState(() => _error = '不是有效的 TOTP 二维码，可返回手动输入');
                  }
                }
              }
            },
            errorBuilder: (_, _) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('无法使用摄像头。请检查相机权限，或返回手动输入密钥。'),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(_error ?? '二维码仅在本机解析，不上传图片。'),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import '../ui.dart';

class OtpPage extends StatelessWidget {
  const OtpPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      PageHeader(title: '验证码', subtitle: '为账号多加一层保护'),
      Padding(padding: EdgeInsets.all(24), child: Text('验证码录入将在下一阶段接入')),
    ],
  );
}

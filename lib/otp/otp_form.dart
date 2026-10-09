import 'package:flutter/material.dart';
import '../ui.dart';
import 'otp_entry.dart';

class OtpFormPage extends StatefulWidget {
  const OtpFormPage({super.key, this.entry});
  final OtpEntry? entry;
  @override
  State<OtpFormPage> createState() => _OtpFormPageState();
}

class _OtpFormPageState extends State<OtpFormPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.entry?.name);
  late final _account = TextEditingController(text: widget.entry?.account);
  late final _secret = TextEditingController(text: widget.entry?.secret);
  @override
  void dispose() {
    for (final controller in [_name, _account, _secret]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      OtpEntry(
        id:
            widget.entry?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        account: _account.text.trim(),
        secret: _secret.text.trim(),
        color: widget.entry?.color ?? mint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.entry == null ? '添加验证码' : '编辑验证码')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  '多一层保护',
                  style: TextStyle(
                    fontSize: 22,
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请使用演示密钥。验证码为预设示例，不可用于登录。',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => message(context, '扫码功能尚未接入'),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('扫描二维码'),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '服务名称 *',
                    hintText: '例如：GitHub',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写服务名称' : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _account,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '账号 *',
                    hintText: 'demo@example.com',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写账号' : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _secret,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '演示密钥 *',
                    hintText: 'DEMO_SECRET_ONLY',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写演示密钥' : null,
                ),
                const SizedBox(height: 28),
                FilledButton(onPressed: _save, child: const Text('保存条目')),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import '../ui.dart';
import 'otp_entry.dart';
import 'totp.dart';
import 'scanner_page.dart';
import '../core/crypto_box.dart';
import 'package:uuid/uuid.dart';

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
  late String _algorithm = widget.entry?.algorithm ?? 'SHA1';
  late int _digits = widget.entry?.digits ?? 6;
  late final _period = TextEditingController(
    text: '${widget.entry?.period ?? 30}',
  );
  @override
  void dispose() {
    for (final controller in [_name, _account, _secret, _period]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      OtpEntry(
        id: widget.entry?.id ?? const Uuid().v4(),
        name: _name.text.trim(),
        account: _account.text.trim(),
        secret: normalizeSecret(_secret.text),
        algorithm: _algorithm,
        digits: _digits,
        period: int.parse(_period.text),
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
                  '密钥将在本机加密保存，验证码离线计算。请保持设备时间准确。',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<Json>(
                      context,
                      MaterialPageRoute(builder: (_) => const ScannerPage()),
                    );
                    if (result == null || !mounted) return;
                    setState(() {
                      _name.text = result['name'] as String;
                      _account.text = result['account'] as String;
                      _secret.text = result['secret'] as String;
                      _algorithm = result['algorithm'] as String;
                      _digits = result['digits'] as int;
                      _period.text = '${result['period']}';
                    });
                  },
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
                    labelText: '密钥 *',
                    hintText: 'Base32 密钥',
                  ),
                  obscureText: true,
                  validator: (v) {
                    try {
                      normalizeSecret(v ?? '');
                      return null;
                    } catch (_) {
                      return '请填写有效的 Base32 密钥';
                    }
                  },
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  key: ValueKey(_algorithm),
                  initialValue: _algorithm,
                  decoration: const InputDecoration(labelText: '算法'),
                  items: ['SHA1', 'SHA256', 'SHA512']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => _algorithm = v!),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
                  key: ValueKey(_digits),
                  initialValue: _digits,
                  decoration: const InputDecoration(labelText: '位数'),
                  items: [6, 8]
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text('$v 位')),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _digits = v!),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _period,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '刷新周期（秒）'),
                  validator: (v) =>
                      (int.tryParse(v ?? '') ?? 0) < 1 ||
                          (int.tryParse(v ?? '') ?? 0) > 300
                      ? '周期需为 1 到 300 秒'
                      : null,
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

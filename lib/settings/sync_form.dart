import 'package:flutter/material.dart';
import '../ui.dart';

class SyncFormPage extends StatefulWidget {
  const SyncFormPage({super.key});
  @override
  State<SyncFormPage> createState() => _SyncFormPageState();
}

class _SyncFormPageState extends State<SyncFormPage> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController(text: 'https://vault.example.com');
  final _token = TextEditingController(text: 'demo-token-only');
  bool _hidden = true;
  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('云同步配置')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F0E8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.cloud_outlined, color: mint, size: 32),
                      SizedBox(height: 12),
                      Text(
                        '自己的云，自己的密码箱',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '此页面仅演示配置流程，不保存地址与令牌，也不会连接服务器。',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _address,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://vault.example.com',
                  ),
                  validator: (value) {
                    final uri = Uri.tryParse(value?.trim() ?? '');
                    return uri == null ||
                            uri.scheme != 'https' ||
                            uri.host.isEmpty
                        ? '请填写完整的 HTTPS 地址'
                        : null;
                  },
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _token,
                  obscureText: _hidden,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '演示同步令牌',
                    hintText: '请勿填写真实令牌',
                    suffixIcon: IconButton(
                      tooltip: _hidden ? '显示令牌' : '隐藏令牌',
                      onPressed: () => setState(() => _hidden = !_hidden),
                      icon: Icon(
                        _hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写演示令牌' : null,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () {
                    if (_form.currentState!.validate()) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('确认演示配置'),
                ),
                const SizedBox(height: 18),
                const Text(
                  '云端连接与加密同步将在后续版本接入。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import '../core/crypto_box.dart';
import '../core/vault_store.dart';
import '../ui.dart';

enum SetupMode { create, change, recover }

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, this.mode = SetupMode.create});
  final SetupMode mode;
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  VaultSetup? _setup;
  bool _busy = false, _saved = false, _installed = false;
  String? _error;
  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    if (!_installed) _setup?.key.destroy();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = VaultScope.read(context);
    final generation = store.epoch;
    try {
      final setup = switch (widget.mode) {
        SetupMode.create => await store.crypto.create(_password.text),
        SetupMode.change => await store.prepareChange(
          _current.text,
          _password.text,
        ),
        SetupMode.recover => await store.prepareRecovery(
          _current.text,
          _password.text,
        ),
      };
      if (!mounted || store.epoch != generation) {
        setup.key.destroy();
        return;
      }
      _current.clear();
      _password.clear();
      _confirm.clear();
      setState(() => _setup = setup);
    } catch (_) {
      if (mounted) setState(() => _error = '验证失败，请检查主密码或恢复密钥');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install() async {
    if (!_saved || _busy) return;
    setState(() => _busy = true);
    _installed = true;
    final store = VaultScope.read(context);
    try {
      if (widget.mode == SetupMode.create) {
        await store.initialize(_setup!);
      } else {
        await store.applyChange(_setup!);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _setup = null;
          _installed = false;
          _saved = false;
          _error = '保存失败，请检查存储空间后重新生成';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.mode) {
          SetupMode.create => '设置主密码',
          SetupMode.change => '修改主密码',
          SetupMode.recover => '恢复密码箱',
        }),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_setup == null)
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        const Text(
                          '主密码至少 12 个字符。建议使用独特的长口令。',
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 24),
                        if (widget.mode != SetupMode.create) ...[
                          TextFormField(
                            controller: _current,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: widget.mode == SetupMode.recover
                                  ? '恢复密钥'
                                  : '当前主密码',
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? '请填写验证信息' : null,
                          ),
                          const SizedBox(height: 18),
                        ],
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(labelText: '新主密码'),
                          validator: (v) =>
                              (v?.length ?? 0) < 12 ? '主密码至少 12 个字符' : null,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _confirm,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(labelText: '确认主密码'),
                          validator: (v) =>
                              v != _password.text ? '两次主密码不一致' : null,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _busy ? null : _prepare,
                          child: Text(_busy ? '正在生成…' : '生成恢复密钥'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  const Text(
                    '保存恢复密钥',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '请抄写或保存到独立的安全位置。此密钥可以解密全部密码和验证码。主密码与恢复密钥均丢失时无法恢复。修改后请保存新的恢复密钥。',
                  ),
                  const SizedBox(height: 24),
                  SelectableText(
                    _setup!.recoveryKey,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: mint,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _saved,
                    onChanged: (v) => setState(() => _saved = v ?? false),
                    title: const Text('我已保存恢复密钥'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  FilledButton(
                    onPressed: !_saved || _busy ? null : _install,
                    child: Text(_busy ? '正在保存…' : '完成设置'),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

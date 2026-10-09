import 'package:flutter/material.dart';
import 'sync_service.dart';
import '../ui.dart';

class MergePage extends StatefulWidget {
  const MergePage({super.key, required this.service});
  final SyncService service;
  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  final _form = GlobalKey<FormState>();
  final _credential = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _recovery = false, _busy = false, _saved = false, _transferred = false;
  RemoteRecovery? _setup;
  String? _error;
  @override
  void dispose() {
    _credential.dispose();
    _password.dispose();
    _confirm.dispose();
    if (!_transferred) _setup?.setup.key.destroy();
    super.dispose();
  }

  Future<void> _merge() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_recovery && _setup == null) {
        final setup = await widget.service.prepareRemoteRecovery(
          _credential.text,
          _password.text,
        );
        if (!mounted) {
          setup.setup.key.destroy();
          return;
        }
        setState(() => _setup = setup);
        _credential.clear();
        _password.clear();
        _confirm.clear();
        return;
      }
      if (_recovery && !_saved) return;
      _transferred = true;
      await widget.service.mergeRemote(
        _credential.text,
        recovery: _recovery,
        mergeLocal: widget.service.store.records.isNotEmpty,
        recoverySetup: _setup,
      );
      _setup = null;
      await widget.service.quietSync();
      if (mounted) {
        message(context, '云端密码箱已解锁并合并，本地条目已保留');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '解锁或合并失败，请检查主密码、恢复密钥及连接';
          _setup = null;
          _transferred = false;
          _saved = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('解锁云端密码箱')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('服务器已有独立的加密密码箱。解锁后，本地账号会以新条目合并，不覆盖云端条目。'),
            const SizedBox(height: 20),
            Form(
              key: _form,
              child: Column(
                children: [
                  if (_setup == null) ...[
                    SwitchListTile(
                      title: const Text('使用恢复密钥'),
                      value: _recovery,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _recovery = v),
                    ),
                    TextFormField(
                      controller: _credential,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: _recovery ? '云端恢复密钥' : '云端主密码',
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? '请输入解锁凭据' : null,
                    ),
                    if (_recovery) ...[
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '新主密码'),
                        validator: (v) =>
                            (v?.length ?? 0) < 12 ? '主密码至少 12 个字符' : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '确认新主密码'),
                        validator: (v) =>
                            v != _password.text ? '两次主密码不一致' : null,
                      ),
                    ],
                  ] else ...[
                    const Text('请保存新的恢复密钥。完成后会更新云端主密码与恢复密钥设置。'),
                    const SizedBox(height: 16),
                    SelectableText(
                      _setup!.setup.recoveryKey,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: mint,
                      ),
                    ),
                    CheckboxListTile(
                      value: _saved,
                      onChanged: (v) => setState(() => _saved = v ?? false),
                      title: const Text('我已保存恢复密钥'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy || (_setup != null && !_saved)
                        ? null
                        : _merge,
                    child: Text(
                      _busy
                          ? '正在处理…'
                          : _recovery && _setup == null
                          ? '生成新的恢复密钥'
                          : '解锁并合并',
                    ),
                  ),
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
          ],
        ),
      ),
    ),
  );
}

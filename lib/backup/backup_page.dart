import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/vault_store.dart';
import '../ui.dart';
import 'backup_codec.dart';

Future<void> selectBackup(VaultStore store) async {
  final file = await FilePicker.pickFile(dialogTitle: '选择 KeyBox 加密备份');
  if (file == null) return;
  final length = await file.length();
  if (length == null || length > BackupCodec.maxFile) {
    throw const FormatException('备份文件不可读取或超过 24 MiB');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > BackupCodec.maxFile) throw const FormatException('备份文件过大');
  // Native file selection may background the app. Stage ciphertext only;
  // the app resumes the import wizard after the next successful unlock.
  store.stageBackup(bytes);
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, this.importFile});
  final Uint8List? importFile;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController(), _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy || !_form.currentState!.validate()) return;
    final store = VaultScope.read(context);
    final password = _password.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codec = BackupCodec(store);
      if (widget.importFile != null) {
        final count = await codec.import(widget.importFile!, password);
        if (!mounted) return;
        Navigator.pop(context);
        message(context, '已导入 $count 个条目，现有数据已保留');
      } else {
        final encrypted = await codec.export(password);
        if (!mounted) return;
        _password.clear();
        _confirm.clear();
        final target = await FilePicker.saveFile(
          fileName: 'keybox-${DateTime.now().millisecondsSinceEpoch}.keybox',
          bytes: encrypted,
        );
        if (!mounted) return;
        if (target != null) {
          Navigator.pop(context);
          message(context, '加密备份已导出');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = '操作失败，请检查备份密码、文件格式及存储空间');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.importFile == null ? '导出加密备份' : '导入加密备份'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.importFile == null
                    ? '设置独立的备份密码。备份不包含同步账号凭据，忘记备份密码无法解密文件。'
                    : '输入此备份的密码。导入会添加新条目，保留所有现有数据；重复导入也会生成副本。',
              ),
              const SizedBox(height: 24),
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: '备份密码'),
                      validator: (v) =>
                          widget.importFile == null && (v?.length ?? 0) < 12
                          ? '备份密码至少 12 个字符'
                          : (v == null || v.isEmpty ? '请输入备份密码' : null),
                    ),
                    if (widget.importFile == null) ...[
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '确认备份密码'),
                        validator: (v) =>
                            v != _password.text ? '两次备份密码不一致' : null,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _run,
                      child: Text(
                        _busy
                            ? '正在处理…'
                            : widget.importFile == null
                            ? '加密并导出'
                            : '解密并合并',
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
    ),
  );
}

import 'package:flutter/material.dart';
import '../ui.dart';
import 'password_entry.dart';

class PasswordFormPage extends StatefulWidget {
  const PasswordFormPage({super.key, this.entry});
  final PasswordEntry? entry;
  @override
  State<PasswordFormPage> createState() => _PasswordFormPageState();
}

class _PasswordFormPageState extends State<PasswordFormPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.entry?.name);
  late final _username = TextEditingController(text: widget.entry?.username);
  late final _password = TextEditingController(text: widget.entry?.password);
  late final _website = TextEditingController(text: widget.entry?.website);
  late final _notes = TextEditingController(text: widget.entry?.notes);
  bool _hidden = true;
  @override
  void dispose() {
    for (final controller in [_name, _username, _password, _website, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      PasswordEntry(
        id:
            widget.entry?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        website: _website.text.trim(),
        notes: _notes.text.trim(),
        category: widget.entry?.category ?? '个人',
        color: widget.entry?.color ?? mint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.entry == null ? '添加密码' : '编辑密码')),
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
                  '给账号一个熟悉的名字',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '仅用于页面演示，请填写虚构内容。',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '名称 *',
                    hintText: '例如：我的邮箱',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写名称' : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _username,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '用户名 / 邮箱',
                    hintText: 'demo@example.com',
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _password,
                  obscureText: _hidden,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '密码 *',
                    hintText: '填写示例密码',
                    suffixIcon: IconButton(
                      tooltip: _hidden ? '显示密码' : '隐藏密码',
                      onPressed: () => setState(() => _hidden = !_hidden),
                      icon: Icon(
                        _hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写密码' : null,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _website,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '网址',
                    hintText: 'https://example.com',
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    hintText: '记录一点与账号有关的信息',
                  ),
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

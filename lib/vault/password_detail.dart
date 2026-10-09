import 'package:flutter/material.dart';
import '../ui.dart';
import 'password_entry.dart';

class PasswordDetailPage extends StatefulWidget {
  const PasswordDetailPage({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });
  final PasswordEntry entry;
  final Future<PasswordEntry?> Function(PasswordEntry) onEdit;
  final VoidCallback onDelete;
  @override
  State<PasswordDetailPage> createState() => _PasswordDetailPageState();
}

class _PasswordDetailPageState extends State<PasswordDetailPage> {
  bool _visible = false;
  late PasswordEntry _entry = widget.entry;
  Future<void> _edit() async {
    final updated = await widget.onEdit(_entry);
    if (updated != null && mounted) {
      setState(() {
        _entry = updated;
        _visible = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号详情'),
        actions: [
          TextButton(onPressed: _edit, child: const Text('编辑')),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    ServiceAvatar(name: entry.name, color: entry.color),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Text(
                            entry.category,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const DemoBadge(),
                  ],
                ),
                const SizedBox(height: 32),
                _field(
                  '用户名',
                  entry.username.isEmpty ? '未填写' : entry.username,
                  entry.username.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '复制用户名',
                          onPressed: () => copyDemo(context, entry.username),
                          icon: const Icon(Icons.copy_rounded, size: 20),
                        ),
                ),
                _field(
                  '密码',
                  _visible ? entry.password : '••••••••••••',
                  Wrap(
                    children: [
                      IconButton(
                        tooltip: _visible ? '隐藏密码' : '显示密码',
                        onPressed: () => setState(() => _visible = !_visible),
                        icon: Icon(
                          _visible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                      ),
                      IconButton(
                        tooltip: '复制密码',
                        onPressed: () => copyDemo(context, entry.password),
                        icon: const Icon(Icons.copy_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                _field(
                  '网址',
                  entry.website.isEmpty ? '未填写' : entry.website,
                  entry.website.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '复制网址',
                          onPressed: () => copyDemo(context, entry.website),
                          icon: const Icon(Icons.copy_rounded, size: 20),
                        ),
                ),
                _field('备注', entry.notes.isEmpty ? '暂无备注' : entry.notes, null),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (!await confirmDelete(context, entry.name) ||
                        !context.mounted) {
                      return;
                    }
                    widget.onDelete();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除条目'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB75252),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '此账号为虚构示例，不可用于实际登录。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, String value, Widget? action) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(color: ink, fontSize: 16, height: 1.5),
        ),
        if (action != null)
          Align(alignment: Alignment.centerRight, child: action),
      ],
    ),
  );
}

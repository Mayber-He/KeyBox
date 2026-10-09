import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/crypto_box.dart';
import '../ui.dart';
import 'sync_service.dart';

class ConflictsPage extends StatelessWidget {
  const ConflictsPage({super.key, required this.service});
  final SyncService service;
  Future<void> _resolve(
    BuildContext context,
    String id,
    ConflictChoice choice,
  ) async {
    try {
      await service.resolve(id, choice);
      await service.quietSync();
    } catch (error) {
      if (context.mounted) {
        message(
          context,
          error is StateError ? error.message.toString() : '无法处理冲突，数据已保留',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('同步冲突')),
    body: ListenableBuilder(
      listenable: service,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('选择要保留的版本。删除与编辑发生冲突时，也由你确认。'),
          if (service.metadataConflict != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('主密码与恢复设置发生冲突。保留云端后，下次解锁需要云端的主密码。'),
                    for (final local in [true, false])
                      TextButton(
                        onPressed: service.busy
                            ? null
                            : () async {
                                try {
                                  await service.resolveMetadata(local);
                                  await service.quietSync();
                                } catch (_) {
                                  if (context.mounted) {
                                    message(context, '设置冲突未解决，请重试');
                                  }
                                }
                              },
                        child: Text(local ? '保留本地设置' : '保留云端设置'),
                      ),
                  ],
                ),
              ),
            ),
          for (final conflict in service.conflicts)
            _ConflictCard(
              key: ValueKey('${conflict.id}:${conflict.local['operation_id']}'),
              service: service,
              conflict: conflict,
              onChoose: (choice) => _resolve(context, conflict.id, choice),
            ),
          if (service.conflicts.isEmpty && service.metadataConflict == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('没有待处理冲突', textAlign: TextAlign.center),
            ),
        ],
      ),
    ),
  );
}

class _ConflictCard extends StatefulWidget {
  const _ConflictCard({
    super.key,
    required this.service,
    required this.conflict,
    required this.onChoose,
  });
  final SyncService service;
  final SyncConflict conflict;
  final Future<void> Function(ConflictChoice) onChoose;
  @override
  State<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<_ConflictCard> {
  late final Future<List<Json?>> _data = _read();
  bool _show = false, _busy = false;
  Future<List<Json?>> _read() async {
    final c = widget.conflict, store = widget.service.store;
    return [
      c.local['deleted'] == 1
          ? null
          : await store.decryptRecord(
              c.id,
              Json.from(jsonDecode(c.local['payload'] as String) as Map),
            ),
      c.remote['deleted'] == true || c.remote['payload'] == null
          ? null
          : await store.decryptRecord(
              c.id,
              Json.from(c.remote['payload'] as Map),
            ),
    ];
  }

  Widget _version(String title, Json? data) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (data == null)
          const Text('已删除或云端不存在')
        else ...[
          Text('${data['name']}'),
          for (final field in ['username', 'account', 'website', 'notes'])
            if ((data[field] as String? ?? '').isNotEmpty)
              Text('${data[field]}'),
          if (data['password'] != null)
            Text('密码：${_show ? data['password'] : '••••••••'}'),
          if (data['secret'] != null)
            Text('验证码密钥：${_show ? data['secret'] : '••••••••'}'),
        ],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('无法验证条目，已保留原数据，请重新同步');
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _version('本地版本', snapshot.data![0]),
              _version('云端版本', snapshot.data![1]),
              TextButton(
                onPressed: () => setState(() => _show = !_show),
                child: Text(_show ? '隐藏敏感内容' : '显示敏感内容'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final choice in ConflictChoice.values)
                    OutlinedButton(
                      onPressed: _busy || widget.service.busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              await widget.onChoose(choice);
                              if (mounted) setState(() => _busy = false);
                            },
                      child: Text(switch (choice) {
                        ConflictChoice.local => '保留本地',
                        ConflictChoice.cloud => '保留云端',
                        ConflictChoice.both => '保留两份',
                      }),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

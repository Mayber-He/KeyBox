import 'dart:async';
import 'package:flutter/material.dart';
import '../ui.dart';
import 'otp_entry.dart';
import 'otp_form.dart';

class OtpPage extends StatefulWidget {
  const OtpPage({super.key});
  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final _entries = demoTokens();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _started = DateTime.now();
  late final Timer _timer;
  int _elapsed = 0;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed = DateTime.now().difference(_started).inSeconds);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _edit([OtpEntry? entry]) async {
    final result = await Navigator.push<OtpEntry>(
      context,
      MaterialPageRoute(builder: (_) => OtpFormPage(entry: entry)),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (entry == null) {
        _entries.insert(0, result);
      } else {
        _entries[_entries.indexWhere((item) => item.id == entry.id)] = result;
      }
    });
    message(context, entry == null ? '已添加演示验证码' : '已保存修改');
  }

  Future<void> _delete(OtpEntry entry) async {
    if (!await confirmDelete(context, entry.name) || !mounted) return;
    setState(() => _entries.remove(entry));
    message(context, '已删除演示验证码');
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _entries
        .where(
          (entry) =>
              '${entry.name} ${entry.account}'.toLowerCase().contains(query),
        )
        .toList();
    final remaining = 30 - _elapsed % 30;
    return CustomScrollView(
      controller: _scroll,
      key: const PageStorageKey('otp'),
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: '验证码',
            subtitle: '多一层保护，多一份安心',
            action: IconButton.filled(
              tooltip: '添加验证码',
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SearchBox(
            controller: _search,
            onChanged: (_) => setState(() {}),
            hint: '搜索服务或账号',
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 16, color: mint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '每 30 秒轮换预设演示码 · ${_entries.length} 个账号',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(searching: query.isNotEmpty, label: '验证码'),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final entry = visible[index];
              final code = entry.demoCode(_elapsed ~/ 30);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _edit(entry),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ServiceAvatar(
                                name: entry.name,
                                color: entry.color,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      entry.account,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: '验证码操作',
                                onSelected: (action) {
                                  if (action == 'edit') {
                                    _edit(entry);
                                  } else {
                                    _delete(entry);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('编辑'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final digits = Semantics(
                                label: '演示验证码 $code',
                                excludeSemantics: true,
                                child: Wrap(
                                  spacing: 12,
                                  children: [
                                    for (final part in [
                                      code.substring(0, 3),
                                      code.substring(3),
                                    ])
                                      Text(
                                        part,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 34,
                                          color: mint,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                              final controls = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Semantics(
                                    label: '$remaining 秒后刷新演示码',
                                    child: SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            value: remaining / 30,
                                            strokeWidth: 3,
                                            backgroundColor: const Color(
                                              0xFFE9F0EB,
                                            ),
                                            color: remaining <= 5
                                                ? const Color(0xFFC5894E)
                                                : mint,
                                          ),
                                          Text(
                                            '$remaining',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '复制验证码',
                                    onPressed: () => copyDemo(context, code),
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      color: muted,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              );
                              if (constraints.maxWidth < 300 ||
                                  MediaQuery.textScalerOf(context).scale(34) >
                                      41) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    digits,
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: controls,
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: digits),
                                  const SizedBox(width: 12),
                                  controls,
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

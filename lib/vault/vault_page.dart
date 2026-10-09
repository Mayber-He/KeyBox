import 'package:flutter/material.dart';
import '../ui.dart';
import 'password_entry.dart';
import 'password_detail.dart';
import 'password_form.dart';
import '../core/vault_store.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});
  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  List<PasswordEntry> get _entries => VaultScope.of(context).records
      .where((row) => row['kind'] == 'password')
      .map(PasswordEntry.fromData)
      .toList();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Future<PasswordEntry?> _edit([PasswordEntry? entry]) async {
    final result = await Navigator.push<PasswordEntry>(
      context,
      MaterialPageRoute(builder: (_) => PasswordFormPage(entry: entry)),
    );
    if (result == null || !mounted) return null;
    try {
      await VaultScope.read(
        context,
      ).save('password', result.toData(), id: result.id);
      if (!mounted) return null;
      message(context, entry == null ? '已添加条目' : '已保存修改');
    } catch (_) {
      if (mounted) message(context, '保存失败，请检查存储空间或重新解锁');
      return null;
    }
    return result;
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _entries
        .where(
          (entry) =>
              '${entry.name} ${entry.username} ${entry.website} ${entry.category}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return CustomScrollView(
      controller: _scroll,
      scrollBehavior: ScrollConfiguration.of(
        context,
      ).copyWith(overscroll: false),
      key: const PageStorageKey('vault'),
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: '密码箱',
            subtitle: '把重要的账号，安放在这里',
            action: IconButton.filled(
              onPressed: () => _edit(),
              tooltip: '添加密码',
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F0E8),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const BrandMark(size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '井井有条，轻松找到',
                          style: TextStyle(
                            color: ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_entries.length} 个账号 · 本机加密保存',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SearchBox(
            controller: _search,
            onChanged: (_) => setState(() {}),
            hint: '搜索名称、账号或网址',
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              query.isEmpty ? '全部账号' : '搜索结果 · ${visible.length}',
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(searching: query.isNotEmpty, label: '密码条目'),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final entry = visible[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PasswordDetailPage(
                          entry: entry,
                          onEdit: _edit,
                          onDelete: () =>
                              VaultScope.read(context).delete(entry.id),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ServiceAvatar(name: entry.name, color: entry.color),
                          const SizedBox(width: 14),
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
                                  entry.username.isEmpty
                                      ? '未填写账号'
                                      : entry.username,
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
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: muted,
                            size: 20,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const mint = Color(0xFF2C806A);
const ink = Color(0xFF233E37);
const canvas = Color(0xFFF6F8F5);
const muted = Color(0xFF75847E);

ThemeData keyBoxTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: mint, surface: Colors.white),
  scaffoldBackgroundColor: canvas,
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: ink,
      letterSpacing: -1,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE3EAE4)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: mint, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: mint,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: const Color(0xFFDDEEE5),
    labelTextStyle: WidgetStateProperty.all(
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    elevation: 0,
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: ink,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

void message(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> copyDemo(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) message(context, '已复制');
}

Future<bool> confirmDelete(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除条目？'),
        content: Text('删除“$name”？连接云同步后也会同步此删除操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFB75252))),
          ),
        ],
      ),
    ) ??
    false;

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(Icons.key_rounded, color: Colors.white, size: size * .55),
  );
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFE4EEE7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      '加密',
      style: TextStyle(color: mint, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            const DemoBadge(),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: muted, fontSize: 13)),
      ],
    ),
  );
}

class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hint,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, color: muted),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    ),
  );
}

class ServiceAvatar extends StatelessWidget {
  const ServiceAvatar({super.key, required this.name, this.color = mint});
  final String name;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(fontSize: 21, color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.searching, required this.label});
  final bool searching;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
    child: Column(
      children: [
        Icon(
          searching ? Icons.search_off_rounded : Icons.inbox_outlined,
          size: 52,
          color: muted,
        ),
        const SizedBox(height: 16),
        Text(
          searching ? '没有找到相关条目' : '还没有$label',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          searching ? '试试其他名称或账号' : '点击右上角的加号，添加第一个条目',
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
      ],
    ),
  );
}

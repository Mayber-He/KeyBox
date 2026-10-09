import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'ui.dart';
import 'vault/vault_page.dart';
import 'otp/otp_page.dart';
import 'settings/settings_page.dart';

class KeyBoxApp extends StatelessWidget {
  const KeyBoxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KeyBox',
    debugShowCheckedModeBanner: false,
    theme: keyBoxTheme(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const UnlockPage(),
  );
}

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key});
  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _hidden = true;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _unlock() {
    if (!_form.currentState!.validate()) return;
    _password.clear();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [BrandMark(), Spacer(), DemoBadge()]),
                  const SizedBox(height: 64),
                  const Text(
                    '留一份安心，\n给数字生活。',
                    style: TextStyle(
                      fontSize: 34,
                      color: ink,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '欢迎回到 KeyBox',
                    style: TextStyle(
                      color: mint,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('密码与验证码，一处轻松管理。', style: TextStyle(color: muted)),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidden,
                    enableSuggestions: false,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _unlock(),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '请输入任意非空内容以进入演示'
                        : null,
                    decoration: InputDecoration(
                      labelText: '主密码',
                      hintText: '输入任意内容体验',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _unlock,
                      child: const Text('解锁密码箱'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => message(context, '指纹解锁尚未接入'),
                      icon: const Icon(Icons.fingerprint_rounded, size: 28),
                      label: const Text('使用指纹解锁'),
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Center(
                    child: Text(
                      '静态演示 · 请勿输入真实密码\n所有示例数据将在重启后重置',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12, height: 1.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: IndexedStack(
            index: _index,
            children: const [VaultPage(), OtpPage(), SettingsPage()],
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.lock_outline_rounded),
          selectedIcon: Icon(Icons.lock_rounded),
          label: '密码箱',
        ),
        NavigationDestination(
          icon: Icon(Icons.shield_outlined),
          selectedIcon: Icon(Icons.shield_rounded),
          label: '验证码',
        ),
        NavigationDestination(icon: Icon(Icons.tune_rounded), label: '设置'),
      ],
    ),
  );
}

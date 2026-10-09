import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/vault_store.dart';
import 'security/setup_page.dart';
import 'ui.dart';
import 'vault/vault_page.dart';
import 'otp/otp_page.dart';
import 'settings/settings_page.dart';
import 'sync/sync_service.dart';

class KeyBoxApp extends StatefulWidget {
  const KeyBoxApp({super.key, required this.store, this.sync});
  final VaultStore store;
  final SyncService? sync;
  @override
  State<KeyBoxApp> createState() => _KeyBoxAppState();
}

class _KeyBoxAppState extends State<KeyBoxApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  bool _wasUnlocked = false;
  @override
  void initState() {
    super.initState();
    _wasUnlocked = widget.store.unlocked;
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_changed);
  }

  void _changed() {
    if (_wasUnlocked && !widget.store.unlocked) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
    if (!_wasUnlocked && widget.store.unlocked) widget.sync?.quietSync();
    _wasUnlocked = widget.store.unlocked;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.store.unlocked) {
      widget.sync?.quietSync();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.store.lock();
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = VaultScope(
      store: widget.store,
      child: MaterialApp(
        navigatorKey: _navigator,
        title: 'KeyBox',
        debugShowCheckedModeBanner: false,
        theme: keyBoxTheme(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ListenableBuilder(
          listenable: widget.store,
          builder: (_, _) =>
              widget.store.unlocked ? const HomePage() : const UnlockPage(),
        ),
      ),
    );
    return widget.sync == null
        ? app
        : SyncScope(service: widget.sync!, child: app);
  }
}

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key});
  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _hidden = true, _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await VaultScope.read(context).unlock(_password.text);
      if (mounted) _password.clear();
    } catch (_) {
      if (mounted) setState(() => _error = '主密码不正确，或加密数据无法验证');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = VaultScope.of(context);
    return Scaffold(
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
                    const SizedBox(height: 56),
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
                    const SizedBox(height: 20),
                    Text(
                      store.configured ? '欢迎回到 KeyBox' : '创建你的密码箱',
                      style: const TextStyle(
                        color: mint,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '密码与验证码，本机加密，离线可用。',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 32),
                    if (store.configured) ...[
                      TextFormField(
                        controller: _password,
                        obscureText: _hidden,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _unlock(),
                        validator: (v) =>
                            v == null || v.isEmpty ? '请输入主密码' : null,
                        decoration: InputDecoration(
                          labelText: '主密码',
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
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _unlock,
                          child: Text(_busy ? '正在解锁…' : '解锁密码箱'),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const SetupPage(mode: SetupMode.recover),
                                ),
                              ),
                        child: const Text('使用恢复密钥'),
                      ),
                    ] else
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const SetupPage(),
                            ),
                          ),
                          child: const Text('设置主密码'),
                        ),
                      ),
                    const SizedBox(height: 28),
                    const Text(
                      '主密码仅用于本地解密，不发送到服务器。\n请妥善保管恢复密钥。',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.8),
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

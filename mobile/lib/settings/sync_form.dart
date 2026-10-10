import 'package:flutter/material.dart';
import '../sync/api_client.dart';
import '../sync/sync_service.dart';
import '../sync/merge_page.dart';
import '../ui.dart';

class SyncFormPage extends StatefulWidget {
  const SyncFormPage({super.key, required this.service});
  final SyncService service;
  @override
  State<SyncFormPage> createState() => _SyncFormPageState();
}

class _SyncFormPageState extends State<SyncFormPage> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController();
  bool _hidden = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await widget.service.store.config('sync_url');
    final username = await widget.service.store.config('sync_username');
    if (!mounted) return;
    _address.text = url ?? '';
    _username.text = username ?? '';
  }

  @override
  void dispose() {
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.connect(
        _address.text,
        _username.text,
        _password.text,
      );
      if (mounted) {
        _password.clear();
        message(context, '服务器已连接并同步');
        Navigator.pop(context);
      }
    } on RemoteVaultRequired {
      if (mounted) {
        _password.clear();
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => MergePage(service: widget.service),
          ),
        );
        if (mounted && widget.service.remoteVault == null) {
          Navigator.pop(context);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiError && error.status == 401
              ? '同步账号或密码不正确'
              : error is ApiError && error.status == 429
              ? '登录尝试过多，请 15 分钟后重试'
              : '连接未完成。请检查 HTTPS 地址、网络或设置中的同步状态',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('云同步配置')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.cloud_outlined, color: mint, size: 40),
              const SizedBox(height: 16),
              const Text(
                '自己的云，自己的密码箱',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              const SizedBox(height: 12),
              const Text('使用管理员创建的同步账号。同步密码和主密码相互独立；服务器只接收密码箱密文。'),
              const SizedBox(height: 24),
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _address,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        hintText: 'https://maybing.top/keybox/api/',
                      ),
                      validator: (v) {
                        final uri = Uri.tryParse(v?.trim() ?? '');
                        return uri == null ||
                                uri.scheme != 'https' ||
                                uri.host.isEmpty ||
                                uri.userInfo.isNotEmpty ||
                                uri.hasQuery ||
                                uri.hasFragment
                            ? '请填写完整 HTTPS 地址，不含账号或参数'
                            : null;
                      },
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _username,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: '同步账号'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '请输入同步账号' : null,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidden,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: '同步密码',
                        suffixIcon: IconButton(
                          tooltip: _hidden ? '显示同步密码' : '隐藏同步密码',
                          onPressed: () => setState(() => _hidden = !_hidden),
                          icon: Icon(
                            _hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? '请输入同步密码' : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _connect,
                      child: Text(_busy ? '正在连接…' : '登录并同步'),
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
              const SizedBox(height: 24),
              const Text(
                '刷新会话保存在系统安全存储中。修改主密码不会修改同步账号密码。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

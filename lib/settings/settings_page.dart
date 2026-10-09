import 'package:flutter/material.dart';
import '../ui.dart';
import '../core/vault_store.dart';
import '../security/setup_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('settings'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PageHeader(title: '设置', subtitle: '让 KeyBox 更适合你'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F0E8),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Row(
              children: [
                BrandMark(),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KeyBox',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '简单收纳，安心生活',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _section('安全', [
          _item(
            Icons.lock_rounded,
            '立即锁定',
            '清除内存中的解密密钥',
            () => VaultScope.read(context).lock(),
          ),
          _item(
            Icons.fingerprint_rounded,
            '指纹解锁',
            '更轻松地打开密码箱',
            () => message(context, '指纹解锁尚未接入'),
            trailing: Switch(
              value: false,
              onChanged: (_) => message(context, '指纹解锁尚未接入'),
            ),
          ),
          _item(
            Icons.lock_outline_rounded,
            '修改主密码',
            '管理你的解锁方式',
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const SetupPage(mode: SetupMode.change),
              ),
            ),
          ),
          _item(
            Icons.key_outlined,
            '恢复密钥',
            '验证主密码后换发恢复密钥',
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const SetupPage(mode: SetupMode.change),
              ),
            ),
          ),
        ]),
        _section('关于', [
          _item(
            Icons.info_outline_rounded,
            '关于 KeyBox',
            '版本 0.2.0',
            () => showAboutDialog(
              context: context,
              applicationName: 'KeyBox',
              applicationVersion: '0.2.0',
              applicationIcon: const BrandMark(),
              children: const [
                Text('密码与验证码，一处轻松管理。\n\n条目在本机加密保存；云端保存密文。主密码与同步账号密码分别使用。'),
              ],
            ),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 24, 32, 8),
          child: Text(
            '主密码与恢复密钥均丢失时，已有密文无法恢复',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: 56,
                    endIndent: 16,
                    color: Color(0xFFF0F3EF),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _item(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    Widget? trailing,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    leading: Icon(icon, color: mint, size: 23),
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(subtitle, style: const TextStyle(color: muted, fontSize: 11)),
    ),
    trailing:
        trailing ??
        const Icon(Icons.chevron_right_rounded, color: muted, size: 20),
    onTap: onTap,
  );
}

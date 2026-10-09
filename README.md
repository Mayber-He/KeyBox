# KeyBox

个人使用的 Flutter 密码箱与 TOTP 验证码 App，采用中文、薄荷绿 Material 3 界面。Android 为当前验证平台，保留 iOS 工程。

首次启动从空密码箱开始，设置至少 12 字符的主密码，并确认保存随机恢复密钥。主密码用于本机解密；云同步使用独立账号密码，两者可以分别修改。主密码与恢复密钥均丢失时，已有密文无法恢复。

## 目录结构

```text
KeyBox/
├── mobile/    # Flutter 客户端：Android/iOS、页面、测试及依赖
├── backend/   # FastAPI 服务、数据库迁移及后端测试
├── deploy/    # Docker Compose 与 Caddy 配置
├── docs/      # 接口契约、部署说明及验收记录
├── artifacts/ # 本地验证产物，不提交 Git
└── README.md
```

Flutter 命令在 `mobile/` 中执行；后端和部署命令在仓库根目录执行。Android Studio 或其他 Flutter IDE 打开 `mobile/`。客户端内部按 `core`、`vault`、`otp`、`security`、`sync`、`backup` 和 `settings` 组织代码。

## 已实现

- 密码条目搜索、详情、密码显隐、复制、增删改，SQLite 加密持久化；进程重启和进入后台后锁定。
- Argon2id 派生密钥、AES-256-GCM 加密、独立随机密码箱密钥；修改主密码和恢复操作会换发恢复密钥。
- 离线 TOTP：SHA-1、SHA-256、SHA-512，6/8 位，支持手动录入及 `otpauth://totp` 扫码；拒绝 HOTP 与无效参数。
- FastAPI 单账号同步：CLI 创建账号、轮换刷新令牌、设备会话撤销、密文接口、版本检查、幂等写入与永久删除标记。
- 客户端自动/手动同步、离线队列、明确的冲突选择；首次连接已有云端密码箱时，解锁后确认合并本地条目。
- 独立备份密码加密导出、验证后以新 UUID 合并导入；不会清空现有数据，重复导入会生成副本。
- Docker Compose、Caddy HTTPS、持久化数据卷，以及 SQLite 一致性备份/恢复 CLI。

服务器保存账号、设备信息、条目 UUID、版本、时间、删除标记与密文，不接收主密码、恢复密钥、明文条目或 TOTP 计算请求。客户端刷新令牌使用平台安全存储，解锁密钥仅在内存中使用。运行时可能存在由库或字符串生成的临时副本，不能承诺托管内存的所有副本立即被物理清零。

## Android 客户端

本次环境为 Flutter 3.41.9、Dart 3.11.5、Android SDK 和 JDK。安装后从仓库根目录进入客户端运行：

```sh
cd mobile
flutter doctor
flutter pub get
flutter devices
flutter run -d <device-id>
```

在设置中连接 `https://你的域名`，填写服务器 CLI 创建的同步账号与密码。客户端正常入口只接受 HTTPS 根地址。验证码依赖手机时间，请保持系统时间准确。指纹解锁、系统自动填充和公开注册尚未实现。

```sh
flutter analyze
flutter test --no-pub --concurrency=1 --reporter expanded
flutter test --no-pub integration_test/demo_flow_test.dart -d <device-id> --reporter expanded
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

以上命令均在 `mobile/` 中执行，APK 位于 `mobile/build/app/outputs/flutter-apk/app-debug.apk`。文件名 `demo_flow_test.dart` 沿用原工程；内容现为真实加密流程，全部使用虚构测试数据。APK 使用调试签名。iOS 需要后续 macOS/Xcode、签名与运行验证，工程已加入相机用途说明与 Keychain entitlement。

选择备份文件可能触发系统文件界面并让 App 锁定；返回后先重新解锁，再输入备份密码完成导入。导出前先生成完整密文文件，系统保存界面不会收到条目明文。备份文件与恢复密钥需要分别保管。

## 后端本地运行

使用 Python 3.12，在仓库根目录另开终端，建立虚拟环境并安装锁定依赖：

```sh
python -m venv .venv
# Windows PowerShell:
.venv/Scripts/python.exe -m pip install -r backend/requirements.lock.txt
.venv/Scripts/python.exe -m pip install --no-deps -e backend
.venv/Scripts/python.exe -m keybox_backend.cli create-account YOUR_USERNAME
.venv/Scripts/python.exe -m uvicorn keybox_backend.app:app --host 127.0.0.1 --port 8000 --workers 1 --no-access-log
```

Linux 使用 `.venv/bin/python`。CLI 隐藏输入并确认独立同步密码，不在命令参数中传入密码。服务启动与 CLI 会执行 Alembic 迁移；默认数据库为当前目录的 `keybox.db`，可用 `KEYBOX_DATABASE_URL` 指定持久化 SQLite 路径。

```sh
.venv/Scripts/python.exe -m pytest backend/tests -q
.venv/Scripts/python.exe -m keybox_backend.cli reset-password YOUR_USERNAME
.venv/Scripts/python.exe -m keybox_backend.cli backup path/to/new-backup.db
.venv/Scripts/python.exe -m keybox_backend.cli restore path/to/backup.db path/to/new-restored.db
```

备份目标不能已经存在。服务器恢复操作创建新数据库并撤销恢复出的全部设备会话；停服后切换数据库路径，客户端重新登录。服务器数据库备份包含认证哈希和密文，并非客户端的独立密码加密备份。

[接口契约与加密格式](docs/api.md)、[部署与运维操作](docs/deployment.md)、[实施与验收记录](docs/implementation.md)。

## 真实 HTTP 双客户端测试

`mobile/test/sync_live_test.dart` 需显式启用，平常测试会跳过。它使用两个独立本地数据库、真实 HTTP 和虚构账号；准备一个全新的测试服务器数据库，不能指向个人正式服务器。

在单独的 PowerShell 终端设置数据库并创建测试账号；密码输入测试文件中的 `fictional-sync-password-2026`：

```powershell
$env:KEYBOX_DATABASE_URL = 'sqlite:///./artifacts/live-fresh.db'
.venv/Scripts/python.exe -m keybox_backend.cli create-account sync-live-test
.venv/Scripts/python.exe -m uvicorn keybox_backend.app:app --host 127.0.0.1 --port 18765 --workers 1 --no-access-log
```

先在仓库根目录建立 `artifacts` 目录，每次选择新的数据库路径。另一个终端从仓库根目录执行：

```sh
cd mobile
flutter test --no-pub test/sync_live_test.dart --dart-define=KEYBOX_TEST_SERVER=http://127.0.0.1:18765 --reporter expanded
```

本地 HTTP 仅由测试代码显式开启，生产配置页面不能启用。测试结束后停止临时服务器。

## 验证状态

2026-10-09 已完成后端 43 项测试、客户端 18 项测试、真实 HTTP 双客户端联调 1 项、Android 模拟器集成 3 项及 Flutter 静态分析。模拟器检查包括真实解锁、加密保存、复制、删除、后台锁定、320dp 双倍字体、平台安全存储和备份恢复；保留上下边界滚动比例回归检查。TOTP 使用 [RFC 6238 附录 B](https://www.rfc-editor.org/info/rfc6238/) 的全部算法/时间测试向量。

尚未完成 Android 真机相机扫码、真机安全存储/后台行为/换机恢复、iOS 运行，以及 Linux Docker/Compose/Caddy HTTPS 实际运行验收。尚未部署阿里云，也未导入真实个人数据。完成这些上线检查后再导入真实条目。

开发分支为 `codex/keybox-backend`，每个功能阶段检查通过后采用 Conventional Commits 单独提交并推送。

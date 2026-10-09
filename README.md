# KeyBox

一个简洁清新的 Flutter 密码箱与动态验证码前端演示。当前提供 Android 演示版本，并保留 iOS 工程。

## 当前功能

- 演示解锁：输入任意非空内容即可进入，支持输入显隐。
- 密码箱：示例账号列表、搜索、详情、密码显隐、复制、新增、编辑和确认删除。
- 验证码：六位预设演示码、30 秒倒计时、搜索、复制、新增、编辑和确认删除。
- 设置：安全、云同步、备份、关于，以及可填写的同步配置演示表单。
- 薄荷绿 Material 3 主题、中文系统控件、小屏与大字体布局；切换标签保留搜索和滚动位置。

**这是静态前端演示，没有真实认证、加密、持久化或网络同步。请勿填写真实密码、OTP 密钥或同步令牌。**

条目只保存在内存中，应用进程重启后恢复示例数据。OTP 密钥字段不参与计算，页面每 30 秒轮换预设数字，不能用于实际登录。复制按钮会将当前示例文本写入系统剪贴板。同步表单关闭后丢弃填写内容，不访问服务器。

## 开发环境

本次开发使用 Flutter 3.41.9 stable、Dart 3.11.5。安装 Flutter、Android SDK 和对应的 JDK 后检查环境：

```sh
flutter doctor
flutter pub get
flutter devices
```

## 运行 Android 演示

连接启用 USB 调试的 Android 手机，或启动 Android 模拟器。将设备列表中的 ID 填入命令：

```sh
flutter run -d <device-id>
```

本机模拟器示例：

```sh
flutter emulators --launch Pixel_10_Pro
flutter run -d emulator-5554
```

进入解锁页后输入 `demo`，即可体验三个主页面。

## 检查与构建

```sh
flutter analyze
dart format --output=none --set-exit-if-changed lib integration_test
flutter build apk --debug
```

构建输出为 `build/app/outputs/flutter-apk/app-debug.apk`。可在手机上安装，或通过 ADB 安装到已连接设备：

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

这是使用调试签名的演示 APK，不是生产发布包。iOS 工程需要在 macOS/Xcode 环境中另外构建与验证。

已连接 Android 设备时，可以运行端到端验收：

```sh
flutter test integration_test/demo_flow_test.dart -d <device-id> --reporter expanded
```

验收覆盖空解锁校验、密码新增/编辑/复制/删除、标签搜索状态、验证码增删改与复制、同步配置校验与丢弃，以及 320dp 小屏和双倍字体布局。测试使用虚构数据，不连接服务器。

## 代码组织

```text
lib/
  main.dart             应用入口
  app.dart              解锁页、应用配置与底部导航
  ui.dart               主题和少量通用 UI 元素
  vault/                密码模型、列表、详情与共用表单
  otp/                  验证码模型、卡片与共用表单
  settings/             设置页与同步配置演示表单
```

采用页面内部的简单内存状态，不引入数据库、后端或复杂状态管理框架。

## 提交流程

开发分支为 `codex/keybox-ui`。每个功能完成并检查通过后单独提交、立即推送，采用 Conventional Commits，例如：

```text
feat(vault): 添加密码条目演示交互
fix(ui): 修复页面布局问题
docs: 添加前端演示运行说明
```

当前未接入的指纹、扫码、主密码管理、恢复密钥、导入导出和同步入口均提供明确提示，不模拟成功。

## 验证记录

2026-10-09，在 Pixel 10 Pro 模拟器（Android 17 / API 37）完成：

- `flutter analyze`：无问题。
- `flutter build apk --debug`：构建成功，并安装、启动普通演示 APK。
- Android 集成验收：2 项通过，覆盖完整编辑流程和 320dp 小屏、双倍字体布局。测试隔离文本输入法，剪贴板仍使用平台接口。
- 普通 APK：检查解锁页原生键盘布局，确认预设验证码实际轮换，并保存主要页面截图。

尚未进行 Android 真机和 iOS 运行验证。本地截图和临时验收工具位于 Git 忽略的 `artifacts/`，构建产物位于 Git 忽略的 `build/`。

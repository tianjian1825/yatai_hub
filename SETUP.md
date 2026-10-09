# 亚太HUB (Yatai HUB) Flutter 项目初始化指南

本文档提供详细的项目初始化步骤，适用于团队成员在不同电脑环境下快速启动开发。

> 本项目（`yatai_hub`，应用名「亚太HUB」）从 SZST新质OA（`flutter-suixinpai`）分离而来，聚焦兼职工作流 + 素材上传 + 任务群聊。

## 环境要求

### 必需软件

1. **Flutter SDK**
   - 推荐版本：`3.44.5 (stable)`（当前项目使用）
   - 最低版本：满足 `pubspec.yaml` 中 `sdk: ^3.12.0` 约束
   - 下载地址：https://flutter.dev/docs/get-started/install
   - 验证安装：`flutter --version`
   - 升级当前频道：`flutter upgrade`

2. **Dart SDK**
   - 推荐版本：3.12.0+（随 Flutter 3.44.5 一起安装）
   - 兼容范围：`^3.12.0`
   - 验证安装：`dart --version`

3. **Git**
   - 版本：2.0+
   - 下载地址：https://git-scm.com/downloads
   - 验证安装：`git --version`

4. **IDE（任选其一）**
   - Android Studio（推荐，包含 Android 开发工具）
   - VS Code + Flutter 扩展（轻量级）
   - IntelliJ IDEA（功能完整）

### 平台特定要求

#### Windows 开发

- **启用开发者模式**（支持符号链接）：
  ```powershell
  start ms-settings:developers
  ```
  或在 "设置 > 更新和安全 > 开发者选项" 中启用

#### Android 开发

- Android SDK（最低 API Level 24，推荐 API Level 36+）
- Android Studio 或 Android SDK Command-line Tools
- Java JDK 11+ (推荐 JDK 17)
- Gradle 7.0+ (随项目自动下载)
- 接受 Android licenses：`flutter doctor --android-licenses`

#### iOS 开发（仅限 macOS）

- Xcode 14.0+ (推荐 Xcode 15+)
- CocoaPods 1.12+
  ```bash
  sudo gem install cocoapods
  ```
- macOS 12.0+ (推荐 macOS 13+)
- iOS 开发证书和配置文件（用于真机测试）
- 已配置 Apple Developer 账号（用于真机部署）

**注意**：钉钉登录功能必须在真机上测试，模拟器不支持钉钉 SDK。

---

## 克隆项目

### 1. 克隆代码仓库

```bash
git clone https://git.meiwish.com:60077/szst/yatai-hub.git
cd yatai-hub
```

### 2. 验证 Flutter 环境

运行 Flutter Doctor 检查环境配置：

```bash
flutter doctor -v
```

**预期输出示例**：
```
[✓] Flutter (Channel stable, 3.41.9)
[✓] Android toolchain - develop for Android devices (Android SDK version 36.1.0)
[✓] Xcode - develop for iOS and macOS (仅 macOS，Xcode 26+)
[✓] Chrome - develop for the web
[✓] Android Studio
[✓] VS Code
[✓] Connected device
```

确保所有必需的组件都已正确安装（✓ 标记）。常见问题见文档末尾的"常见问题"部分。

**重要提示**：
- 如有 [!] 标记，按照提示信息进行修复
- Android licenses 未接受：运行 `flutter doctor --android-licenses`
- Xcode 配置问题：运行 `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`

---

## 安装依赖

### 1. 安装 Flutter 依赖包

```bash
flutter pub get
```

### 2. 平台特定依赖安装

#### iOS 平台（仅限 macOS）

```bash
cd ios
pod install
cd ..
```

> **注**：群聊 IM 的离线消息库依赖 `sqflite`（其 iOS 原生 pod `sqflite_darwin` 在此步自动安装）。拉取含新依赖（`sqflite` / `scrollable_positioned_list`）的分支后，务必先 `flutter pub get` 再 `pod install`，否则 iOS 构建会因缺少原生模块失败。

如果遇到 CocoaPods 问题，可尝试：

```bash
cd ios
rm -rf Pods Podfile.lock
pod deintegrate
pod install
cd ..
```

#### Android 平台

首次运行时会自动下载 Gradle 依赖，无需手动操作。

---

## 运行项目

### 1. 查看可用设备

```bash
flutter devices
```

### 2. 启动应用

#### 在所有可用设备上运行

```bash
flutter run
```

#### 在指定设备上运行

```bash
# Android 模拟器/设备
flutter run -d android

# iOS 模拟器（仅限 macOS）
flutter run -d iPhone

# Windows
flutter run -d windows

# Web
flutter run -d chrome
```

### 3. 热重载

应用运行时：
- 按 `r` 键：热重载（保留应用状态）
- 按 `R` 键：热重启（重置应用状态）
- 按 `q` 键：退出应用

---

## 构建应用

### Android

#### Debug APK（用于开发测试）
```bash
flutter build apk --debug
```

#### Release APK（用于生产环境）

**方式 1：通用 APK（兼容所有架构，体积较大 ~39MB）**
```bash
flutter build apk --release
```

**方式 2：分架构 APK（推荐，体积更小 ~20-23MB）**
```bash
flutter build apk --release --split-per-abi
```
会生成 3 个文件：
- `app-armeabi-v7a-release.apk` (32位 ARM，约 20.8MB)
- `app-arm64-v8a-release.apk` (64位 ARM，约 22.7MB)
- `app-x86_64-release.apk` (x86 模拟器)

**方式 3：App Bundle（推荐上传应用商店）**
```bash
flutter build appbundle --release
```

构建产物位置：`build/app/outputs/`

### iOS（仅限 macOS）

#### 构建 iOS 应用

```bash
# 构建 Release 版本
flutter build ios --release

# 或在 Xcode 中构建
open ios/Runner.xcworkspace
```

**步骤**：
1. 在 Xcode 中打开 `ios/Runner.xcworkspace`（不是 `.xcodeproj`）
2. 选择 Team 和 Signing Certificate
3. 选择目标设备或 Generic iOS Device
4. Product → Archive
5. 导出 IPA 文件

**重要配置**：
- 钉钉 SDK 集成：`ios/Runner/DingTalkAuthPlugin.swift`
- 灵动岛配置：需要配置 App Group (`group.com.amgroup.hub`)
- URL Scheme：用于钉钉登录回调

#### iOS 真机调试

```bash
# 查看已连接的 iOS 设备
flutter devices

# 在真机上运行
flutter run -d <device-id>
```

### Windows

```bash
flutter build windows --release
```

构建产物位置：`build/windows/runner/Release/`

### Web

```bash
flutter build web --release
```

构建产物位置：`build/web/`

---

## 项目结构说明

```
yatai-hub/
├── lib/                        # Dart 源代码
│   ├── main.dart              # 应用入口
│   ├── pages/                 # UI 页面
│   ├── models/                # 数据模型
│   ├── services/              # 业务逻辑和 API 服务
│   └── widgets/               # 可复用组件
├── assets/                     # 静态资源（图片等）
├── android/                    # Android 原生配置
├── ios/                        # iOS 原生配置
├── windows/                    # Windows 原生配置
├── linux/                      # Linux 原生配置
├── macos/                      # macOS 原生配置
├── web/                        # Web 配置
├── pubspec.yaml               # 依赖配置文件
├── CLAUDE.md                  # Claude Code 项目说明
└── SETUP.md                   # 本文档
```

---

## 代码提交规范

### 提交前检查

```bash
# 代码分析
flutter analyze

# 格式化代码
dart format .

# 运行测试
flutter test
```

### 提交流程

```bash
# 查看修改状态
git status

# 添加修改文件
git add .

# 提交（建议使用有意义的提交信息）
git commit -m "feat: 添加素材上传功能"

# 推送到远程
git push origin main
```

### 提交信息格式建议

- `feat: 新功能`
- `fix: 修复 bug`
- `docs: 文档更新`
- `style: 代码格式调整`
- `refactor: 代码重构`
- `test: 测试相关`
- `chore: 构建/工具链相关`

---

## 常见问题

### 1. Flutter Doctor 提示 Android licenses 未接受

```bash
flutter doctor --android-licenses
```

然后一路按 `y` 接受所有协议。

### 2. iOS pod install 失败

```bash
# 更新 CocoaPods 仓库
pod repo update

# 清理缓存重新安装
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install
cd ..
```

### 3. Flutter 版本不匹配

```bash
# 检查当前版本
flutter --version

# 更新到最新稳定版
flutter upgrade

# 切换到指定频道（stable/beta/dev）
flutter channel stable
flutter upgrade
```

### 4. 依赖冲突

```bash
# 清理缓存
flutter clean

# 重新获取依赖
flutter pub get
```

### 5. Windows 上符号链接错误

确保已启用开发者模式（见上文 "Windows 开发" 部分）。

### 6. Git CRLF 警告（Windows）

这是正常的，Git 会自动处理行尾符转换。可以忽略或配置：

```bash
git config --global core.autocrlf true
```

### 7. Android Gradle 下载慢

修改 `android/build.gradle.kts`，添加国内镜像源：

```kotlin
allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}
```

### 8. 无法访问公司内网 Git 仓库

确保：
- VPN 已连接（如需要）
- Git 凭据已正确配置
- SSH 密钥已添加到 GitLab（如使用 SSH）

**配置 Git 凭据**：
```bash
# 配置用户名和邮箱
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# 保存凭据（避免重复输入密码）
git config --global credential.helper store
```

### 9. 钉钉登录无法测试

**问题**：钉钉 SDK 不支持模拟器

**解决方案**：
- 必须在真机上测试（Android 或 iOS 真机）
- 确保真机已安装钉钉 App
- 使用 `flutter run -d <device-id>` 在真机上运行

### 10. iOS 灵动岛不显示

**可能原因**：
1. 设备不支持（需要 iPhone 14 Pro 及以上，iOS 16.2+）
2. App Group 未配置：需要在 Xcode 中配置 `group.com.amgroup.hub`
3. Widget Extension 未正确添加

**解决方案**：在 Xcode 中为 Runner 与 `UploadActivityWidget` 两个 target 配置相同 App Group `group.com.amgroup.hub`，并确认 Widget Extension 已正确添加。

---

## 开发环境配置建议

### VS Code 推荐扩展

- Flutter
- Dart
- Awesome Flutter Snippets
- Error Lens
- GitLens

### Android Studio 推荐插件

- Flutter
- Dart
- Rainbow Brackets
- Material Theme UI

### 调试工具

#### Flutter DevTools

```bash
flutter pub global activate devtools
flutter pub global run devtools
```

#### 查看应用日志

```bash
flutter logs
```

---

## 获取帮助

- **项目文档**：查看 `CLAUDE.md` 了解项目架构和开发规范
- **Flutter 官方文档**：https://flutter.dev/docs
- **常见问题**：https://flutter.dev/docs/resources/faq
- **团队沟通**：如有问题请联系项目负责人

---

## 快速开始总结

```bash
# 1. 验证环境
flutter doctor -v

# 2. 克隆项目
git clone https://git.meiwish.com:60077/szst/yatai-hub.git
cd yatai-hub

# 3. 安装依赖
flutter pub get

# 4. iOS 额外步骤（仅 macOS）
cd ios && pod install && cd ..

# 5. 查看可用设备
flutter devices

# 6. 运行项目
flutter run

# 7. 或在指定设备运行
flutter run -d android    # Android
flutter run -d iPhone     # iOS

# 完成！
```

## 重要提示

1. **首次运行**：首次运行会下载必要的依赖，可能需要 5-10 分钟
2. **网络要求**：需要稳定的网络连接以下载 Gradle、CocoaPods 等依赖
3. **真机测试**：钉钉登录功能必须在真机上测试，模拟器不支持
4. **iOS 开发**：需要 macOS 环境和 Apple Developer 账号
5. **代码规范**：提交前运行 `flutter analyze` 和 `dart format .`

## 下一步

- 查看 [README.md](./README.md) 了解项目功能和架构
- 查看 [CLAUDE.md](./CLAUDE.md) 了解详细的开发文档

祝开发顺利！ 🚀

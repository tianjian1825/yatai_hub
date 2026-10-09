# 亚太HUB (Yatai HUB)

面向兼职人员的协同平台，以 Android / iOS 移动端为主。本项目从 **SZST新质OA（`flutter-suixinpai`）** 分离而来，聚焦「兼职工作流 + 素材上传 + 任务群聊」，去除了原 OA 的客服 / 商务 / 客户档案 / 日程 / 考勤 / 随心拍素材库浏览等模块。

- 当前版本：`1.0.0+1`（常量维护在 `lib/app_info.dart`）
- Flutter SDK：`3.44.5 (stable)` ｜ Dart SDK：`^3.12.0`
- 应用名称：`亚太HUB`
- 包名：iOS `com.amgroup.hub` ｜ Android `com.amgroup.hub`

## 项目概述

`亚太HUB` 围绕兼职协同场景构建，当前代码覆盖以下能力：

- 兼职工作流：接单、任务资料录入、每日打卡、钱包结算与提现
- 跨角色任务群聊 IM（sqlite 离线库 + 双通道前台推送）
- 医疗素材上传（大文件分片上传到 NAS，支持系统「分享到本 App」）
- 登录 / 注册：账号密码、游客模式，注册支持护照 OCR 识别回填
- 用户中心、隐私政策、通知、缓存清理等应用级能力
- 原生集成：本地通知、iOS Live Activities（灵动岛）

## 核心业务能力

- 登录与访问控制
  账号密码登录、游客模式，以及基于 Bearer Token 的接口认证；注册页支持护照 OCR 拍照识别并回填，提交后等待管理员审核。
- 兼职模块
  兼职用户的独立工作流：接单（我已接单 / 接单列表）、任务详情、任务资料录入、每日打卡、钱包结算与提现。
- 任务群聊 IM
  跨角色任务群聊，含离线消息库、@提及、引用跳转、撤回、双通道前台推送与未读红点。
- 上传中心
  支持图片、视频、文档上传；大文件自动切换分片上传；支持系统分享入队；上传任务支持重试、持久化恢复和后台通知。
- 用户中心
  个人资料、账号管理、应用设置、关于页、我的作品与我的钱包入口。

## 技术栈

- Flutter + Dart
- Dio
- SharedPreferences
- `setState` + `StreamController`
- `image_picker` / `file_picker` / `video_player`
- `flutter_local_notifications` / `jpush_flutter`（极光推送）
- `sqflite` / `scrollable_positioned_list`（群聊离线库与消息定位）
- `live_activities`

## 目录结构

```text
lib/
├── main.dart                            # 启动入口、登录态校验、服务初始化
├── app_info.dart                        # 版本号常量（与 pubspec.yaml 手动同步）
├── pages/
│   ├── main_page.dart                   # 主容器，声明式动态底部导航
│   ├── login_page.dart                  # 登录（账号密码 / 游客）
│   ├── register_page.dart               # 注册（邮箱密码 + 护照 OCR + 资料上传）
│   ├── privacy_policy_page.dart         # 隐私政策
│   ├── material_upload_page.dart        # 素材上传主流程
│   ├── material_preview_page.dart       # 素材预览
│   ├── upload_manager_page.dart         # 上传管理
│   ├── user_center_page.dart            # 用户中心
│   ├── part_time/                       # 兼职域页面（任务/录入/打卡/钱包结算）
│   ├── chat/                            # 任务群聊 IM（会话列表 + 全屏群聊）
│   └── user_center/                     # 用户中心子页面（资料/账号/设置/关于/作品）
├── services/                            # 认证、接口、上传、缓存、通知、推送、兼职、群聊服务
├── models/                              # 用户、素材、上传、兼职、结算、群聊等数据模型
├── utils/                               # 通用工具
├── theme/                               # 全局主题与配色（app_theme.dart：AppColors / AppTheme）
└── widgets/                             # 通用组件与群聊组件（widgets/chat/）

assets/                                  # 底部导航、图标等资源
android/                                 # Android 原生配置、权限、极光推送、分享接收
ios/                                     # iOS 原生工程、Live Activity Widget
scripts/                                 # 项目脚本（regenerate_splash.sh 等）
docs/                                    # 文档目录
```

## 运行机制

### 启动流程

应用启动时按顺序执行以下初始化逻辑：

1. 初始化 `UploadQueueManager`，恢复持久化上传任务并启动网络监听。
2. 异步触发缓存自动清理，不阻塞首屏。
3. 检查是否需要展示隐私政策。
4. 检查本地登录态，并在已登录时验证 Token 可用性、初始化用户信息、预加载部门列表。
5. 启动群聊前台编排器、系统分享接收器、推送跳转路由。

### 主导航

- 底栏为声明式动态 Tab：`兼职`、`消息`（仅当有群聊时显示）、`上传`、`我的`，索引统一由 `_MainTab` 列表重算。
- `兼职` 为主入口，含两个子 Tab：我已接单 / 接单列表。
- `消息` Tab 显隐由群聊会话与未读广播驱动。

### 上传系统

- 小文件走 `NasUploadService`
- 大于等于 `30MB` 的文件走 `NasChunkedUploadService`
- 默认分片大小为 `15MB`（服务端可通过 init 覆盖）
- 上传队列默认最大并发数为 `3`，单任务默认最大重试次数为 `3`
- 上传任务会持久化到本地，应用重启后可恢复未完成任务
- 支持系统「分享到本 App」直接入队；Android 侧显示本地通知进度，iOS 侧优先使用 Live Activities 展示上传状态

## 开发环境

- Flutter SDK：`3.44.5 (stable)`（可通过 `flutter upgrade` 升级到同 channel 的最新稳定版）
- Dart SDK：兼容 `^3.12.0`
- Android Studio / Xcode（详细要求见 [SETUP.md](./SETUP.md)）
- CocoaPods（iOS）
- 真机测试环境（推送、Live Activities / 灵动岛等能力建议在真机上验证）

## 快速开始

```bash
git clone https://git.meiwish.com:60077/szst/yatai-hub.git
cd yatai-hub

flutter pub get

# iOS 首次运行或原生依赖变更后执行
cd ios && pod install && cd ..

# 查看设备并运行
flutter devices
flutter run -d <deviceId>
```

## 常用开发命令

```bash
flutter pub get
flutter analyze
dart format .
flutter test

flutter build apk --release --split-per-abi
flutter build appbundle --release
flutter build ios --release

dart run flutter_launcher_icons
bash scripts/regenerate_splash.sh
```

## 平台集成说明

### Android

- 已声明网络、媒体读取、通知、前台服务、唤醒锁等权限
- `applicationId = com.amgroup.hub`（kotlin 包 `com/amgroup/hub`）
- 系统分享接收：`com/amgroup/hub/ShareReceiverActivity.kt`
- 极光推送原生服务：`com/amgroup/hub/JPushService.kt`，Application 类 `SuixinPaiApplication.kt`

### iOS

- Bundle ID：`com.amgroup.hub`，显示名 `亚太HUB`
- 已声明相册、相机、麦克风等权限文案，启用 `NSSupportsLiveActivities`
- 包含 `ios/UploadActivityWidget/` 用于上传进度 Live Activity / 灵动岛展示
- 使用前需在 Xcode 中正确配置 App Group：`group.com.amgroup.hub`

### 启动图生成

- 应用启动图生成脚本 `scripts/regenerate_splash.sh`

## 关键服务与数据点

### 核心服务

- `AuthService` — 管理 Access Token 与本地登录态。
- `UserService` / `UserRegisterInfoService` — 用户信息、角色标记 / 注册资料提交与修改重交。
- `UploadQueueManager` — 管理任务队列、网络状态、持久化恢复、通知与 Live Activity。
- `ShareIntentService` — 接收系统「分享到本 App」的文件并入上传队列。
- `PartTimeTaskService` / `ParttimeClockService` / `SettlementService` — 兼职任务 / 打卡 / 结算接口。
- `ParttimeChatService` / `ChatLocalDb` / `ChatMessageRepository` — 任务群聊网络接口、前台推送编排、sqlite 离线库与先本地后网络编排。
- `JPushService` / `PushRouterService` — 极光推送初始化（登录后才 init）与推送点击跳转路由。

### 常用本地存储键

| Key | 说明 |
| --- | --- |
| `user_access_token` / `user_sign` | Access Token，兼容旧字段 |
| `is_logged_in` | 本地登录标记 |
| `is_guest_mode` | 游客模式标记 |
| `show_chat_tab` | 「消息」Tab 是否显示 |
| `upload_task_{taskId}` | 持久化上传任务 |
| `route_auto_detect_enabled` | 是否启用自动线路检测 |

## 验证与测试

当前仓库还没有完善的根目录 `test/` 体系，验证主要依赖静态检查和手动回归：

- 最低建议：`dart format .` + `flutter analyze`
- 修改上传、认证、通知、兼职、群聊流程时，建议走一遍真实页面链路
- iOS 相关改动需要额外验证：本地通知权限、Live Activities / 灵动岛展示

## 常见问题

### 登录或注册异常

- 账号密码登录失败时，先确认接口环境 `ApiConfig.baseUrl`（默认生产）是否正确
- 注册需填写邮箱 + 密码 + 护照信息，护照 OCR 识别失败不阻断提交，可手动填写
- 注册提交后需等待管理员审核，审核态在 `PartTimePendingPage` 展示

### 推送收不到或不跳转

- `JPushService` 仅在登录态确认后才 `initialize()`，隐私同意期不启动
- 冷启动跳转依赖 `PushRouterService`，可确认 `action` 与 extras 是否正确

### 上传任务中断或失败

- 大文件会自动改走分片上传
- 网络抖动时任务会按队列策略自动重试
- 应用进入后台或重启后，未完成任务会尝试从本地恢复

### iOS 构建或灵动岛异常

- 原生依赖变更后重新执行 `pod install`
- 检查 App Group 是否已正确配置为 `group.com.amgroup.hub`
- 确认设备与系统版本支持 Live Activities

## 相关文档

- [SETUP.md](./SETUP.md)
- [CLAUDE.md](./CLAUDE.md)
- [PARTTIME_CHAT_API.md](./PARTTIME_CHAT_API.md) — 任务群聊接口契约
- [PUSH_NOTIFICATION_CONFIG.md](./PUSH_NOTIFICATION_CONFIG.md) — 推送配置

## 安全说明

- 请勿提交真实账号、Token、签名文件或环境密钥
- 涉及 `lib/services/api_client.dart`、认证、原生配置的改动需要重点复核
- 项目包含私有业务接口，导出日志和截图时注意脱敏

---

私有项目，仅供内部使用。分离自 `flutter-suixinpai`。

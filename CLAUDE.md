# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**亚太HUB (Yatai HUB / `yatai_hub`)** — 面向兼职人员的协同平台。本项目从 **SZST新质OA（`flutter-suixinpai`）** 分离而来，只保留并聚焦「兼职工作流 + 素材上传 + 任务群聊」链路，去除了原 OA 的客服 / 商务 / 客户档案 / 日程 / 考勤 / 随心拍素材库浏览等模块。

**版本**: 1.0.0+1（版本号常量维护在 `lib/app_info.dart`，需与 `pubspec.yaml` 手动同步） | **Flutter**: 3.44.5 (stable) | **Dart SDK**: ^3.12.0

> 本项目从 uni-app → Flutter（`flutter-suixinpai`）迁移后再分离。原全量 OA 项目位于 `/Users/sakuraovo/Desktop/project/flutter-suixinpai`，可参考其 API 契约与业务逻辑。

## Development Commands

```bash
flutter pub get                          # 安装依赖
cd ios && pod install && cd ..           # iOS CocoaPods（仅 macOS）
flutter run                              # 调试模式运行
flutter run -d <device_id>              # 指定设备运行
flutter build apk --release --split-per-abi  # Android 分架构构建（推荐）
flutter build ios --release              # iOS 构建
flutter analyze                          # 静态分析
dart format .                            # 代码格式化
flutter test                             # 运行测试
flutter clean && flutter pub get         # 清理重建
dart run flutter_launcher_icons          # 重新生成应用图标
bash scripts/regenerate_splash.sh        # 重新生成启动图
```

## Architecture

### 三层结构: pages/ → services/ → models/

- **pages/**: UI 页面，使用 `setState` 管理本地状态
- **services/**: 业务逻辑层，关键服务使用**单例模式**（通过 factory 构造函数访问）
- **models/**: 数据模型，均带 `fromJson` 工厂方法
- **widgets/**: 可复用组件（`bottom_tabbar`、`empty_state_widget`、`image_preview_page`、`passport_capture_guide`、`privacy_policy_dialog`、`widgets/chat/`）
- **utils/**: 通用工具（`map_launcher` 地图导航、`overlay_toast` 浮层提示——弹窗内提示必须用它，SnackBar 会被 bottomSheet 挡住）
- **theme/**: 全局主题与配色（`app_theme.dart`，详见下面「主题与配色」）

### 主题与配色（`lib/theme/app_theme.dart`）

`AppColors` 集中配色常量、`AppTheme.light` 是全局主题，`main.dart` 用 `theme: AppTheme.light`。取色用 `AppColors.*`，不要新写本地 `const`。

| 常量 | 值 | 用途 |
|---|---|---|
| `AppColors.primary` | `#709BF7` | 日期选择器、加载指示器等 Material 自带控件的强调色 |
| `AppColors.primaryDark` | `#366CDF` | AppBar 背景 / 品牌主色 |

**两个踩过的坑：**

- `ColorScheme.fromSeed(seedColor: X)` 的 M3 tonalSpot 算法会把种子色的色度压到 chroma 36 并取 tone 40 —— `#366CDF` 实测被算成 **`#495D92`**（发灰的蓝）。所以 `fromSeed` 之后**必须** `.copyWith(primary: X, onPrimary: Colors.white)`，否则日期选择器选中圈、`CircularProgressIndicator`、输入框聚焦线、Switch/Checkbox 全是灰蓝。M3 日期选择器的底色另取 `surfaceContainerHigh`（`#E8E7EF` 灰白），靠 `datePickerTheme.backgroundColor: Colors.white` 压成纯白。
- `showDatePicker` / `showModalBottomSheet` 的 builder context 来自 Navigator，**不继承调用点所在页面的 Theme**，需要非默认主题时显式传 `AppTheme.pickerBuilder`。

`app_theme.dart` 与姊妹项目 `../flutter-suixinpai` **字节级同源**（文件内无项目内 import），改一端后直接 `cp` 到另一端。文件里的 `AppTheme.pink` / `AppColors.pink` 是那边商务与会议纪要模块用的，本仓无对应模块、暂无调用者，刻意保留以维持同源，**不要当死代码删掉**。

### 主导航（MainPage — 声明式动态 Tab）

MainPage 用声明式 `enum _MainTab { partTime, chat, upload, my }` 计算可见 Tab，切换一律走 `indexOf`（不硬编码索引）。共 4 个底栏 Tab（消息 Tab 动态显隐）：

- **兼职** (`part_time/part_time_page.dart`) — 主入口，两个子 Tab：我已接单 / 接单列表
- **消息**（动态）(`chat/chat_conversations_page.dart`) — 会话列表（任务群/科室群/私聊混排）。**非兼职账号常显**（他们要用通讯录发起私聊），兼职仅在有会话时显示（缓存键 `show_chat_tab` 只记「上次是否有会话」），详见「群聊 IM 模块」
- **上传** (`material_upload_page.dart`) — 素材上传核心流程
- **我的** (`user_center_page.dart`) — 用户中心

消息 Tab 显隐由 `ParttimeChatService` 的 `onConversationsChanged`/`onUnreadChanged`/`onTaskRead` 广播驱动，`_setShowChatTab` 会把 `_currentIndex` 重映射到原 Tab 避免错位。

### 兼职模块（`pages/part_time/`，核心业务）

兼职用户登录后进入独立工作流，主入口 `part_time_page.dart`（我已接单 / 接单列表）：

- **任务**: `part_time_task_detail_page`（任务详情）、`part_time_pending_page`（待处理 / 注册审核态：审核中、驳回原因 + 重新提交）
- **资料录入**: `part_time_task_data_entry_page` — 为任务录入客户/订单资料（order_draft 含 birth_time/passport_number，随心拍带 parttime_task_id，多客人用 main_client_id）
- **打卡**: 每日打卡，`parttime_clock_out_sheet`（结束兼职）。打卡 submit 兼作编辑（按 work_date 命中则重置为待审核）；被驳回（`can_edit=true`）进入「修改重交」态，预填原记录并展示驳回原因
- **群聊入口**: 「我已接单」卡片、任务详情页入口均 push `ChatPage`；列表未读计数取 `unread_comment_count`
- **我的兼职**: `my_parttime_tab`（用户中心 Tab）+ `parttime_record_detail_page`（打卡记录详情）
- **钱包/结算**: `wallet_page`（钱包总览 + 收入流水 + 提现/月结底栏）→ `settlement_history_page`（结算/提现历史）→ `settlement_detail_page`（结算单明细）。无打工证（`can_withdraw=1`）App 手动提现，有打工证走后台月结

相关服务: `part_time_task_service`, `parttime_clock_service`, `settlement_service`, `order_entry_meta_service`（群聊见下）

### 群聊 IM 模块（`pages/chat/`、`widgets/chat/`）

任务「留言板」升级为**群聊会话**（接口契约见 `PARTTIME_CHAT_API.md`）。群成员含发起人/执行人(兼职)/责任客服/管理员，**跨角色**——非兼职用户也能收推送、看「消息」Tab、进群聊。

**三种会话（`conv_type`）**：`1`=任务群（`task_id`=任务 ID，不传即此）、`2`=科室群（`task_id`=**科室 ID**）、`3`=私聊（`task_id`=**私聊会话 ID**，由 `chat/private/open` 返回）。兼职上下班打卡会往其科室群播报系统消息。三种 ID 来自不同表**会撞号**，所以凡是把会话当唯一键的地方（sqlite 主键、活跃会话集合、已读/未读广播）都必须用 `models/chat_target.dart` 的 `ChatTarget`（conv_type + task_id）而非裸 taskId；`isTask` 是精确 `==1`，**不能用「非科室群」判定**否则私聊会被当任务群。科室群差异：无任务上下文（菜单只留「群成员」）、`can_manage=false` 不可增删成员、入口只有「消息」Tab 与推送。

**私聊（`conv_type=3`）**：收发/已读/撤回/会话列表/未读汇总/推送全部复用群聊接口，另有两个专属入口 `GET /v1/parttime_task/contacts`（通讯录）与 `POST /v1/parttime_task/chat/private/open`（get-or-create，不发消息），通讯录**仅 `roleid ≠ 275` 可访问**（只列兼职）。`private/open` 原先也限「仅非兼职可发起、对方必须是兼职」，**后端正在放开该限制**——所以群聊用户名片的「发消息」按钮**不按角色显隐**（谁都能点，发不出去由后端 msg 提示），前端不要再加角色判断。私聊页**没有右上角三点菜单、没有 @**（`mention_*` 恒空），成员管理三接口对 3 一律被后端拒绝。

- **页面**: `chat_page.dart`（全屏会话，三类共用，`convType` 默认 1：reverse 列表、引用 + 点击跳转定位、撤回、@提及、系统灰条 `msg_type=2`、新消息分隔线 `last_read_id`、乐观发送；`isPrivate` 时裁掉菜单与 @）、`chat_conversations_page.dart`（「消息」Tab 会话列表，三类混排，科室群青色图标 + 「科室」标签，私聊显示对方圆形头像且不拼成员数；右上角通讯录入口仅非兼职可见；滚动分页 + 本地搜索，见下「分页（会话列表）」「会话搜索只能本地」）、`chat_contacts_page.dart`（通讯录：本地秒显 + 网络对齐、搜索去抖走接口、滚动分页；整行点击进私聊——`conv_id>0` 直接进、跳过 open；`mobile` 非空时行右侧给拨号按钮，`tel:` 调系统拨号盘，Android 需 manifest `<queries>` 声明 DIAL+tel、iOS 需 `LSApplicationQueriesSchemes` 加 `tel`）
- **组件**: `widgets/chat/`（`chat_message_bubble`——**点**他人头像弹用户名片 / **长按**快捷 @、`chat_user_card_sheet`——用户名片（头像+姓名+兼职标签，手机号可复制/拨号，底部「发消息」按钮；手机号与已有 `conv_id` 取自本地通讯录缓存，缺失时按姓名兜底打一次 contacts 接口且**不落库**；私聊页内不给按钮）、`chat_members_sheet`——点行（自己那行除外）也弹名片，选了私聊则连成员弹窗一起 pop 并把 intent 交回 `chat_page` 跳转、`chat_staff_picker_sheet`、`mention_picker_sheet`、`chat_member_avatar`——头像空/失败回退首字，通讯录与私聊会话行共用、`hospital_info_sheet`、`client_profile_sheet`、`query_sheet_widgets`）；拨号统一走 `utils/phone_dialer.dart`（通讯录行与名片共用）
- **服务/存储**: `ParttimeChatService`（网络接口 + 前台推送编排；三个广播 `onTaskRead`/`onForegroundNewMessage`/`onUnreadChanged` 都携带 `ChatTarget`，`onConversationsChanged` 无参；`getContacts`/`openPrivateChat` 为私聊专属）、`ChatLocalDb`（sqlite 离线库，v5 共 7 表：`chat_message`/`chat_conversation`/`chat_sync_meta`——后两张主键为 `conv_type+task_id`，`chat_message` 加 `conv_type` 列且查询必带；+ 查询缓存 `chat_task_context`/`chat_hospital_cache`/`chat_client_cache`；+ 通讯录 `chat_contact`）、`ChatMessageRepository`（消息先本地后网络，全部方法以 `ChatTarget` 定位；通讯录 `localContacts`/`fetchContacts`）、`ChatContextService`（群内查询的数据编排）；模型 `models/chat_message.dart`、`models/chat_target.dart`、`models/chat_query.dart`、`models/chat_contact.dart`
- **库迁移**: v2→v3 只给 `chat_message` 加列（`message_id` 后端全局唯一，历史消息保留），`chat_conversation`/`chat_sync_meta` 因主键要变直接重建（纯缓存，网络会补齐）；v3→v4 建 `chat_contact` + 给 `chat_conversation` 加 `peer_user_id`/`avatar` 两列（纯 ALTER，主键不变，会话缓存全保留）；v4→v5 给 `chat_contact` 加 `mobile` 列
- **通讯录本地缓存**: 只有「无关键词第 1 页」拉取成功才 `replaceContacts` 整表替换——搜索结果/后续分页是残缺子集，写进去会让离线看到的人少一截。`private/open` 成功后 `cacheContactConvId` 写回 `conv_id`，下次点该人不再打 open
- **群内查询**（AppBar 三点菜单）: 进群聊时拉一次 `/v1/parttime_task/detail` 得 `client_id`/`hospital_id` 落 `chat_task_context`，据此决定两个入口显隐——
  - **医院信息查询** → `/v1/kr_hospital/detail`，**只解析 basic_info** 里的韩文名/英文名/别名/中文地址/韩文地址/合作状态（返点财务、CRM 账密、收款码、联系人电话等节点不解析不落地）；逐行可复制、地址点击调 `utils/map_launcher.dart` 导航
  - **客户资料查询** → 聚合 `/v1/kefu/client/detail`（`kf_name`=客服、`edit_user_name`=编辑、`register_time` 已格式化）+ `/v1/kefu/order/list` + `/v1/archives/list` + `/v1/appoint/list` + `/v1/schedule/paylist`（client_id + archives_id=0，成交/消费），分五张卡片，只读无操作按钮、**不展示任何联系方式**
  - 本项目虽已剥离客服模块，但这两个弹窗**只用 `ApiClient` 直接打接口 + 自解析原始 JSON**（`models/chat_query.dart`），不依赖任何客服/商务 service，与 `flutter-suixinpai` 保持同一份代码，双端同步改动
  - 字段口径以客服系统前端 `../kf_service`（`src/pages/CustomerDetailPage.tsx`、`src/api/`）为准
- **分页（消息）**: 首屏/历史用 `before_id`（`has_more_old`）、增量拉新用 `after_id`（`newest_id` 续拉）、引用跳转用 `around_id`（`scrollable_positioned_list` 滚到任意 index）；本地秒显 + 网络对齐
- **分页（会话列表）**: `conversations` 只收 `page`/`page_size`（≤50），后端把三类会话全量组装排序后 `array_slice`，`total` 是会话总数。前端每页 20、滚到底 `_loadMore`，按 `(conv_type,task_id)` 去重合并（翻页期间来新消息会让后端顺序变动，同一条可能出现在两页）。刷新分两种语义：下拉 / Tab 双击 `reset:true` 回第 1 页，推送广播与从会话页返回只更新已有行并补新会话、**不截断**已加载的后续页。**排序前端也要排**（`_compareConv`）：科室群整体置顶 → `last_message_time` DESC → `last_message_id` DESC，与后端 `usort` 及本地库 `allConversations` 的 `orderBy` 三处必须同口径，否则秒显那屏会在网络返回后整体跳一次
- **会话摘要本地自维护（防返回闪动）**: 群聊页收发消息/撤回后，`ChatMessageRepository.touchConversationSummary` 同时做两件事——UPDATE sqlite `chat_conversation` 那一行的 `last_message*`（**只 UPDATE 不 INSERT**，缺 title/member_count，插半行会冒出无标题 0 人的行）、广播 `onConversationSummaryUpdated`（补丁 `ChatConvSummary`，**不是整行**，列表页 `copyWith` 只改摘要字段）。少了这一步，返回列表会先亮进群前的旧摘要与旧排序、等网络回来再跳一下。列表页另在 `_syncAfterChat` 里读本地库 `_patchExisting`（只覆盖已加载的行，不追加，否则分页状态被本地全量冲掉）兜底列表被重建的情况；网络 `_refresh` 照旧跑，只是值一致所以看不出变化。`lastMessageId <= 新值` 是防乱序覆盖（撤回旧消息 / 慢到的增量）
- **摘要文案必须与后端逐字一致**: `ChatMessage.conversationPreview` 复刻后端 `_conv_preview`/`_message_summary`（`parttime_task.php:3382`/`:2621`）：撤回 → `[消息已撤回]`、系统消息 → 原文、无字无图 → 空串，否则空白压成单空格 + trim、超 **80 字**（PHP `mb_strlen` 口径，故 Dart 用 `runes` 而非 `String.length`）截断加 `...`、有附件按类型追加 `[N张图片]` / `[N个视频]`（都有则图片在前、空格分隔，与后端 `_count_media_kinds` 同构：总量以 `images` 为准，类型优先取 `media[i].type`，对不齐时按 URL 后缀猜），仍为空则 `[新消息]`。**视频也存在 `images` 里，一律说成「张图片」是错的**；引用条同理走 `quote.image_type`（旧数据为空串时按原件后缀兜底，不能拿缩略图判断——视频缩略图是截帧 jpg）。文案不一致的话本地先行更新的那行会在网络刷新时闪一下文字
- **会话搜索只能本地**: 接口无 keyword 参数。搜索源是 `_localAll`（sqlite 全量 + 网络已见行的并集，网络值覆盖本地旧值），**不是**当前分页出来的 `_list` —— 否则第 2 页之后的会话搜不到。搜索态不参与分页，`onTaskRead` 清未读要两份一起清
- **前台推送**: 后端双通道（通知 + 透传）。`ParttimeChatService().startForegroundCoordinator()` 在 `main.dart` 启动，订阅 `onMessage`（透传，前台实时刷新当前会话）+ `onNotification`（在该会话页时清通知栏不跳转），均按 `message_id` 去重
- **已读/红点**: `onTaskRead` 广播清零「我已接单」列表红点（**只认任务群** `target.isTask`，科室群/私聊已读不清任务红点）；退登 `ChatLocalDb().clearAll()` 防跨账号串数据
- **底栏「消息」Tab 红点**: 走 `GET /v1/parttime_task/chat/unread_count`（`task_id=0` 汇总，后端反查全部任务群/科室群/私聊，**不受分页影响**）。**不要退回按 conversations 第 1 页 `any(unread>0)` 判**——未读会话排在 20 名之外就漏了。Tab 显隐另取 `conversations` 的 `total`（`page_size=1` 省传输），两个请求在 `_checkChatTab` 里并发发出。`getAllUnread` 返回 `Map<ChatTarget,int>`：`tasks` 每项都带 `conv_type`，用裸 `taskId` 作键会让三类会话撞号互相覆盖
- **发送幂等**: 每条带 `client_msg_id`，弱网重发后端去重返回 `duplicated=true`
- 依赖: `sqflite`、`scrollable_positioned_list`（iOS 需 `pod install`）

### 用户中心（`pages/user_center/`）

- `user_profile_page`（个人资料）、`account_management_page`（账号管理）、`app_settings_page`（应用设置）、`about_page`（关于）、`my_works_tab`（我的作品）
- 钱包入口在「我的」页（兼职显示「我的钱包」）

### 上传系统架构（NAS 存储）

```
用户选择文件 / 系统分享进来 → MaterialUploadPage → UploadQueueManager (单例, max 3 并发)
    ├─→ < 30MB: NasUploadService (直传)
    └─→ ≥ 30MB: NasChunkedUploadService (15MB 分片)
         → 后端 NAS 存储
         → 成功后: MaterialApi.submitMaterial()
```

**关键参数**（`NasChunkedUploadService` / `UploadQueueManager`）：
- NAS 上传接口: `/v1/nas_upload/upload_image`
- 分片阈值: 30MB（`minChunkFileSize`）
- 分片大小: 15MB（`chunkSize`，服务端可通过 init 返回 `chunk_size` 覆盖）
- 并发上传: 3（`maxConcurrentUploads`）
- 最大重试: 3 次

**任务生命周期**: `queued → uploading → completed/failed`
- Stream 进度更新: `UploadQueueManager.taskUpdatesStream`
- 任务持久化: `TaskPersistenceRepository`（SharedPreferences）
- App 后台时自动保存，前台恢复

**系统分享入口**: `ShareIntentService` 处理「分享到本 App」的图片/视频/文件——已登录（非游客）直接入上传队列并切到「上传」Tab；未登录/游客静默忽略。设计仿 `PushRouterService`（`start` 始终订阅热接收流并取一次冷启动数据）。Android 侧对应 `ShareReceiverActivity.kt`。

### API 与认证

**Base URL**: `http://10.29.91.46:8000/`（测试） / `https://oa.aimei.group`（生产，当前默认）
配置位于 `ApiConfig` 类（`api_client.dart`），切换环境修改 `baseUrl` getter（默认 `baseUrlProd`）。

> ⚠️ 调试时把 `baseUrl` 改回 `baseUrlTest` 不要提交。仓库带 `.githooks/pre-commit` 拦截该误提交，需启用：`git config core.hooksPath .githooks`。

**认证方式**: Bearer Token（Authorization header）
- Token 存储: SharedPreferences key `user_access_token`（兼容旧 `user_sign` 键）
- `ApiClient` 拦截器自动添加 `Authorization: Bearer {token}` header，并带 `frontend: 'frontend'` header
- 401 错误触发重新登录（`_isHandlingAuthExpired` 防止重复跳转）

**登录/注册方式**（`login_page.dart` / `register_page.dart`）：
1. 账号密码登录（主要）: 邮箱/账号 + 密码（≥6 位）
2. 注册: `RegisterPage` → POST `/v1/register`，填邮箱 + 密码 + 护照信息；支持**护照 OCR** 拍照/相册识别并回填姓名/性别/出生日期（识别失败不阻断）；提交后等待管理员审核。手机号校验兼容海外号码（6-20 位）
3. 游客模式: 账号密码表单内输入预置游客账号进入

### App 初始化流程（main.dart）

1. `UploadQueueManager().initialize()` — 初始化上传队列和网络服务
2. `CacheService().autoCleanupIfNeeded()` — 非阻塞缓存清理
3. 检查隐私政策 → 检查登录状态
4. 如已登录: 验证 token → 初始化 UserService → 预加载部门列表
5. `ParttimeChatService().startForegroundCoordinator()` + `ShareIntentService().start()` + `PushRouterService().start()`
6. 进入 MainPage 或 LoginPage

### App 生命周期管理

`YataiHubApp` 实现 `WidgetsBindingObserver`：
- **前台(resumed)**: 取消通知，恢复上传队列
- **后台(paused/inactive)**: 保存任务，启用通知
- **关闭(detached)**: 保存任务

### 核心单例服务

通过 factory 构造函数获取共享实例（如 `UploadQueueManager()`、`AuthService()`）：

| 服务 | 职责 |
|------|------|
| `ApiClient` | Dio HTTP 客户端，Bearer Token 认证，请求/响应拦截器 |
| `AuthService` | 登录状态管理，Access Token 存储（兼容旧 sign 键） |
| `GuestModeService` | 游客模式管理 |
| `UserService` | 用户信息管理（含角色判断、兼职账号停用状态） |
| `UserRegisterInfoService` | 注册资料提交 / 修改重交 |
| `UploadQueueManager` | 上传队列管理，最多 3 并发，自动重试 3 次，Stream 进度更新 |
| `NasUploadService` / `NasChunkedUploadService` | NAS 直传 / 分片上传 |
| `UploadNotificationService` | 本地通知 + iOS Live Activity（灵动岛），App Group `group.com.amgroup.hub` |
| `TaskPersistenceRepository` | 上传任务持久化（SharedPreferences） |
| `MaterialApi` / `OssApi` / `ScheduleApi` | 素材提交 / OSS / 排期相关接口 |
| `ShareIntentService` | 系统「分享到本 App」接收，入上传队列 |
| `DepartmentService` | 部门数据管理（带缓存和预加载） |
| `EventBusService` | 全局事件总线（素材上传完成、线路变更等事件） |
| `RouteSettingsService` | 浏览/上传线路（固定海外，无设置页与 IP 自动检测） |
| `NetworkService` | 网络连接监控，Stream 通知 |
| `CacheService` / `ListCacheService` | 全局缓存清理 / 列表分页缓存 |
| `PrivacyPolicyService` | 隐私政策版本与同意状态 |
| `JPushService` | 极光推送 SDK（含 FCM/APNs 厂商通道），高优先级通知渠道 `im_message`（群聊消息）。**登录后才 initialize**，隐私同意期不启动 |
| `PushRouterService` | 推送点击跳转路由，解析 `action`/extras 跳转；缓存冷启动未消费动作（`consumePending`） |
| `PartTimeTaskService` / `ParttimeClockService` / `SettlementService` | 兼职任务 / 打卡 / 结算接口 |
| `ParttimeChatService` / `ChatLocalDb` / `ChatMessageRepository` | 群聊网络接口+前台推送编排 / sqlite 离线库 / 先本地后网络编排 |
| `ChatContextService` | 群聊内医院信息 / 客户资料查询的数据编排（任务上下文 + 快照缓存） |

### 推送与跳转路由（JPush）

- `JPushService` 延迟初始化：`main.dart` 在隐私同意期**不** init，等登录态确认后才 `initialize()`。原生推送 MethodChannel 为 `com.suixinpai.push`（沿用旧命名）。
- `PushRouterService().start()` 在启动期始终订阅，登录后立即接管跳转。
- 跳转协议（`action` + extras）：
  - `open_part_time_hall` → 兼职 Tab → 子 Tab「接单列表」
  - `open_part_time_task` + `task_id` → push `PartTimeTaskDetailPage`
  - `open_part_time_clock` + `clock_id` → push `ParttimeRecordDetailPage`
  - `open_part_time_settlement` + `settle_id` → push `SettlementDetailPage`
  - `open_part_time_register` → `PartTimePendingPage`（审核中 / 驳回重交）
  - `open_part_time_comment` + `task_id`(+`message_id`、`conv_type`、`title`) → push `ChatPage` 并定位 message_id；`conv_type=2` 时 task_id 是科室 ID，进科室群（兼职打卡播报走这条）；`conv_type=3` 时 task_id 是私聊会话 ID，`title` 为发送者姓名
- 校验：登录态 + 非游客；`open_part_time_comment` / `open_part_time_register` 跨角色仅校验登录态 + 非游客。
- 群聊新消息**双通道**：通知走 PushRouter；透传 + 前台走 `ParttimeChatService` 前台编排器，二者不重叠。
- 冷启动 extras 可能早于 `MainPage` 挂载到达，`_pending` 缓存最后一次未消费动作，由 `consumePending` 触发。

### SharedPreferences 键约定

- `user_access_token` / `user_sign`（兼容）: 认证 token
- `is_logged_in`: 登录标记
- `is_guest_mode`: 游客模式标记
- `show_chat_tab`: 「消息」Tab 是否显示（缓存上次状态）
- `upload_task_{taskId}`: 持久化上传任务 JSON
- `route_auto_detect_enabled`: IP 自动检测标志

### 平台特定注意事项

**标识**：应用名 `亚太HUB`；iOS Bundle ID `com.amgroup.hub`，App Group `group.com.amgroup.hub`；Android `applicationId = com.amgroup.hub`（kotlin 包 `com/amgroup/hub`）。

**iOS**: Live Activities 支持灵动岛显示上传进度（iOS 16.2+），Widget 工程 `ios/UploadActivityWidget/`。灵动岛相关能力需物理设备测试。

**Android**: 权限在 `AndroidManifest.xml`。系统分享接收 `com/amgroup/hub/ShareReceiverActivity.kt`，极光 `com/amgroup/hub/JPushService.kt`，Application 类 `SuixinPaiApplication.kt`。

**Windows**: 需启用开发者模式 `start ms-settings:developers`。

### 添加新 API 端点

在 `lib/services/` 中对应的 API 服务文件添加方法，使用 `ApiClient()` 单例：

```dart
static Future<List<MyModel>> getData(String param) async {
  try {
    final response = await ApiClient().dio.get('/v1/path',
      queryParameters: {'param': param});
    if (response.data['code'] == 0) {
      return (response.data['data'] as List)
          .map((item) => MyModel.fromJson(item)).toList();
    }
    return [];
  } catch (e) {
    if (kDebugMode) print('Error: $e');
    return [];
  }
}
```

### 跨页面通信

使用 `EventBusService`（单例）的 broadcast Stream（如 `onMaterialUploaded`、`onRouteChanged`），UI 通过 `StreamBuilder` 或 `stream.listen()` 订阅。

### Git 仓库

`https://git.meiwish.com:60077/szst/yatai-hub.git`，主分支: `main`。
（分离自 `https://git.meiwish.com:60077/fangjiebao/flutter-suixinpai`。）

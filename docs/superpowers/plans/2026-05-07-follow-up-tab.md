# 首页跟进模块实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在首页新增「跟进」Tab（`bdFlag=1 || isAdmin=1` 可见），Tab 内默认显示跟进列表（样式与随心拍一致），右下角 FAB 跳转到独立的新增跟进表单页。

**Architecture:** 新建 `lib/pages/follow_up/` 目录，`FollowUpListPage` 从 `MaterialListTab` 独立拷贝并添加 Scaffold + FAB，`FollowUpFormPage` 从 `MaterialUploadPage` 独立拷贝并修改标题与缓存键。`home_page.dart` 增加 `_hasBd` 角色判断并接入新 Tab。两个新页面与原页面互不引用，后续各自演进。

**Tech Stack:** Flutter, Dart, SharedPreferences, UploadQueueManager（单例），MaterialApi（暂复用），FilterPanel widget

---

## 文件清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `lib/pages/follow_up/follow_up_list_page.dart` | 跟进列表页（含 FAB） |
| 新建 | `lib/pages/follow_up/follow_up_form_page.dart` | 新增跟进表单页 |
| 修改 | `lib/pages/home_page.dart` | 加 `_hasBd`、跟进 Tab |

---

## Task 1: 创建跟进列表页 FollowUpListPage

**Files:**
- Create: `lib/pages/follow_up/follow_up_list_page.dart`

- [ ] **Step 1: 拷贝源文件**

```bash
mkdir -p lib/pages/follow_up
cp lib/pages/material_list_tab.dart lib/pages/follow_up/follow_up_list_page.dart
```

- [ ] **Step 2: 批量重命名类名**

在 `follow_up_list_page.dart` 中执行以下替换（全文替换）：

| 原文本 | 替换为 |
|--------|--------|
| `class MaterialListTab extends StatefulWidget` | `class FollowUpListPage extends StatefulWidget` |
| `class MaterialListTabState extends State<MaterialListTab>` | `class FollowUpListPageState extends State<FollowUpListPage>` |
| `State<MaterialListTab> createState() => MaterialListTabState()` | `State<FollowUpListPage> createState() => FollowUpListPageState()` |
| `/// 素材列表Tab页面（随心拍）` | `/// 跟进列表页` |

- [ ] **Step 3: 修改缓存键前缀**

找到 `_generateCacheKey()` 方法，将第一行从：

```dart
params.add('material_list');
```

改为：

```dart
params.add('follow_up_list');
```

- [ ] **Step 4: 将 build() 返回值从 Column 改为 Scaffold + FAB**

找到主 `build()` 方法（约第 688 行，特征：`return Column(`），将整个方法替换为：

```dart
@override
Widget build(BuildContext context) {
  super.build(context);

  return Scaffold(
    backgroundColor: Colors.white,
    body: Column(
      children: [
        _buildSearchBar(),
        if (_isOffline && _materialGroups.isNotEmpty) _buildOfflineHint(),
        _buildStatusBar(),
        Expanded(child: _buildMaterialList()),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FollowUpFormPage()),
        ).then((_) => _loadMaterials(isRefresh: true));
      },
      backgroundColor: const Color(0xFF2979FF),
      child: const Icon(Icons.add, color: Colors.white),
    ),
  );
}
```

- [ ] **Step 5: 在文件顶部 import 区域添加对表单页的引用**

在现有 import 列表末尾添加：

```dart
import 'follow_up_form_page.dart';
```

- [ ] **Step 6: 修复相对路径 import（因文件移到子目录）**

将文件顶部所有 `../` 改为 `../../`（原文件在 `pages/`，新文件在 `pages/follow_up/`，需多一级）：

```dart
// 原
import '../models/material_item.dart';
import '../services/material_api.dart';
import '../services/list_cache_service.dart';
import '../services/api_client.dart';
import '../services/network_service.dart';
import '../services/route_settings_service.dart';
import '../services/event_bus_service.dart';
import '../widgets/filter_panel.dart';
import 'material_preview_page.dart';
import 'filtered_materials_page.dart';

// 改为
import '../../models/material_item.dart';
import '../../services/material_api.dart';
import '../../services/list_cache_service.dart';
import '../../services/api_client.dart';
import '../../services/network_service.dart';
import '../../services/route_settings_service.dart';
import '../../services/event_bus_service.dart';
import '../../widgets/filter_panel.dart';
import '../material_preview_page.dart';
import '../filtered_materials_page.dart';
```

- [ ] **Step 7: 验证编译**

```bash
flutter analyze lib/pages/follow_up/follow_up_list_page.dart
```

预期：无 error（warning 可暂忽略）。

- [ ] **Step 8: Commit**

```bash
git add lib/pages/follow_up/follow_up_list_page.dart
git commit -m "feat: 新增跟进列表页 FollowUpListPage"
```

---

## Task 2: 创建新增跟进表单页 FollowUpFormPage

**Files:**
- Create: `lib/pages/follow_up/follow_up_form_page.dart`

- [ ] **Step 1: 拷贝源文件**

```bash
cp lib/pages/material_upload_page.dart lib/pages/follow_up/follow_up_form_page.dart
```

- [ ] **Step 2: 批量重命名类名**

在 `follow_up_form_page.dart` 中执行以下全文替换：

| 原文本 | 替换为 |
|--------|--------|
| `class MaterialUploadPage extends StatefulWidget` | `class FollowUpFormPage extends StatefulWidget` |
| `class _MaterialUploadPageState extends State<MaterialUploadPage>` | `class _FollowUpFormPageState extends State<FollowUpFormPage>` |
| `State<MaterialUploadPage> createState() => _MaterialUploadPageState()` | `State<FollowUpFormPage> createState() => _FollowUpFormPageState()` |
| `/// 素材上传页面` | `/// 新增跟进表单页` |

- [ ] **Step 3: 移除 editId 参数（跟进只新建，不编辑）**

找到类定义部分，将：

```dart
class FollowUpFormPage extends StatefulWidget {
  final int? editId; // 编辑记录ID,如果为null则为新建模式

  const FollowUpFormPage({super.key, this.editId});
```

替换为：

```dart
class FollowUpFormPage extends StatefulWidget {
  const FollowUpFormPage({super.key});
```

- [ ] **Step 4: 修改 AppBar 标题**

找到 `_buildCustomNavbar()` 方法（约第 1168 行，特征：`String title = '素材上传'`），将标题逻辑改为固定标题，同时移除返回按钮判断：

```dart
Widget _buildCustomNavbar() {
  const String title = '新增跟进';
  const bool showBackButton = true;
  // 其余代码保持不变
```

注意：原方法中 `showBackButton` 的定义行也要删除（原为 `final showBackButton = widget.editId != null;`），替换为上方的 `const bool showBackButton = true;`。

- [ ] **Step 5: 修改缓存键，避免与原上传页共用缓存**

全文替换以下缓存 key：

| 原 key | 新 key |
|--------|--------|
| `'cached_category_id'` | `'fu_cached_category_id'` |
| `'cached_visibility_id'` | `'fu_cached_visibility_id'` |
| `'cached_upload_files'` | `'fu_cached_upload_files'` |
| `'cached_upload_region'` | `'fu_cached_upload_region'` |

- [ ] **Step 6: 修复相对路径 import（因文件移到子目录）**

将文件顶部所有以 `'../` 开头的 import 改为 `'../../`，以 `'upload_manager_page` / `'material_preview_page` 开头的同级引用改为 `'../`：

```dart
// 模型和服务：../  → ../../
import '../../models/material_category.dart';
import '../../models/hospital.dart';
import '../../models/department.dart';
import '../../models/visibility_option.dart';
import '../../models/upload_file.dart';
import '../../services/material_api.dart';
import '../../services/upload_queue_manager.dart';
import '../../services/event_bus_service.dart';
import '../../services/route_settings_service.dart';
import '../../services/department_service.dart';
import '../../services/guest_mode_service.dart';
import '../../models/material_item.dart';

// 同级页面：改为 ../
import '../upload_manager_page.dart';
import '../material_preview_page.dart';
```

- [ ] **Step 7: 修复所有 widget.editId 引用**

全文搜索 `widget.editId`，共有以下处理方式：
- 初始化中的编辑模式加载逻辑（`if (widget.editId != null) { _loadEditData(); }`）：改为不执行（删除或注释掉该判断）
- 提交时的区分逻辑（新建 vs 编辑接口）：只保留新建分支，删除 editId 相关的编辑提交分支

搜索命令确认所有引用：
```bash
grep -n "widget.editId\|editId" lib/pages/follow_up/follow_up_form_page.dart
```

逐一处理每处引用，确保没有对 `widget.editId` 的读取（类中已无该字段）。

- [ ] **Step 8: 验证编译**

```bash
flutter analyze lib/pages/follow_up/follow_up_form_page.dart
```

预期：无 error。

- [ ] **Step 9: Commit**

```bash
git add lib/pages/follow_up/follow_up_form_page.dart
git commit -m "feat: 新增跟进表单页 FollowUpFormPage"
```

---

## Task 3: 修改 home_page.dart 接入跟进 Tab

**Files:**
- Modify: `lib/pages/home_page.dart`

- [ ] **Step 1: 添加 import**

在文件顶部现有 import 列表末尾添加：

```dart
import 'follow_up/follow_up_list_page.dart';
```

- [ ] **Step 2: 添加 _hasBd 字段和 GlobalKey**

在 `_HomePageState` 的字段声明区（`_hasKefu`、`_hasSchedule` 等附近），添加：

```dart
bool _hasBd = false;
final GlobalKey<FollowUpListPageState> _followUpTabKey = GlobalKey();
```

- [ ] **Step 3: 更新 _getTabCount 方法**

将原方法：

```dart
int _getTabCount(bool isAdm, bool hasKefu, bool hasSchedule) {
  int count = 0;
  if (isAdm) {
    count = 3;
  } else {
    if (hasKefu) count++;
    if (hasSchedule) count += 2;
  }
  return count;
}
```

替换为：

```dart
int _getTabCount(bool isAdm, bool hasKefu, bool hasSchedule, bool hasBd) {
  int count = 0;
  if (isAdm || hasKefu) count++;
  if (isAdm || hasSchedule) count += 2;
  if (isAdm || hasBd) count++;
  return count;
}
```

- [ ] **Step 4: 更新 _checkRole 方法**

将原方法：

```dart
Future<void> _checkRole() async {
  final kefuFlag = await UserService().getKefuFlag();
  final scheduleFlag = await UserService().getScheduleFlag();
  final isAdmin = await UserService().getIsAdmin();

  final hasKefu = kefuFlag == 1;
  final hasSchedule = scheduleFlag == 1;
  final isAdm = isAdmin == 1;

  final tabCount = _getTabCount(isAdm, hasKefu, hasSchedule);

  if (mounted) {
    setState(() {
      _hasKefu = hasKefu;
      _hasSchedule = hasSchedule;
      _isAdmin = isAdm;
      _initialized = true;
    });
    
    if (tabCount > 1) {
      _tabController = TabController(length: tabCount, vsync: this);
    }
  }
}
```

替换为：

```dart
Future<void> _checkRole() async {
  final kefuFlag = await UserService().getKefuFlag();
  final scheduleFlag = await UserService().getScheduleFlag();
  final isAdmin = await UserService().getIsAdmin();
  final bdFlag = await UserService().getBdFlag();

  final hasKefu = kefuFlag == 1;
  final hasSchedule = scheduleFlag == 1;
  final isAdm = isAdmin == 1;
  final hasBd = bdFlag == 1;

  final tabCount = _getTabCount(isAdm, hasKefu, hasSchedule, hasBd);

  if (mounted) {
    setState(() {
      _hasKefu = hasKefu;
      _hasSchedule = hasSchedule;
      _isAdmin = isAdm;
      _hasBd = hasBd;
      _initialized = true;
    });
    
    if (tabCount > 1) {
      _tabController = TabController(length: tabCount, vsync: this);
    }
  }
}
```

- [ ] **Step 5: 更新 refreshToTop 方法**

将原方法替换为（动态计算各 Tab 索引，避免硬编码）：

```dart
void refreshToTop() {
  final tabCount = _getTabCount(_isAdmin, _hasKefu, _hasSchedule, _hasBd);
  if (tabCount > 1 && _tabController != null) {
    final index = _tabController!.index;
    int offset = 0;

    if (_isAdmin || _hasKefu) {
      if (index == offset) { _customerListKey.currentState?.refreshToTop(); return; }
      offset++;
    }
    if (_isAdmin || _hasSchedule) {
      if (index == offset) { _scheduleTabKey.currentState?.refreshToTop(); return; }
      if (index == offset + 1) { _appointmentGroupTabKey.currentState?.refreshToTop(); return; }
      offset += 2;
    }
    if (_isAdmin || _hasBd) {
      if (index == offset) { _followUpTabKey.currentState?.refreshToTop(); return; }
    }
  } else {
    if (_hasKefu) {
      _customerListKey.currentState?.refreshToTop();
    } else if (_hasBd) {
      _followUpTabKey.currentState?.refreshToTop();
    } else {
      _scheduleTabKey.currentState?.refreshToTop();
    }
  }
}
```

- [ ] **Step 6: 更新 build() — 多 Tab 分支加入跟进 Tab**

找到多 Tab 的构建部分（`if (tabCount > 1)` 内部），在末尾的 `return Scaffold(...)` 之前，在已有的 `if (_isAdmin || _hasSchedule)` 块之后添加：

```dart
if (_isAdmin || _hasBd) {
  tabs.add(const Tab(text: '跟进'));
  tabViews.add(FollowUpListPage(key: _followUpTabKey));
}
```

完整的多 Tab 构建块应为：

```dart
if (tabCount > 1) {
  List<Widget> tabs = [];
  List<Widget> tabViews = [];

  if (_isAdmin || _hasKefu) {
    tabs.add(const Tab(text: '工作台'));
    tabViews.add(CustomerManagementPage(key: _customerListKey, isTabMode: true));
  }
  if (_isAdmin || _hasSchedule) {
    tabs.add(const Tab(text: '日程'));
    tabViews.add(ScheduleListTab(key: _scheduleTabKey));
    tabs.add(const Tab(text: '预约组'));
    tabViews.add(AppointmentGroupTab(key: _appointmentGroupTabKey));
  }
  if (_isAdmin || _hasBd) {
    tabs.add(const Tab(text: '跟进'));
    tabViews.add(FollowUpListPage(key: _followUpTabKey));
  }

  return Scaffold(
    // ... 原有 Scaffold 代码不变
  );
}
```

- [ ] **Step 7: 更新 build() — 单 Tab 分支加入纯 BD 用户入口**

找到单 Tab 分支（`if (_hasKefu)` 的判断），在其后添加 BD 用户分支：

```dart
if (_hasKefu) {
  return CustomerManagementPage(key: _customerListKey);
}

// 纯 BD 用户：首页直接显示跟进列表
if (_hasBd) {
  return Scaffold(
    backgroundColor: Colors.white,
    body: Column(
      children: [
        _buildTopBar(),  // 复用现有 _buildTopBar，标题改为'跟进'
        Expanded(child: FollowUpListPage(key: _followUpTabKey)),
      ],
    ),
  );
}
```

同时更新 `_buildTopBar()` 方法，使其接受标题参数：

```dart
Widget _buildTopBar({String title = '日程'}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: SafeArea(
      bottom: false,
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF333333),
            ),
          ),
        ],
      ),
    ),
  );
}
```

纯日程用户的原有调用 `_buildTopBar()` 保持不变，纯 BD 用户调用 `_buildTopBar(title: '跟进')`。

- [ ] **Step 8: 验证编译**

```bash
flutter analyze lib/pages/home_page.dart
```

预期：无 error。

- [ ] **Step 9: Commit**

```bash
git add lib/pages/home_page.dart
git commit -m "feat: 首页接入跟进 Tab，bdFlag=1 或管理员可见"
```

---

## Task 4: 端到端验证

- [ ] **Step 1: 启动应用，确认普通用户首页无跟进 Tab**

```bash
flutter run -d <device_id>
```

以 `bdFlag=0`、`kefuFlag=0`、`scheduleFlag=0` 的账号登录，首页应只显示日程。

- [ ] **Step 2: 以 BD 用户身份验证跟进 Tab 可见**

以 `bdFlag=1` 账号登录，首页应出现「跟进」Tab（多角色时与其他 Tab 并列）。

- [ ] **Step 3: 验证列表加载**

切换到跟进 Tab，应显示列表（与随心拍样式一致），搜索和筛选功能正常。

- [ ] **Step 4: 验证新增跳转**

点击右下角 FAB，应跳转至「新增跟进」表单页，标题为「新增跟进」，表单功能与原上传页一致。

- [ ] **Step 5: 验证返回刷新**

表单提交后返回，列表应自动刷新。

- [ ] **Step 6: 最终 Commit**

```bash
git add .
git commit -m "feat: 跟进模块端到端验证通过"
```

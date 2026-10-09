# 首页跟进模块设计文档

**日期：** 2026-05-07  
**状态：** 已确认，待实施

---

## 需求概述

在首页新增「跟进」Tab，可见规则与随心拍模块的「医院资料」Tab 一致（`bdFlag=1 || isAdmin=1`）。Tab 默认展示跟进列表，右下角有新增按钮，点击后进入独立的跟进表单页。

---

## 可见规则

| Tab | 显示条件 |
|-----|---------|
| 工作台 | `kefuFlag=1 \|\| isAdmin=1` |
| 日程 | `scheduleFlag=1 \|\| isAdmin=1` |
| 预约组 | `scheduleFlag=1 \|\| isAdmin=1` |
| **跟进（新增）** | **`bdFlag=1 \|\| isAdmin=1`** |

- 多角色用户：所有符合条件的 Tab 全部显示
- 纯 BD 用户（仅 `bdFlag=1`）：首页只有「跟进」一个 Tab，不显示 TabBar，直接展示列表页

---

## 新增文件

```
lib/pages/follow_up/
├── follow_up_tab.dart        # Tab 容器（嵌入 home_page.dart）
├── follow_up_list_page.dart  # 跟进列表页
└── follow_up_form_page.dart  # 新增跟进表单页
```

---

## 修改文件

### `lib/pages/home_page.dart`

1. 新增 `_hasBd` 状态字段
2. `_checkRole()` 增加 `UserService().getBdFlag()` 查询
3. `_getTabCount()` 签名加入 `hasBd` 参数，admin 时 count 改为 4
4. `build()` 加入跟进 Tab 条件分支
5. 纯 BD 用户单 Tab 分支：直接返回 `FollowUpTab`
6. `refreshToTop()` 更新各 Tab 索引映射

---

## 跟进列表页（FollowUpListPage）

与 `MaterialListTab` 视觉和交互保持一致。

**功能：**
- 无限滚动，分页加载（每页 20 条）
- 下拉刷新
- 顶部搜索框（关键词搜索）
- 筛选面板（与随心拍相同）：素材类别（9 种）、归属标签（11 种区域）、医院、可见范围
- 卡片样式与随心拍素材卡片一致
- 右下角 FAB（`+`），点击跳转 `FollowUpFormPage`

**接口（暂用，后续替换为专属跟进接口）：**
- 列表：`POST /v1/casually/upload_history_new`

---

## 新增跟进表单页（FollowUpFormPage）

与 `MaterialUploadPage` **完全独立**，不共享任何组件，后续各自演进。

**功能：**
- AppBar 标题：「新增跟进」
- 表单字段、验证顺序、交互逻辑与 `MaterialUploadPage` 完全一致
- 文件上传复用 `UploadQueueManager` 单例（上传基础设施合理共享）

**接口（暂用，后续替换）：**
- 提交：`POST /v1/casually/upload_new`

**与原上传页的区别：**
- 独立文件，互不引用
- AppBar 标题不同（「新增跟进」vs「上传素材」）
- 后续字段、接口可各自独立调整

---

## 数据流

```
home_page.dart
└── _hasBd=true → 跟进 Tab
    └── FollowUpTab
        └── FollowUpListPage（默认）
            ├── 加载列表：POST /v1/casually/upload_history_new
            └── FAB 点击 → FollowUpFormPage
                └── 提交：POST /v1/casually/upload_new
                    └── 成功后返回列表并刷新
```

---

## 不在本次范围内

- 跟进专属 API 接口开发（后端）
- 跟进列表与上传列表的数据隔离（依赖专属接口）
- 跟进记录的编辑、删除功能

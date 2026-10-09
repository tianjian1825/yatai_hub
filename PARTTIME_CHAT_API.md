# 兼职任务「群聊对话」接口文档

> 兼职 App 任务详情的「留言板」已改造为以任务为单位的**群聊会话**。本文档面向 App 前端，描述 FastAPI 层对外接口。
> 业务逻辑由客服系统 PHP `open_api` 承载，App 只对接本服务（FastAPI）。

## 通用约定

- **Base URL**：`{服务域名}/v1/parttime_task`
- **鉴权**：所有接口需 `Authorization: Bearer <JWT>`（钉钉 OAuth 登录后获取，30 天有效）。
- **统一响应包裹**：

```json
{ "code": 0, "msg": "success", "data": { }, "time": "1781601067" }
```

- `code = 0` 成功；非 0 为业务错误，`msg` 为可直接展示给用户的中文提示，HTTP 仍为 200。
- 鉴权失败返回 HTTP 401。
- 下文每个接口的「响应」一栏仅描述 `data` 字段内容。

### 会话类型 conv_type（任务群 / 科室群 / 私聊）

所有群聊接口新增 `conv_type`：

| conv_type | 会话 | `task_id` 含义 |
|---|---|---|
| `1`（默认，不传即此） | 任务群 | 兼职任务 ID |
| `2` | 科室群 | **科室 ID** |
| `3` | 私聊（1v1） | **私聊会话 ID**（`chat/private/open` 返回） |

- 传参位置与所在接口一致：`messages` / `unread_count` / `members` 走 query，`send` / `read` 走 body。
- `message/recall` 只需 `message_id`，**不传** `conv_type`。
- `conversations` **不传** `conv_type`，返回任务群 + 科室群 + 私聊**混排**列表，每条自带 `conv_type`；进入某会话后用该条的 `conv_type` + `task_id` 调后续接口。
- 科室群成员随科室自动同步：`members` 固定返回 `can_manage=false`，前端隐藏拉人/移人/退群入口；误调 invite/remove/leave 返回 `4003 科室群成员随科室自动同步，不支持拉人/移除/退出`。
- 兼职上下班打卡会往其科室群推一条系统消息，推送 payload：
  `{"action":"open_part_time_comment","conv_type":2,"task_id":<科室ID>}`。
- ⚠️ 三种 ID 来自不同表，**会撞号**（科室 45 / 任务 45 / 私聊会话 45 可同时存在）。客户端凡是把会话当唯一键的地方（本地库主键、活跃会话集合、已读/未读广播）都必须用 `conv_type + task_id` 复合键，见 `models/chat_target.dart`。

### 群聊模型要点

- **扁平消息流**：所有消息按时间正序排成一条流（无主楼/回复层级）。
- **引用**：发送时可携带 `quote_message_id` 引用任意一条历史消息；消息体附带被引用消息的快照 `quote`。
- **分页与增量**：向上翻历史用 `before_id`（反向游标，传上一屏 `oldest_id`）；停留会话内拉新消息用 `after_id`（正向增量，传本地最大 `message_id`）。`after_id` 优先于 `before_id`。
- **会话级已读**：每人每任务只维护「最后已读消息ID」`last_read_id`。拉取最新一屏（`before_id=0`）、增量拉新（`after_id>0`）或调用 `chat/read` 都会推进已读；翻历史（`before_id>0`）不影响。`chat/messages` 响应回传 `last_read_id`，用于画「新消息分隔线」。
- **消息类型**：`msg_type` 1=普通消息，2=系统灰条（如"X 把 Y 拉入群聊"/"X 退出群聊"，`user_id=0`）。系统消息与已撤回消息**不计入未读**。
- **撤回**：发送者可在 **2 分钟内**撤回自己的消息；撤回后该消息 `recalled=true`、`content`/`images` 清空，前端按灰条展示"X 撤回了一条消息"。
- **图片 / 视频与缩略图**：聊天里的图片与视频**走 NAS**（`POST /v1/nas_upload/upload_image`，单请求直传，不走 30MB 分片），上传时 `generate_thumbnail=1` 图片会得到 `thumbnail`、视频会得到 ffmpeg 第 1 秒截帧 `video_frame`（**视频也要传 1**，否则没有封面）。NAS 缩略图文件名是独立时间戳、**无法由原件 URL 推导**（OSS 那套 `?x-oss-process=` 参数对 NAS 静态服务无效），所以发送时必须用 `media` 把 `thumb` 带上，服务端落库到消息的 `media` 列。
  - 兼容策略是**双向降级**：老消息 / 后台留言板发的图 `media` 为空 → 服务端按 `images` 兜底合成（`thumb` 为空串）；客户端连到未支持 `media` 的旧后端 → 按 `images` 兜底。两端发版顺序任意，不需要卡时序。
  - 客户端渲染：列表格子用 `thumb`（空则回退 `url`），点开预览与保存到相册始终用 `url`。视频截帧失败时后端会落一个 **0 字节空 jpg** 并照常返回 `video_frame`，客户端需要 error 兜底（回退黑块 + 播放图标）。
- **@提及**：发送可带 `mention_user_ids`（被@成员）或 `mention_all`（@所有人）；被@者收到 `type=mention` 通知，会话列表标记 `has_mention`。
- **发送幂等**：发送可带 `client_msg_id`，弱网重发时同一用户相同 `client_msg_id` 直接返回首次结果（`duplicated=true`）。
- **闭群成员**：仅群成员可查看/发送。任务发起人、执行人、责任客服**自动入群**；仅发起人/责任客服/管理员可拉人或移除成员；普通成员可主动退群，**发起人不可退群**。
- **通知**：发消息后给群内其他成员写一条站内信并触发极光推送（`extras.action = open_part_time_comment`，含 `task_id`、`message_id`；被@者通知 `type=mention`，其余 `type=chat`）。

### 通用错误码（业务 code）

| code | 含义 |
|---|---|
| 2001 | 必填参数缺失 |
| 400  | 参数不合法（如内容图片同时为空、移除发起人、发起人退群、超 2 分钟撤回） |
| 4003 | 无权限（不在群 / 非管理者 / 撤回他人消息 / 科室群不支持成员增删与退出） |
| 4004 | 资源不存在（任务/引用消息/消息不存在） |
| 500  | 保存失败 |

---

## 一、群聊消息

### 1.1 消息列表（反向游标 / 正向增量）

`GET /v1/parttime_task/chat/messages`

**Query 参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| task_id | int | 是 | - | 任务ID |
| before_id | int | 否 | 0 | 反向游标：返回该消息ID**之前**的更早消息；0=最新一屏 |
| after_id | int | 否 | 0 | 正向增量：返回该消息ID**之后**的更新消息（**优先于 before_id**） |
| limit | int | 否 | 20 | 单次条数，1~100 |

**说明**：返回的 `list` 始终按时间**正序**（旧→新）。
- **首屏**：`before_id=0`（不传 after_id）→ 最新一屏，并推进已读到本屏最新。
- **翻历史**：用上一次的 `oldest_id` 作为 `before_id` 续拉，直到 `has_more=false`；翻历史不推进已读。
- **拉新（增量）**：停留会话时用本地最大 `message_id` 作为 `after_id` 拉新消息，并推进已读。`has_more=true` 表示还有更新的消息未取完，可继续用最后一条 `message_id` 续拉。

**响应 data**

```json
{
  "list": [
    {
      "message_id": 24,
      "task_id": 31,
      "msg_type": 2,
      "recalled": false,
      "content": "群主 把 郑朝辉 拉入群聊",
      "images": [],
      "user_id": 0,
      "username": "",
      "roleid": 0,
      "avatar": "",
      "created_at": 1781601060,
      "quote_message_id": 0,
      "quote": null,
      "mention_all": false,
      "mention_user_ids": []
    },
    {
      "message_id": 26,
      "task_id": 31,
      "msg_type": 1,
      "recalled": false,
      "content": "@你看下",
      "images": [],
      "user_id": 1,
      "username": "久久",
      "roleid": 2,
      "avatar": "https://.../avatar/1.png",
      "created_at": 1781601069,
      "quote_message_id": 0,
      "quote": null,
      "mention_all": false,
      "mention_user_ids": [2]
    }
  ],
  "has_more": false,
  "oldest_id": 24,
  "last_read_id": 26,
  "unread_count": 0
}
```

**消息对象字段**

| 字段 | 类型 | 说明 |
|---|---|---|
| message_id | int | 消息ID |
| msg_type | int | 1=普通消息，2=系统灰条（`user_id=0`，前端居中灰字展示） |
| recalled | bool | 是否已撤回；为 true 时 `content`/`images`/`quote` 已清空，按"X 撤回了一条消息"灰条展示（X 用 `username`） |
| content | string | 文本内容（可空，仅图片时为空串） |
| images | string[] | 原件 URL 列表（最多 9 张）。**形状固定为纯字符串数组**——旧版 App 与客服后台留言板模板都按 `string[]` 读，不可改成对象 |
| media | object[] | 与 `images` **同序等长**的富媒体列表，每项 `{url, thumb, type, w?, h?, duration?}`：`url`=原件、`thumb`=缩略图（图片为 200×200 缩略图，视频为第 1 秒截帧，**可能为空**）、`type`=`image`/`video`。老消息与后台发的图没有缩略图，此时 `thumb` 为空串，客户端回退 `url`。NAS 缩略图文件名是独立时间戳，**无法由原件 URL 推导**，所以必须随消息下发 |
| user_id / username / roleid | int/string/int | 发送人（系统消息为 0/""/0） |
| avatar | string | 发送人头像（库内原值，可能为相对路径；系统消息为空串） |
| created_at | int | 发送时间戳（秒） |
| quote_message_id | int | 被引用消息ID；0=未引用 |
| quote | object\|null | 被引用消息快照：`message_id, user_id, username, content(截断50字), image(首图原件), image_thumb(首图缩略图，可能空), image_type(首个附件类型 image/video，旧数据为空串)`；引用消息不存在/被撤回时为 null |
| mention_all | bool | 是否@所有人 |
| mention_user_ids | int[] | 被@的成员 userid 列表 |

| 顶层字段 | 说明 |
|---|---|
| has_more | 反向：是否还有更早消息；正向(after_id)：是否还有更新消息 |
| oldest_id | 本屏最小消息ID（翻历史时用作下一页 `before_id`） |
| last_read_id | 当前用户在本任务的最后已读消息ID（用于画"新消息分隔线"） |
| unread_count | 当前用户在本任务的未读数（已扣除系统/撤回消息；本接口已推进已读时通常为 0） |

---

### 1.2 发送消息

`POST /v1/parttime_task/chat/send`

**Body (JSON)**

| 字段 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| task_id | int | 是 | - | 任务ID |
| content | string | 否 | "" | 文本，最长 1000 字 |
| images | string[] | 否 | [] | 原件 URL，最多 9 张（先调 `/v1/nas_upload/upload_image` 拿 URL）。**旧版兼容字段**：传了 `media` 时可不传，服务端由 media 反推 |
| media | object[] | 否 | [] | 富媒体列表，最多 9 项，每项 `{url, thumb?, type?, w?, h?, duration?}`。**优先级高于 `images`**：传了它，服务端按它落库并反推 images。`thumb` 取上传接口返回的 `thumbnail.file_url`（图片）或 `video_frame.file_url`（视频）；`type` 留空则服务端按扩展名推断 |
| quote_message_id | int | 否 | 0 | 引用的消息ID；0=不引用 |
| client_msg_id | string | 否 | "" | 客户端消息ID（≤64字），弱网重发幂等去重，建议每条消息生成唯一值 |
| mention_user_ids | int[] | 否 | [] | 被@的成员 userid（非群成员自动忽略） |
| mention_all | bool | 否 | false | 是否@所有人 |

> `content` 与 `images` 不能同时为空。

**响应 data**

```json
{ "message_id": 23, "task_id": 31, "quote_message_id": 22, "created_at": 1781601067 }
```

> 幂等命中（相同 `client_msg_id` 重发）时额外返回 `"duplicated": true`，`message_id` 为首次那条。

---

### 1.3 撤回消息

`POST /v1/parttime_task/chat/message/recall`

仅可撤回**本人**消息，且发送后 **2 分钟内**。撤回后该消息在 `chat/messages` 中 `recalled=true`、内容清空。

**Body (JSON)**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| message_id | int | 是 | 要撤回的消息ID |

**响应 data**

```json
{ "message_id": 27, "task_id": 31, "recalled": true }
```

> 失败场景：非本人消息 → 4003；超 2 分钟 → 400「超过2分钟，无法撤回」。

---

### 1.5 未读数

`GET /v1/parttime_task/chat/unread_count`

**Query 参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| task_id | int | 否 | 0 | >0=查单任务；0=我在群所有任务的未读汇总 |

**响应 data（单任务，task_id>0）**

```json
{ "task_id": 31, "total_unread": 2 }
```

**响应 data（汇总，task_id=0）**

```json
{ "total_unread": 5, "tasks": [ { "task_id": 31, "unread_count": 2 }, { "task_id": 40, "unread_count": 3 } ] }
```

> 汇总只返回未读数 > 0 的任务。系统灰条与已撤回消息不计入未读。

---

### 1.6 推进已读位置

`POST /v1/parttime_task/chat/read`

进入会话或滚动到底时调用（无需重新拉消息即可清未读）。

**Body (JSON)**

| 字段 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| task_id | int | 是 | - | 任务ID |
| up_to_id | int | 否 | 0 | 已读到的消息ID；0=该任务最新消息 |

**响应 data**

```json
{ "task_id": 31, "last_read_id": 23, "unread_count": 0 }
```

---

### 1.7 最近会话列表

`GET /v1/parttime_task/chat/conversations`

App IM 首页用：返回我所在的全部任务群 + 科室群 + 私聊（混排），按最后消息时间倒序。

**Query 参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| page | int | 否 | 1 | 页码 |
| page_size | int | 否 | 20 | 每页数量，1~50 |

**响应 data**

```json
{
  "list": [
    {
      "task_id": 31,
      "last_message_id": 27,
      "last_message": "@你看下",
      "last_message_time": 1781601069,
      "unread_count": 2,
      "has_mention": true,
      "member_count": 3
    }
  ],
  "total": 1,
  "page": 1,
  "page_size": 20
}
```

| 字段 | 说明 |
|---|---|
| last_message | 最后一条消息预览（附件按类型拼 `[N张图片]` / `[N个视频]`，两者都有则图片在前空格分隔；系统消息为其文本，已撤回为 `[消息已撤回]`） |
| last_message_time | 最后消息时间戳；无消息时为 0 |
| unread_count | 该会话未读数 |
| has_mention | 是否有"未读且@我（或@所有人）"的消息 |
| member_count | 在群成员数 |

私聊行（`conv_type=3`）额外带三个字段，群聊行为空/0：

| 私聊特有字段 | 说明 |
|---|---|
| title / group_name | 对方姓名 |
| peer_user_id | 对方 userid |
| avatar | 对方头像 |

排序：科室群整体置顶，私聊与任务群按最后消息时间倒序混排。**空会话（还没发过消息）不出现在列表**。

---

## 一之二、私聊（conv_type=3）

私聊复用上面 1.1~1.7 全部接口，只需 `conv_type=3` + `task_id=私聊会话 ID`；另有两个专属入口。

- `msg_type` 私聊一般无 2（系统灰条）；**无 @ 功能**，`mention_all`/`mention_user_ids` 恒为空，发送时可不传。
- `messages` 响应的 `title`/`group_name` 为对方姓名。
- **权限**：仅 `roleid ≠ 275` 可访问通讯录、可发起私聊；兼职只能在已存在的会话里回复（会话不存在返回「会话不存在」）。
- **不支持的操作**：`chat/member/invite`、`chat/member/remove`、`chat/member/leave` 对 `conv_type=3` 一律拒绝（返回「仅任务群支持…」）。
- **推送**：对方发消息后收信人收到极光推送，`action=open_part_time_comment`，payload 含 `task_id`、`conv_type=3`、`message_id`、`title`（发送者姓名），正文为消息摘要。

### 1.8 通讯录（列全部兼职人员）

`GET /v1/parttime_task/contacts` ｜ 仅 `roleid ≠ 275` 可访问（兼职调用返回「无权限」）

**Query 参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| keyword | string | 否 | - | 姓名 / 用户名关键词，模糊匹配（大小写不敏感，中英文均可） |
| page | int | 否 | 1 | 页码 |
| page_size | int | 否 | 20 | 每页数量，最大 50 |

**响应 data**

```json
{
  "list": [
    {
      "user_id": 1360,
      "username": "王鹏",
      "avatar": "https://.../a.jpg?x-oss-process=image/resize,m_fill,w_300,h_300",
      "roleid": 275,
      "mobile": "13800138000",
      "conv_id": 0
    }
  ],
  "total": 2,
  "page": 1,
  "page_size": 10
}
```

| 字段 | 说明 |
|---|---|
| user_id | 兼职人员 userid，发起私聊时作为 `peer_id` |
| username | 姓名（realname，回退 username） |
| avatar | 头像（已补全 URL + 缩放参数，可能为空串） |
| roleid | 固定 275 |
| mobile | 手机号，可能为空串（未登记）。App 在该行右侧给拨号按钮，`tel:` 调系统拨号盘 |
| conv_id | 与当前登录人已存在的私聊会话 ID；0=尚未建过。>0 时前端可直接进会话（当 `task_id` + `conv_type=3`），**跳过 private/open** |

### 1.9 发起 / 获取私聊会话

`POST /v1/parttime_task/chat/private/open` ｜ 仅 `roleid ≠ 275` 可发起 ｜ `Content-Type: application/json`

get-or-create：会话已存在则返回原会话，不存在则新建。**不会发送任何消息**。

**请求参数**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| peer_id | int | 是 | 对方兼职人员 userid（通讯录里选中的），必须是兼职（roleid=275） |

**响应 data**

```json
{
  "task_id": 12,
  "conv_type": 3,
  "peer": {
    "user_id": 1360,
    "username": "王鹏",
    "avatar": "https://.../a.jpg?x-oss-process=image/resize,m_fill,w_300,h_300",
    "roleid": 275
  }
}
```

| 字段 | 说明 |
|---|---|
| task_id | 私聊会话 ID，后续所有 `chat/*` 接口用它 + `conv_type=3` |
| conv_type | 固定 3 |
| peer | 对方信息（进会话页展示对方姓名/头像用） |

**业务错误 msg**：`兼职人员不能主动发起私聊`（roleid=275 调用）、`只能与兼职人员发起私聊`（peer 不是 275）、`对方不存在或已离职`、`不能和自己私聊`。

---

## 二、群成员

### 2.1 成员列表

`GET /v1/parttime_task/chat/members`

**Query 参数**：`task_id`（int，必填）

**响应 data**

```json
{
  "task_id": 31,
  "list": [
    { "user_id": 1, "username": "久久", "roleid": 2, "member_role": 1, "source": 1, "joined_at": 1781601065 },
    { "user_id": 2, "username": "郑朝辉", "roleid": 2, "member_role": 2, "source": 2, "joined_at": 1781601066 }
  ],
  "can_manage": true
}
```

| 字段 | 说明 |
|---|---|
| member_role | 1=发起人/群主，2=普通成员 |
| source | 1=自动入群（三方），2=被邀请 |
| can_manage | 当前用户是否可拉人/移除（发起人/责任客服/管理员为 true） |

> 首次调用该接口（或任何群聊接口）会自动把发起人、执行人、责任客服补入群。

---

### 2.2 拉人进群（批量）

`POST /v1/parttime_task/chat/member/invite` — 仅 `can_manage=true` 的用户可调用。

**Body (JSON)**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| task_id | int | 是 | 任务ID |
| user_ids | int[] | 是 | 要拉入的员工 userid 列表（不存在/离职者自动跳过） |

**响应 data**

```json
{
  "task_id": 31,
  "list": [ /* 同 2.1 的成员列表 */ ],
  "added": [2]
}
```

> `added` 为本次实际成功拉入的 userid。被拉者会收到一条站内信 + 极光推送。

---

### 2.3 移除成员

`POST /v1/parttime_task/chat/member/remove` — 仅 `can_manage=true` 的用户可调用，不可移除任务发起人。

**Body (JSON)**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| task_id | int | 是 | 任务ID |
| user_id | int | 是 | 要移除的成员 userid |

**响应 data**

```json
{ "task_id": 31, "list": [ /* 移除后的成员列表 */ ] }
```

---

### 2.4 主动退群（本人）

`POST /v1/parttime_task/chat/member/leave` — 普通成员主动退群；**任务发起人不可退群**。退群产生群内系统灰条。

**Body (JSON)**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| task_id | int | 是 | 任务ID |

**响应 data**

```json
{ "task_id": 31, "left": true }
```

> 发起人调用 → 400「任务发起人不可退出群聊」；非群成员 → 4003。

---

### 2.5 选人：搜索在职员工

`GET /v1/parttime_task/staff/search` — 拉人进群时的选人数据源。

**Query 参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| keyword | string | 否 | "" | 姓名/用户名关键词，空=全部在职员工 |
| page | int | 否 | 1 | 页码 |
| page_size | int | 否 | 20 | 每页数量，1~50 |

**响应 data**

```json
{
  "list": [ { "user_id": 1, "username": "久久", "roleid": 2 } ],
  "total": 672,
  "page": 1,
  "page_size": 20
}
```

---

## 三、通知中心（站内信）

> 极光推送到达时可据 `extras` 跳转；进入 App 后用以下接口拉取持久化的站内信列表与未读角标。
> 群聊新消息/被拉入群的 `action` 均为 `open_part_time_comment`，`payload` 含 `task_id`（新消息另含 `message_id`）。

### 3.1 通知列表（反向游标）

`GET /v1/parttime_task/notifications`

**Query 参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| before_id | int | 否 | 0 | 游标：返回该通知ID之前的更早通知；0=最新 |
| limit | int | 否 | 20 | 单次条数，1~100 |

**响应 data**

```json
{
  "list": [
    {
      "id": 3,
      "type": "chat",
      "action": "open_part_time_comment",
      "title": "兼职任务有新消息",
      "content": "引用上一条",
      "payload": { "task_id": 31, "message_id": 23 },
      "task_id": 31,
      "is_read": 0,
      "created_at": 1781601067
    }
  ],
  "has_more": false,
  "oldest_id": 1,
  "unread_count": 3
}
```

| 字段 | 说明 |
|---|---|
| type | 通知类型，群聊为 `chat` |
| action | 跳转动作（同极光 `extras.action`） |
| payload | 跳转所需参数（如 `task_id`、`message_id`） |
| is_read | 0=未读 1=已读 |

---

### 3.2 通知未读数

`GET /v1/parttime_task/notifications/unread_count`

**响应 data**

```json
{ "unread_count": 3 }
```

---

### 3.3 标记已读（单条 / 全部）

`POST /v1/parttime_task/notifications/read`

**Body (JSON)**

| 字段 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| notification_id | int | 否 | 0 | 通知ID；0=全部标记已读 |

**响应 data**

```json
{ "unread_count": 0 }
```

---

## 四、极光推送约定（客户端处理）

发送群聊消息 / 被@ / 被拉入群时，群内相关成员会收到极光推送：

| 字段 | 值 |
|---|---|
| title | 新消息=`兼职任务有新消息`；被@=`有人在群里@了你`；被拉入群=`你被拉入兼职任务群聊` |
| alert(content) | 消息摘要（文字截断 80 字，附件为 `[N张图片]` / `[N个视频]`）/ `点击查看任务群聊` |
| extras.action | `open_part_time_comment` |
| extras.task_id | 任务ID |
| extras.message_id | 新消息ID（被拉入群时无此字段） |

客户端据 `extras.action` 跳转到对应任务群聊页（`task_id`），并定位到 `message_id`。

> 同一条消息：被@的成员收 `title=有人在群里@了你`、站内信 `type=mention`；其余成员收 `title=兼职任务有新消息`、站内信 `type=chat`。两类推送的 `extras` 结构一致。

---

## 五、与旧版「留言板」接口的差异（迁移说明）

| 旧接口（已下线） | 新接口 |
|---|---|
| `GET /comments` | `GET /chat/messages`（扁平流+反向游标，去掉主楼/回复树） |
| `POST /comment` | `POST /chat/send`（`parent_id`/`reply_to_comment_id` → `quote_message_id`） |
| `GET /comment/unread_count` | `GET /chat/unread_count` |
| `GET /comment/readers`（已读人员） | 已移除（改为会话级已读，新增 `POST /chat/read`） |
| 字段 `comment_id` | `message_id` |
| 留言新消息走**钉钉**通知 | 改为**极光推送 + 站内信通知中心** |

> App 增强（在群聊基础上新增）：正向增量 `after_id`、最近会话列表 `chat/conversations`、系统灰条消息 `msg_type=2`、消息头像 `avatar`、新消息分隔线 `last_read_id`、发送幂等 `client_msg_id`、主动退群 `chat/member/leave`、撤回 `chat/message/recall`、@提及（`mention_user_ids`/`mention_all` + `type=mention` 通知 + 会话 `has_mention`）。

---

## 六、前端调用时序

### 6.1 进入群聊会话（首屏）

```
用户点开任务群聊
   │
   ├─ GET /chat/members?task_id=T          // 渲染群成员、标题人数；记录 can_manage 决定是否显示“+拉人/移除”
   │     · 该调用会自动建群（补入发起人/执行人/责任客服）
   │
   └─ GET /chat/messages?task_id=T&before_id=0&limit=20
         · list 正序渲染，滚动到底部（最新在下）
         · 该调用已自动把已读推进到本屏最新 → 本会话角标可置 0
         · 记录 oldest_id 供上拉加载；has_more 决定是否还能上拉
```

> 说明：拉取最新一屏（`before_id=0`）即视为已读，通常**无需**再单独调 `/chat/read`。响应里的 `last_read_id` 用于在该位置之后画"——以下为新消息——"分隔线；`msg_type=2` 的居中灰字、`recalled=true` 的"X 撤回了一条消息"灰条照常渲染。

### 6.2 上拉加载更早消息（历史分页）

```
用户上滑到顶部且 has_more=true
   │
   └─ GET /chat/messages?task_id=T&before_id={当前最旧的 message_id}&limit=20
         · 把返回 list 拼接到现有消息**前面**（更早）
         · 更新本地最旧 message_id、has_more
         · 加载历史不影响已读位置（不会回退未读）
```

### 6.3 拉取新消息（停留会话时的增量）

```
收到极光推送 / 定时轮询（在该会话内）
   │
   └─ GET /chat/messages?task_id=T&after_id={当前最新的 message_id}&limit=20
         · 返回比 after_id 更新的消息（正序），追加到列表**底部**
         · has_more=true 表示一次没取完，用最后一条 message_id 继续拉
         · 该调用会推进已读 → 会话角标置 0
```

### 6.4 发送消息（含引用 / @ / 幂等）

```
用户输入/选图；可“引用”某条(quote_message_id)、可@成员
   │ 生成本地唯一 client_msg_id（弱网重发用同一个）
   ├─ POST /chat/send { task_id, content, images?, quote_message_id?,
   │                    client_msg_id, mention_user_ids?, mention_all? }
   │      → { message_id, created_at } （重发命中返回 duplicated:true，message_id 仍为首条）
   │
   └─ 前端用 message_id（或 client_msg_id）去重后乐观上屏
         · 失败可用同一 client_msg_id 重发，服务端保证不产生重复
         · @候选成员来自 GET /chat/members
```

### 6.5 接收新消息 / 已读角标刷新

```
A. App 在前台、正停留在该会话：
   · 收到极光推送(extras.action=open_part_time_comment, 同 task_id)
   · → GET /chat/messages?after_id={本地最新 message_id} 追加尾部（已读自动推进）

B. App 在前台、但不在该会话（如会话列表/任务列表页）：
   · 进入会话列表 GET /chat/conversations（每行带未读、has_mention、最后消息预览）
   · 或 GET /chat/unread_count（task_id=0 汇总）给任务渲染小红点
   · my_tasks 每行也带 unread_comment_count 字段可直接用

C. 离开会话但希望显式清未读（未走拉取时）：
   · POST /chat/read { task_id }  // up_to_id 省略=清到最新
```

### 6.6 会话列表首页

```
进入 IM 首页
   └─ GET /chat/conversations?page=1
         · 按 last_message_time 倒序渲染：群、最后消息预览、时间、未读数
         · has_mention=true 显示“[有人@我]”强提醒
         · 点击进入 6.1 会话首屏
```

### 6.7 拉人 / 移除 / 退群（成员管理）

```
拉人（can_manage=true）
   ├─ GET /staff/search?keyword=张&page=1
   └─ POST /chat/member/invite { task_id, user_ids:[...] }  → 刷新成员面板；群内出现“X 把 … 拉入群聊”灰条

移除（can_manage=true）
   └─ POST /chat/member/remove { task_id, user_id }         → 发起人不可移除（后端拦截）；群内出现移出灰条

退群（普通成员本人）
   └─ POST /chat/member/leave { task_id }                   → 发起人不可退（后端拦截）；群内出现“X 退出群聊”灰条；前端退出会话页
```

### 6.8 撤回消息

```
长按自己 2 分钟内的消息 → “撤回”
   └─ POST /chat/message/recall { message_id }
         → 成功后该条 recalled=true，前端就地替换为“你撤回了一条消息”灰条
         · 超时/非本人由后端拦截并返回提示
```

### 6.9 通知中心（站内信）

```
进入 App / 通知页
   ├─ GET /notifications/unread_count        // 顶部铃铛角标
   ├─ GET /notifications?before_id=0&limit=20 // 列表，上拉用 oldest_id 续拉
   │
   ├─ 点击某条通知：
   │     · 据 payload.task_id (+ message_id) 跳转到对应任务群聊
   │     · POST /notifications/read { notification_id }  // 单条置已读
   │
   └─ “全部已读”按钮：
         · POST /notifications/read {}        // notification_id 省略=全部
```

### 6.10 极光推送落地处理（客户端）

```
收到推送
   │ 解析 extras: { action, task_id, message_id? }
   │
   ├─ action == open_part_time_comment：
   │     · App 在前台且在该 task 会话 → 直接增量刷新消息(6.5 A)
   │     · 否则 → 更新会话/通知角标；用户点击时跳转任务群聊并定位 message_id
   │
   └─ 同时建议刷新 /notifications/unread_count 以同步铃铛角标
```

> 角标体系小结：**会话内未读**用 `/chat/unread_count`（或 my_tasks 行字段），**通知中心未读**用 `/notifications/unread_count`，二者相互独立。

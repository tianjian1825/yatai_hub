# 推送声音 + 悬浮通知 后端配置说明（给推送后端）

> 目标：让 App 收到极光推送时**有提示音**、并在 Android 上以**悬浮横幅（heads-up）**弹出。
> 适用 App：SZST新质OA（包名 `com.amgroup.oa`，极光 AppKey `bd01ecb8b0536126252afacf`）。
> 推送服务：极光 JPush，服务端走 Push REST API（`POST /v3/push`）。

---

## 0. 一句话结论

- **iOS / 安卓在线（极光长连接）/ 安卓离线（厂商通道）走的是不同链路，声音和悬浮要分别配，缺一个那条链路就哑。**
- 声音和悬浮在 **Android 8.0+ 由“通知渠道(channel)的 importance”决定**，所以后端下发时必须带正确的 `channel_id`，并保证该渠道是高优先级（HIGH）。
- iOS 必须在 payload 里带 `sound`，否则锁屏/后台都不响。

---

## 1. Android —— 在线推送（极光长连接，App 在前台或后台挂着）

Android 8.0(API 26) 起，**声音和悬浮横幅完全由通知渠道 importance 决定**，`priority`/`sound` 字段在高版本只是兜底。要同时拿到「声音 + 悬浮」，渠道 importance 必须是 **HIGH(4) 或以上**。

`notification.android` 建议这样下发：

```jsonc
"notification": {
  "android": {
    "alert": "你有一条新的群聊消息",
    "title": "随心拍",
    "priority": 2,            // PRIORITY_MAX，Android 7.x 及以下用它出悬浮
    "alert_type": 7,          // 声音+震动+呼吸灯（7.x 及以下兜底）
    "channel_id": "im_message", // ★ 关键：指定高优先级渠道，见下方说明
    "sound": "default"        // 8.0 以下生效；8.0+ 由渠道决定
  }
}
```

### ★ 关于 channel_id（客户端已建好渠道，后端按此下发）

- Android 8.0+ 的声音/悬浮由「渠道」决定，而渠道是在 **App 端创建**的。后端下发的 `channel_id` 必须对应 App 里**已存在且 importance=HIGH** 的渠道，否则系统会落到默认渠道、效果不可控。
- ✅ **客户端已新建高优先级渠道，后端统一下发以下 channel_id 即可命中：**

  | 项 | 值 |
  |----|----|
  | **channel_id** | **`im_message`** |
  | importance | HIGH（带提示音 + 悬浮横幅） |
  | 适用 | 群聊及重要业务推送 |

- 该渠道在 App 进程启动时创建（含极光独立推送进程），App 一经安装启动即生效。**只要 `notification.android.channel_id` 填 `im_message`，在线推送即有声音 + 悬浮。**
- 厂商离线通道（第 2 节）里各厂商的 `channel_id` 也建议统一填 `im_message`，与本地渠道保持一致。

> ⚠️ 渠道一旦由用户设备创建，其 importance/声音无法再被代码修改（Android 限制）。若后续要调整渠道属性，需改渠道 id 或让用户在系统设置里改。当前 `im_message` 已设为最高优先级+默认提示音，正常无需变动。

---

## 2. Android —— 离线推送（厂商通道：小米/华为/荣耀/OPPO/VIVO/魅族/FCM）

App 被杀或长连接断开时，推送走**厂商通道**，此时声音/悬浮由**各厂商的通知通道 + 消息分类**决定，和极光默认渠道无关。这是国内安卓最容易“没声音/不弹”的地方，**每个厂商都要单独配**。

在极光 Push API 的 `options.third_party_channel` 里逐厂商下发，示例：

```jsonc
"options": {
  "third_party_channel": {
    "xiaomi": {
      "distribution": "secondary_push",
      "channel_id": "im_message"      // 需在小米后台申请的通道 id
    },
    "huawei": {
      "distribution": "secondary_push",
      "importance": "NORMAL",          // NORMAL=服务与通讯类，能出声音/悬浮；LOW=资讯类会被折叠静音
      "category": "IM",                // 即时通讯自分类，避免被限频/折叠
      "channel_id": "im_message"
    },
    "honor": {
      "distribution": "secondary_push",
      "importance": "NORMAL"
    },
    "oppo": {
      "distribution": "secondary_push",
      "channel_id": "im_message"       // OPPO 需在后台申请的通道
    },
    "vivo": {
      "distribution": "secondary_push",
      "category": "IM",                // vivo 系统消息分类，需申请
      "push_mode": 0                   // 0=正式，1=测试
    },
    "fcm": { "distribution": "ohter_push" }
  }
}
```

### 各厂商必须做的「申请」工作（不申请就静音/折叠/限频）

国内厂商对“营销类”消息默认折叠、静音、限频，要出声音和悬浮，必须把消息归到**通讯/服务类高优先级通道**，这通常需要在厂商后台申请资质：

| 厂商 | 要点 |
|------|------|
| 小米 | 后台申请「私信消息」类通道 id，普通 `channel_id` 会被归为「营销/资讯」折叠静音 |
| 华为/荣耀 | 申请「服务与通讯」自分类权益，`category=IM`、`importance=NORMAL`；否则归资讯类静音 |
| OPPO | 申请「IM/系统/通信」私信通道，配置 `channel_id`；公信通道有日限频且静音 |
| VIVO | 申请系统消息分类 `category`，未分类走运营消息会限频 |

> 这些是**厂商后台**的配置/申请，需要用对应厂商开发者账号操作，再把申请到的 `channel_id` / 分类填到极光后台对应厂商通道里。极光控制台「应用设置 → 推送设置 → Android 厂商通道」也要先把各厂商的 AppKey/Secret 填好并启用。

---

## 3. iOS —— payload 必须带 sound

```jsonc
"notification": {
  "ios": {
    "alert": { "title": "随心拍", "body": "你有一条新的群聊消息" },
    "sound": "default",        // ★ 不带这个字段，锁屏/后台都不会响
    "badge": "+1",
    "mutable-content": true
  }
}
```

`options` 里注意环境：

```jsonc
"options": {
  "apns_production": true   // 正式包 true，开发调试 Xcode 真机包 false（生产环境务必 true）
}
```

> ✅ **iOS 前台（重点）**：客户端用的 jpush_flutter 已默认开启「前台展示声音+横幅」，**App 端无需改动**。但 iOS 前台**只有收到「带 `alert`+`sound` 的通知体(notification)」才会响铃弹横幅**；如果前台只下发了**透传静默消息(message)**，iOS 前台不会响也不弹。
>
> ⚠️ **因此后端务必注意**：群聊是「透传(message) + 通知(notification)」双通道。要让 **iOS 前台**也有声音，对在线 iOS 设备必须**同时下发带 `alert` + `sound:"default"` 的 `notification`**，不能只发 `message` 透传。`notification` 与 `message` 在同一次 `/v3/push` 请求里一起带上即可（见第 4 节示例，已同时包含两者）。

---

## 4. 完整请求示例（/v3/push，组合在线 + 厂商 + iOS）

```jsonc
{
  "platform": ["android", "ios"],
  "audience": { "registration_id": ["<目标设备 RID>"] },
  "notification": {
    "android": {
      "alert": "你有一条新的群聊消息",
      "title": "随心拍",
      "priority": 2,
      "alert_type": 7,
      "channel_id": "im_message",
      "sound": "default"
    },
    "ios": {
      "alert": { "title": "随心拍", "body": "你有一条新的群聊消息" },
      "sound": "default",
      "badge": "+1",
      "mutable-content": true
    }
  },
  "message": {              // 透传（前台实时刷新用，App 已依赖，保持原样）
    "msg_content": "...",
    "content_type": "...",
    "extras": { "action": "open_part_time_comment", "task_id": 123, "message_id": 456 }
  },
  "options": {
    "apns_production": true,
    "third_party_channel": {
      "xiaomi": { "distribution": "secondary_push", "channel_id": "im_message" },
      "huawei": { "distribution": "secondary_push", "importance": "NORMAL", "category": "IM", "channel_id": "im_message" },
      "honor":  { "distribution": "secondary_push", "importance": "NORMAL" },
      "oppo":   { "distribution": "secondary_push", "channel_id": "im_message" },
      "vivo":   { "distribution": "secondary_push", "category": "IM", "push_mode": 0 },
      "fcm":    { "distribution": "ohter_push" }
    }
  }
}
```

> 注：`extras` 里的 `action`/`task_id`/`message_id` 是 App 现有跳转协议字段，**不要改**，否则点击跳转会失效。

---

## 5. 验证清单

按链路逐个验，别只测一种状态：

1. **iOS 后台/锁屏**：有声音 + 横幅。（前台静默是预期）
2. **Android 在线（App 在前台/后台挂着，未被杀）**：有声音 + 悬浮横幅。
3. **Android 离线（App 划掉/杀进程）**：逐个真机厂商测 —— 小米、华为、OPPO、VIVO 各一台，确认有声音 + 悬浮，不被折叠。
4. 若某厂商无声/不弹 → 99% 是该厂商通道的「通知分类/channel 资质」没申请到位，回到第 2 节对应厂商排查。

---

## 6. 易变字段提醒

极光厂商通道字段（`importance`/`category`/`distribution` 取值、各厂商是否支持 `channel_id`）会随极光 SDK 与厂商政策更新，**以极光官方最新「第三方厂商通道 REST API」文档为准**。本说明给出的是当前通用配置方向。

/// 群聊会话标识（会话类型 + 业务 ID）
///
/// 后端 `/v1/parttime_task/chat/*` 用 `conv_type` 区分会话类型，`task_id` 复用为
/// 三种业务 ID：
/// - `conv_type=1`（默认）任务群 → `task_id` = 兼职任务 ID
/// - `conv_type=2` 科室群     → `task_id` = 科室 ID
/// - `conv_type=3` 私聊       → `task_id` = 私聊会话 ID（private/open 返回）
///
/// 三种 ID 来自不同表，**必然会撞号**（科室 45 / 任务 45 / 私聊会话 45 可以同时
/// 存在），所以凡是「作为唯一键」的地方（活跃会话集合、已读/新消息广播、sqlite
/// 查询条件）都必须用本类而不是裸 `taskId`，否则会串会话、串红点。
class ChatTarget {
  /// 1=任务群 2=科室群 3=私聊
  final int convType;

  /// 任务 ID（任务群）/ 科室 ID（科室群）/ 私聊会话 ID（私聊）
  final int taskId;

  const ChatTarget({required this.convType, required this.taskId});

  const ChatTarget.task(this.taskId) : convType = 1;
  const ChatTarget.department(this.taskId) : convType = 2;
  const ChatTarget.private(this.taskId) : convType = 3;

  /// 未知/缺省 conv_type 按任务群处理（与后端"不传即任务群"一致）
  factory ChatTarget.of(int? convType, int taskId) => ChatTarget(
    convType: (convType == 2 || convType == 3) ? convType! : 1,
    taskId: taskId,
  );

  /// 任务群。注意必须是精确 `==1`：科室群与私聊都不是任务群，
  /// 用「非科室群」判定会把私聊误认成任务群（污染任务上下文缓存、误清任务红点）。
  bool get isTask => convType == 1;
  bool get isDepartment => convType == 2;
  bool get isPrivate => convType == 3;

  @override
  bool operator ==(Object other) =>
      other is ChatTarget &&
      other.convType == convType &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(convType, taskId);

  @override
  String toString() => 'ChatTarget($convType:$taskId)';
}

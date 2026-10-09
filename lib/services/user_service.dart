import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/models/collected_material_item.dart';
import 'package:yatai_hub/models/upload_history.dart';
import 'package:yatai_hub/services/api_client.dart';
import 'package:yatai_hub/services/route_settings_service.dart';

/// 收藏列表返回结果
class CollectListResult {
  final List<CollectedMaterialItem> items;
  final int count;

  CollectListResult({required this.items, required this.count});
}

/// 用户服务 - 单例模式
class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  bool _hasSuccessfulUserInfoInit = false;
  Future<bool>? _initUserInfoFuture;

  // 缓存键
  static const String _keyUserId = 'uid';
  static const String _keyUsername = 'username';
  static const String _keyUserAvatar = 'user_avatar';
  static const String _keyUserDepartment = 'user_department';
  static const String _keyUserDepartmentId = 'user_department_id';
  static const String _keyUserCenter = 'user_center_cache';
  static const String _keyScheduleFlag = 'schedule_flag';
  static const String _keyKefuFlag = 'kefu_flag';
  static const String _keyBackendUserId = 'user_backend_id';
  static const String _keySiteId = 'user_siteid';
  static const String _keyIsAdmin = 'user_is_admin';
  static const String _keyBdFlag = 'bd_flag';
  static const String _keyRoleId = 'user_role_id';
  static const String _keyDisabled = 'user_disabled';
  static const String _keyParttimeAuditStatus = 'parttime_audit_status';
  static const String _keyParttimeDisableReason = 'parttime_disable_reason';
  static const String _keyFollowUpFlag = 'follow_up_flag';
  static const String _keyRequireAttendanceWifi = 'require_attendance_wifi';

  /// 兼职用户的 roleid
  static const int rolePartTime = 275;

  /// 获取主客户端（使用 ApiClient 的 Dio 实例）
  Dio get _mainClient => ApiClient().dio;

  // ==================== 用户信息缓存 ====================

  /// 获取后端用户ID（getUserInfo 返回的 userid 字段）
  Future<String?> getBackendUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBackendUserId);
  }

  /// 保存后端用户ID
  Future<void> saveBackendUserId(String backendUserId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBackendUserId, backendUserId);
  }

  /// 获取用户ID
  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  /// 保存用户ID
  Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
  }

  /// 获取用户名
  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  /// 保存用户名
  Future<void> saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
  }

  /// 获取用户头像
  Future<String?> getUserAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserAvatar);
  }

  /// 保存用户头像
  Future<void> saveUserAvatar(String avatar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserAvatar, avatar);
  }

  /// 获取用户部门
  Future<String?> getUserDepartment() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserDepartment);
  }

  /// 保存用户部门
  Future<void> saveUserDepartment(String department) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserDepartment, department);
  }

  /// 获取用户部门ID
  Future<int?> getUserDepartmentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyUserDepartmentId);
  }

  /// 保存用户部门ID
  Future<void> saveUserDepartmentId(int depId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUserDepartmentId, depId);
  }

  /// 获取日程标志
  Future<int> getScheduleFlag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyScheduleFlag) ?? 0;
  }

  /// 保存日程标志
  Future<void> saveScheduleFlag(int scheduleFlag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyScheduleFlag, scheduleFlag);
  }

  /// 获取客服标志（1=客服角色，0=普通角色）
  Future<int> getKefuFlag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyKefuFlag) ?? 0;
  }

  /// 保存客服标志
  Future<void> saveKefuFlag(int kefuFlag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyKefuFlag, kefuFlag);
  }

  /// 获取 SiteId
  Future<int> getSiteId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keySiteId) ?? 0;
  }

  /// 保存 SiteId
  Future<void> saveSiteId(int siteId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySiteId, siteId);
  }

  /// 获取 isAdmin
  Future<int> getIsAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyIsAdmin) ?? 0;
  }

  /// 保存 isAdmin
  Future<void> saveIsAdmin(int isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIsAdmin, isAdmin);
  }

  /// 获取角色 ID（兼职用户=275）
  Future<int> getRoleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyRoleId) ?? 0;
  }

  /// 保存角色 ID
  Future<void> saveRoleId(int roleId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRoleId, roleId);
  }

  /// 是否兼职用户
  Future<bool> isPartTimeUser() async {
    return (await getRoleId()) == rolePartTime;
  }

  /// 获取账号审核状态（0=已通过，1=待审核）
  Future<int> getDisabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDisabled) ?? 0;
  }

  /// 保存账号审核状态
  Future<void> saveDisabled(int disabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDisabled, disabled);
  }

  /// 获取兼职审核状态（0=待审核 / 1=已通过 / 2=已驳回）
  Future<int> getParttimeAuditStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyParttimeAuditStatus) ?? 0;
  }

  /// 保存兼职审核状态
  Future<void> saveParttimeAuditStatus(int status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyParttimeAuditStatus, status);
  }

  /// 获取停用原因（仅「已通过+已停用」时非空）
  Future<String> getParttimeDisableReason() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyParttimeDisableReason) ?? '';
  }

  /// 保存停用原因
  Future<void> saveParttimeDisableReason(String reason) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyParttimeDisableReason, reason);
  }

  /// 是否兼职用户且被后端拦截（roleid==275 && disabled==1）。
  ///
  /// disabled==1 涵盖三种业务状态：待审核 / 已驳回 / 已通过后被停用，
  /// 统一落地到 [PartTimePendingPage]，由其依据 parttime_audit_status 区分展示。
  Future<bool> isPartTimePendingReview() async {
    if (!await isPartTimeUser()) return false;
    return (await getDisabled()) == 1;
  }

  /// 强制重新拉取 getUserInfo（绕过已初始化缓存），用于运行时检测停用等状态变化。
  Future<bool> refreshUserInfo() async {
    resetUserInfoInitState();
    return initUserInfo();
  }

  /// 修改昵称/头像（POST /v1/user/profile），两者至少传一个
  ///
  /// 成功后用后端返回的生效值同步本地缓存（username / avatar），
  /// 返回 (是否成功, 提示消息)。
  Future<(bool, String)> updateProfile({
    String? nickname,
    String? avatar,
  }) async {
    try {
      final body = <String, dynamic>{'nickname': ?nickname, 'avatar': ?avatar};
      final response = await _mainClient.post('/v1/user/profile', data: body);
      final data = response.data;
      if (data is Map && data['code'] == 0) {
        final result = data['data'];
        if (result is Map) {
          final newNickname = result['nickname']?.toString() ?? '';
          final newAvatar = result['avatar']?.toString() ?? '';
          if (newNickname.isNotEmpty) await saveUsername(newNickname);
          if (newAvatar.isNotEmpty) await saveUserAvatar(newAvatar);
        }
        return (true, data['msg']?.toString() ?? '修改成功');
      }
      return (
        false,
        data is Map ? (data['msg']?.toString() ?? '修改失败') : '修改失败',
      );
    } on DioException catch (e) {
      // 422 参数校验错误：从响应体提取提示
      final respData = e.response?.data;
      if (respData is Map) {
        final msg = respData['msg'];
        if (msg is String && msg.isNotEmpty) return (false, msg);
        if (respData['detail'] != null) return (false, '参数格式错误，请检查输入');
      }
      if (kDebugMode) print('修改昵称/头像失败: $e');
      return (false, '修改失败，请稍后重试');
    } catch (e) {
      if (kDebugMode) print('修改昵称/头像失败: $e');
      return (false, '修改失败，请稍后重试');
    }
  }

  /// 获取 bdFlag（1=BD角色，可查看医院资料）
  Future<int> getBdFlag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBdFlag) ?? 0;
  }

  /// 保存 bdFlag
  Future<void> saveBdFlag(int bdFlag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBdFlag, bdFlag);
  }

  /// 获取 followUpFlag（1=跟进角色，可查看跟进模块）
  Future<int> getFollowUpFlag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyFollowUpFlag) ?? 0;
  }

  /// 保存 followUpFlag
  Future<void> saveFollowUpFlag(int followUpFlag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyFollowUpFlag, followUpFlag);
  }

  /// 是否需要 WiFi 验证才能打卡（dispatch_departments 中含 id=115 时为 true）
  Future<bool> getRequireAttendanceWifi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRequireAttendanceWifi) ?? false;
  }

  Future<void> saveRequireAttendanceWifi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRequireAttendanceWifi, value);
  }

  /// 保存用户基本信息
  Future<void> saveUserBasicInfo({
    required String userId,
    required String username,
    required String avatar,
    required String department,
    int? departmentId,
  }) async {
    final futures = [
      saveUserId(userId),
      saveUsername(username),
      saveUserAvatar(avatar),
      saveUserDepartment(department),
    ];

    if (departmentId != null) {
      futures.add(saveUserDepartmentId(departmentId));
    }

    await Future.wait(futures);
  }

  /// 获取isChina标志（用于判断国内外线路）
  /// 现在从 RouteSettingsService 读取浏览线路
  Future<bool> getIsChina() async {
    try {
      final RouteSettingsService routeSettings = RouteSettingsService();
      final browseRoute = await routeSettings.getBrowseRoute();
      return browseRoute == RouteSettingsService.routeDomestic;
    } catch (e) {
      if (kDebugMode) print('获取线路信息失败: $e');
      return true; // 默认国内
    }
  }

  /// 保存isChina标志
  /// 现在通过 RouteSettingsService 保存浏览线路
  Future<void> saveIsChina(bool isChina) async {
    try {
      final RouteSettingsService routeSettings = RouteSettingsService();
      final route = isChina
          ? RouteSettingsService.routeDomestic
          : RouteSettingsService.routeOverseas;
      await routeSettings.setBrowseRoute(route);
    } catch (e) {
      if (kDebugMode) print('保存线路信息失败: $e');
    }
  }

  /// 清除用户信息缓存
  Future<void> clearUserCache() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyUserId),
      prefs.remove(_keyUsername),
      prefs.remove(_keyUserAvatar),
      prefs.remove(_keyUserDepartment),
      prefs.remove(_keyUserDepartmentId),
      prefs.remove(_keyUserCenter),
      prefs.remove(_keyScheduleFlag),
      prefs.remove(_keyKefuFlag),
      prefs.remove(_keyBackendUserId),
      prefs.remove(_keySiteId),
      prefs.remove(_keyIsAdmin),
      prefs.remove(_keyBdFlag),
      prefs.remove(_keyRoleId),
      prefs.remove(_keyDisabled),
      prefs.remove(_keyParttimeAuditStatus),
      prefs.remove(_keyParttimeDisableReason),
      prefs.remove(_keyFollowUpFlag),
    ]);
    resetUserInfoInitState();
  }

  /// 重置用户信息初始化状态（用于登出或切换账号后重新拉取）
  void resetUserInfoInitState() {
    _hasSuccessfulUserInfoInit = false;
    _initUserInfoFuture = null;
  }

  // ==================== API 调用 ====================

  /// 初始化用户信息（从服务器获取基本用户信息）
  /// 对应 uni-app 的 /v1/casually/getUserInfo 接口
  Future<bool> initUserInfo() async {
    // 成功后不再重复请求，避免启动阶段被多个页面重复触发
    if (_hasSuccessfulUserInfoInit) {
      return true;
    }

    // 并发场景复用同一个请求，避免同一时刻发起多次 getUserInfo
    if (_initUserInfoFuture != null) {
      return _initUserInfoFuture!;
    }

    _initUserInfoFuture = _doInitUserInfo();
    final result = await _initUserInfoFuture!;
    _initUserInfoFuture = null;
    return result;
  }

  Future<bool> _doInitUserInfo() async {
    try {
      final response = await _mainClient.post('/v1/casually/getUserInfo');

      if (kDebugMode) {
        print('getUserInfo 响应: ${response.data}');
      }

      // 解析响应数据（可能是字符串或Map）
      Map<String, dynamic>? jsonData;
      if (response.data is String) {
        try {
          jsonData = jsonDecode(response.data);
        } catch (e) {
          if (kDebugMode) print('JSON解析失败: $e');
        }
      } else if (response.data is Map) {
        jsonData = Map<String, dynamic>.from(response.data);
      }

      if (jsonData == null) {
        if (kDebugMode) print('响应数据格式错误');
        return false;
      }

      // 检查返回码（兼容字符串"1"和数字0/1）
      final code = jsonData['code'];
      final isSuccess = code == '1' || code == 1 || code == '0' || code == 0;

      if (isSuccess && jsonData['data'] != null) {
        final data = jsonData['data'];

        if (kDebugMode) {
          print('用户数据: $data');
        }

        // 提取用户信息
        final String backendUserId = data['userid']?.toString() ?? '';
        final String userId = data['ding_userid']?.toString() ?? '';
        final String username = data['name']?.toString() ?? '';
        final String avatar = data['avatar']?.toString() ?? '';
        final String department = data['department_name']?.toString() ?? '';
        final int? depId = data['dep_id'] is int
            ? data['dep_id']
            : (data['dep_id'] != null
                  ? int.tryParse(data['dep_id'].toString())
                  : null);
        final int scheduleFlag = data['schedule_flag'] is int
            ? data['schedule_flag']
            : (data['schedule_flag'] != null
                  ? int.tryParse(data['schedule_flag'].toString()) ?? 0
                  : 0);
        final int kefuFlag = data['kefu_flag'] is int
            ? data['kefu_flag']
            : (data['kefu_flag'] != null
                  ? int.tryParse(data['kefu_flag'].toString()) ?? 0
                  : 0);
        final int siteId = data['siteid'] is int
            ? data['siteid']
            : (data['siteid'] != null
                  ? int.tryParse(data['siteid'].toString()) ?? 0
                  : 0);
        final int isAdmin = data['is_admin'] is int
            ? data['is_admin']
            : (data['is_admin'] != null
                  ? int.tryParse(data['is_admin'].toString()) ?? 0
                  : 0);
        final int bdFlag = data['bd_flag'] is int
            ? data['bd_flag']
            : (data['bd_flag'] != null
                  ? int.tryParse(data['bd_flag'].toString()) ?? 0
                  : 0);
        final int roleId = data['roleid'] is int
            ? data['roleid']
            : (data['roleid'] != null
                  ? int.tryParse(data['roleid'].toString()) ?? 0
                  : 0);
        final int disabled = data['disabled'] is int
            ? data['disabled']
            : (data['disabled'] != null
                  ? int.tryParse(data['disabled'].toString()) ?? 0
                  : 0);
        final int followUpFlag = data['follow_up_flag'] is int
            ? data['follow_up_flag']
            : (data['follow_up_flag'] != null
                  ? int.tryParse(data['follow_up_flag'].toString()) ?? 0
                  : 0);
        // 兼职审核状态：disabled=1 不再唯一等于「待审核」，需结合此字段区分
        // 待审核(0) / 已通过(1) / 已驳回(2)；已通过+disabled=1 即「已停用」
        final int parttimeAuditStatus = data['parttime_audit_status'] is int
            ? data['parttime_audit_status']
            : (data['parttime_audit_status'] != null
                  ? int.tryParse(data['parttime_audit_status'].toString()) ?? 0
                  : 0);
        final String parttimeDisableReason =
            data['parttime_disable_reason']?.toString() ?? '';

        if (kDebugMode) {
          print(
            '解析到 userId: $userId, username: $username, depId: $depId, scheduleFlag: $scheduleFlag, kefuFlag: $kefuFlag, siteId: $siteId, isAdmin: $isAdmin, bdFlag: $bdFlag, roleId: $roleId, disabled: $disabled, followUpFlag: $followUpFlag',
          );
        }

        // 保存到本地缓存
        await saveUserBasicInfo(
          userId: userId,
          username: username,
          avatar: avatar,
          department: department,
          departmentId: depId,
        );

        // 保存后端用户ID
        if (backendUserId.isNotEmpty) {
          await saveBackendUserId(backendUserId);
        }

        // 保存日程标志
        await saveScheduleFlag(scheduleFlag);

        // 保存客服标志
        await saveKefuFlag(kefuFlag);

        // 保存 siteid
        await saveSiteId(siteId);

        // 保存 isAdmin
        await saveIsAdmin(isAdmin);

        // 保存 bdFlag
        await saveBdFlag(bdFlag);
        // 保存角色 ID（用于兼职用户判定）
        await saveRoleId(roleId);

        // 保存账号审核状态（兼职用户拦截依据：待审核/已驳回/已停用 均为 1）
        await saveDisabled(disabled);
        // 保存兼职审核状态 + 停用原因（用于区分停用态与待审核/驳回）
        await saveParttimeAuditStatus(parttimeAuditStatus);
        await saveParttimeDisableReason(parttimeDisableReason);
        // 保存 followUpFlag
        await saveFollowUpFlag(followUpFlag);

        // 解析 dispatch_departments，id=115 表示需要 WiFi 验证打卡
        final dispatchDepts = data['dispatch_departments'];
        final requireWifi =
            dispatchDepts is List &&
            dispatchDepts.any(
              (d) => (d is Map) && (d['id'] as num?)?.toInt() == 115,
            );
        await saveRequireAttendanceWifi(requireWifi);

        _hasSuccessfulUserInfoInit = true;
        return true;
      } else {
        if (kDebugMode) print('getUserInfo 返回失败: code=$code');
        return false;
      }
    } catch (e) {
      if (kDebugMode) print('初始化用户信息失败: $e');
      return false;
    }
  }

  /// 获取收藏列表
  Future<CollectListResult> getCollectList({
    required int page,
    required int pageSize,
    String type = 'all',
    String fileSort = 'all',
    String fileSuffix = '',
    String materialCategory = '',
    String countryType = '',
  }) async {
    try {
      final bool isChina = await getIsChina();
      final response = await _mainClient.get(
        '/v1/casually/collect_list',
        queryParameters: {
          'page': page.toString(),
          'page_size': pageSize.toString(),
          'type': type,
          'file_sort': fileSort,
          'file_suffix': fileSuffix,
          'material_category': materialCategory,
          'country_type': countryType,
          'is_domestic': isChina ? 1 : 0,
        },
      );

      if (response.data['code'] == 0 &&
          response.data['data'] != null &&
          response.data['data']['data'] != null &&
          response.data['data']['data']['list'] != null) {
        final List<dynamic> list = response.data['data']['data']['list'];
        final items = list
            .map((item) => CollectedMaterialItem.fromJson(item))
            .toList();

        // 从同一个响应中获取总数
        int count = 0;
        final countValue = response.data['data']['count'];
        if (countValue is int) {
          count = countValue;
        } else if (countValue is String) {
          count = int.tryParse(countValue) ?? 0;
        }

        return CollectListResult(items: items, count: count);
      }
      return CollectListResult(items: [], count: 0);
    } catch (e) {
      if (kDebugMode) print('获取收藏列表失败: $e');
      // 网络错误时重新抛出异常，让调用方能够区分网络错误和正常空数据
      rethrow;
    }
  }

  /// 切换收藏状态
  /// [kclId] 素材ID
  Future<bool> toggleCollect(int kclId) async {
    try {
      final response = await _mainClient.post(
        '/v1/casually/toggle_collect',
        data: {'kcl_id': kclId},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('切换收藏状态失败: $e');
      return false;
    }
  }

  /// 获取上传历史
  Future<List<UploadHistoryDateGroup>> getUploadHistory({
    required int page,
    required int pageSize,
    String text = '',
    String time = '',
    int flag = 1,
    String activityStartTime = '',
    String activityEndTime = '',
    int materialCategory = 0,
    int? isDomestic,
  }) async {
    try {
      // 如果未指定 isDomestic，从 RouteSettingsService 读取浏览线路
      int finalIsDomestic = isDomestic ?? 1; // 默认国内
      if (isDomestic == null) {
        try {
          final RouteSettingsService routeSettings = RouteSettingsService();
          finalIsDomestic = await routeSettings.getBrowseRoute();
        } catch (e) {
          if (kDebugMode) print('获取浏览线路失败，使用默认值: $e');
        }
      }

      final response = await _mainClient.post(
        '/v1/casually/upload_history_new',
        data: {
          'page': page,
          'page_size': pageSize,
          'text': text,
          'time': time,
          'flag': flag,
          'activity_start_time': activityStartTime,
          'activity_end_time': activityEndTime,
          'material_category': materialCategory,
          'is_domestic': finalIsDomestic,
        },
      );

      if (response.data['code'] == 0 && response.data['data'] != null) {
        final data = response.data['data'];
        if (data['data'] != null && data['data'] is List) {
          final List<dynamic> list = data['data'];
          return list
              .map((item) => UploadHistoryDateGroup.fromJson(item))
              .toList();
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('获取上传历史失败: $e');
      // 网络错误时重新抛出异常，让调用方能够区分网络错误和正常空数据
      rethrow;
    }
  }

  /// 获取上传历史总数
  Future<int> getUploadHistoryCount({
    String text = '',
    String time = '',
    int flag = 1,
    String activityStartTime = '',
    String activityEndTime = '',
    int materialCategory = 0,
    int? isDomestic,
  }) async {
    try {
      // 如果未指定 isDomestic，从 RouteSettingsService 读取浏览线路
      int finalIsDomestic = isDomestic ?? 1; // 默认国内
      if (isDomestic == null) {
        try {
          final RouteSettingsService routeSettings = RouteSettingsService();
          finalIsDomestic = await routeSettings.getBrowseRoute();
        } catch (e) {
          if (kDebugMode) print('获取浏览线路失败，使用默认值: $e');
        }
      }

      final response = await _mainClient.post(
        '/v1/casually/upload_history_new',
        data: {
          'page': 1,
          'page_size': 1,
          'text': text,
          'time': time,
          'flag': flag,
          'activity_start_time': activityStartTime,
          'activity_end_time': activityEndTime,
          'material_category': materialCategory,
          'is_domestic': finalIsDomestic,
        },
      );

      if (response.data['code'] == 0 && response.data['data'] != null) {
        final count = response.data['data']['count'];
        if (count is int) return count;
        if (count is String) return int.tryParse(count) ?? 0;
        return 0;
      }
      return 0;
    } catch (e) {
      if (kDebugMode) print('获取上传历史总数失败: $e');
      return 0;
    }
  }

  /// 删除单个上传素材
  /// [id] 素材ID
  /// [casuallyId] 上传记录ID
  Future<bool> deleteUploadMaterial({
    required int id,
    required int casuallyId,
  }) async {
    try {
      final response = await _mainClient.post(
        '/v1/casually/delete_upload_one',
        data: {'id': id, 'casually_id': casuallyId},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('删除上传素材失败: $e');
      return false;
    }
  }

  /// 删除整个上传记录（包含所有素材）
  /// [id] 上传记录ID
  Future<bool> deleteUploadRecord(int id) async {
    try {
      final response = await _mainClient.post(
        '/v1/casually/delete_upload_all',
        data: {'id': id},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('删除上传记录失败: $e');
      return false;
    }
  }

  /// 批量删除上传素材
  /// [ids] 素材ID列表（逗号分隔的字符串）
  Future<bool> deleteBatchUploadMaterials(String ids) async {
    try {
      final response = await _mainClient.post(
        '/v1/casually/delete_upload_one',
        data: {'id': ids},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('批量删除上传素材失败: $e');
      return false;
    }
  }

  /// 更新素材浏览量
  /// [id] 素材ID
  Future<bool> updateShowCount(int id) async {
    try {
      final response = await _mainClient.post(
        '/v1/casually/update_show_count',
        data: {'id': id},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('更新浏览量失败: $e');
      return false;
    }
  }

  /// 更新素材下载量
  /// [id] 素材ID
  Future<bool> updateDownloadCount(int id) async {
    try {
      final response = await _mainClient.post(
        '/v1/casually/update_download_count',
        data: {'id': id},
      );

      return response.data['code'] == 0;
    } catch (e) {
      if (kDebugMode) print('更新下载量失败: $e');
      return false;
    }
  }
}

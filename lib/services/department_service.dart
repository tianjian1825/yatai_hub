import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yatai_hub/models/department.dart';
import 'package:yatai_hub/services/material_api.dart';

/// 部门服务 - 单例模式
/// 负责管理部门列表的获取和缓存
class DepartmentService {
  static final DepartmentService _instance = DepartmentService._internal();
  factory DepartmentService() => _instance;
  DepartmentService._internal();

  // 缓存键
  static const String _keyDepartments = 'cached_departments';
  static const String _keyDepartmentsTimestamp = 'cached_departments_timestamp';

  // 缓存有效期：7天（单位：毫秒）
  static const int _cacheValidDuration = 7 * 24 * 60 * 60 * 1000;

  // 内存缓存
  List<Department>? _departments;

  /// 获取部门列表
  /// [forceRefresh] 是否强制从服务器刷新
  Future<List<Department>> getDepartments({bool forceRefresh = false}) async {
    // 如果内存中有缓存且不强制刷新，直接返回
    if (_departments != null && _departments!.isNotEmpty && !forceRefresh) {
      return _departments!;
    }

    // 尝试从本地缓存获取
    if (!forceRefresh) {
      final cached = await _loadFromCache();
      if (cached != null && cached.isNotEmpty) {
        _departments = cached;
        return cached;
      }
    }

    // 从服务器获取
    try {
      final departments = await MaterialApi.getDepartments();
      if (departments.isNotEmpty) {
        _departments = departments;
        await _saveToCache(departments);
      }
      return departments;
    } catch (e) {
      if (kDebugMode) print('获取部门列表失败: $e');
      // 如果获取失败，尝试返回本地缓存（即使过期）
      final cached = await _loadFromCache(ignoreExpiration: true);
      if (cached != null && cached.isNotEmpty) {
        _departments = cached;
        return cached;
      }
      return [];
    }
  }

  /// 根据部门ID列表获取部门名称列表
  /// [departmentIds] 部门ID字符串，如 "26,18"
  Future<List<String>> getDepartmentNames(String? departmentIds) async {
    if (departmentIds == null || departmentIds.isEmpty) {
      return [];
    }

    final departments = await getDepartments();
    final ids = departmentIds
        .split(',')
        .map((id) => int.tryParse(id.trim()))
        .where((id) => id != null)
        .toList();

    return departments
        .where((dept) => ids.contains(dept.id))
        .map((dept) => dept.displayName)
        .toList();
  }

  /// 根据部门ID获取部门对象
  Future<Department?> getDepartmentById(int id) async {
    final departments = await getDepartments();
    try {
      return departments.firstWhere((dept) => dept.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 从本地缓存加载
  /// [ignoreExpiration] 是否忽略过期时间
  Future<List<Department>?> _loadFromCache({
    bool ignoreExpiration = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查缓存是否过期
      if (!ignoreExpiration) {
        final timestamp = prefs.getInt(_keyDepartmentsTimestamp) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - timestamp > _cacheValidDuration) {
          return null; // 缓存过期
        }
      }

      final jsonStr = prefs.getString(_keyDepartments);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list.map((item) => Department.fromJson(item)).toList();
      }
    } catch (e) {
      if (kDebugMode) print('从缓存加载部门列表失败: $e');
    }
    return null;
  }

  /// 保存到本地缓存
  Future<void> _saveToCache(List<Department> departments) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(
        departments.map((dept) => dept.toJson()).toList(),
      );
      await prefs.setString(_keyDepartments, jsonStr);
      await prefs.setInt(
        _keyDepartmentsTimestamp,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      if (kDebugMode) print('保存部门列表到缓存失败: $e');
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    _departments = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDepartments);
    await prefs.remove(_keyDepartmentsTimestamp);
  }

  /// 预加载部门列表（用于app启动时）
  Future<void> preload() async {
    try {
      await getDepartments();
    } catch (e) {
      if (kDebugMode) print('部门列表预加载失败: $e');
    }
  }
}

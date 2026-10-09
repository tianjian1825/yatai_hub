import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/persisted_task.dart';
import 'upload_queue_manager.dart' show UploadTaskStatus;

/// 任务持久化仓库
/// 负责保存和加载上传任务到 SharedPreferences
class TaskPersistenceRepository {
  // 单例模式
  static final TaskPersistenceRepository _instance =
      TaskPersistenceRepository._internal();

  factory TaskPersistenceRepository() => _instance;

  TaskPersistenceRepository._internal();

  /// 存储键
  static const String _storageKey = 'upload_tasks_v1';

  /// 保存任务列表
  ///
  /// [tasks] 要保存的任务列表
  /// 失败时记录日志但不抛出异常（防御式编程）
  Future<void> saveTasks(List<PersistedTask> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 序列化任务列表为JSON
      final jsonList = tasks.map((task) => task.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      // 保存到SharedPreferences
      await prefs.setString(_storageKey, jsonString);

      // if (kDebugMode) {
      //   print('[持久化] 保存了 ${tasks.length} 个任务');
      // }
    } catch (e) {
      // 保存失败时记录日志，但不抛出异常
      if (kDebugMode) {
        print('[持久化] 保存任务失败: $e');
      }
    }
  }

  /// 加载任务列表
  ///
  /// 返回验证后的任务列表（已过滤Web任务、已验证文件存在）
  /// 失败时返回空列表（不抛出异常）
  Future<List<PersistedTask>> loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        if (kDebugMode) {
          print('[持久化] 没有找到已保存的任务');
        }
        return [];
      }

      // 反序列化JSON
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final tasks = jsonList
          .map((json) => PersistedTask.fromJson(json as Map<String, dynamic>))
          .toList();

      if (kDebugMode) {
        print('[持久化] 加载了 ${tasks.length} 个任务');
      }

      // 验证和过滤任务
      final validTasks = <PersistedTask>[];

      for (final task in tasks) {
        // 1. 过滤不应该显示的任务（超过5天等）
        if (!task.shouldDisplay()) {
          continue;
        }

        // 2. 验证文件是否存在（仅对需要继续上传的任务）
        // 已完成的任务不需要验证本地文件
        if (task.localPath.isNotEmpty && task.isResumable()) {
          final fileExists = await _validateTaskFile(task);
          if (!fileExists) {
            continue;
          }
        }

        validTasks.add(task);
      }

      // 清理旧任务
      await _cleanupOldTasks(validTasks);

      if (kDebugMode) {
        print('[持久化] 验证后剩余 ${validTasks.length} 个有效任务');
      }

      return validTasks;
    } catch (e) {
      // 加载失败时返回空列表
      if (kDebugMode) {
        print('[持久化] 加载任务失败: $e');
        print('[持久化] 清空损坏的缓存');
      }

      // 清空损坏的缓存
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_storageKey);
      } catch (e) {
        // 忽略清空错误
      }

      return [];
    }
  }

  /// 验证任务文件是否存在
  ///
  /// [task] 要验证的任务
  /// 返回 true 如果文件存在，否则返回 false
  Future<bool> _validateTaskFile(PersistedTask task) async {
    if (task.localPath.isEmpty) {
      return false;
    }

    try {
      final file = File(task.localPath);
      return await file.exists();
    } catch (e) {
      if (kDebugMode) {
        print('[持久化] 验证文件失败: ${task.localPath} - $e');
      }
      return false;
    }
  }

  /// 清理旧任务
  ///
  /// 移除超过5天的非完成状态任务，已完成的任务保留（用户可能需要后续提交）
  /// [tasks] 当前任务列表
  Future<void> _cleanupOldTasks(List<PersistedTask> tasks) async {
    try {
      final now = DateTime.now();
      final tasksToKeep = <PersistedTask>[];
      int removedCount = 0;

      for (final task in tasks) {
        final age = now.difference(task.createdAt).inDays;

        // 已完成的任务始终保留
        if (task.status == UploadTaskStatus.completed) {
          tasksToKeep.add(task);
        } else if (age >= 5) {
          // 非完成状态超过5天的任务清理
          removedCount++;
        } else {
          tasksToKeep.add(task);
        }
      }

      if (removedCount > 0) {
        // 保存清理后的任务列表
        tasks.clear();
        tasks.addAll(tasksToKeep);

        final prefs = await SharedPreferences.getInstance();
        if (tasksToKeep.isEmpty) {
          await prefs.remove(_storageKey);
        } else {
          final jsonList = tasksToKeep.map((task) => task.toJson()).toList();
          final jsonString = jsonEncode(jsonList);
          await prefs.setString(_storageKey, jsonString);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[持久化] 清理旧任务失败: $e');
      }
    }
  }

  /// 删除单个任务
  ///
  /// [taskId] 要删除的任务ID
  Future<void> deleteTask(String taskId) async {
    try {
      final tasks = await loadTasks();
      final updatedTasks = tasks
          .where((task) => task.taskId != taskId)
          .toList();

      if (updatedTasks.length != tasks.length) {
        await saveTasks(updatedTasks);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[持久化] 删除任务失败: $taskId - $e');
      }
    }
  }

  /// 清空所有任务
  Future<void> clearAllTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      if (kDebugMode) {
        print('[持久化] 清空任务失败: $e');
      }
    }
  }
}

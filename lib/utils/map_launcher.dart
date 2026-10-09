import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yatai_hub/utils/overlay_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// 调用系统地图/导航应用打开指定地址
///
/// 优先用平台原生 scheme 直接拉起手机里的地图/导航 App（而非浏览器）：
/// - iOS：`https://maps.apple.com` 是 Apple 地图的 universal link，会被系统
///   直接路由到 Apple 地图 App。
/// - Android：`geo:` 触发 ACTION_VIEW 隐式 Intent，由系统弹出/调起默认地图
///   App（Google 地图、高德、百度等），不会落到浏览器。
/// 原生 scheme 都失败时，才回退到 Google 地图网页版。
///
/// [context] 仅用于失败时提示；调用方若已 dispose 请自行判断 mounted。
Future<void> openAddressInMap(BuildContext context, String address) async {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return;
  final query = Uri.encodeComponent(trimmed);
  final candidates = <Uri>[
    if (Platform.isIOS)
      Uri.parse('https://maps.apple.com/?q=$query')
    else
      Uri.parse('geo:0,0?q=$query'),
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
  ];
  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // 尝试下一个候选
    }
  }
  // 用浮层提示：调用方可能是底部弹窗内的地址行，SnackBar 会被弹窗挡住
  if (context.mounted) {
    showOverlayToast(context, '无法打开地图应用', icon: Icons.error_outline);
  }
}

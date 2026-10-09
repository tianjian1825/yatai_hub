import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yatai_hub/pages/privacy_policy_page.dart';

/// 隐私政策对话框
/// 不可关闭的对话框，用户必须同意才能继续使用应用
class PrivacyPolicyDialog extends StatelessWidget {
  const PrivacyPolicyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 禁止返回键关闭对话框
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              const Text(
                '隐私政策与用户协议',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 24),

              // 内容文字（带可点击链接）
              _buildContentText(context),
              const SizedBox(height: 32),

              // 按钮行
              Row(
                children: [
                  // 不同意按钮
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleDisagree(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('不同意', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 同意按钮
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF366CDF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        '同意',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建内容文字（带可点击的隐私政策链接）
  Widget _buildContentText(BuildContext context) {
    return RichText(
      textAlign: TextAlign.left,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 15,
          height: 1.6,
          color: Color(0xFF666666),
        ),
        children: [
          const TextSpan(
            text:
                '欢迎使用亚太HUB！我们非常重视您的隐私和个人信息保护。\n\n'
                '在使用我们的服务之前，请您仔细阅读',
          ),
          TextSpan(
            text: '《隐私政策》',
            style: const TextStyle(
              color: Color(0xFF366CDF),
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w500,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                // 打开隐私政策WebView页面
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrivacyPolicyPage(),
                  ),
                );
              },
          ),
          const TextSpan(
            text:
                '，了解我们如何收集、使用和保护您的信息。\n\n'
                '点击"同意"即表示您已阅读并同意遵守我们的隐私政策。',
          ),
        ],
      ),
    );
  }

  /// 处理用户点击"不同意"
  /// 显示二次确认对话框
  Future<void> _handleDisagree(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 确认对话框也不可通过点击外部关闭
      builder: (context) => PopScope(
        canPop: false, // 确认对话框也禁止返回键关闭
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            '无法继续使用',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            '您必须同意隐私政策才能使用本应用。\n\n'
            '点击"重新查看"可再次阅读隐私政策。',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Color(0xFF666666),
            ),
          ),
          actions: [
            // 退出应用按钮
            TextButton(
              onPressed: () {
                // 关闭确认对话框
                Navigator.of(context).pop(false);
                // 关闭主对话框
                Navigator.of(context).pop(false);
                // 退出应用
                SystemNavigator.pop();
              },
              child: Text(
                '退出应用',
                style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              ),
            ),
            // 重新查看按钮
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF366CDF),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              child: const Text('重新查看', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );

    // 如果用户选择"重新查看"，保持主对话框打开
    // 如果用户选择"退出应用"，应用会退出
    // shouldReview 为 true 时不做任何操作，保持主对话框打开
  }
}

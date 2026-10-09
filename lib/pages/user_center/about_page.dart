import 'package:flutter/material.dart';
import 'package:yatai_hub/app_info.dart';

/// 关于页面
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  // 应用信息
  static const String appName = '亚太HUB';
  static const String appVersion = AppInfo.version;
  static const String copyright = '© 2026 亚太HUB开发团队';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          '关于',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // 应用图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/app_logo_mark.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: const Color(0xFF366CDF),
                      child: const Icon(
                        Icons.photo_camera,
                        size: 50,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 应用名称
            const Text(
              appName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 40),
            // 应用信息卡片
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildInfoItem(
                    icon: Icons.verified,
                    title: '版本',
                    value: 'v$appVersion',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // 版权信息
            const Text(
              copyright,
              style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: const Color(0xFF366CDF)),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, color: Color(0xFF757575)),
          ),
        ],
      ),
    );
  }

}

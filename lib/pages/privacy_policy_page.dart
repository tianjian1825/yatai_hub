import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 隐私政策页面
/// 使用WebView展示完整的隐私政策内容
class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  // 隐私政策URL
  static const String _privacyPolicyUrl =
      'https://xinzhi.aimei.group/privacy_policy.html';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  /// 初始化WebView控制器
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            // 显示错误提示
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('加载失败: ${error.description}'),
                  backgroundColor: Colors.red[400],
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_privacyPolicyUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '隐私政策',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // WebView内容
          WebViewWidget(controller: _controller),

          // 加载指示器
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF366CDF)),
            ),
        ],
      ),
    );
  }
}

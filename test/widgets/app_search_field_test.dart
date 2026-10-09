import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatai_hub/widgets/app_search_field.dart';

void main() {
  testWidgets('搜索图标与输入文字纵向中线重合', (tester) async {
    final controller = TextEditingController(text: '测试输入');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AppSearchField(
              controller: controller,
              hintText: '请输入想搜索的内容',
              onSearch: () {},
            ),
          ),
        ),
      ),
    );

    final iconBox = tester.getRect(find.byIcon(Icons.search));
    final textBox = tester.getRect(find.byType(EditableText));

    expect(
      (iconBox.center.dy - textBox.center.dy).abs(),
      lessThan(0.5),
      reason: '图标中线 ${iconBox.center.dy} 与文字中线 ${textBox.center.dy} 应重合',
    );

    // 整体高度固定 40，避免各页面各写一套度量
    expect(tester.getSize(find.byType(AppSearchField)).height, 40);
  });

  testWidgets('enabled=false 时输入与搜索按钮同时禁用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSearchField(
            controller: TextEditingController(),
            hintText: '该分类不支持机构名搜索',
            enabled: false,
            onSearch: () {},
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, null);
  });

  testWidgets('showClear 有输入才出现清除按钮，点击清空并回调', (tester) async {
    final controller = TextEditingController();
    var cleared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSearchField(
            controller: controller,
            hintText: '搜索姓名',
            showClear: true,
            onClear: () => cleared = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close), findsNothing);

    await tester.enterText(find.byType(TextField), '张三');
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(controller.text, '');
    expect(cleared, true);
    expect(find.byIcon(Icons.close), findsNothing);
  });
}

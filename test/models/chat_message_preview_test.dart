import 'package:flutter_test/flutter_test.dart';
import 'package:yatai_hub/models/chat_message.dart';

/// `ChatMessage.conversationPreview` 与后端 `_conv_preview` / `_message_summary`
/// （kefu `parttime_task.php`）必须逐字一致：会话摘要由群聊页本地先行更新、再被
/// 网络刷新覆盖，两侧文案不同的话那一行会闪一下文字。
///
/// 期望值全部用后端逻辑实测过（图片在前、视频在后、空格分隔）。
void main() {
  ChatMessage msg({
    String content = '',
    List<String> images = const [],
    List<ChatMedia>? media,
    int msgType = 1,
    bool recalled = false,
  }) => ChatMessage(
    messageId: 1,
    taskId: 1,
    content: content,
    images: images,
    media: media,
    msgType: msgType,
    recalled: recalled,
  );

  const video = ChatMedia(url: 'http://n/a.mp4', isVideo: true);
  const video2 = ChatMedia(url: 'http://n/b.mov', isVideo: true);
  const image = ChatMedia(url: 'http://n/a.jpg');
  const image2 = ChatMedia(url: 'http://n/b.png');

  group('附件按类型计数', () {
    test('纯视频说「个视频」而不是「张图片」', () {
      expect(
        msg(images: ['http://n/a.mp4'], media: [video]).conversationPreview,
        '[1个视频]',
      );
      expect(
        msg(
          images: ['http://n/a.mp4', 'http://n/b.mov'],
          media: [video, video2],
        ).conversationPreview,
        '[2个视频]',
      );
    });

    test('纯图片沿用原文案', () {
      expect(
        msg(
          images: ['http://n/a.jpg', 'http://n/b.png'],
          media: [image, image2],
        ).conversationPreview,
        '[2张图片]',
      );
    });

    test('图片与视频混合时图片在前、空格分隔', () {
      expect(
        msg(
          images: ['http://n/a.jpg', 'http://n/b.png', 'http://n/a.mp4'],
          media: [image, image2, video],
        ).conversationPreview,
        '[2张图片] [1个视频]',
      );
    });

    test('有文字时附件后缀追加在文字之后', () {
      expect(
        msg(
          content: '看下这个',
          images: ['http://n/a.mp4'],
          media: [video],
        ).conversationPreview,
        '看下这个 [1个视频]',
      );
    });

    test('media 缺失时按 URL 后缀兜底判断（老消息 / 后台只写 images）', () {
      // 不传 media：构造函数按 images 合成，isVideo 由 MediaSaver 判定
      expect(
        msg(images: ['http://n/a.jpg', 'http://n/c.mp4']).conversationPreview,
        '[1张图片] [1个视频]',
      );
    });

    test('media 与 images 长度不一致时以 images 为准、按后缀猜类型', () {
      expect(
        msg(
          images: ['http://n/a.jpg', 'http://n/c.mp4'],
          media: [image], // 错位的脏数据
        ).conversationPreview,
        '[1张图片] [1个视频]',
      );
    });
  });

  group('非附件分支', () {
    test('撤回优先于一切', () {
      expect(
        msg(
          content: '原文',
          images: ['http://n/a.mp4'],
          media: [video],
          recalled: true,
        ).conversationPreview,
        '[消息已撤回]',
      );
    });

    test('系统消息返回原文', () {
      expect(
        msg(content: '张三 已上班打卡', msgType: 2).conversationPreview,
        '张三 已上班打卡',
      );
    });

    test('无文字无附件返回空串（后端 _conv_preview 同样提前返回）', () {
      expect(msg().conversationPreview, '');
    });

    test('连续空白压成单空格并 trim', () {
      expect(msg(content: '  今天\n\n下午  见  ').conversationPreview, '今天 下午 见');
    });

    test('超 80 字按 code point 截断并加 ...', () {
      final long = '医' * 100;
      final preview = msg(content: long).conversationPreview;
      expect(preview.runes.length, 83); // 80 + '...'
      expect(preview.endsWith('...'), isTrue);
    });

    test('emoji 按 code point 计数（mb_strlen 口径，不是 UTF-16 长度）', () {
      final long = '😀' * 90; // String.length=180，runes=90
      final preview = msg(content: long).conversationPreview;
      expect(preview.runes.length, 83);
    });
  });
}

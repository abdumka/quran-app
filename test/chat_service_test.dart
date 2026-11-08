import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:islamic_dawah_mushaf/services/chat_attachment_picker.dart';
import 'package:islamic_dawah_mushaf/services/chat_service.dart';
import 'package:islamic_dawah_mushaf/widgets/chat/chat_screen.dart';
import 'package:islamic_dawah_mushaf/widgets/menu/contact_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

String threadBody({
  String? id = 'ABC123',
  int unread = 0,
  List<Map<String, Object?>> messages = const [],
}) => jsonEncode({
  'thread_id': id,
  'blocked': false,
  'unread': unread,
  'messages': messages,
});

http.Response jsonOk(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('network use', () {
    test('start makes no request for an install with no conversation', () async {
      var calls = 0;
      final chat = ChatService(
        client: MockClient((_) async {
          calls++;
          return jsonOk(threadBody());
        }),
      );
      await chat.start();
      expect(calls, 0);
    });

    test('start refreshes once for an install with a conversation', () async {
      SharedPreferences.setMockInitialValues({'chatThreadId': 'ABC123'});
      final paths = <String>[];
      final chat = ChatService(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return jsonOk(threadBody(unread: 2));
        }),
      );
      await chat.start();
      await chat.start();
      expect(paths, ['/api/chat/thread']);
      expect(chat.unread.value, 2);
    });

    test('the push token is not sent before the first message', () async {
      var calls = 0;
      final chat = ChatService(
        client: MockClient((_) async {
          calls++;
          return jsonOk('{}');
        }),
      );
      await chat.updatePushToken('token-1');
      expect(calls, 0);
    });

    test('the push token goes up once when it changes', () async {
      SharedPreferences.setMockInitialValues({'chatThreadId': 'ABC123'});
      final tokens = <String>[];
      final chat = ChatService(
        client: MockClient((request) async {
          if (request.url.path == '/api/chat/token') {
            tokens.add(jsonDecode(request.body)['fcm_token'] as String);
          }
          return jsonOk(threadBody());
        }),
      );
      await chat.start();
      await chat.updatePushToken('token-1');
      await chat.updatePushToken('token-1');
      await chat.updatePushToken('token-2');
      expect(tokens, ['token-1', 'token-2']);
    });
  });

  group('sending', () {
    test('the install key stays the same and goes in a header', () async {
      final keys = <String?>{};
      final chat = ChatService(
        client: MockClient((request) async {
          keys.add(request.headers['X-Chat-Key']);
          return jsonOk(threadBody());
        }),
      );
      await chat.send(text: 'a');
      await chat.send(text: 'b');
      expect(keys.length, 1);
      expect(keys.first, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('device info goes only with the first message, if allowed', () async {
      final bodies = <Map<String, dynamic>>[];
      final chat = ChatService(
        client: MockClient((request) async {
          if (request.method == 'DELETE') return jsonOk('{}');
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return jsonOk(threadBody());
        }),
      );
      await chat.send(text: 'a', includeDeviceInfo: false);
      await chat.deleteConversation();
      await chat.send(text: 'b');
      await chat.send(text: 'c');
      final posts = bodies.where((b) => b.containsKey('text')).toList();
      expect(posts[0].containsKey('meta'), isFalse);
      expect(posts[1].containsKey('meta'), isTrue);
      expect(posts[2].containsKey('meta'), isFalse);
    });

    test('a file is uploaded first, then named in the message', () async {
      final order = <String>[];
      String? attached;
      List<int>? uploaded;
      final chat = ChatService(
        client: MockClient((request) async {
          order.add('${request.method} ${request.url.path}');
          if (request.method == 'PUT') {
            uploaded = request.bodyBytes;
            expect(request.url.queryParameters['name'], 'a.jpg');
            return jsonOk('{"id":"f0"}');
          }
          attached = (jsonDecode(request.body) as Map)['attachment_id'] as String?;
          return jsonOk(threadBody());
        }),
      );
      final progress = <double>[];
      final failure = await chat.send(
        text: '',
        file: ChatDraftFile(
          name: 'a.jpg',
          kind: 'image',
          bytes: Uint8List.fromList(List.filled(200000, 7)),
          originalSize: 900000,
        ),
        onProgress: progress.add,
      );
      expect(failure, isNull);
      expect(order, ['PUT /api/chat/attachments', 'POST /api/chat/messages']);
      expect(attached, 'f0');
      expect(uploaded!.length, 200000);
      expect(progress.last, 1.0);
    });

    test('a refused file stops the send and says why', () async {
      final chat = ChatService(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          return http.Response('{"error":"unsupported_file"}', 415);
        }),
      );
      final failure = await chat.send(
        text: 'x',
        file: ChatDraftFile(
          name: 'a.jpg',
          kind: 'image',
          bytes: Uint8List(10),
          originalSize: 10,
        ),
      );
      expect(failure?.code, 'unsupported_file');
      expect(failure?.message, contains('صورة أو ملف PDF'));
    });

    test('no connection is reported, not thrown', () async {
      final chat = ChatService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect((await chat.send(text: 'x'))?.code, 'network');
      expect(await chat.refresh(), isFalse);
    });
  });

  group('reading', () {
    test('messages and a deleted attachment parse', () async {
      final chat = ChatService(
        client: MockClient(
          (_) async => jsonOk(
            threadBody(
              unread: 1,
              messages: [
                {
                  'id': 1,
                  'from': 'me',
                  'text': 'سلام',
                  'at': 1000,
                  'attachment': {'deleted': true},
                  'read_by_team': true,
                },
                {'id': 2, 'from': 'team', 'text': 'وعليكم', 'at': 2000},
              ],
            ),
          ),
        ),
      );
      await chat.refresh();
      final messages = chat.messages.value;
      expect(messages[0].fromMe, isTrue);
      expect(messages[0].attachment!.deleted, isTrue);
      expect(messages[0].readByTeam, isTrue);
      expect(messages[1].fromMe, isFalse);
      expect(messages[1].text, 'وعليكم');
      expect(chat.unread.value, 1);
    });

    test('marking read clears the badge', () async {
      final paths = <String>[];
      final chat = ChatService(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return jsonOk(threadBody(unread: 1));
        }),
      );
      await chat.refresh();
      await chat.markRead();
      expect(chat.unread.value, 0);
      expect(paths.last, '/api/chat/read');
    });

    test('deleting forgets the conversation here too', () async {
      final chat = ChatService(
        client: MockClient((_) async => jsonOk(threadBody())),
      );
      await chat.refresh();
      expect(chat.threadId.value, 'ABC123');
      expect(await chat.deleteConversation(), isTrue);
      expect(chat.threadId.value, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chatThreadId'), isNull);
    });
  });

  group('sizes and times', () {
    test('the long edge is limited and the shape kept', () {
      expect(ChatAttachmentPicker.scaledSize(3000, 4000, 1600), (1200, 1600));
      expect(ChatAttachmentPicker.scaledSize(4000, 1000, 1600), (1600, 400));
      expect(ChatAttachmentPicker.scaledSize(800, 600, 1600), (800, 600));
    });

    test('times use Western digits', () {
      final now = DateTime(2026, 11, 7, 12);
      expect(formatChatTime(DateTime(2026, 11, 7, 9, 5), now: now), '09:05');
      expect(formatChatTime(DateTime(2026, 11, 6, 21, 40), now: now), '6/11 21:40');
    });

    test('sizes read naturally', () {
      expect(formatChatSize(240 * 1024), '240 KB');
      expect(formatChatSize(1024 * 1024 * 19 ~/ 10), '1.9 MB');
      expect(formatChatSize(10), '1 KB');
    });
  });

  group('screens', () {
    testWidgets('the contact page has the new card first, and keeps email', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ContactContent(onOpenLink: (_) async {})),
        ),
      );
      final chatCard = tester.getTopLeft(find.text('راسلنا مباشرة'));
      final facebook = tester.getTopLeft(find.text('صفحة فيسبوك'));
      expect(chatCard.dy, lessThan(facebook.dy));
      expect(find.text('البريد الإلكتروني'), findsOneWidget);
    });

    testWidgets('first run shows topics, and an empty send explains itself', (
      tester,
    ) async {
      final chat = ChatService(
        client: MockClient((_) async => jsonOk(threadBody(id: null))),
      );
      await tester.pumpWidget(MaterialApp(home: ChatScreen(service: chat)));
      await tester.pumpAndSettle();
      expect(find.text('مشكلة في التلاوة'), findsOneWidget);
      expect(find.textContaining('فريق المصحف الجامع'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(find.text('اكتب رسالة أو أرفق ملفًا أولًا.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a reply shows as the team, and a failed send can retry', (
      tester,
    ) async {
      var online = true;
      final chat = ChatService(
        client: MockClient((request) async {
          if (!online) throw http.ClientException('offline');
          if (request.url.path == '/api/chat/read') return jsonOk('{}');
          return jsonOk(
            threadBody(
              messages: [
                {'id': 2, 'from': 'team', 'text': 'وعليكم السلام', 'at': 2000},
              ],
            ),
          );
        }),
      );
      await tester.pumpWidget(MaterialApp(home: ChatScreen(service: chat)));
      await tester.pumpAndSettle();
      expect(find.text('وعليكم السلام'), findsOneWidget);

      online = false;
      await tester.enterText(find.byType(TextField), 'رسالتي');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('لم تُرسل'), findsOneWidget);
      expect(find.text('رسالتي'), findsOneWidget);

      online = true;
      await tester.tap(find.textContaining('لم تُرسل'));
      await tester.pumpAndSettle();
      expect(find.textContaining('لم تُرسل'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

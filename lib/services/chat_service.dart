import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'debug_log_service.dart';
import 'tv_service.dart';

/// A file ready to send, already shrunk and with its metadata removed.
class ChatDraftFile {
  final String name;

  /// `image` or `pdf`.
  final String kind;
  final Uint8List bytes;

  /// Size before shrinking, shown so the user can see it worked.
  final int originalSize;

  const ChatDraftFile({
    required this.name,
    required this.kind,
    required this.bytes,
    required this.originalSize,
  });
}

class ChatAttachment {
  final String? id;
  final String name;
  final String kind;
  final int size;

  /// An admin removed the file, so only a note is left in the chat.
  final bool deleted;

  const ChatAttachment({
    this.id,
    this.name = '',
    this.kind = '',
    this.size = 0,
    this.deleted = false,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    if (json['deleted'] == true) return const ChatAttachment(deleted: true);
    return ChatAttachment(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatMessage {
  final int id;
  final bool fromMe;
  final String text;
  final DateTime at;
  final ChatAttachment? attachment;
  final bool readByTeam;

  const ChatMessage({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.at,
    this.attachment,
    this.readByTeam = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final attachment = json['attachment'];
    return ChatMessage(
      id: (json['id'] as num).toInt(),
      fromMe: json['from'] == 'me',
      text: json['text'] as String? ?? '',
      at: DateTime.fromMillisecondsSinceEpoch(
        (json['at'] as num).toInt(),
      ).toLocal(),
      attachment: attachment is Map<String, dynamic>
          ? ChatAttachment.fromJson(attachment)
          : null,
      readByTeam: json['read_by_team'] == true,
    );
  }
}

/// Why a send failed, as the words the user sees.
class ChatFailure {
  final String code;
  const ChatFailure(this.code);

  String get message {
    switch (code) {
      case 'too_large':
        return 'الملف أكبر من 5 MB. اختر ملفًا أصغر.';
      case 'unsupported_file':
        return 'هذا النوع غير مدعوم. أرسل صورة أو ملف PDF.';
      case 'file_limit':
        return 'وصلت إلى حد اليوم: 3 مرفقات.';
      case 'message_limit':
        return 'وصلت إلى حد اليوم: 10 رسائل. حاول غدًا.';
      case 'storage_full':
        return 'التخزين ممتلئ الآن. أرسل رسالتك بدون مرفق.';
      case 'blocked':
        return 'تعذّر الإرسال من هذا الجهاز.';
      case 'too_many_requests':
        return 'الخدمة مشغولة الآن. حاول لاحقًا.';
      case 'too_long':
        return 'الرسالة أطول من 1000 حرف.';
      default:
        return 'تعذّر الإرسال. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.';
    }
  }
}

/// «راسلنا مباشرة»: this install's private conversation with the team.
///
/// There are no accounts. The first send makes a random private key that stays
/// on this phone, and only its hash exists on the server, so whoever holds the
/// key is the conversation. Reinstalling usually starts a new one, unless Android
/// restores the app's backup.
///
/// Nothing here touches the network at launch unless this install has already
/// sent a message, and the push token leaves the phone only with that first
/// message. The phone only ever talks to this one Worker address.
class ChatService {
  ChatService({http.Client? client}) : _client = client ?? http.Client();

  static final ChatService instance = ChatService();

  static const String baseUrl = 'https://chat.mushaf-qaloon.com';
  static const int maxTextLength = 1000;

  static const String _keyPref = 'chatInstallKey';
  static const String _threadPref = 'chatThreadId';
  static const String _tokenPref = 'chatPushTokenSent';

  static const Duration _timeout = Duration(seconds: 25);
  static const Duration _uploadTimeout = Duration(seconds: 90);
  static const int _uploadChunk = 64 * 1024;
  static const int _cacheLimit = 12;

  final http.Client _client;

  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  final ValueNotifier<List<ChatMessage>> messages =
      ValueNotifier<List<ChatMessage>>(const []);
  final ValueNotifier<String?> threadId = ValueNotifier<String?>(null);
  final ValueNotifier<bool> blocked = ValueNotifier<bool>(false);

  /// Set by the chat screen, so a push for an open chat refreshes it instead of
  /// posting a notification on top of it.
  bool chatOpen = false;

  bool _started = false;
  String? _pushToken;
  void Function()? _opener;
  bool _openPending = false;

  /// Most recently used last. Files are fetched once per run, not re-downloaded
  /// on every rebuild.
  final Map<String, Uint8List> _files = {};

  /// The feature is for phones only: no push on the web app, no keyboard on TV.
  static bool get isAvailable =>
      !kIsWeb &&
      !TvService.instance.isTv &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Called after the first frame. Costs one small request, and only for an
  /// install that already has a conversation.
  Future<void> start() async {
    if (_started || !isAvailable) return;
    _started = true;
    final prefs = await SharedPreferences.getInstance();
    threadId.value = prefs.getString(_threadPref);
    if (threadId.value == null) return;
    await refresh();
    await _sendPushTokenIfNew();
  }

  /// Lets the reader open the chat when a notification is tapped. A tap that
  /// cold-started the app waits here until the reader is up.
  void attachOpener(void Function() opener) {
    _opener = opener;
    if (_openPending) {
      _openPending = false;
      opener();
    }
  }

  void requestOpen() {
    if (chatOpen) {
      unawaited(refresh());
      return;
    }
    final opener = _opener;
    if (opener == null) {
      _openPending = true;
    } else {
      opener();
    }
  }

  /// A push arrived while the app is open.
  void handleForegroundPush() {
    unawaited(refresh());
  }

  /// From the push service, whenever Firebase issues or changes the token.
  Future<void> updatePushToken(String token) async {
    _pushToken = token;
    if (threadId.value != null) await _sendPushTokenIfNew();
  }

  Future<void> _sendPushTokenIfNew() async {
    final token = _pushToken;
    if (token == null || threadId.value == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_tokenPref) == token) return;
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/chat/token'),
            headers: await _jsonHeaders(),
            body: jsonEncode({'fcm_token': token}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) await prefs.setString(_tokenPref, token);
    } catch (error) {
      _log('token update failed: $error');
    }
  }

  Future<String> _installKey() async {
    final prefs = await SharedPreferences.getInstance();
    var key = prefs.getString(_keyPref);
    if (key == null || key.length != 64) {
      key = _generateKey();
      await prefs.setString(_keyPref, key);
    }
    return key;
  }

  static String _generateKey() {
    final random = Random.secure();
    final out = StringBuffer();
    for (var i = 0; i < 32; i++) {
      out.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  Future<Map<String, String>> _jsonHeaders() async => {
    'X-Chat-Key': await _installKey(),
    'Content-Type': 'application/json',
  };

  /// Fetches the conversation. Returns false if the server couldn't be reached,
  /// in which case what's on screen stays as it is.
  Future<bool> refresh() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/chat/thread'),
            headers: {'X-Chat-Key': await _installKey()},
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return false;
      await _applyThread(response.body);
      return true;
    } catch (error) {
      _log('refresh failed: $error');
      return false;
    }
  }

  Future<void> _applyThread(String body) async {
    final data = jsonDecode(body);
    final id = data['thread_id'] as String?;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_threadPref);
    } else {
      await prefs.setString(_threadPref, id);
    }
    threadId.value = id;
    blocked.value = data['blocked'] == true;
    unread.value = (data['unread'] as num?)?.toInt() ?? 0;
    messages.value = [
      for (final message in (data['messages'] as List<dynamic>))
        ChatMessage.fromJson(message as Map<String, dynamic>),
    ];
  }

  /// Sends a message, uploading [file] first if there is one. Returns null on
  /// success. On failure nothing is lost: the caller keeps the draft.
  Future<ChatFailure?> send({
    required String text,
    String? topic,
    bool includeDeviceInfo = true,
    ChatDraftFile? file,
    void Function(double progress)? onProgress,
  }) async {
    try {
      String? attachmentId;
      if (file != null) {
        final uploaded = await _upload(file, onProgress);
        if (uploaded is ChatFailure) return uploaded;
        attachmentId = uploaded as String;
      }
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/chat/messages'),
            headers: await _jsonHeaders(),
            body: jsonEncode({
              'text': text,
              'topic': topic,
              if (includeDeviceInfo && threadId.value == null)
                'meta': await _deviceInfo(),
              'attachment_id': attachmentId,
              'fcm_token': _pushToken,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return _failureFrom(response);
      await _applyThread(response.body);
      final token = _pushToken;
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenPref, token);
      }
      return null;
    } catch (error) {
      _log('send failed: $error');
      return const ChatFailure('network');
    }
  }

  /// Returns the new attachment's id, or a [ChatFailure].
  Future<Object> _upload(
    ChatDraftFile file,
    void Function(double progress)? onProgress,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/api/chat/attachments',
    ).replace(queryParameters: {'name': file.name, 'kind': file.kind});
    final request = http.StreamedRequest('PUT', uri)
      ..headers['X-Chat-Key'] = await _installKey()
      ..contentLength = file.bytes.length;
    final responseFuture = _client.send(request).timeout(_uploadTimeout);
    var sent = 0;
    while (sent < file.bytes.length) {
      final end = min(sent + _uploadChunk, file.bytes.length);
      request.sink.add(file.bytes.sublist(sent, end));
      sent = end;
      onProgress?.call(sent / file.bytes.length);
      await Future<void>.delayed(Duration.zero);
    }
    await request.sink.close();
    final response = await http.Response.fromStream(await responseFuture);
    if (response.statusCode != 200) return _failureFrom(response);
    final id = (jsonDecode(response.body) as Map<String, dynamic>)['id'];
    _remember(id as String, file.bytes);
    return id;
  }

  ChatFailure _failureFrom(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['error'] is String) {
        return ChatFailure(data['error'] as String);
      }
    } catch (_) {}
    return const ChatFailure('server');
  }

  Future<String> _deviceInfo() async {
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'iOS'
        : 'Android';
    try {
      final info = await PackageInfo.fromPlatform();
      return '$platform · v${info.version} (${info.buildNumber})';
    } catch (_) {
      return platform;
    }
  }

  /// Marks the team's replies as read, which clears the badge and tells the
  /// portal the user has seen them.
  Future<void> markRead() async {
    if (unread.value == 0) return;
    unread.value = 0;
    try {
      await _client
          .post(
            Uri.parse('$baseUrl/api/chat/read'),
            headers: await _jsonHeaders(),
            body: '{}',
          )
          .timeout(_timeout);
    } catch (error) {
      _log('mark read failed: $error');
    }
  }

  /// «حذف المحادثة»: removes the text and files from the server at once.
  Future<bool> deleteConversation() async {
    try {
      final response = await _client
          .delete(
            Uri.parse('$baseUrl/api/chat/thread'),
            headers: {'X-Chat-Key': await _installKey()},
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_threadPref);
      await prefs.remove(_tokenPref);
      threadId.value = null;
      unread.value = 0;
      messages.value = const [];
      _files.clear();
      return true;
    } catch (error) {
      _log('delete failed: $error');
      return false;
    }
  }

  /// This install's own file, from memory or the server.
  Future<Uint8List?> attachmentBytes(String id) async {
    final cached = _files.remove(id);
    if (cached != null) {
      _files[id] = cached;
      return cached;
    }
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/chat/attachments/$id'),
            headers: {'X-Chat-Key': await _installKey()},
          )
          .timeout(_uploadTimeout);
      if (response.statusCode != 200) return null;
      _remember(id, response.bodyBytes);
      return response.bodyBytes;
    } catch (error) {
      _log('file fetch failed: $error');
      return null;
    }
  }

  void _remember(String id, Uint8List bytes) {
    _files[id] = bytes;
    while (_files.length > _cacheLimit) {
      _files.remove(_files.keys.first);
    }
  }

  void _log(String message) {
    debugPrint('[Chat] $message');
    try {
      DebugLogService.instance.log('[Chat] $message');
    } catch (_) {}
  }
}

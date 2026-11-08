import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/chat_attachment_picker.dart';
import '../../services/chat_service.dart';
import '../../services/notification_center.dart';

/// «راسلنا مباشرة»: the user's private conversation with the team.
class ChatScreen extends StatefulWidget {
  /// Replaceable so tests can run without the real server.
  final ChatService? service;

  const ChatScreen({super.key, this.service});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _FailedSend {
  final String text;
  final ChatDraftFile? file;
  final String reason;
  const _FailedSend(this.text, this.file, this.reason);
}

class _ChatScreenState extends State<ChatScreen> {
  static const List<String> _topics = [
    'مشكلة في التلاوة',
    'ملاحظة على المصحف',
    'اقتراح',
    'سؤال',
  ];
  static const Duration _refreshEvery = Duration(seconds: 30);

  late final ChatService _chat = widget.service ?? ChatService.instance;
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_FailedSend> _failed = [];

  Timer? _timer;
  String? _topic;
  bool _includeDeviceInfo = true;
  ChatDraftFile? _draft;
  String? _error;
  bool _sending = false;
  double? _progress;
  bool _loading = true;
  bool _notificationsOff = false;

  @override
  void initState() {
    super.initState();
    _chat.chatOpen = true;
    _chat.messages.addListener(_onMessages);
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chat.chatOpen = false;
    _chat.messages.removeListener(_onMessages);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _reload();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reload() async {
    await _chat.refresh();
    await _chat.markRead();
  }

  void _onMessages() {
    if (mounted) setState(() {});
    _scrollToEnd();
    if (_chat.unread.value > 0) unawaited(_chat.markRead());
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _showAttachMenu() async {
    FocusScope.of(context).unfocus();
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('صورة'),
                onTap: () => Navigator.pop(context, 'photo'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: const Text('ملف PDF'),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final result = choice == 'photo'
        ? await ChatAttachmentPicker.pickPhoto()
        : await ChatAttachmentPicker.pickPdf();
    if (!mounted) return;
    setState(() {
      _error = result.error;
      if (result.file != null) _draft = result.file;
    });
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final file = _draft;
    if (text.isEmpty && file == null) {
      setState(() => _error = 'اكتب رسالة أو أرفق ملفًا أولًا.');
      return;
    }
    if (text.length > ChatService.maxTextLength) {
      setState(() => _error = const ChatFailure('too_long').message);
      return;
    }
    final firstMessage = _chat.threadId.value == null;
    setState(() {
      _sending = true;
      _progress = file == null ? null : 0;
      _error = null;
      _text.clear();
      _draft = null;
    });
    final failure = await _chat.send(
      text: text,
      topic: _topic,
      includeDeviceInfo: _includeDeviceInfo,
      file: file,
      onProgress: (value) {
        if (mounted) setState(() => _progress = value);
      },
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _progress = null;
      if (failure != null) _failed.add(_FailedSend(text, file, failure.message));
    });
    _scrollToEnd();
    if (failure == null && firstMessage) {
      // Asked here, on the first send, when the reason for it is obvious.
      final allowed = await NotificationCenter.instance.requestPermission();
      if (mounted) setState(() => _notificationsOff = !allowed);
    }
  }

  Future<void> _retry(_FailedSend failed) async {
    setState(() {
      _failed.remove(failed);
      _sending = true;
    });
    final failure = await _chat.send(
      text: failed.text,
      topic: _topic,
      includeDeviceInfo: _includeDeviceInfo,
      file: failed.file,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (failure != null) {
        _failed.add(_FailedSend(failed.text, failed.file, failure.message));
      }
    });
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المحادثة؟'),
          content: const Text(
            'تُحذف الرسائل والمرفقات من الخادم نهائيًا، ولا يمكن استرجاعها.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('احذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final done = await _chat.deleteConversation();
    if (!mounted) return;
    setState(() {
      _failed.clear();
      _error = done ? null : 'تعذّر حذف المحادثة. حاول مرة أخرى.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ChatColors.of(context);
    final hasThread = _chat.threadId.value != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.background,
          foregroundColor: colors.ink,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'راسلنا مباشرة',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            if (hasThread)
              PopupMenuButton<String>(
                onSelected: (_) => _confirmDelete(),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'حذف المحادثة',
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildList(colors, hasThread)),
              _buildComposer(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(_ChatColors colors, bool hasThread) {
    final messages = _chat.messages.value;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(14),
      children: [
        _Bubble(
          colors: colors,
          fromMe: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _teamLabel(colors),
              const SizedBox(height: 3),
              Text(
                'السلام عليكم ورحمة الله. اكتب لنا سؤالك أو اقتراحك أو مشكلة '
                'واجهتك، وسنردّ عليك هنا. يصلك إشعار حين نردّ.',
                style: TextStyle(color: colors.ink, height: 1.55),
              ),
            ],
          ),
        ),
        if (_loading && !hasThread)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_loading && !hasThread) ..._buildFirstRun(colors),
        for (final message in messages) _buildMessage(message, colors),
        for (final failed in _failed) _buildFailed(failed, colors),
        if (_notificationsOff)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'الإشعارات مغلقة، فلن يصلك تنبيه. افتح هذه الصفحة لرؤية الرد.',
              style: TextStyle(color: colors.muted, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildFirstRun(_ChatColors colors) {
    return [
      const SizedBox(height: 10),
      Text(
        'المحادثة مرتبطة بهذا التثبيت، وقد تضيع عند حذف التطبيق.',
        style: TextStyle(color: colors.muted, fontSize: 12.5),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 7,
        runSpacing: 2,
        children: [
          for (final topic in _topics)
            ChoiceChip(
              label: Text(topic, style: const TextStyle(fontSize: 12.5)),
              selected: _topic == topic,
              onSelected: (selected) =>
                  setState(() => _topic = selected ? topic : null),
            ),
        ],
      ),
      const SizedBox(height: 6),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: _includeDeviceInfo,
        onChanged: (value) =>
            setState(() => _includeDeviceInfo = value ?? false),
        title: Text(
          'أرفق رقم الإصدار ونوع النظام',
          style: TextStyle(color: colors.muted, fontSize: 13),
        ),
      ),
    ];
  }

  Widget _teamLabel(_ChatColors colors) => Text(
    'فريق المصحف الجامع',
    style: TextStyle(
      color: colors.accent,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _buildMessage(ChatMessage message, _ChatColors colors) {
    final ink = message.fromMe ? colors.myInk : colors.ink;
    return _Bubble(
      colors: colors,
      fromMe: message.fromMe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.fromMe) ...[
            _teamLabel(colors),
            const SizedBox(height: 3),
          ],
          if (message.attachment != null) ...[
            _AttachmentView(
              attachment: message.attachment!,
              chat: _chat,
              ink: ink,
            ),
            const SizedBox(height: 5),
          ],
          if (message.text.isNotEmpty)
            Text(message.text, style: TextStyle(color: ink, height: 1.55)),
          const SizedBox(height: 3),
          Text(
            message.fromMe
                ? '${formatChatTime(message.at)} · '
                      '${message.readByTeam ? 'قرأها الفريق' : 'أُرسلت'}'
                : formatChatTime(message.at),
            style: TextStyle(
              color: ink.withValues(alpha: 0.72),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailed(_FailedSend failed, _ChatColors colors) {
    return _Bubble(
      colors: colors,
      fromMe: true,
      failed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed.file != null)
            Text(
              isolateBidi(failed.file!.name),
              style: TextStyle(color: colors.myInk, fontSize: 12.5),
            ),
          if (failed.text.isNotEmpty)
            Text(failed.text, style: TextStyle(color: colors.myInk)),
          const SizedBox(height: 3),
          Text(
            failed.reason,
            style: TextStyle(color: colors.myInk, fontSize: 12),
          ),
          InkWell(
            onTap: _sending ? null : () => _retry(failed),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'لم تُرسل · اضغط لإعادة المحاولة',
                style: TextStyle(
                  color: colors.myInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.myInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(_ChatColors colors) {
    final blocked = _chat.blocked.value;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.bar,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _error!,
                style: TextStyle(
                  color: colors.error,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (_draft != null) _buildDraft(colors),
          if (_progress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: LinearProgressIndicator(value: _progress),
            ),
          if (blocked)
            Text(
              'تعذّر الإرسال من هذا الجهاز.',
              style: TextStyle(color: colors.muted),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    enabled: !_sending,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    minLines: 1,
                    maxLines: 5,
                    maxLength: ChatService.maxTextLength,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك…',
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: colors.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إرفاق صورة أو ملف PDF',
                  onPressed: _sending ? null : _showAttachMenu,
                  icon: Icon(Icons.attach_file_rounded, color: colors.accent),
                ),
                IconButton.filled(
                  tooltip: 'إرسال',
                  style: IconButton.styleFrom(backgroundColor: colors.accent),
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: colors.background,
                          textDirection: TextDirection.rtl,
                        ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDraft(_ChatColors colors) {
    final draft = _draft!;
    final shrunk = draft.originalSize > draft.bytes.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: draft.kind == 'image'
                ? Image.memory(
                    draft.bytes,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                  )
                : Container(
                    width: 42,
                    height: 42,
                    color: colors.error,
                    alignment: Alignment.center,
                    child: const Text(
                      'PDF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isolateBidi(draft.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.ink, fontSize: 12.5),
                ),
                Text(
                  shrunk
                      ? '${formatChatSize(draft.originalSize)} → ${formatChatSize(draft.bytes.length)}'
                      : formatChatSize(draft.bytes.length),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إزالة المرفق',
            visualDensity: VisualDensity.compact,
            onPressed: _sending ? null : () => setState(() => _draft = null),
            icon: Icon(Icons.close_rounded, color: colors.muted, size: 20),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _ChatColors colors;
  final bool fromMe;
  final bool failed;
  final Widget child;

  const _Bubble({
    required this.colors,
    required this.fromMe,
    required this.child,
    this.failed = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: fromMe
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: width * 0.8),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
        decoration: BoxDecoration(
          color: fromMe ? colors.mine : colors.card,
          borderRadius: BorderRadius.circular(14),
          border: failed
              ? Border.all(color: colors.error, width: 1.5)
              : fromMe
              ? null
              : Border.all(color: colors.border),
        ),
        child: child,
      ),
    );
  }
}

class _AttachmentView extends StatelessWidget {
  final ChatAttachment attachment;
  final ChatService chat;
  final Color ink;

  const _AttachmentView({
    required this.attachment,
    required this.chat,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    if (attachment.deleted || attachment.id == null) {
      return Text(
        'حُذف المرفق',
        style: TextStyle(
          color: ink.withValues(alpha: 0.8),
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (attachment.kind == 'image') {
      return FutureBuilder<Uint8List?>(
        future: chat.attachmentBytes(attachment.id!),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return SizedBox(
              height: 90,
              width: 150,
              child: Center(
                child: snapshot.connectionState == ConnectionState.done
                    ? Icon(Icons.image_not_supported_rounded, color: ink)
                    : const CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.memory(
              bytes,
              height: 170,
              fit: BoxFit.contain,
              cacheHeight: 500,
            ),
          );
        },
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.picture_as_pdf_rounded, color: ink, size: 20),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${isolateBidi(attachment.name)} · ${formatChatSize(attachment.size)}',
            style: TextStyle(color: ink, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

/// The app's cream and brown, matching «تواصل معنا».
class _ChatColors {
  final Color background;
  final Color bar;
  final Color card;
  final Color border;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color mine;
  final Color myInk;
  final Color error;

  const _ChatColors({
    required this.background,
    required this.bar,
    required this.card,
    required this.border,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.mine,
    required this.myInk,
    required this.error,
  });

  factory _ChatColors.of(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return const _ChatColors(
        background: Color(0xFF111111),
        bar: Color(0xFF151515),
        card: Color(0xFF1A1A1A),
        border: Color(0xFF53401F),
        ink: Color(0xFFF1ECE2),
        muted: Color(0xFFA89A80),
        accent: Color(0xFFC9A56A),
        mine: Color(0xFF4D3C22),
        myInk: Color(0xFFF7F0E2),
        error: Color(0xFFE2614B),
      );
    }
    return const _ChatColors(
      background: Color(0xFFF6F1E5),
      bar: Color(0xFFFBF7EF),
      card: Color(0xFFF8F1DE),
      border: Color(0xFFE2D2A5),
      ink: Color(0xFF35250E),
      muted: Color(0xFF7A6748),
      accent: Color(0xFF8B7355),
      mine: Color(0xFF8B7355),
      myInk: Color(0xFFFFFDF8),
      error: Color(0xFFC2412D),
    );
  }
}

/// Lets a file name pick its own direction inside surrounding Arabic text.
String isolateBidi(String text) => '\u2068$text\u2069';

/// Always Western digits, whatever the phone's locale.
String formatChatTime(DateTime at, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}';
  if (at.year == reference.year &&
      at.month == reference.month &&
      at.day == reference.day) {
    return time;
  }
  return '${at.day}/${at.month} $time';
}

String formatChatSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  final kb = (bytes / 1024).round();
  return '${kb < 1 ? 1 : kb} KB';
}

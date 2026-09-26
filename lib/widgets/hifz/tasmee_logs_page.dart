import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'hifz_palette.dart';
import '../../services/install_id.dart';
import '../../services/tasmee_session_recorder.dart';
import '../../services/tasmee_upload_service.dart';

/// Lists every saved التسميع session (audio + decision log) with share /
/// delete actions and the "keep how many sessions" setting.
class TasmeeLogsPage extends StatefulWidget {
  const TasmeeLogsPage({super.key});

  @override
  State<TasmeeLogsPage> createState() => _TasmeeLogsPageState();
}

class _TasmeeLogsPageState extends State<TasmeeLogsPage> {

  List<TasmeeSessionFiles> _sessions = const [];
  int _keep = TasmeeSessionRecorder.defaultKeep;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final sessions = await TasmeeSessionRecorder.listSessions();
    final keep = await TasmeeSessionRecorder.keepCount();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _keep = keep;
      _loading = false;
    });
  }

  Future<void> _share(List<TasmeeSessionFiles> sessions) async {
    final files = [
      for (final s in sessions)
        for (final f in s.files) XFile(f.path),
    ];
    if (files.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          subject: 'سجلات التسميع',
          text: 'تسجيلات جلسات التسميع وسجلات القرارات (للتحليل).',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّرت المشاركة')),
      );
    }
  }

  /// Uploads the sessions' files to the owner's private bucket (no share
  /// sheet). Only offered when the build carries upload credentials.
  Future<void> _upload(List<TasmeeSessionFiles> sessions) async {
    final upload = TasmeeUploadService.instance;
    final paths = [
      for (final s in sessions)
        for (final f in s.files) f.path,
    ];
    if (paths.isEmpty || upload.busy.value) return;
    final installId = await InstallId.get();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failed = await upload.uploadAll(paths, installId: installId);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        failed.isEmpty
            ? 'تم رفع ${paths.length} ملفًا بنجاح'
            : 'تعذّر رفع ${failed.length} من ${paths.length} ملفًا — تحقّق من الاتصال وحاول مرة أخرى',
      ),
      duration: const Duration(seconds: 5),
    ));
  }

  /// Store builds carry no upload key (the owner ships without it), and then
  /// there is no button at all: users share a session themselves if they
  /// want to. Only a build made with the key shows the button.
  Widget _uploadButton(List<TasmeeSessionFiles> sessions, {Color? color}) {
    final upload = TasmeeUploadService.instance;
    if (!upload.isConfigured) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: upload.busy,
      builder: (context, busy, _) => IconButton(
        tooltip: upload.isConfigured ? 'رفع إلى الخادم' : 'الرفع غير مفعّل في هذه النسخة',
        icon: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: HifzPalette.of(context).title),
              )
            : Icon(Icons.cloud_upload_outlined, color: color),
        onPressed: upload.isConfigured && !busy && sessions.isNotEmpty
            ? () => _upload(sessions)
            : null,
      ),
    );
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف كل السجلات؟'),
        content: Text('سيتم حذف ${_sessions.length} جلسة نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TasmeeSessionRecorder.deleteAll();
    await _refresh();
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _when(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = HifzPalette.of(context);
    final total = _sessions.fold<int>(0, (sum, s) => sum + s.bytes);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: p.bg,
          foregroundColor: p.title,
          title: const Text('سجلات التسميع', style: TextStyle(fontFamily: 'Tajawal')),
          actions: [
            _uploadButton(_sessions),
            IconButton(
              tooltip: 'مشاركة الكل',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: _sessions.isEmpty ? null : () => _share(_sessions),
            ),
            IconButton(
              tooltip: 'حذف الكل',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _sessions.isEmpty ? null : _deleteAll,
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: p.title))
            : ListView(
                children: [
                  ListTile(
                    leading: Icon(Icons.history_rounded, color: p.title),
                    title: Text('عدد الجلسات المحفوظة',
                        style: TextStyle(color: p.text)),
                    subtitle: Text(
                      'تُحذف الأقدم تلقائيًا. الحجم الحالي: ${_size(total)}',
                      style: TextStyle(color: p.sub),
                    ),
                    trailing: DropdownButton<int>(
                      value: TasmeeSessionRecorder.keepChoices.contains(_keep)
                          ? _keep
                          : TasmeeSessionRecorder.defaultKeep,
                      dropdownColor: p.raised,
                      style: TextStyle(color: p.title, fontSize: 16),
                      items: [
                        for (final n in TasmeeSessionRecorder.keepChoices)
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await TasmeeSessionRecorder.setKeepCount(v);
                        await _refresh();
                      },
                    ),
                  ),
                  if (!TasmeeUploadService.instance.isConfigured && kDebugMode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'زر الرفع معطّل: هذه النسخة بُنيت بدون مفتاح الرفع '
                        '(--dart-define-from-file=tools/r2_upload.json). '
                        'يمكنك مشاركة السجلات بزر المشاركة.',
                        style: TextStyle(color: p.sub, fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  Divider(color: p.border),
                  if (_sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'لا توجد جلسات محفوظة بعد. تُسجَّل كل جلسة تسميع تلقائيًا '
                        '(الصوت وسجل القرارات) وتظهر هنا.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.sub),
                      ),
                    ),
                  for (final s in _sessions)
                    ListTile(
                      leading: Icon(
                        s.files.any((f) => f.path.endsWith('.wav'))
                            ? Icons.graphic_eq_rounded
                            : Icons.description_outlined,
                        color: p.title,
                      ),
                      title: Text(
                        s.page == null ? s.stem : 'صفحة ${s.page}',
                        style: TextStyle(color: p.text),
                      ),
                      subtitle: Text(
                        '${_when(s.modified)} · ${_size(s.bytes)} · '
                        '${s.files.map((f) => f.uri.pathSegments.last.split('.').last).join(' + ')}',
                        style: TextStyle(color: p.sub),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _uploadButton([s], color: p.title),
                          IconButton(
                            tooltip: 'مشاركة',
                            icon: Icon(Icons.ios_share_rounded, color: p.title),
                            onPressed: () => _share([s]),
                          ),
                          IconButton(
                            tooltip: 'حذف',
                            icon: Icon(Icons.delete_outline_rounded,
                                color: p.sub),
                            onPressed: () async {
                              await TasmeeSessionRecorder.deleteSession(s);
                              await _refresh();
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

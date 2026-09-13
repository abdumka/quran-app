import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/tasmee_session_recorder.dart';

/// Lists every saved التسميع session (audio + decision log) with share /
/// delete actions and the "keep how many sessions" setting.
class TasmeeLogsPage extends StatefulWidget {
  const TasmeeLogsPage({super.key});

  @override
  State<TasmeeLogsPage> createState() => _TasmeeLogsPageState();
}

class _TasmeeLogsPageState extends State<TasmeeLogsPage> {
  static const Color _gold = Color(0xFFD2B97E);

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
    final total = _sessions.fold<int>(0, (sum, s) => sum + s.bytes);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1C1C1E),
          foregroundColor: _gold,
          title: const Text('سجلات التسميع', style: TextStyle(fontFamily: 'Tajawal')),
          actions: [
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
            ? const Center(child: CircularProgressIndicator(color: _gold))
            : ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.history_rounded, color: _gold),
                    title: const Text('عدد الجلسات المحفوظة',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'تُحذف الأقدم تلقائيًا. الحجم الحالي: ${_size(total)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    trailing: DropdownButton<int>(
                      value: TasmeeSessionRecorder.keepChoices.contains(_keep)
                          ? _keep
                          : TasmeeSessionRecorder.defaultKeep,
                      dropdownColor: const Color(0xFF2C2C2E),
                      style: const TextStyle(color: _gold, fontSize: 16),
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
                  const Divider(color: Color(0xFF2C2C2E)),
                  if (_sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'لا توجد جلسات محفوظة بعد. تُسجَّل كل جلسة تسميع تلقائيًا '
                        '(الصوت وسجل القرارات) وتظهر هنا.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ),
                  for (final s in _sessions)
                    ListTile(
                      leading: Icon(
                        s.files.any((f) => f.path.endsWith('.wav'))
                            ? Icons.graphic_eq_rounded
                            : Icons.description_outlined,
                        color: _gold,
                      ),
                      title: Text(
                        s.page == null ? s.stem : 'صفحة ${s.page}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${_when(s.modified)} · ${_size(s.bytes)} · '
                        '${s.files.map((f) => f.uri.pathSegments.last.split('.').last).join(' + ')}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'مشاركة',
                            icon: const Icon(Icons.ios_share_rounded, color: _gold),
                            onPressed: () => _share([s]),
                          ),
                          IconButton(
                            tooltip: 'حذف',
                            icon: Icon(Icons.delete_outline_rounded,
                                color: Colors.white.withValues(alpha: 0.6)),
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

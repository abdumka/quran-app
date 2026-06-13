import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/debug_log_service.dart';

class DebugLogViewer extends StatefulWidget {
  const DebugLogViewer({super.key});

  @override
  State<DebugLogViewer> createState() => _DebugLogViewerState();
}

class _DebugLogViewerState extends State<DebugLogViewer> {
  late Future<String> _logFuture;

  @override
  void initState() {
    super.initState();
    _logFuture = DebugLogService.instance.readAll();
  }

  Future<void> _refresh() async {
    setState(() {
      _logFuture = DebugLogService.instance.readAll();
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ اللوج')),
    );
  }

  Future<void> _clear() async {
    await DebugLogService.instance.clear();
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم مسح اللوج')),
    );
  }

  Future<void> _share(String text) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Quran Debug Log',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('Quran Debug Log'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _logFuture,
        builder: (context, snapshot) {
          final text = snapshot.data ?? (snapshot.hasError
              ? 'Error loading log: ${snapshot.error}'
              : 'Loading...');

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xFF1D1D1D),
                child: SelectableText(
                  'Path: ${DebugLogService.instance.logFilePath ?? 'unknown'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('تحديث'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _copy(text),
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ اللوج'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _share(text),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('إرسال اللوج'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _clear,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('مسح اللوج'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171717),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.45,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

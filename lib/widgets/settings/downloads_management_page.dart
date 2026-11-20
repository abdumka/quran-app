import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../services/app_look_service.dart';
import '../../services/athkar_download_service.dart';
import '../../services/audio_download_service.dart';
import '../../services/margin_images_service.dart';
import '../../services/tafsir_cache_service.dart';
import '../../models/tafsir_edition.dart';
import '../../theme/app_surfaces.dart';
import '../../utils/after_opening.dart';

// The new look's dialog corners and buttons; null [s] (the previous look and
// night mode) keeps the theme's own.
ShapeBorder? _dialogShape(AppSurfaces? s) => s == null
    ? null
    : RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSurfaces.radius),
      );

ButtonStyle? _quietTextStyle(AppSurfaces? s) =>
    s == null ? null : TextButton.styleFrom(foregroundColor: s.text);

ButtonStyle? _primaryStyle(AppSurfaces? s) => s == null
    ? null
    : FilledButton.styleFrom(
        backgroundColor: s.button,
        foregroundColor: s.onButton,
      );

ButtonStyle? _tonalStyle(AppSurfaces? s) => s == null
    ? null
    : FilledButton.styleFrom(
        backgroundColor: s.buttonQuiet,
        foregroundColor: s.text,
      );

class DownloadsManagementPage extends StatefulWidget {
  final AudioDownloadService audioDownloadService;
  final MarginImagesService marginImagesService;
  final TafsirCacheService tafsirCacheService;

  const DownloadsManagementPage({
    super.key,
    required this.audioDownloadService,
    required this.marginImagesService,
    required this.tafsirCacheService,
  });

  @override
  State<DownloadsManagementPage> createState() =>
      _DownloadsManagementPageState();
}

class _DownloadsManagementPageState extends State<DownloadsManagementPage> {
  String _formatBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes <= 0) return '0 MB';
    final value = bytes / mb;
    if (value >= 100) return '${value.toStringAsFixed(0)} MB';
    if (value >= 10) return '${value.toStringAsFixed(1)} MB';
    return '${value.toStringAsFixed(2)} MB';
  }

  Future<bool> _confirmDelete({
    required String title,
    required String body,
  }) async {
    final s = AppSurfaces.maybeOf(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: s?.sheet,
        shape: _dialogShape(s),
        title: Text(title, textDirection: TextDirection.rtl),
        content: Text(body, textDirection: TextDirection.rtl),
        actions: [
          TextButton(
            style: _quietTextStyle(s),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: _primaryStyle(s),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _deleteAudioDownloads() async {
    final confirmed = await _confirmDelete(
      title: 'حذف ملفات الصوت',
      body:
          'سيتم حذف جميع ملفات الصوت المحملة من الجهاز. يمكنك إعادة تحميلها لاحقًا. هل تريد المتابعة؟',
    );
    if (!confirmed) return;
    await widget.audioDownloadService.deleteDownloads();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioDownloadState>(
      valueListenable: widget.audioDownloadService.state,
      builder: (context, audioState, _) {
        return ValueListenableBuilder<MarginImagesState>(
          valueListenable: widget.marginImagesService.state,
          builder: (context, marginState, _) {
            return ValueListenableBuilder<TafsirCacheState>(
              valueListenable: widget.tafsirCacheService.state,
              builder: (context, tafsirState, _) {
                final totalBytes =
                    audioState.installedBytes + tafsirState.installedBytes;
                // null in the previous look and in night mode: the old colours
                // stay
                final s = AppSurfaces.maybeOf(context);
                final previous = AppLookScope.isPrevious(context);

                return Scaffold(
                  backgroundColor: s?.page ?? const Color(0xFFF6F1E5),
                  appBar: AppBar(
                    centerTitle: true,
                    elevation: 0,
                    backgroundColor: s?.page ?? const Color(0xFFF6F1E5),
                    foregroundColor: s?.text ?? const Color(0xFF3D3122),
                    // On an Arabic page "back" sits on the right, pointing
                    // right; the previous look keeps Flutter's own arrow.
                    automaticallyImplyLeading: previous,
                    actions: previous
                        ? null
                        : [
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_rounded),
                              tooltip: 'رجوع',
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                            const SizedBox(width: 4),
                          ],
                    title: Text(
                      'إدارة الملفات المحمّلة',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: previous
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  body: ListView(
                    // An explicit padding turns off the list's own bottom inset,
                    // so the navigation bar's height is added back here.
                    padding: EdgeInsets.fromLTRB(
                      14,
                      10,
                      14,
                      16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          // the new look: a flat card with a hairline
                          color: s?.card,
                          borderRadius: BorderRadius.circular(
                            s == null ? 18 : AppSurfaces.radius,
                          ),
                          gradient: s != null
                              ? null
                              : const LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [
                                    Color(0xFFF8F3E8),
                                    Color(0xFFEADFC7),
                                  ],
                                ),
                          border: Border.all(
                            color:
                                s?.border ??
                                const Color(0xFF8D6E3F).withValues(alpha: 0.22),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المساحة المستخدمة الآن',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: s == null
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: s?.text ?? const Color(0xFF2F2418),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatBytes(totalBytes),
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: s == null
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                                color: s?.accent ?? const Color(0xFF8D6E3F),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'تشمل الملفات الإضافية فقط، ولا تشمل الصور الأساسية المدمجة مع التطبيق.',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: s?.muted ?? const Color(0xFF6A5A45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const DownloadedPackageCard(
                        title: 'الصور الأساسية',
                        subtitle:
                            'مدمجة مع التطبيق وتعمل دائمًا كأساس للقراءة.',
                        sizeLabel: 'ضمن التطبيق',
                        statusLabel: 'متوفرة دائمًا',
                        icon: Icons.image_outlined,
                      ),
                      const SizedBox(height: 10),
                      DownloadedPackageCard(
                        title: 'ملفات الصوت',
                        subtitle: audioState.isComplete
                            ? 'جميع ملفات التلاوة محملة، يمكن الاستماع بدون إنترنت.'
                            : audioState.downloadedFiles > 0
                            ? 'تم تحميل ${audioState.downloadedFiles} من ${audioState.totalFiles} ملف.'
                            : 'غير محملة حاليًا.',
                        sizeLabel: audioState.installedBytes > 0
                            ? audioState.installedSizeLabel
                            : '0 MB',
                        statusLabel: audioState.isComplete
                            ? 'مكتملة'
                            : audioState.downloadedFiles > 0
                            ? 'جزئية'
                            : 'غير محملة',
                        icon: Icons.audio_file_rounded,
                        actionLabel: audioState.downloadedFiles > 0
                            ? 'حذف'
                            : null,
                        onAction:
                            audioState.downloadedFiles > 0 &&
                                !audioState.isDownloading
                            ? _deleteAudioDownloads
                            : null,
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(height: 10),
                        const AthkarDownloadsCard(),
                      ],
                      const SizedBox(height: 10),
                      // The margin pages ship inside the app now, so the card
                      // keeps its familiar wording but has nothing to delete.
                      DownloadedPackageCard(
                        title: 'عرض الهوامش',
                        subtitle: marginState.isEnabled
                            ? 'محمل ومفعّل الآن.'
                            : 'محمل على الجهاز ويمكن تفعيله من الإعدادات.',
                        sizeLabel: 'ضمن التطبيق',
                        statusLabel: marginState.isEnabled ? 'مفعّل' : 'محمل',
                        icon: Icons.photo_size_select_large_rounded,
                      ),
                      const SizedBox(height: 10),
                      TafsirDownloadsSection(
                        service: widget.tafsirCacheService,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class DownloadedPackageCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String sizeLabel;
  final String statusLabel;
  final IconData icon;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  const DownloadedPackageCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sizeLabel,
    required this.statusLabel,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: s?.card ?? const Color(0xFFF3EFE6),
        borderRadius: BorderRadius.circular(
          s == null ? 18 : AppSurfaces.radius,
        ),
        border: Border.all(
          color: s?.border ?? const Color(0xFF8D6E3F).withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.rtl,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: s?.icon ?? const Color(0xFF5C4522)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: s == null ? FontWeight.w800 : FontWeight.w600,
                    color: s?.text ?? const Color(0xFF2F2418),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: s?.muted ?? const Color(0xFF6A5A45),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  textDirection: TextDirection.rtl,
                  children: [
                    InfoChip(label: 'الحجم: $sizeLabel'),
                    InfoChip(label: statusLabel),
                    if (actionLabel != null)
                      FilledButton.tonal(
                        style: _tonalStyle(s),
                        onPressed: onAction == null
                            ? null
                            : () {
                                onAction!();
                              },
                        child: Text(actionLabel!),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  final String label;

  const InfoChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final s = AppSurfaces.maybeOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: s?.tile ?? const Color(0xFFF8F3E8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: s?.tile ?? const Color(0xFF8D6E3F).withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: s == null ? FontWeight.w700 : FontWeight.w500,
          color: s?.text ?? const Color(0xFF5C4522),
        ),
      ),
    );
  }
}

/// One card per online tafsir edition (Ibn Kathir / Tabari / Qurtubi) letting the
/// user download the whole edition for offline reading, watch progress, and
/// delete just that edition's cached pages. On-demand page caching also lands
/// here, so this reflects everything cached.
class TafsirDownloadsSection extends StatefulWidget {
  final TafsirCacheService service;
  const TafsirDownloadsSection({super.key, required this.service});

  @override
  State<TafsirDownloadsSection> createState() => _TafsirDownloadsSectionState();
}

class _TafsirDownloadsSectionState extends State<TafsirDownloadsSection> {
  final Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    widget.service.downloadState.addListener(_onDownloadChanged);
    // Counting the cached pages (thousands of files) waits until the page
    // has slid in (owner, 2026-11-13).
    afterOpening(_refresh);
  }

  @override
  void dispose() {
    widget.service.downloadState.removeListener(_onDownloadChanged);
    super.dispose();
  }

  void _onDownloadChanged() {
    // When a download finishes (goes idle), re-read cached page counts.
    if (!widget.service.downloadState.value.isDownloading) _refresh();
  }

  Future<void> _refresh() async {
    final counts = <String, int>{};
    for (final e in TafsirEdition.onlineEditions) {
      counts[e.id] = await widget.service.cachedPageCount(e);
      if (!mounted) return;
    }
    // one rebuild for all editions
    setState(() => _counts.addAll(counts));
  }

  Future<void> _delete(TafsirEdition e) async {
    final s = AppSurfaces.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: s?.sheet,
        shape: _dialogShape(s),
        title: Text('حذف ${e.name}', textDirection: TextDirection.rtl),
        content: Text(
          'سيتم حذف صفحات ${e.name} المحمّلة من الجهاز. يمكن إعادة تنزيلها لاحقًا. هل تريد المتابعة؟',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            style: _quietTextStyle(s),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: _primaryStyle(s),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.service.deleteEdition(e);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TafsirDownloadState>(
      valueListenable: widget.service.downloadState,
      builder: (context, dl, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in TafsirEdition.onlineEditions) ...[
              _editionCard(e, dl),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _editionCard(TafsirEdition e, TafsirDownloadState dl) {
    const total = TafsirEdition.onlinePageCount;
    final bool activeHere = dl.isDownloading && dl.editionId == e.id;
    final bool activeOther = dl.isDownloading && dl.editionId != e.id;
    final int cached = activeHere ? dl.done : (_counts[e.id] ?? 0);
    final bool complete = cached >= total;

    final String statusLabel = activeHere
        ? 'جارٍ التحميل'
        : complete
        ? 'مكتملة'
        : cached > 0
        ? 'جزئية'
        : 'غير محمّلة';

    // null in the previous look and in night mode: the old colours stay
    final s = AppSurfaces.maybeOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: s?.card ?? const Color(0xFFF3EFE6),
        borderRadius: BorderRadius.circular(
          s == null ? 18 : AppSurfaces.radius,
        ),
        border: Border.all(
          color: s?.border ?? const Color(0xFF8D6E3F).withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: TextDirection.rtl,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: s?.icon ?? const Color(0xFF5C4522),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: s == null
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: s?.text ?? const Color(0xFF2F2418),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      e.subtitle,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: s?.muted ?? const Color(0xFF6A5A45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Download lives in Settings (TafsirDownloadTile) — this page only
          // shows what's cached and lets the user delete it.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            textDirection: TextDirection.rtl,
            children: [
              InfoChip(label: '$cached / $total صفحة'),
              InfoChip(label: statusLabel),
              if (cached > 0 && !activeHere)
                FilledButton.tonal(
                  style: _tonalStyle(s),
                  onPressed: activeOther ? null : () => _delete(e),
                  child: const Text('حذف'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// «أصوات الأذكار»: the athkar's recordings for listening without internet,
/// in the voices the athkar play in (owner, 2026-11-20: in the downloads
/// page, one card like the others, nothing more). A thin bar while it
/// downloads; delete takes every athkar recording off the phone.
class AthkarDownloadsCard extends StatefulWidget {
  const AthkarDownloadsCard({super.key});

  @override
  State<AthkarDownloadsCard> createState() => _AthkarDownloadsCardState();
}

class _AthkarDownloadsCardState extends State<AthkarDownloadsCard> {
  final _service = AthkarDownloadService.instance;

  @override
  void initState() {
    super.initState();
    afterOpening(_service.refresh);
  }

  static String _mb(int bytes) {
    final value = bytes / (1024 * 1024);
    if (value >= 10) return '${value.toStringAsFixed(0)} MB';
    return '${value.toStringAsFixed(1)} MB';
  }

  static String _voicesLine(List<String> voices) {
    if (voices.isEmpty) return 'لتسمع الأذكار دون إنترنت.';
    if (voices.length == 1) return 'بصوت ${voices.first}، لتسمعها دون إنترنت.';
    final others = voices.length == 2 ? 'بصوت ${voices[1]}' : 'بأصوات أخرى';
    return 'بصوت ${voices.first}، وما لم يسجّله $others، لتسمعها دون إنترنت.';
  }

  Future<void> _delete() async {
    final s = AppSurfaces.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: s?.sheet,
        shape: _dialogShape(s),
        title: const Text(
          'حذف أصوات الأذكار',
          textDirection: TextDirection.rtl,
        ),
        content: const Text(
          'سيتم حذف تسجيلات الأذكار من الجهاز، وتُسمع من الإنترنت عند تشغيلها. هل تريد المتابعة؟',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            style: _quietTextStyle(s),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: _primaryStyle(s),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) await _service.delete();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSurfaces.maybeOf(context);
    final accent = s?.accent ?? const Color(0xFF8D6E3F);
    return ValueListenableBuilder<AthkarDownloadState>(
      valueListenable: _service.state,
      builder: (context, st, _) {
        final progress = st.total == 0 ? 0.0 : st.done / st.total;
        // one chip: where it stands and how big it is
        final status = st.downloading
            ? 'جارٍ التحميل ${(progress * 100).floor()}%'
            : st.failed
            ? 'توقف، تحقق من الاتصال'
            : st.complete
            ? 'مكتملة · ${_mb(st.bytes)}'
            : st.done > 0
            ? 'جزئية · ${_mb(st.bytes)}'
            : 'نحو ${_mb(st.estimate)}';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: s?.card ?? const Color(0xFFF3EFE6),
            borderRadius: BorderRadius.circular(
              s == null ? 18 : AppSurfaces.radius,
            ),
            border: Border.all(
              color:
                  s?.border ?? const Color(0xFF8D6E3F).withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: TextDirection.rtl,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.record_voice_over_outlined,
                  color: s?.icon ?? const Color(0xFF5C4522),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أصوات الأذكار',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: s == null
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: s?.text ?? const Color(0xFF2F2418),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _voicesLine(st.voices),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: s?.muted ?? const Color(0xFF6A5A45),
                      ),
                    ),
                    if (st.downloading) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          color: accent,
                          backgroundColor: accent.withValues(alpha: 0.15),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      textDirection: TextDirection.rtl,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InfoChip(label: status),
                        if (st.downloading)
                          FilledButton.tonal(
                            style: _tonalStyle(s),
                            onPressed: _service.cancel,
                            child: const Text('إيقاف'),
                          )
                        else if (!st.complete && st.total > 0)
                          FilledButton.tonal(
                            style: _tonalStyle(s),
                            onPressed: _service.download,
                            child: const Text('تحميل'),
                          ),
                        if (!st.downloading && st.bytes > 0)
                          FilledButton.tonal(
                            style: _tonalStyle(s),
                            onPressed: _delete,
                            child: const Text('حذف'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

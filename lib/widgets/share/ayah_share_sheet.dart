import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/reciter.dart';
import '../../services/app_update_service.dart';
import '../../services/reciter_service.dart';
import '../../services/share/ayah_share_text.dart';
import '../../services/share/ayah_video_service.dart';
import '../../services/share/share_video_config.dart';
import '../../theme/app_surfaces.dart';
import 'ayah_video_player.dart';

/// Wording the server can change (`strings` in share_video.json).
String _t(
  String key,
  String fallback, [
  Map<String, Object?> args = const {},
]) => ShareVideoConfig.tr(key, fallback, args);

/// The share icon of the ayah menu: «فيديو الآية» or «نص الآية». Where the
/// video cannot be made (web, or switched off from the server) the text is
/// shared straight away.
Future<void> showAyahShareSheet(
  BuildContext context, {
  required int surah,
  required int ayah,
}) async {
  final config = await ShareVideoConfig.load();
  await AppUpdateService.instance.load();
  final video =
      config.videoOn(
        platform: Platform.isIOS ? 'ios' : 'android',
        build: AppUpdateService.instance.currentBuild,
      ) &&
      await AyahVideoService.instance.isSupported();
  if (!context.mounted) return;
  if (!video) {
    await AyahShareText.share(context, surah, ayah);
    return;
  }
  final c = _SheetColors.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: c.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheet) {
      Widget option(String id, IconData icon, String title, String sub) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(sheet).pop(id),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.hair),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c.iconBack,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: c.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: c.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              _Handle(color: c.handle),
              const SizedBox(height: 10),
              Text(
                _t('sheetTitle', 'مشاركة الآية'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 14),
              option(
                'video',
                Icons.videocam_rounded,
                _t('videoChoice', 'فيديو الآية'),
                _t('videoChoiceNote', 'تلاوة بخط المصحف على خلفية متحركة'),
              ),
              option(
                'text',
                Icons.text_fields_rounded,
                _t('textChoice', 'نص الآية'),
                _t('textChoiceNote', 'النص مع اسم السورة ورقم الآية'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'text') {
    await AyahShareText.share(context, surah, ayah);
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _AyahVideoSheet(config: config, surah: surah, ayah: ayah, colors: c),
    );
  }
}

class _SheetColors {
  const _SheetColors({
    required this.sheet,
    required this.card,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.hair,
    required this.handle,
    required this.chip,
    required this.chipOn,
    required this.onChipOn,
    required this.iconBack,
  });

  final Color sheet;
  final Color card;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color hair;
  final Color handle;
  final Color chip;
  final Color chipOn;
  final Color onChipOn;
  final Color iconBack;

  static _SheetColors of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = AppSurfaces.maybeOf(context);
    if (dark || s == null) {
      return dark
          ? const _SheetColors(
              sheet: Color(0xFF19130A),
              card: Color(0xFF241B0D),
              text: Color(0xFFFFF4D6),
              muted: Color(0xFF9C8A62),
              accent: Color(0xFFD6B35D),
              onAccent: Color(0xFF19130A),
              hair: Color(0xFF6B5527),
              handle: Color(0xFF6B5527),
              chip: Color(0xFF2E2414),
              chipOn: Color(0xFFD6B35D),
              onChipOn: Color(0xFF19130A),
              iconBack: Color(0xFF2E2414),
            )
          : const _SheetColors(
              sheet: Color(0xFFF8F1DE),
              card: Color(0xFFFFFBF1),
              text: Color(0xFF35250E),
              muted: Color(0xFFA8977A),
              accent: Color(0xFF8D6E3F),
              onAccent: Colors.white,
              hair: Color(0xFFE2D2A5),
              handle: Color(0xFFD9C79A),
              chip: Color(0xFFEADDBB),
              chipOn: Color(0xFF8D6E3F),
              onChipOn: Colors.white,
              iconBack: Color(0xFFF1E7CF),
            );
    }
    return _SheetColors(
      sheet: s.sheet,
      card: s.card,
      text: s.text,
      muted: s.muted,
      accent: s.accent,
      onAccent: s.onButton,
      hair: s.hair,
      handle: s.handle,
      chip: s.tile,
      chipOn: s.selected,
      onChipOn: s.onSelected,
      iconBack: s.tile,
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 5,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(10),
    ),
  );
}

enum _Phase { choose, working, done, failed }

class _AyahVideoSheet extends StatefulWidget {
  const _AyahVideoSheet({
    required this.config,
    required this.surah,
    required this.ayah,
    required this.colors,
  });

  final ShareVideoConfig config;
  final int surah;
  final int ayah;
  final _SheetColors colors;

  @override
  State<_AyahVideoSheet> createState() => _AyahVideoSheetState();
}

class _AyahVideoSheetState extends State<_AyahVideoSheet> {
  static const _prefBg = 'shareVideo.background';
  static const _prefShape = 'shareVideo.shape';
  static const _prefEffect = 'shareVideo.effect';

  late ShareVideoShape _shape = widget.config.shapes.first;
  late ShareVideoEffect _effect = widget.config.effects.first;
  late ShareVideoBackground _bg =
      widget.config.background(widget.config.defaultBackground) ??
      widget.config.backgrounds.first;
  late String _category = _bg.category;
  late Reciter _reciter = ReciterService.instance.selected.value;
  late int _from = widget.ayah;
  late int _to = widget.ayah;
  int _count = 0;

  /// [_reciter]'s breaths in this surah: the range only ever starts and ends
  /// on a breath's edge. Null while loading, or when it cannot be loaded
  /// (then the buttons step by one ayah and making the video still widens
  /// the range to whole breaths).
  AyahBreaths? _breaths;

  /// How long [_from]..[_to] plays, when known.
  Duration? _length;
  bool _measuring = false;
  bool _stepping = false;
  String _limitNote = '';
  int _breathsGen = 0;
  int _measureGen = 0;

  _Phase _phase = _Phase.choose;
  AyahVideoProgress? _progress;
  File? _result;
  ShareVideoShape? _resultShape;

  /// The gallery copy of [_result]: null while it is being saved.
  GallerySave? _saved;
  String _error = '';
  String _note = '';

  _SheetColors get c => widget.colors;
  ShareVideoConfig get config => widget.config;

  @override
  void initState() {
    super.initState();
    _restore();
    AyahVideoService.instance.ayahCount(widget.surah).then((n) {
      if (mounted) setState(() => _count = n);
    });
    _loadBreaths();
  }

  /// The reciter's breaths, then the range moved out to whole breaths: a
  /// joining (Habti) reciter never gets a range that ends where he does
  /// not stop. Runs again whenever the reciter changes.
  Future<void> _loadBreaths() async {
    final gen = ++_breathsGen;
    setState(() {
      _breaths = null;
      _length = null;
      _limitNote = '';
    });
    try {
      final b = await AyahVideoService.instance.breaths(_reciter, widget.surah);
      if (!mounted || gen != _breathsGen) return;
      setState(() {
        _breaths = b;
        _from = b.at(_from).from;
        _to = b.at(_to).to;
      });
      _measure();
    } catch (e) {
      debugPrint('AyahVideo: breaths: $e');
    }
  }

  Future<void> _measure() async {
    final b = _breaths;
    if (b == null) return;
    final gen = ++_measureGen;
    setState(() => _measuring = true);
    final len = await AyahVideoService.instance.rangeLength(
      _reciter,
      b,
      _from,
      _to,
    );
    if (!mounted || gen != _measureGen) return;
    setState(() {
      _length = len;
      _measuring = false;
    });
  }

  /// Moves the range to [from]..[to]. Growing it past the limits (owner,
  /// 2026-11-18: 4 minutes; and the ayat count) is refused with a note,
  /// except within a single breath: the longest ayah alone always fits.
  Future<void> _setRange(int from, int to) async {
    final b = _breaths;
    final look = config.video;
    final growing = to - from > _to - _from;
    final single = b != null && b.indexOf(from) == b.indexOf(to);
    if (b != null && growing && !single) {
      if (to - from + 1 > look.maxAyat) {
        setState(
          () => _limitNote = _t('limitAyat', 'لا يزيد الفيديو على {n} آية', {
            'n': look.maxAyat,
          }),
        );
        return;
      }
      setState(() => _stepping = true);
      final len = await AyahVideoService.instance.rangeLength(
        _reciter,
        b,
        from,
        to,
      );
      if (!mounted) return;
      if (len != null && len.inMilliseconds > look.maxSeconds * 1000) {
        setState(() {
          _stepping = false;
          _limitNote = _t('limitTime', 'لا يزيد الفيديو على {limit}', {
            'limit': AyahVideoService.formatLimit(look.maxSeconds),
          });
        });
        return;
      }
      _measureGen++;
      setState(() {
        _stepping = false;
        _from = from;
        _to = to;
        _length = len;
        _measuring = false;
        _limitNote = '';
      });
      return;
    }
    setState(() {
      _from = from;
      _to = to;
      _limitNote = '';
    });
    _measure();
  }

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final bg = config.background(prefs.getString(_prefBg));
      if (bg != null) {
        _bg = bg;
        _category = bg.category;
      }
      final shape = prefs.getString(_prefShape);
      for (final s in config.shapes) {
        if (s.id == shape) _shape = s;
      }
      final effect = prefs.getString(_prefEffect);
      for (final e in config.effects) {
        if (e.id == effect) _effect = e;
      }
    });
  }

  Future<void> _remember() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBg, _bg.id);
    await prefs.setString(_prefShape, _shape.id);
    await prefs.setString(_prefEffect, _effect.id);
  }

  @override
  void dispose() {
    final pr = _progress;
    if (_phase == _Phase.working && pr != null) {
      AyahVideoService.instance.cancel(pr);
    }
    pr?.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    _remember();
    final progress = AyahVideoProgress();
    setState(() {
      _phase = _Phase.working;
      _progress?.dispose();
      _progress = progress;
      _error = '';
      _note = '';
    });
    try {
      final plan = await AyahVideoService.instance.plan(
        _reciter,
        widget.surah,
        _from,
        _to,
      );
      if (plan.from != _from || plan.to != _to) {
        // The reciter joins these ayat in one breath, so the video holds
        // the whole breath.
        _note = _t(
          'breathWidened',
          'يقرأ القارئ هذه الآيات بنفَس واحد، فشمل الفيديو الآيات من {from} إلى {to}.',
          {'from': plan.from, 'to': plan.to},
        );
      }
      final out = await AyahVideoService.instance.render(
        config: config,
        reciter: _reciter,
        plan: plan,
        shape: _shape,
        background: _bg,
        effect: _effect,
        progress: progress,
      );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _result = out;
        _resultShape = _shape;
      });
      // It plays in the sheet at once (AyahVideoPlayer) and goes into the
      // gallery meanwhile; sharing is the button under it.
      _saveToGallery();
    } on AyahVideoCancelled {
      if (mounted) setState(() => _phase = _Phase.choose);
    } on AyahVideoError catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = e.message;
        });
      }
    } catch (e) {
      debugPrint('AyahVideo: $e');
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = _t('renderFailed', 'تعذّر إنشاء الفيديو');
        });
      }
    }
  }

  Future<void> _saveToGallery() async {
    final f = _result;
    if (f == null) return;
    setState(() => _saved = null);
    final saved = await AyahVideoService.instance.saveToGallery(f);
    if (mounted && _result == f) setState(() => _saved = saved);
  }

  Future<void> _share() async {
    final f = _result;
    if (f == null) return;
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(f.path, mimeType: 'video/mp4')],
          sharePositionOrigin: box == null || !box.hasSize
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      debugPrint('AyahVideo: share failed: $e');
    }
  }

  // ───────────────────── layout ─────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _Handle(color: c.handle)),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _t('videoTitle', 'فيديو الآية'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...switch (_phase) {
              _Phase.choose => _chooser(),
              _Phase.working => _working(),
              _Phase.done => _done(),
              _Phase.failed => _failed(),
            },
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
    child: Text(t, style: TextStyle(fontSize: 13, color: c.muted)),
  );

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
    child: Material(
      color: on ? c.chipOn : c.chip,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: on ? FontWeight.w800 : FontWeight.w500,
              color: on ? c.onChipOn : c.text,
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _chooser() {
    final maxAyat = config.video.maxAyat;
    final count = _count == 0 ? widget.ayah : _count;
    return [
      _label(_t('reciter', 'القارئ')),
      _reciterPicker(),
      _label(_t('shape', 'الشكل')),
      Wrap(
        children: [
          for (final s in config.shapes)
            _chip(s.title, s.id == _shape.id, () => setState(() => _shape = s)),
        ],
      ),
      _label(_t('background', 'الخلفية')),
      Wrap(
        children: [
          for (final cat in config.categories)
            _chip(
              cat.title,
              cat.id == _category,
              () => setState(() => _category = cat.id),
            ),
        ],
      ),
      SizedBox(
        height: 76,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final b in config.backgrounds.where(
              (b) => b.category == _category,
            ))
              _BgThumb(
                key: ValueKey(b.id),
                config: config,
                background: b,
                selected: b.id == _bg.id,
                accent: c.accent,
                placeholder: c.chip,
                onTap: () => setState(() => _bg = b),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(_bg.title, style: TextStyle(fontSize: 12.5, color: c.text)),
      ),
      _label(_t('effect', 'تأثير الصوت')),
      Wrap(
        children: [
          for (final e in config.effects)
            _chip(
              e.title,
              e.id == _effect.id,
              () => setState(() => _effect = e),
            ),
        ],
      ),
      _label(_t('ayat', 'الآيات')),
      Row(
        children: [
          Expanded(
            child: _Stepper(
              label: _t('from', 'من'),
              value: _from,
              colors: c,
              onMinus: _stepping ? null : _fromMinus(),
              onPlus: _stepping ? null : _fromPlus(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stepper(
              label: _t('to', 'إلى'),
              value: _to,
              colors: c,
              onMinus: _stepping ? null : _toMinus(),
              onPlus: _stepping ? null : _toPlus(count, maxAyat),
            ),
          ),
        ],
      ),
      ..._rangeNotes(),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _tooLong || _stepping ? null : _make,
              icon: const Icon(Icons.movie_creation_outlined),
              label: Text(
                _t('create', 'إنشاء الفيديو'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t('close', 'إغلاق'), style: TextStyle(color: c.text)),
          ),
        ],
      ),
    ];
  }

  // Each button moves by a whole breath once the breaths are known.
  VoidCallback? _fromMinus() {
    final b = _breaths;
    if (b == null) return _from > 1 ? () => _setRange(_from - 1, _to) : null;
    final i = b.indexOf(_from);
    return i > 0 ? () => _setRange(b.list[i - 1].from, _to) : null;
  }

  VoidCallback? _fromPlus() {
    final b = _breaths;
    if (b == null) return _from < _to ? () => _setRange(_from + 1, _to) : null;
    final i = b.indexOf(_from);
    return b.list[i].to < _to ? () => _setRange(b.list[i + 1].from, _to) : null;
  }

  VoidCallback? _toMinus() {
    final b = _breaths;
    if (b == null) return _to > _from ? () => _setRange(_from, _to - 1) : null;
    final i = b.indexOf(_to);
    return b.list[i].from > _from
        ? () => _setRange(_from, b.list[i - 1].to)
        : null;
  }

  VoidCallback? _toPlus(int count, int maxAyat) {
    final b = _breaths;
    if (b == null) {
      return _to < count && _to - _from + 1 < maxAyat
          ? () => _setRange(_from, _to + 1)
          : null;
    }
    final i = b.indexOf(_to);
    return i < b.list.length - 1
        ? () => _setRange(_from, b.list[i + 1].to)
        : null;
  }

  /// Making the video waits for a range that fits the limit.
  bool get _tooLong {
    final b = _breaths;
    final len = _length;
    return b != null &&
        len != null &&
        b.indexOf(_from) != b.indexOf(_to) &&
        len.inMilliseconds > config.video.maxSeconds * 1000;
  }

  /// Under the ayat: the length, the reciter's joined ayat at the range's
  /// edges, and why a button stopped.
  List<Widget> _rangeNotes() {
    final lines = <String>[];
    final b = _breaths;
    if (b != null) {
      for (final e in {b.at(_from), b.at(_to)}) {
        if (e.isJoined) {
          lines.add(
            _t(
              'breathNote',
              'يقرأ هذا القارئ الآيات {from} إلى {to} بنفَس واحد',
              {'from': e.from, 'to': e.to},
            ),
          );
        }
      }
    }
    final len = _length;
    final over = _tooLong;
    return [
      if (_measuring || len != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            len == null || _measuring
                ? _t('lengthMeasuring', 'مدة التلاوة…')
                : _t('length', 'مدة التلاوة نحو {time}', {'time': _clock(len)}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: over ? Colors.red.shade700 : c.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ),
      if (_limitNote.isNotEmpty || over)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            over
                ? _t('tooLong', 'المقطع أطول من {limit}، قصّره', {
                    'limit': AyahVideoService.formatLimit(
                      config.video.maxSeconds,
                    ),
                  })
                : _limitNote,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
          ),
        ),
    ];
  }

  Widget _reciterPicker() {
    return ValueListenableBuilder<int>(
      // the list grows when the server adds a reciter
      valueListenable: ReciterService.instance.revision,
      builder: (context, _, _) {
        final reciters = ReciterService.instance.reciters;
        if (!reciters.any((r) => r.id == _reciter.id) && reciters.isNotEmpty) {
          _reciter = reciters.first;
        }
        return PopupMenuButton<String>(
          initialValue: _reciter.id,
          color: c.sheet,
          constraints: BoxConstraints(
            minWidth: 240,
            maxHeight: ReciterService.pickerMenuMaxHeight(48),
          ),
          onSelected: (id) {
            for (final r in reciters) {
              if (r.id == id && r.id != _reciter.id) {
                setState(() => _reciter = r);
                _loadBreaths();
              }
            }
          },
          itemBuilder: (_) => [
            for (final r in reciters)
              PopupMenuItem<String>(
                value: r.id,
                child: Text(
                  r.shortName,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: r.id == _reciter.id
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.hair),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 20, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _reciter.shortName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.expand_more_rounded, color: c.muted),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _working() {
    final pr = _progress!;
    return [
      const SizedBox(height: 26),
      ValueListenableBuilder<String>(
        valueListenable: pr.stage,
        builder: (_, stage, _) => Text(
          stage.isEmpty ? _t('preparing', 'جارٍ التجهيز') : stage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: c.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 14),
      ValueListenableBuilder<double?>(
        valueListenable: pr.fraction,
        builder: (_, f, _) => Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: f,
                minHeight: 8,
                color: c.accent,
                backgroundColor: c.chip,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              f == null ? '' : '${(f * 100).round()}%',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _t('privacyNote', 'يُنشأ الفيديو على هاتفك، ولا يُرفع إلى أي مكان.'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: c.muted),
      ),
      const SizedBox(height: 16),
      Center(
        child: TextButton(
          onPressed: () => AyahVideoService.instance.cancel(pr),
          child: Text(_t('cancel', 'إلغاء'), style: TextStyle(color: c.text)),
        ),
      ),
    ];
  }

  List<Widget> _done() => [
    const SizedBox(height: 12),
    if (_result case final f?)
      AyahVideoPlayer(
        // A new file needs a new native view: the view reads its path once.
        key: ValueKey('${f.path}#${_result.hashCode}'),
        file: f,
        aspectRatio:
            (_resultShape ?? _shape).width / (_resultShape ?? _shape).height,
        accent: c.accent,
      ),
    const SizedBox(height: 10),
    _galleryLine(),
    if (_note.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _note,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
      ),
    const SizedBox(height: 14),
    FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      onPressed: _share,
      icon: const Icon(Icons.share_rounded),
      label: Text(
        _t('shareVideo', 'مشاركة الفيديو'),
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    const SizedBox(height: 6),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () => setState(() => _phase = _Phase.choose),
          child: Text(
            _t('another', 'فيديو آخر'),
            style: TextStyle(color: c.text),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t('close', 'إغلاق'), style: TextStyle(color: c.text)),
        ),
      ],
    ),
  ];

  /// «تم الحفظ في معرض الصور», or why not with a retry.
  Widget _galleryLine() {
    final saved = _saved;
    final (IconData icon, String text) = switch (saved) {
      null => (
        Icons.downloading_rounded,
        _t('gallerySaving', 'جارٍ الحفظ في معرض الصور…'),
      ),
      GallerySave.saved => (
        Icons.check_circle_rounded,
        _t('gallerySaved', 'تم الحفظ في معرض الصور'),
      ),
      GallerySave.denied => (
        Icons.block_rounded,
        _t(
          'galleryDenied',
          'لم يُحفظ: اسمح للتطبيق بإضافة الصور من إعدادات الهاتف',
        ),
      ),
      GallerySave.noSpace => (
        Icons.sd_card_alert_rounded,
        _t('galleryNoSpace', 'لم يُحفظ: لا توجد مساحة كافية في الهاتف'),
      ),
      GallerySave.failed => (
        Icons.error_outline_rounded,
        _t('galleryFailed', 'تعذّر الحفظ في معرض الصور'),
      ),
    };
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Icon(
          icon,
          size: 18,
          color: saved == GallerySave.saved ? c.accent : c.muted,
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: saved == GallerySave.saved ? c.text : c.muted,
          ),
        ),
        if (saved != null && saved != GallerySave.saved)
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            onPressed: _saveToGallery,
            child: Text(
              _t('retrySave', 'حاول مجددًا'),
              style: TextStyle(color: c.accent),
            ),
          ),
      ],
    );
  }

  List<Widget> _failed() => [
    const SizedBox(height: 22),
    Icon(Icons.error_outline_rounded, size: 42, color: c.muted),
    const SizedBox(height: 8),
    Text(
      _error,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 15,
        color: c.text,
        fontWeight: FontWeight.w700,
      ),
    ),
    const SizedBox(height: 16),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: c.onAccent,
          ),
          onPressed: _make,
          child: Text(_t('retry', 'حاول مرة أخرى')),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => setState(() => _phase = _Phase.choose),
          child: Text(_t('back', 'رجوع'), style: TextStyle(color: c.text)),
        ),
      ],
    ),
  ];
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.colors,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final _SheetColors colors;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    Widget button(IconData icon, VoidCallback? onTap) => IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      color: c.text,
      disabledColor: c.muted.withValues(alpha: 0.5),
      style: IconButton.styleFrom(backgroundColor: c.chip),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.hair),
      ),
      child: Row(
        children: [
          button(Icons.remove_rounded, onMinus),
          Expanded(
            child: Text(
              '$label $value',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
            ),
          ),
          button(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }
}

/// A background's picture; downloaded the first time it scrolls into view
/// (the clip itself only when it is used).
class _BgThumb extends StatelessWidget {
  const _BgThumb({
    super.key,
    required this.config,
    required this.background,
    required this.selected,
    required this.accent,
    required this.placeholder,
    required this.onTap,
  });

  final ShareVideoConfig config;
  final ShareVideoBackground background;
  final bool selected;
  final Color accent;
  final Color placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: FutureBuilder<File?>(
              future: AyahVideoService.instance.thumb(config, background),
              builder: (_, snap) {
                final f = snap.data;
                if (f == null) return ColoredBox(color: placeholder);
                return Image.file(
                  f,
                  fit: BoxFit.cover,
                  cacheWidth: 160,
                  errorBuilder: (_, _, _) => ColoredBox(color: placeholder),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

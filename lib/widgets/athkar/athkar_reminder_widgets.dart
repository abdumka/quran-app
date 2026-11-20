import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/athkar.dart';
import '../../services/athkar_reminder_service.dart';
import '../../services/athkar_service.dart';
import '../../services/city_key.dart';
import '../../services/city_search_service.dart';
import '../../services/daily_page_service.dart';
import '../../services/notification_center.dart';
import '../../services/tv_service.dart';
import '../settings/daily_page_tile.dart'
    show DailyPageTimeSheet, formatDailyPageTime, formatNextReminder;
import '../settings/settings_components.dart';
import 'athkar_home_page.dart';
import 'athkar_reader_page.dart';
import 'athkar_widgets.dart';

/// Whether this device shows the athkar reminders at all (phones only).
bool get athkarRemindersShown =>
    AthkarReminderService.supported && !TvService.instance.isTv;

// ------------------------------------------------------------------ words

/// «10 دقائق», «50 دقيقة».
String athkarMinutesText(int minutes) {
  final m = minutes.abs();
  if (m == 1) return 'دقيقة';
  if (m == 2) return 'دقيقتين';
  if (m <= 10) return '$m دقائق';
  return '$m دقيقة';
}

/// «قبل الشروق بـ50 دقيقة», «عند الغروب», «بعد الشروق بـ20 دقيقة».
String athkarOffsetText(AthkarReminderKind kind, int offset) {
  if (offset == 0) return 'عند ${kind.sunWord}';
  return '${offset < 0 ? 'قبل' : 'بعد'} ${kind.sunWord} بـ${athkarMinutesText(offset)}';
}

String _clock(DateTime t) => formatDailyPageTime(t.hour * 60 + t.minute);

/// The place line: «طرابلس», or «طرابلس (حسب توقيت هاتفك)» before one is set.
String athkarPlaceText() {
  final s = AthkarReminderService.instance;
  final chosen = s.place.value;
  if (chosen != null) return chosen.name;
  final zone = s.zonePlace.value;
  if (zone == null) return 'لم يُحدَّد بعد';
  return zone.name.isEmpty
      ? 'حسب توقيت هاتفك'
      : '${zone.name} (حسب توقيت هاتفك)';
}

/// One line for a reminder in a list: how it is timed.
String athkarReminderSummary(AthkarReminderKind kind) {
  final s = AthkarReminderService.instance;
  final c = s.config(kind).value;
  if (!c.on) return 'متوقف';
  if (c.mode == AthkarReminderMode.fixed) {
    return 'كل يوم ${formatDailyPageTime(c.fixedMinutes)}';
  }
  return '${athkarOffsetText(kind, c.offset)}، ${athkarPlaceText()}';
}

Listenable get _athkarReminderListenable {
  final s = AthkarReminderService.instance;
  return Listenable.merge([s.morning, s.evening, s.place, s.zonePlace]);
}

Future<void> _explainDenied(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      content: const Text(
        'الإشعارات غير مسموحة لهذا التطبيق. اسمح بها من إعدادات الهاتف ثم أعد المحاولة.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('حسنًا'),
        ),
      ],
    ),
  ),
);

Future<void> _toggle(
  BuildContext context,
  AthkarReminderKind kind,
  bool value,
) async {
  final r = await AthkarReminderService.instance.setEnabled(kind, value);
  if (r == DailyPageEnableResult.permissionDenied && context.mounted) {
    await _explainDenied(context);
  }
}

// ------------------------------------------------------------------ opening

/// Opens the athkar a tapped reminder is for: the «أذكار الصباح» or «أذكار
/// المساء» tile's section (from the data, so a server update can move it).
Future<void> openAthkarForReminder(
  NavigatorState navigator,
  AthkarReminderKind kind,
) async {
  await Future.wait([
    AthkarService.instance.load(),
    AthkarStore.instance.load(),
  ]);
  final icon = kind == AthkarReminderKind.morning ? 'sun' : 'moon';
  AthkarFeatured? tile;
  for (final f in AthkarService.instance.data.featured) {
    if (f.icon == icon) tile = f;
  }
  if (!navigator.mounted) return;
  if (tile == null) {
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const AthkarHomePage()),
    );
    return;
  }
  final section = tile;
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => AthkarReaderPage(
        title: section.label,
        items: section.section.items,
        section: section.section,
      ),
    ),
  );
}

// ------------------------------------------------------------------ location

/// What asking for the phone's location gave.
class AthkarLocateResult {
  const AthkarLocateResult({this.place, this.note, this.openSettings});

  final AthkarPlace? place;

  /// Why there is no place, for the top of the city list.
  final String? note;

  /// Opens the phone's settings where the reader can fix it.
  final Future<bool> Function()? openSettings;
}

/// The phone's approximate location as a place. Only "while using the app"
/// and approximate is asked for; the reading stays on the phone.
Future<AthkarLocateResult> locateAthkarPlace() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const AthkarLocateResult(
        note: 'خدمة الموقع متوقفة في هاتفك. شغّلها، أو اختر مدينتك من القائمة.',
        openSettings: Geolocator.openLocationSettings,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return const AthkarLocateResult(
        note:
            'الموقع غير مسموح لهذا التطبيق. لتسمح به: افتح الإعدادات، ثم الأذونات '
            'أو الخصوصية، ثم الموقع، واختر «أثناء استخدام التطبيق». '
            'ويمكنك بدلًا من ذلك اختيار مدينتك.',
        openSettings: Geolocator.openAppSettings,
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return const AthkarLocateResult(
        note: 'لا بأس، اختر مدينتك من القائمة. الوقت محسوب لها بالدقة نفسها.',
      );
    }
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }
    if (position == null) {
      return const AthkarLocateResult(
        note: 'لم نتمكن من معرفة موقعك الآن، فاختر مدينتك من القائمة.',
      );
    }
    return AthkarLocateResult(
      place: await CitySearchService.instance.placeForLocation(
        position.latitude,
        position.longitude,
      ),
    );
  } catch (error) {
    debugPrint('locateAthkarPlace failed: $error');
    return const AthkarLocateResult(
      note: 'لم نتمكن من معرفة موقعك الآن، فاختر مدينتك من القائمة.',
    );
  }
}

/// The city list; returns the place picked (or null).
Future<AthkarPlace?> pickAthkarPlace(
  BuildContext context, {
  AthkarLocateResult? why,
}) => Navigator.of(context).push<AthkarPlace>(
  MaterialPageRoute(builder: (_) => AthkarCityPickerPage(why: why)),
);

/// Picks a place (location first when [useLocation]) and saves it.
Future<void> chooseAthkarPlace(
  BuildContext context, {
  bool useLocation = false,
}) async {
  final service = AthkarReminderService.instance;
  AthkarLocateResult? why;
  if (useLocation) {
    why = await locateAthkarPlace();
    if (why.place != null) {
      await service.setPlace(why.place!);
      return;
    }
  }
  if (!context.mounted) return;
  final picked = await pickAthkarPlace(context, why: why);
  if (picked != null) await service.setPlace(picked);
}

// ------------------------------------------------------------------ intro

/// The first opening of الأذكار (owner, 2026-11-19): one screen says what the
/// reminders are, then the phone asks for notifications and for the
/// location; a reader who says no to the location picks a city. Shown once,
/// whatever the answer; never at app start.
Future<void> maybeShowAthkarReminderIntro(BuildContext context) async {
  if (!athkarRemindersShown) return;
  final service = AthkarReminderService.instance;
  await service.load();
  if (service.introShown || !context.mounted) return;
  await service.markIntroShown();
  if (!context.mounted) return;
  final c = AthkarColors.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: c.card,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.wb_twilight_rounded, color: c.icon, size: 34),
              const SizedBox(height: 10),
              Text(
                'تذكير بأذكار الصباح والمساء',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'نذكّرك كل يوم بأذكار الصباح قبل الشروق بـ50 دقيقة، وبأذكار '
                'المساء قبل الغروب بـ30 دقيقة. ويمكنك تغيير الوقت أو إيقاف '
                'التذكير من الإعدادات.',
                style: TextStyle(color: c.text, fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 8),
              Text(
                'لنحسب الشروق والغروب عندك نحتاج إلى موقعك التقريبي أو اسم '
                'مدينتك. يُحسب الوقت على هاتفك، ولا يُرسَل موقعك إلى أي جهة.',
                style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.6),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.button,
                  foregroundColor: c.onButton,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(sheet).pop('location'),
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('استخدم موقعي'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () => Navigator.of(sheet).pop('city'),
                child: const Text('اختر مدينتي من القائمة'),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheet).pop(),
                child: Text('ليس الآن', style: TextStyle(color: c.muted)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    if (choice != null) {
      await NotificationCenter.instance.requestPermission();
      if (context.mounted) {
        await chooseAthkarPlace(context, useLocation: choice == 'location');
      }
    }
    // notifications may have just been allowed: the reminders that were left
    // at their default (these two and «صفحة اليوم») come on now
    await service.refreshSchedule(force: true);
    await DailyPageService.instance.refreshSchedule();
  } catch (error) {
    debugPrint('athkar reminder intro: $error');
  }
}

// ------------------------------------------------------------------ editor

/// The settings of one reminder: on/off, «مع الشروق» or «وقت محدد», the
/// 10-minute steps, the place and the next time it fires.
Future<void> showAthkarReminderEditor(
  BuildContext context,
  AthkarReminderKind kind,
) {
  final c = AthkarColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.card,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AthkarReminderEditor(kind: kind),
  );
}

class _AthkarReminderEditor extends StatelessWidget {
  const _AthkarReminderEditor({required this.kind});

  final AthkarReminderKind kind;

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    final s = AthkarReminderService.instance;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: _athkarReminderListenable,
          builder: (context, _) {
            final cfg = s.config(kind).value;
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final next = s.nextFire(kind);
            final sun = s.sunEvent(kind, today);
            Widget muted(String text) => Text(
              text,
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'تذكير ${kind.label}',
                          style: TextStyle(
                            color: c.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Switch(
                        value: cfg.on,
                        onChanged: (v) => _toggle(context, kind, v),
                      ),
                    ],
                  ),
                  muted(
                    kind == AthkarReminderKind.morning
                        ? 'تذكير كل صباح بأذكار الصباح.'
                        : 'تذكير كل مساء بأذكار المساء.',
                  ),
                  if (cfg.on) ...[
                    const SizedBox(height: 14),
                    _ModePills(kind: kind, mode: cfg.mode),
                    const SizedBox(height: 14),
                    if (cfg.mode == AthkarReminderMode.sun) ...[
                      Row(
                        children: [
                          _StepButton(
                            label: 'قدّم 10',
                            onTap: cfg.offset > kind.minOffset
                                ? () => s.moveOffset(kind, -10)
                                : null,
                          ),
                          Expanded(
                            child: Text(
                              athkarOffsetText(kind, cfg.offset),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _StepButton(
                            label: 'أخّر 10',
                            onTap: cfg.offset < kind.maxOffset
                                ? () => s.moveOffset(kind, 10)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      muted(
                        s.effectivePlace == null
                            ? 'اختر مكانًا ليُحسب ${kind.sunWord}.'
                            : sun == null
                            ? (kind == AthkarReminderKind.morning
                                  ? 'لا تشرق الشمس هنا اليوم، فنذكّرك في وقت ثابت.'
                                  : 'لا تغيب الشمس هنا اليوم، فنذكّرك في وقت ثابت.')
                            : '${kind.sunWord} اليوم ${_clock(sun)}، '
                                  'والتذكير ${_clock(s.fireTime(kind, today))}.',
                      ),
                      const SizedBox(height: 12),
                      const AthkarPlaceRow(),
                      const SizedBox(height: 6),
                      muted('يتغيّر وقت التذكير كل يوم مع الشروق والغروب.'),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'وقت التذكير',
                              style: TextStyle(color: c.text, fontSize: 15),
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.text,
                            ),
                            onPressed: () async {
                              final m = await DailyPageTimeSheet.show(
                                context,
                                title: 'وقت تذكير ${kind.label}',
                                initialMinutes: cfg.fixedMinutes,
                              );
                              if (m != null) {
                                await s.setFixedMinutes(kind, m);
                              }
                            },
                            child: Text(formatDailyPageTime(cfg.fixedMinutes)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      muted('التذكير في وقت ثابت لا يحتاج إلى مكان.'),
                    ],
                    if (next != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                            color: c.icon,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'التذكير القادم: ${formatNextReminder(next)}',
                              style: TextStyle(
                                color: c.icon,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ModePills extends StatelessWidget {
  const _ModePills({required this.kind, required this.mode});

  final AthkarReminderKind kind;
  final AthkarReminderMode mode;

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    Widget pill(AthkarReminderMode m, String label) {
      final on = m == mode;
      return Expanded(
        child: Material(
          color: on ? c.button : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => AthkarReminderService.instance.setMode(kind, m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: on ? c.onButton : c.text,
                  fontSize: 14.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.hair),
      ),
      child: Row(
        children: [
          pill(AthkarReminderMode.sun, 'مع ${kind.sunWord}'),
          pill(AthkarReminderMode.fixed, 'وقت محدد'),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.hair),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}

/// «المكان: طرابلس» with «تغيير» (the city list, or the location again).
class AthkarPlaceRow extends StatelessWidget {
  const AthkarPlaceRow({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    return ListenableBuilder(
      listenable: _athkarReminderListenable,
      builder: (context, _) {
        final chosen = AthkarReminderService.instance.place.value;
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.hair),
          ),
          child: Row(
            children: [
              Icon(
                chosen?.source == 'gps'
                    ? Icons.my_location_rounded
                    : Icons.place_outlined,
                color: c.icon,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      athkarPlaceText(),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((chosen?.detail ?? '').isNotEmpty)
                      Text(
                        chosen!.detail,
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => chooseAthkarPlace(context),
                child: Text(
                  chosen == null ? 'اختر' : 'تغيير',
                  style: TextStyle(color: c.accent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ rows

/// The two reminders as rows in «إعدادات الأذكار».
class AthkarReminderRows extends StatelessWidget {
  const AthkarReminderRows({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    final s = AthkarReminderService.instance;
    return ListenableBuilder(
      listenable: _athkarReminderListenable,
      builder: (context, _) => Column(
        children: [
          for (final kind in AthkarReminderKind.values)
            ListTile(
              dense: true,
              title: Text(
                'تذكير ${kind.label}',
                style: TextStyle(color: c.text, fontSize: 15.5),
              ),
              subtitle: Text(
                athkarReminderSummary(kind),
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
              trailing: Switch(
                value: s.config(kind).value.on,
                onChanged: (v) => _toggle(context, kind, v),
              ),
              onTap: () => showAthkarReminderEditor(context, kind),
            ),
        ],
      ),
    );
  }
}

/// The two reminders in Settings «التذكير والورد اليومي», next to «صفحة
/// اليوم» and «سورة الكهف» (owner, 2026-11-19): the same switches as in
/// «إعدادات الأذكار»; a tap on the line under one opens its settings.
class AthkarRemindersSettingsTile extends StatelessWidget {
  const AthkarRemindersSettingsTile({super.key, this.onInfo});

  final VoidCallback? onInfo;

  static const Color _gold = Color(0xFF8B7355);

  @override
  Widget build(BuildContext context) {
    final s = AthkarReminderService.instance;
    return SettingsCard(
      framed: false,
      child: ListenableBuilder(
        listenable: _athkarReminderListenable,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final kind in AthkarReminderKind.values)
                SettingsSwitchRow(
                  title: kind.label,
                  icon: kind == AthkarReminderKind.morning
                      ? Icons.wb_twilight_rounded
                      : Icons.nights_stay_rounded,
                  value: s.config(kind).value.on,
                  onChanged: (v) => _toggle(context, kind, v),
                  onInfo: kind == AthkarReminderKind.morning ? onInfo : null,
                  subtitle: InkWell(
                    onTap: () => showAthkarReminderEditor(context, kind),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: athkarReminderSummary(kind)),
                            const TextSpan(
                              text: '  ·  تعديل',
                              style: TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF888888),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ city list

/// «اختر مدينتك»: Libya's main cities from the app (offline), every other
/// place from our server while the reader types, and «استخدم موقعي».
class AthkarCityPickerPage extends StatefulWidget {
  const AthkarCityPickerPage({super.key, this.why});

  /// Why the location did not give a place, shown on top.
  final AthkarLocateResult? why;

  @override
  State<AthkarCityPickerPage> createState() => _AthkarCityPickerPageState();
}

class _AthkarCityPickerPageState extends State<AthkarCityPickerPage> {
  final TextEditingController _query = TextEditingController();
  final CitySearchService _cities = CitySearchService.instance;
  Timer? _debounce;
  int _seq = 0;
  String _text = '';
  List<CityResult> _libya = const [];
  List<CityResult> _world = const [];
  bool _searching = false;
  bool _offline = false;
  bool _locating = false;
  AthkarLocateResult? _why;

  @override
  void initState() {
    super.initState();
    _why = widget.why;
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  Future<void> _search(String value) async {
    final seq = ++_seq;
    final libya = await _cities.libya(value);
    if (!mounted || seq != _seq) return;
    final q = CitySearchService.queryWords(value);
    final long = q.any((w) => w.length >= 2);
    setState(() {
      _text = value.trim();
      _libya = libya;
      _world = const [];
      _offline = false;
      _searching = long;
    });
    if (!long) return;
    try {
      final found = await _cities.online(value);
      if (!mounted || seq != _seq) return;
      // the Libyan cities already listed are not repeated
      final shown = [
        for (final t in libya) (CityKey.key(t.name), t.lat, t.lon),
      ];
      setState(() {
        _searching = false;
        _world = [
          for (final r in found)
            if (!shown.any(
              (s) =>
                  s.$1 == CityKey.key(r.name) &&
                  CitySearchService.kmBetween(s.$2, s.$3, r.lat, r.lon) < 15,
            ))
              r,
        ].take(80).toList();
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _searching = false;
        _offline = true;
      });
    }
  }

  Future<void> _useLocation() async {
    setState(() => _locating = true);
    final r = await locateAthkarPlace();
    if (!mounted) return;
    setState(() => _locating = false);
    if (r.place != null) {
      Navigator.of(context).pop(r.place);
    } else {
      setState(() => _why = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AthkarColors.of(context);
    Widget header(String text, IconData icon) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.muted),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: c.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Text(
        text,
        style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
      ),
    );
    Widget city(CityResult r) => ListTile(
      title: Text(r.name, style: TextStyle(color: c.text, fontSize: 15.5)),
      subtitle: r.detail.isEmpty
          ? null
          : Text(r.detail, style: TextStyle(color: c.muted, fontSize: 12.5)),
      onTap: () => Navigator.of(context).pop(r.toPlace()),
    );
    final nothing =
        _text.isNotEmpty &&
        _libya.isEmpty &&
        _world.isEmpty &&
        !_searching &&
        !_offline;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: c.page,
        appBar: AppBar(
          backgroundColor: c.page,
          foregroundColor: c.text,
          elevation: 0,
          title: const Text('اختر مدينتك'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: TextField(
                controller: _query,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(color: c.text),
                decoration: InputDecoration(
                  hintText: 'ابحث بالعربية أو الإنجليزية',
                  hintStyle: TextStyle(color: c.muted),
                  prefixIcon: Icon(Icons.search_rounded, color: c.muted),
                  filled: true,
                  fillColor: c.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.hair),
                  ),
                ),
              ),
            ),
            if (!TvService.instance.isTv)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _locating ? null : _useLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.my_location_rounded, color: c.accent),
                    label: Text(
                      'استخدم موقعي',
                      style: TextStyle(color: c.accent),
                    ),
                  ),
                ),
              ),
            if (_why?.note != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.hair),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _why!.note!,
                      style: TextStyle(color: c.text, fontSize: 13.5, height: 1.5),
                    ),
                    if (_why!.openSettings != null)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => _why!.openSettings!(),
                          child: Text(
                            'افتح الإعدادات',
                            style: TextStyle(color: c.accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (_libya.isNotEmpty) ...[
                    header('ليبيا (في التطبيق)', Icons.smartphone_rounded),
                    for (final r in _libya) city(r),
                  ],
                  if (_text.isEmpty)
                    note('للبحث عن مدينة خارج ليبيا أو عن بلدة ليبية أخرى اكتب اسمها.')
                  else ...[
                    if (_searching || _offline || _world.isNotEmpty)
                      header('أماكن أخرى', Icons.public_rounded),
                    if (_searching)
                      note('يبحث…')
                    else if (_offline)
                      note(
                        'البحث عن أماكن غير المدن الموجودة في التطبيق يحتاج إلى '
                        'الإنترنت. مدن ليبيا الرئيسية تعمل دائمًا.',
                      ),
                    for (final r in _world) city(r),
                    if (nothing) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                        child: Text(
                          'لم نجد «$_text»',
                          style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      note(
                        'اختر أقرب مدينة إليك: كل 25 كم شرقًا أو غربًا تغيّر '
                        'الوقت نحو دقيقة واحدة فقط.',
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

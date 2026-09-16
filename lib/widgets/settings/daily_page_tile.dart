import 'package:flutter/material.dart';

import '../../services/daily_page_service.dart';
import 'settings_components.dart';

const Color _gold = Color(0xFF8B7355);
const Color _border = Color(0xFFE8DCC8);

/// Formats a minute-of-day as a 12-hour Arabic clock string, e.g. "٨:٠٠" is
/// avoided on purpose — the rest of the app uses Western digits (see the
/// "صفحة N" label in the reader's top bar), so this matches.
String formatDailyPageTime(int minutesOfDay) {
  final hour24 = minutesOfDay ~/ 60;
  final minute = minutesOfDay % 60;
  final period = hour24 < 12 ? 'ص' : 'م';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

const List<String> _weekdayNames = [
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// "غدًا 8:00 م" / "الخميس 8:00 م" — a short, human description of when the
/// next reminder lands.
String formatNextReminder(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final daysAway = day.difference(today).inDays;
  final time = formatDailyPageTime(when.hour * 60 + when.minute);
  if (daysAway == 0) return 'اليوم $time';
  if (daysAway == 1) return 'غدًا $time';
  return '${_weekdayNames[when.weekday - 1]} $time';
}

/// The "صفحة اليوم" setting: a switch that turns the daily reading reminder on,
/// and — once on — the controls for when it fires.
///
/// Deliberately a full-width card rather than one of the compact two-per-row
/// switches: enabling it reveals a mode picker and one or two time fields, and
/// the disclosure only reads properly when it expands inside its own card.
class DailyPageTile extends StatelessWidget {
  final bool enabled;
  final DailyPageReminderMode mode;
  final int fixedMinutes;
  final int windowStartMinutes;
  final int windowEndMinutes;
  final DateTime? nextReminderAt;
  final ValueChanged<bool> onToggle;
  final ValueChanged<DailyPageReminderMode> onModeChanged;
  final ValueChanged<int> onFixedMinutesChanged;
  final void Function(int start, int end) onWindowChanged;
  final VoidCallback? onInfo;

  const DailyPageTile({
    super.key,
    required this.enabled,
    required this.mode,
    required this.fixedMinutes,
    required this.windowStartMinutes,
    required this.windowEndMinutes,
    required this.nextReminderAt,
    required this.onToggle,
    required this.onModeChanged,
    required this.onFixedMinutesChanged,
    required this.onWindowChanged,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                // Not auto_stories_rounded: "عرض الصفحتين" already uses it two
                // tiles up, and two identical icons in one list read as the
                // same kind of setting.
                const Icon(Icons.today_rounded, color: _gold, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: SettingsTileHeader(
                    title: 'صفحة اليوم',
                    onInfo: onInfo,
                  ),
                ),
                Switch(
                  activeThumbColor: _gold,
                  value: enabled,
                  onChanged: onToggle,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                'تذكير يومي بقراءة صفحة واحدة على الأقل، مع صفحة عشوائية تُفتح بالضغط على الإشعار.',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF888888),
                  height: 1.4,
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: enabled
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: _buildSchedule(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedule(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 18, thickness: 0.5, color: _border),
        _ModeSelector(mode: mode, onChanged: onModeChanged),
        const SizedBox(height: 10),
        if (mode == DailyPageReminderMode.fixed)
          ReminderTimeField(
            label: 'وقت التذكير',
            minutesOfDay: fixedMinutes,
            onPick: onFixedMinutesChanged,
          )
        else
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: ReminderTimeField(
                  label: 'من',
                  minutesOfDay: windowStartMinutes,
                  // Two fields sharing a phone's width can't fit a label and a
                  // time on one line, so these stack.
                  stacked: true,
                  onPick: (value) => onWindowChanged(value, windowEndMinutes),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ReminderTimeField(
                  label: 'إلى',
                  minutesOfDay: windowEndMinutes,
                  stacked: true,
                  onPick: (value) => onWindowChanged(windowStartMinutes, value),
                ),
              ),
            ],
          ),
        if (nextReminderAt != null) ...[
          const SizedBox(height: 8),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                size: 14,
                color: _gold,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'التذكير القادم: ${formatNextReminder(nextReminderAt!)}',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _gold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Two-way picker for "وقت محدد" vs "وقت عشوائي", styled like the rest of the
/// settings chips.
class _ModeSelector extends StatelessWidget {
  final DailyPageReminderMode mode;
  final ValueChanged<DailyPageReminderMode> onChanged;

  const _ModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: _segment(
              label: 'وقت محدد',
              icon: Icons.schedule_rounded,
              selected: mode == DailyPageReminderMode.fixed,
              onTap: () => onChanged(DailyPageReminderMode.fixed),
            ),
          ),
          Expanded(
            child: _segment(
              label: 'وقت عشوائي',
              icon: Icons.shuffle_rounded,
              selected: mode == DailyPageReminderMode.random,
              onTap: () => onChanged(DailyPageReminderMode.random),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? _gold : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            textDirection: TextDirection.rtl,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : _gold,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : _gold,
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

/// A labelled, tappable time value that opens [DailyPageTimeSheet].
///
/// [stacked] puts the label on its own line above the value, for the two
/// side-by-side fields of the random window where a single line does not fit on
/// a phone.
/// The bordered "label — time" button that opens [DailyPageTimeSheet]. Shared
/// with the Friday Al-Kahf reminder tile.
class ReminderTimeField extends StatelessWidget {
  final String label;
  final int minutesOfDay;
  final bool stacked;
  final ValueChanged<int> onPick;

  const ReminderTimeField({
    super.key,
    required this.label,
    required this.minutesOfDay,
    required this.onPick,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      textDirection: TextDirection.rtl,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: stacked ? 11 : 13,
        fontWeight: FontWeight.w600,
        color: stacked ? const Color(0xFF888888) : const Color(0xFF2C2C2C),
      ),
    );
    final valueRow = Row(
      textDirection: TextDirection.rtl,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            formatDailyPageTime(minutesOfDay),
            textDirection: TextDirection.rtl,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: _gold,
            ),
          ),
        ),
        const SizedBox(width: 2),
        const Icon(Icons.expand_more_rounded, size: 18, color: _gold),
      ],
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await DailyPageTimeSheet.show(
            context,
            title: label,
            initialMinutes: minutesOfDay,
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: stacked ? 8 : 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [labelText, const SizedBox(height: 2), valueRow],
                )
              : Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(child: labelText),
                    const SizedBox(width: 6),
                    valueRow,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Arabic 12-hour time picker.
///
/// Flutter's own `showTimePicker` renders from MaterialLocalizations, which
/// this app doesn't ship an Arabic delegate for — it would drop an English
/// "AM/PM" dialog into an otherwise fully Arabic settings screen. Three wheels
/// keep it in-language and are quicker to set than the dial anyway.
class DailyPageTimeSheet extends StatefulWidget {
  final String title;
  final int initialMinutes;

  const DailyPageTimeSheet({
    super.key,
    required this.title,
    required this.initialMinutes,
  });

  static Future<int?> show(
    BuildContext context, {
    required String title,
    required int initialMinutes,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          DailyPageTimeSheet(title: title, initialMinutes: initialMinutes),
    );
  }

  @override
  State<DailyPageTimeSheet> createState() => _DailyPageTimeSheetState();
}

class _DailyPageTimeSheetState extends State<DailyPageTimeSheet> {
  static const double _itemExtent = 40;

  late int _hour12;
  late int _minute;
  late bool _isPm;

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  @override
  void initState() {
    super.initState();
    final hour24 = widget.initialMinutes ~/ 60;
    _minute = widget.initialMinutes % 60;
    _isPm = hour24 >= 12;
    _hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    _hourController = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
    _periodController = FixedExtentScrollController(initialItem: _isPm ? 1 : 0);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  int get _minutesOfDay {
    final base = _hour12 % 12;
    return (base + (_isPm ? 12 : 0)) * 60 + _minute;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF6F1E5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C2C2C),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatDailyPageTime(_minutesOfDay),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 10),
              // Three bare columns of numbers give no clue which is which, so
              // each wheel is captioned. Same Directionality as the wheels
              // below, so the captions sit over the columns they name.
              const Row(
                children: [
                  Expanded(child: _WheelLabel('ساعة')),
                  Expanded(child: _WheelLabel('دقيقة')),
                  Expanded(child: _WheelLabel('ص / م')),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: _itemExtent * 3,
                child: Stack(
                  children: [
                    // Selection band behind the wheels: an outlined row that
                    // reads as "this line is the value", rather than a faint
                    // tint that could pass for decoration.
                    Center(
                      child: Container(
                        height: _itemExtent,
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _wheel(
                            controller: _hourController,
                            count: 12,
                            labelFor: (index) => '${index + 1}',
                            onSelected: (index) =>
                                setState(() => _hour12 = index + 1),
                          ),
                        ),
                        Expanded(
                          child: _wheel(
                            controller: _minuteController,
                            count: 60,
                            labelFor: (index) =>
                                index.toString().padLeft(2, '0'),
                            onSelected: (index) =>
                                setState(() => _minute = index),
                          ),
                        ),
                        Expanded(
                          child: _wheel(
                            controller: _periodController,
                            count: 2,
                            labelFor: (index) => index == 0 ? 'ص' : 'م',
                            onSelected: (index) =>
                                setState(() => _isPm = index == 1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(_minutesOfDay),
                  child: const Text(
                    'حفظ',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
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

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int index) labelFor,
    required ValueChanged<int> onSelected,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      physics: const FixedExtentScrollPhysics(),
      overAndUnderCenterOpacity: 0.35,
      onSelectedItemChanged: onSelected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) => Center(
          child: Text(
            labelFor(index),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2C2C2C),
            ),
          ),
        ),
      ),
    );
  }
}

/// Caption over one column of [DailyPageTimeSheet]'s wheels.
class _WheelLabel extends StatelessWidget {
  final String text;

  const _WheelLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: _gold.withValues(alpha: 0.75),
      ),
    );
  }
}

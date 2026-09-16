import 'package:flutter/material.dart';

import 'daily_page_tile.dart';
import 'settings_components.dart';

const Color _gold = Color(0xFF8B7355);
const Color _border = Color(0xFFE8DCC8);

/// The "سورة الكهف" setting: a switch for the weekly Friday reminder and, once
/// on, the time it fires — always in the device's own local time.
///
/// Shaped like [DailyPageTile] (full-width card, disclosure on enable) because
/// they sit next to each other in Settings and read as one pair of reminders.
class KahfReminderTile extends StatelessWidget {
  final bool enabled;
  final int minutes;
  final DateTime? nextReminderAt;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onMinutesChanged;
  final VoidCallback? onInfo;

  const KahfReminderTile({
    super.key,
    required this.enabled,
    required this.minutes,
    required this.nextReminderAt,
    required this.onToggle,
    required this.onMinutesChanged,
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
                const Icon(
                  Icons.calendar_month_rounded,
                  color: _gold,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SettingsTileHeader(
                    title: 'سورة الكهف',
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
                'تذكير كل يوم جمعة بقراءة سورة الكهف، تُفتح بالضغط على الإشعار.',
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
              secondChild: _buildSchedule(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 18, thickness: 0.5, color: _border),
        ReminderTimeField(
          label: 'وقت التذكير',
          minutesOfDay: minutes,
          onPick: onMinutesChanged,
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

import 'package:flutter/material.dart';

import '../../services/absence_reminder_service.dart';
import '../../services/daily_page_service.dart';
import '../../theme/app_surfaces.dart';
import 'settings_components.dart';

/// «لا تهجر القرآن» in التذكير والورد اليومي: the switch, and while it is on
/// the number of days without opening the app before it reminds (3, 5, 7).
class AbsenceReminderTile extends StatelessWidget {
  const AbsenceReminderTile({
    super.key,
    required this.onResult,
    required this.onInfo,
  });

  /// Shows the notice for a refused or unsupported switch-on.
  final ValueChanged<DailyPageEnableResult> onResult;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final service = AbsenceReminderService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([service.enabled, service.days]),
      builder: (context, _) {
        final s = AppSurfaces.maybeOf(context);
        final on = service.enabled.value;
        final d = service.days.value;
        return Padding(
          padding: SettingsSwitchRow.padding,
          child: SettingsSwitchRow(
            title: AbsenceReminderService.title,
            icon: Icons.notifications_none_rounded,
            onInfo: onInfo,
            value: on,
            onChanged: (value) async {
              final result = await service.setEnabled(value);
              if (result != DailyPageEnableResult.ok) onResult(result);
            },
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تنبيه إذا لم تفتح المصحف $d أيام',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 12,
                    color: s?.muted ?? const Color(0xFF7B7266),
                  ),
                ),
                if (on) ...[
                  const SizedBox(height: 6),
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      for (final choice in AbsenceReminderService.dayChoices)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            key: ValueKey('absenceDays$choice'),
                            label: Text('$choice أيام'),
                            selected: d == choice,
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            selectedColor:
                                s?.selected ?? const Color(0xFFE6D09A),
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: s?.text ?? const Color(0xFF35250E),
                            ),
                            side: BorderSide(
                              color: s?.border ?? const Color(0xFFE2D2A5),
                            ),
                            onSelected: (_) => service.setDays(choice),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../../config/image_config.dart';
import '../../models/reciter.dart';
import '../../models/tafsir_edition.dart';
import '../../services/audio_download_service.dart';
import '../../services/tafsir_cache_service.dart';
import '../../services/margin_images_service.dart';
import '../../services/high_quality_images_service.dart';
import '../../services/page_color_service.dart';
import '../../surah_data.dart';

class PremiumIconWrapper extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const PremiumIconWrapper({super.key, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? const Color(0xFF8B7355);
    return Icon(icon, color: iconColor, size: 24);
  }
}

class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(right: 16, left: 16, top: 14, bottom: 6),
      child: Text(
        title,
        textDirection: TextDirection.rtl,
        style: const TextStyle(
          color: Color(0xFF8B7355), // Light gold
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  final Widget child;

  const SettingsCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE8DCC8),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

class ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const ActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      dense: true,
      visualDensity: VisualDensity.compact,
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF8B7355)),
      title: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(
              title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C2C2C),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PremiumIconWrapper(icon: icon),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF888888),
            height: 1.4,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// A compact, square-ish navigation card meant to sit two-per-row. Shows an
/// icon and a short title only (no subtitle), so a pair fits the width that a
/// single full ActionTile used to take.
/// A small circular ℹ️ button used to open a setting's instruction card.
class InfoHintButton extends StatelessWidget {
  final VoidCallback onTap;

  const InfoHintButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: Color(0xFF8B7355),
        ),
      ),
    );
  }
}

/// A reusable header row for the larger settings tiles (those with a title and
/// descriptive subtitle). Lays the title out RTL with an optional ℹ️ button
/// next to it so every setting can surface its instruction popup.
class SettingsTileHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onInfo;

  const SettingsTileHeader({super.key, required this.title, this.onInfo});

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Flexible(
          child: Text(
            title,
            textDirection: TextDirection.rtl,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
        ),
        if (onInfo != null) ...[
          const SizedBox(width: 4),
          InfoHintButton(onTap: onInfo!),
        ],
      ],
    );
  }
}

class CompactActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onInfo;

  const CompactActionTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8DCC8), width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              PremiumIconWrapper(icon: icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
              ),
              if (onInfo != null) InfoHintButton(onTap: onInfo!),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact toggle card meant to sit two-per-row: icon, single-line title,
/// and a switch — for simple on/off settings that don't need a subtitle.
class CompactSwitchTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onInfo;

  /// Optional custom leading icon, used instead of [icon] when provided.
  final Widget? iconOverride;

  const CompactSwitchTile({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.onInfo,
    this.iconOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!value),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8DCC8), width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              iconOverride ??
                  Icon(icon, color: const Color(0xFF8B7355), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
              ),
              if (onInfo != null) ...[
                InfoHintButton(onTap: onInfo!),
                const SizedBox(width: 2),
              ],
              const SizedBox(width: 4),
              Switch(
                activeThumbColor: const Color(0xFF8B7355),
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DownloadsManagementTile extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback? onInfo;

  const DownloadsManagementTile({super.key, required this.onOpen, this.onInfo});

  @override
  Widget build(BuildContext context) {
    // The whole row is tappable (no separate "فتح" button): tapping the title
    // opens the downloads management page. The ℹ button keeps its own tap.
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: SettingsTileHeader(
                  title: 'إدارة الملفات المحمّلة',
                  onInfo: onInfo,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_left_rounded, color: Color(0xFF8B7355)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets the user pick which reciter (تلاوة) is used for playback and downloads.
/// A dropdown so it stays compact and organized as more reciters are added.
class ReciterTile extends StatelessWidget {
  final List<Reciter> reciters;
  final Reciter selected;
  final ValueChanged<Reciter> onSelect;
  final VoidCallback? onInfo;

  const ReciterTile({
    super.key,
    required this.reciters,
    required this.selected,
    required this.onSelect,
    this.onInfo,
  });

  Widget _reciterRow(
    Reciter r, {
    required bool checked,
    bool showRiwaya = true,
  }) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Icon(
          checked ? Icons.check_circle_rounded : Icons.person_outline_rounded,
          size: 18,
          color: checked ? const Color(0xFF8B7355) : const Color(0xFFB7A88E),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.name,
                textDirection: TextDirection.rtl,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C2C2C),
                ),
              ),
              if (showRiwaya)
                Text(
                  r.riwaya,
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF888888),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = reciters.firstWhere(
      (r) => r.id == selected.id,
      orElse: () => reciters.first,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'القارئ',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          if (onInfo != null) ...[
            const SizedBox(width: 4),
            InfoHintButton(onTap: onInfo!),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EFE6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF8D6E3F).withValues(alpha: 0.20),
                ),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Reciter>(
                    isExpanded: true,
                    isDense: true,
                    value: current,
                    itemHeight: 54,
                    borderRadius: BorderRadius.circular(12),
                    dropdownColor: const Color(0xFFF6F1E5),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF8B7355),
                    ),
                    onChanged: (r) {
                      if (r != null && r.id != selected.id) onSelect(r);
                    },
                    selectedItemBuilder: (context) => [
                      for (final r in reciters)
                        _reciterRow(r, checked: false, showRiwaya: false),
                    ],
                    items: [
                      for (final r in reciters)
                        DropdownMenuItem<Reciter>(
                          value: r,
                          child: _reciterRow(r, checked: r.id == selected.id),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings dropdown for choosing the default tafsir edition. Mirrors
/// [ReciterTile]; the reader can also switch editions live from the tafsir
/// sheet header.
class TafsirEditionTile extends StatelessWidget {
  final List<TafsirEdition> editions;
  final TafsirEdition selected;
  final ValueChanged<TafsirEdition> onSelect;
  final VoidCallback? onInfo;

  const TafsirEditionTile({
    super.key,
    required this.editions,
    required this.selected,
    required this.onSelect,
    this.onInfo,
  });

  Widget _editionRow(
    TafsirEdition e, {
    required bool checked,
    bool showSubtitle = true,
  }) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Icon(
          checked
              ? Icons.check_circle_rounded
              : (e.isBundled
                  ? Icons.offline_pin_outlined
                  : Icons.cloud_outlined),
          size: 18,
          color: checked ? const Color(0xFF8B7355) : const Color(0xFFB7A88E),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.name,
                textDirection: TextDirection.rtl,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C2C2C),
                ),
              ),
              if (showSubtitle)
                Text(
                  e.isBundled ? e.subtitle : '${e.subtitle} • يتطلب إنترنت',
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF888888),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = editions.firstWhere(
      (e) => e.id == selected.id,
      orElse: () => editions.first,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'التفسير',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          if (onInfo != null) ...[
            const SizedBox(width: 4),
            InfoHintButton(onTap: onInfo!),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EFE6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF8D6E3F).withValues(alpha: 0.20),
                ),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TafsirEdition>(
                    isExpanded: true,
                    isDense: true,
                    value: current,
                    itemHeight: 54,
                    borderRadius: BorderRadius.circular(12),
                    dropdownColor: const Color(0xFFF6F1E5),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF8B7355),
                    ),
                    onChanged: (e) {
                      if (e != null && e.id != selected.id) onSelect(e);
                    },
                    selectedItemBuilder: (context) => [
                      for (final e in editions)
                        _editionRow(e, checked: false, showSubtitle: false),
                    ],
                    items: [
                      for (final e in editions)
                        DropdownMenuItem<TafsirEdition>(
                          value: e,
                          child: _editionRow(e, checked: e.id == selected.id),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AudioDownloadTile extends StatelessWidget {
  final AudioDownloadState state;

  /// Opens the surah download picker (choose "all" or a specific surah).
  final VoidCallback onOpenPicker;

  /// Resume/continue a previously started *full* download in place.
  final Future<void> Function() onDownload;
  final void Function() onCancelDownload;
  final void Function() onPauseDownload;
  final VoidCallback? onInfo;

  const AudioDownloadTile({
    super.key,
    required this.state,
    required this.onOpenPicker,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onPauseDownload,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final bool showInlineAction =
        !state.isComplete && !state.isDownloading && !state.isPaused;
    // Single-line states (idle / complete) use the same tight metrics as the
    // other settings rows; the busy states keep room for the progress UI.
    final bool isBusy = state.isDownloading || state.isPaused;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isBusy ? 10 : 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: SettingsTileHeader(
                    title: 'تحميل الصوتيات',
                    onInfo: onInfo,
                  ),
                ),
                if (state.isComplete) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_rounded,
                      size: 19, color: Color(0xFF4B7F3A)),
                  const SizedBox(width: 6),
                  const Text(
                    'محمّل بالكامل',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4B7F3A),
                    ),
                  ),
                ],
                if (showInlineAction) const SizedBox(width: 8),
                if (showInlineAction)
                  OutlinedButton.icon(
                    onPressed: onOpenPicker,
                    icon: const Icon(
                      Icons.download_rounded,
                      color: Color(0xFF8B7355),
                      size: 16,
                    ),
                    label: Text(
                      state.downloadedFiles > 0 ? 'متابعة التحميل' : 'تحميل',
                      style: const TextStyle(
                        color: Color(0xFF8B7355),
                        fontSize: 12.5,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF8B7355)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          if (state.isPaused && !state.isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: state.progressFraction,
                backgroundColor: const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB0956E)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: TextDirection.rtl,
              children: [
                Text(state.progressLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
                Text(state.percentLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8B7355))),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF8B7355), size: 18),
              label: const Text('استئناف التحميل', style: TextStyle(color: Color(0xFF8B7355), fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8B7355)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
          if (state.isDownloading) ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                  onPressed: onCancelDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.pause_circle_filled_rounded, color: Color(0xFF8B7355)),
                  onPressed: onPauseDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: state.progressFraction > 0 ? state.progressFraction : null,
                      backgroundColor: const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B7355)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: TextDirection.rtl,
              children: [
                Text(state.progressLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF888888))),
                Text(state.percentLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8B7355))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Downloads the currently selected tafsir for offline reading — the tafsir
/// analogue of [AudioDownloadTile]. Bundled editions (Sa'di/Muyassar/Jalalayn)
/// ship with the app so they show "محمّل مع التطبيق"; online editions (Ibn
/// Kathir/Tabari/Qurtubi) download their whole set of pages with progress.
class TafsirDownloadTile extends StatefulWidget {
  final TafsirCacheService service;
  final TafsirEdition edition;
  final VoidCallback? onInfo;

  const TafsirDownloadTile({
    super.key,
    required this.service,
    required this.edition,
    this.onInfo,
  });

  @override
  State<TafsirDownloadTile> createState() => _TafsirDownloadTileState();
}

class _TafsirDownloadTileState extends State<TafsirDownloadTile> {
  int _cached = 0;

  @override
  void initState() {
    super.initState();
    widget.service.downloadState.addListener(_onDownloadChanged);
    _refresh();
  }

  @override
  void didUpdateWidget(TafsirDownloadTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.edition.id != widget.edition.id) _refresh();
  }

  @override
  void dispose() {
    widget.service.downloadState.removeListener(_onDownloadChanged);
    super.dispose();
  }

  void _onDownloadChanged() {
    if (!widget.service.downloadState.value.isDownloading) _refresh();
  }

  Future<void> _refresh() async {
    if (!widget.edition.isOnline) {
      if (mounted) setState(() => _cached = 0);
      return;
    }
    final count = await widget.service.cachedPageCount(widget.edition);
    if (mounted) setState(() => _cached = count);
  }

  /// Names the tafsir and its approximate download size, then downloads it only
  /// on confirmation.
  Future<void> _confirmAndDownload(TafsirEdition e, int cached) async {
    const total = TafsirEdition.onlinePageCount;
    final remaining = total - cached;
    // Approximate the remaining size from the whole-edition estimate.
    final int remainingMb = e.approxDownloadMb > 0
        ? ((e.approxDownloadMb * remaining) / total).ceil()
        : 0;
    final String fullSize =
        e.approxDownloadMb > 0 ? '، نحو ${e.approxDownloadMb} ميجابايت' : '';
    final String remSize = remainingMb > 0 ? '، نحو $remainingMb ميجابايت' : '';
    final body = cached > 0
        ? 'سيتم تحميل ما تبقّى من «${e.name}» ($remaining صفحة$remSize) لقراءته بدون إنترنت. قد يستهلك بيانات. هل تريد المتابعة؟'
        : 'سيتم تحميل «${e.name}» كاملًا ($total صفحة$fullSize) لقراءته بدون إنترنت. قد يستغرق ذلك بعض الوقت ويستهلك بيانات. هل تريد المتابعة؟';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تحميل ${e.name}', textDirection: TextDirection.rtl),
        content: Text(body, textDirection: TextDirection.rtl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تحميل'),
          ),
        ],
      ),
    );
    if (ok == true) widget.service.downloadEdition(e);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TafsirDownloadState>(
      valueListenable: widget.service.downloadState,
      builder: (context, dl, _) {
        final e = widget.edition;
        const total = TafsirEdition.onlinePageCount;
        final bool activeHere = dl.isDownloading && dl.editionId == e.id;
        final bool activeOther = dl.isDownloading && dl.editionId != e.id;
        final int cached = activeHere ? dl.done : _cached;
        final bool complete = e.isOnline && cached >= total;
        final double fraction =
            activeHere ? dl.fraction : (total > 0 ? cached / total : 0);

        return Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 12, vertical: activeHere ? 10 : 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: SettingsTileHeader(
                        title: 'تحميل التفسير',
                        onInfo: widget.onInfo,
                      ),
                    ),
                    if (!e.isOnline) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.offline_pin_rounded,
                          size: 19, color: Color(0xFF4B7F3A)),
                      const SizedBox(width: 6),
                      const Text(
                        'محمّل مع التطبيق',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4B7F3A),
                        ),
                      ),
                    ] else if (complete) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.check_circle_rounded,
                          size: 19, color: Color(0xFF4B7F3A)),
                      const SizedBox(width: 6),
                      const Text(
                        'محمّل بالكامل',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4B7F3A),
                        ),
                      ),
                    ] else if (!activeHere) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: activeOther
                            ? null
                            : () => _confirmAndDownload(e, cached),
                        icon: const Icon(Icons.download_rounded,
                            color: Color(0xFF8B7355), size: 16),
                        label: Text(
                          cached > 0 ? 'متابعة التحميل' : 'تحميل',
                          style: const TextStyle(
                            color: Color(0xFF8B7355),
                            fontSize: 12.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF8B7355)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (activeHere) ...[
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                      onPressed: widget.service.cancelDownload,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: fraction > 0 ? fraction : null,
                          backgroundColor:
                              const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF8B7355)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  textDirection: TextDirection.rtl,
                  children: [
                    Text(
                      '$cached / $total صفحة',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF888888)),
                    ),
                    Text(
                      '${(fraction * 100).round()}%',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8B7355)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Lets the user pick one of three page-image quality levels (numbered so they
/// can be referred to plainly later) and download the optional high-fidelity
/// pack used by level 3. All sources are 720px, so the levels differ by render
/// smoothness and encoding fidelity, not resolution.
class PageQualityTile extends StatelessWidget {
  final int level;
  final HighQualityImagesState hqState;
  final ValueChanged<int> onSelectLevel;
  final Future<void> Function() onDownloadHq;
  final Future<void> Function() onCancelHqDownload;
  final Future<void> Function() onPauseHqDownload;
  final VoidCallback? onInfo;

  const PageQualityTile({
    super.key,
    required this.level,
    required this.hqState,
    required this.onSelectLevel,
    required this.onDownloadHq,
    required this.onCancelHqDownload,
    required this.onPauseHqDownload,
    this.onInfo,
  });

  static const Color _gold = Color(0xFF8B7355);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SettingsTileHeader(title: 'جودة عرض الصفحات', onInfo: onInfo),
          const SizedBox(height: 10),
          _option(
            number: '١',
            name: 'قياسي',
            hint: 'الوضع الحالي — الأخف والأسرع.',
            value: 1,
          ),
          _option(
            number: '٢',
            name: 'محسّن',
            hint: 'عرض أنعم للصفحة، بدون أي تنزيل أو زيادة في حجم التطبيق.',
            value: 2,
          ),
          _option(
            number: '٣',
            name: 'فائق الجودة',
            hint: kBundleHighFidelityImages
                ? 'صور أنقى وأقل ضغطًا (نفس الأبعاد)، مدمجة في التطبيق.'
                : 'حزمة صور أنقى وأقل ضغطًا (نفس الأبعاد). تتطلب تنزيلًا لمرة واحدة.',
            value: 3,
            footer: _hqFooter(),
          ),
        ],
      ),
    );
  }

  Widget _option({
    required String number,
    required String name,
    required String hint,
    required int value,
    Widget? footer,
  }) {
    final bool selected = level == value;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF6EFE2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? _gold : const Color(0xFFE8DCC8),
          width: selected ? 1.2 : 0.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelectLevel(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? _gold : const Color(0xFFEDE4D3),
                    ),
                    child: Text(
                      number,
                      style: TextStyle(
                        color: selected ? Colors.white : _gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          name,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2C2C2C),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF888888),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? _gold : const Color(0xFFBBB1A0),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: footer,
            ),
        ],
      ),
    );
  }

  Widget _hqFooter() {
    // When the high-fidelity pack ships inside the app there is nothing to
    // download — just confirm it is built in.
    if (kBundleHighFidelityImages) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        textDirection: TextDirection.rtl,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF4B7F3A)),
          SizedBox(width: 6),
          Text('مدمجة في التطبيق — لا تحتاج تنزيلاً',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4B7F3A))),
        ],
      );
    }

    if (hqState.isDownloading) {
      return Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.cancel_rounded, color: Colors.red, size: 22),
                onPressed: onCancelHqDownload,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.pause_circle_filled_rounded, color: _gold),
                onPressed: onPauseHqDownload,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: hqState.totalBytes > 0 ? hqState.progress : null,
                    backgroundColor: const Color(0xFFE8DCC8),
                    valueColor: const AlwaysStoppedAnimation<Color>(_gold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            textDirection: TextDirection.rtl,
            children: [
              Text(hqState.progressLabel,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
              Text(hqState.percentLabel,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: _gold)),
            ],
          ),
        ],
      );
    }

    if (hqState.isPaused) {
      return OutlinedButton.icon(
        onPressed: onDownloadHq,
        icon: const Icon(Icons.play_arrow_rounded, color: _gold, size: 18),
        label: Text('استئناف التنزيل (${hqState.progressLabel})',
            style: const TextStyle(color: _gold, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _gold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      );
    }

    if (hqState.isAvailable) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        textDirection: TextDirection.rtl,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF4B7F3A)),
          SizedBox(width: 6),
          Text('الحزمة محمّلة وجاهزة',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4B7F3A))),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: onDownloadHq,
      icon: const Icon(Icons.download_rounded, color: _gold, size: 18),
      label: Text('تنزيل حزمة الجودة الفائقة (${hqState.packageSizeLabel})',
          style: const TextStyle(color: _gold, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: _gold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}

class PageColorTile extends StatelessWidget {
  const PageColorTile({
    super.key,
    required this.selected,
    required this.onChanged,
    this.onInfo,
    this.onPreview,
  });

  final PageColorTheme selected;
  final ValueChanged<PageColorTheme> onChanged;
  final VoidCallback? onInfo;

  /// Opens the full-screen live preview (mushaf page + swatches + save).
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SettingsTileHeader(title: 'لون صفحات المصحف', onInfo: onInfo),
          const SizedBox(height: 10),
          // Live preview — recolors instantly as swatches are tapped, and
          // opens the full-screen preview when tapped.
          if (onPreview != null) ...[
            _PageColorPreviewThumbnail(theme: selected, onTap: onPreview!),
            const SizedBox(height: 12),
          ],
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: PageColorTheme.values.map((option) {
              return PageColorSwatch(
                option: option,
                isSelected: selected == option,
                onTap: () => onChanged(option),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// A single selectable paper-color chip. Shared by the settings tile and the
/// full-screen preview page so both look identical.
class PageColorSwatch extends StatelessWidget {
  const PageColorSwatch({
    super.key,
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final PageColorTheme option;
  final bool isSelected;
  final VoidCallback onTap;

  static const Color _gold = Color(0xFF8B7355);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: option.arabicLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 105,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFF6EFE2) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? _gold : const Color(0xFFE8DCC8),
                width: isSelected ? 1.4 : 0.7,
              ),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: option.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? _gold : const Color(0xFFB8AA94),
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: Color(0xFF5F4B32),
                        )
                      : null,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    option.arabicLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: const Color(0xFF3E3428),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a real mushaf page with the paper-color filter applied, so the user
/// sees exactly how the reader will look. When [croppedHeight] is set it shows
/// a fixed-height top crop (settings thumbnail); otherwise it shows the whole
/// page keeping its aspect ratio (full-screen preview).
class PageColorSamplePreview extends StatelessWidget {
  const PageColorSamplePreview({
    super.key,
    required this.theme,
    this.croppedHeight,
  });

  final PageColorTheme theme;
  final double? croppedHeight;

  static const String _sampleAsset = 'assets/images/page_3.webp';
  static const double _pageAspectRatio = 720 / 1640;

  @override
  Widget build(BuildContext context) {
    final filtered = ColorFiltered(
      colorFilter: theme.lightModeFilter,
      child: Image.asset(
        _sampleAsset,
        fit: croppedHeight != null ? BoxFit.cover : BoxFit.contain,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D3BC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: croppedHeight != null
            ? SizedBox(
                height: croppedHeight,
                width: double.infinity,
                child: filtered,
              )
            : AspectRatio(aspectRatio: _pageAspectRatio, child: filtered),
      ),
    );
  }
}

/// The tappable thumbnail shown inside [PageColorTile] with a "full-screen
/// preview" hint pill overlaid.
class _PageColorPreviewThumbnail extends StatelessWidget {
  const _PageColorPreviewThumbnail({
    required this.theme,
    required this.onTap,
  });

  final PageColorTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'معاينة لون الصفحة بملء الشاشة',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            PageColorSamplePreview(theme: theme, croppedHeight: 150),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fullscreen_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'معاينة',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen live preview: pick a paper color and see it applied to a real
/// mushaf page immediately, then save. Backing out leaves the saved color
/// untouched — the service is only written on save.
class PageColorPreviewPage extends StatefulWidget {
  const PageColorPreviewPage({super.key});

  @override
  State<PageColorPreviewPage> createState() => _PageColorPreviewPageState();
}

class _PageColorPreviewPageState extends State<PageColorPreviewPage> {
  final PageColorService _service = PageColorService.instance;
  late PageColorTheme _selected;

  static const Color _bg = Color(0xFFF6F1E5);
  static const Color _gold = Color(0xFF8D6E3F);

  @override
  void initState() {
    super.initState();
    _selected = _service.selected.value;
  }

  bool get _hasChanges => _selected != _service.selected.value;

  Future<void> _save() async {
    await _service.setSelected(_selected);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          centerTitle: true,
          elevation: 0,
          backgroundColor: _bg,
          foregroundColor: const Color(0xFF3D3122),
          title: const Text(
            'لون صفحات المصحف',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  'اختر لونًا لتشاهد أثره مباشرة على صفحة المصحف، ثم اضغط حفظ.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF6A5A45),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: PageColorSamplePreview(theme: _selected),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: PageColorTheme.values.map((option) {
                    return PageColorSwatch(
                      option: option,
                      isSelected: _selected == option,
                      onTap: () => setState(() => _selected = option),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _hasChanges
                        ? _save
                        : () => Navigator.of(context).pop(false),
                    child: Text(
                      _hasChanges ? 'حفظ' : 'تم',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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

class RecitationBarOpacityTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final double opacity;
  final ValueChanged<double> onChanged;
  final VoidCallback? onInfo;

  const RecitationBarOpacityTile({
    super.key,
    required this.title,
    required this.opacity,
    required this.onChanged,
    this.icon = Icons.opacity_rounded,
    this.onInfo,
  });

  static const Color _gold = Color(0xFF8B7355);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SettingsTileHeader(title: title, onInfo: onInfo),
          const SizedBox(height: 6),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(icon, color: _gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: _gold,
                    thumbColor: _gold,
                    overlayColor: _gold.withValues(alpha: 0.1),
                    inactiveTrackColor: _gold.withValues(alpha: 0.1),
                  ),
                  child: Slider(
                    value: opacity,
                    onChanged: onChanged,
                  ),
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${(opacity * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _gold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MarginImagesTile extends StatelessWidget {
  final MarginImagesState state;
  final Future<void> Function() onDownload;
  final Future<void> Function() onCancelDownload;
  final Future<void> Function() onPauseDownload;
  final Future<void> Function(bool value) onToggleEnabled;
  final VoidCallback? onInfo;

  const MarginImagesTile({
    super.key,
    required this.state,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onPauseDownload,
    required this.onToggleEnabled,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final bool showInlineAction =
        !state.isAvailable && !state.isDownloading && !state.isPaused;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        // Once the pack is available the tile is just a title + switch, so it
        // uses the same tight padding as the other inline toggle settings.
        vertical: state.isAvailable ? 5 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: SettingsTileHeader(
                  title: 'عرض الهوامش',
                  onInfo: onInfo,
                ),
              ),
              if (state.isAvailable) ...[
                const SizedBox(width: 4),
                Switch(
                  activeThumbColor: const Color(0xFF8B7355),
                  value: state.isEnabled,
                  onChanged: onToggleEnabled,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
              if (showInlineAction) const SizedBox(width: 8),
              if (showInlineAction)
                OutlinedButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(
                    Icons.download_rounded,
                    color: Color(0xFF8B7355),
                    size: 16,
                  ),
                  label: const Text(
                    'تحميل',
                    style: TextStyle(
                      color: Color(0xFF8B7355),
                      fontSize: 12.5,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF8B7355)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          if (showInlineAction) const SizedBox(height: 2),
          if (state.isPaused && !state.isDownloading) ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red, size: 22),
                  onPressed: onCancelDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: state.totalBytes > 0 ? state.progress : null,
                      backgroundColor: const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Color(0xFFB0956E)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: TextDirection.rtl,
              children: [
                Text(state.progressLabel,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF888888))),
                Text(state.percentLabel,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8B7355))),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF8B7355), size: 18),
              label: const Text('استئناف التحميل',
                  style: TextStyle(color: Color(0xFF8B7355), fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8B7355)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
          if (state.isDownloading) ...[
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                  onPressed: onCancelDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.pause_circle_filled_rounded, color: Color(0xFF8B7355)),
                  onPressed: onPauseDownload,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: state.totalBytes > 0 ? state.progress : null,
                      backgroundColor: const Color(0xFFE8DCC8).withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B7355)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              textDirection: TextDirection.rtl,
              children: [
                Text(state.progressLabel,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF888888))),
                Text(state.percentLabel,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF8B7355))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet launched from [AudioDownloadTile]: lets the user download the
/// whole Quran ("تحميل الكل") or any individual surah, with live per-surah
/// progress and a search box. All downloads route through
/// [AudioDownloadService] so the main settings tile stays in sync.
class SurahDownloadSheet extends StatefulWidget {
  const SurahDownloadSheet({super.key});

  static const Color _gold = Color(0xFF8B7355);
  static const Color _green = Color(0xFF4B7F3A);

  /// Presents the sheet modally with the app's rounded, RTL styling.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SurahDownloadSheet(),
    );
  }

  @override
  State<SurahDownloadSheet> createState() => _SurahDownloadSheetState();
}

class _SurahDownloadSheetState extends State<SurahDownloadSheet> {
  final AudioDownloadService _service = AudioDownloadService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<SurahDownloadStatus> _statuses = const [];
  String _query = '';

  static const List<String> _arabicDigits = [
    '٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'
  ];

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
    // Keep per-surah rows fresh while a download is running.
    _service.surahState.addListener(_onSurahStateChanged);
    _service.state.addListener(_onSurahStateChanged);
  }

  @override
  void dispose() {
    _service.surahState.removeListener(_onSurahStateChanged);
    _service.state.removeListener(_onSurahStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSurahStateChanged() {
    // When a download finishes (surah goes idle) recompute the cached counts.
    if (_service.surahState.value.surah == 0 && !_service.state.value.isDownloading) {
      _refreshStatuses();
    }
  }

  Future<void> _refreshStatuses() async {
    final statuses = await _service.computeSurahStatuses();
    if (mounted) setState(() => _statuses = statuses);
  }

  String _toArabic(int n) => n
      .toString()
      .split('')
      .map((c) => _arabicDigits[int.parse(c)])
      .join();

  String _ayahLabel(int count) => count == 1
      ? 'آية واحدة'
      : count == 2
          ? 'آيتان'
          : count <= 10
              ? '${_toArabic(count)} آيات'
              : '${_toArabic(count)} آية';

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim();
    if (q.isEmpty) return surahList;
    return surahList.where((s) {
      final name = (s['name'] as String);
      final number = s['number'].toString();
      final arNumber = _toArabic(s['number'] as int);
      return name.contains(q) || number.contains(q) || arNumber.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFBF7EF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                _grabber(),
                _header(context),
                _downloadAllRow(),
                _searchField(),
                const Divider(height: 1, color: Color(0xFFE8DCC8)),
                Expanded(child: _surahList(scrollController)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _grabber() => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFD9CBB2),
          borderRadius: BorderRadius.circular(999),
        ),
      );

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'تحميل الصوتيات',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Color(0xFF888888)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );

  /// Prominent "download all" card, backed by the overall download state.
  Widget _downloadAllRow() {
    return ValueListenableBuilder<AudioDownloadState>(
      valueListenable: _service.state,
      builder: (context, state, _) {
        final bool busy = state.isDownloading;
        final bool anySurahDownloading = _service.surahState.value.surah != 0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EBDB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3D5BB)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFEDE1C9),
                      ),
                      child: Icon(
                        state.isComplete
                            ? Icons.check_rounded
                            : Icons.cloud_download_rounded,
                        color: state.isComplete
                            ? SurahDownloadSheet._green
                            : SurahDownloadSheet._gold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تحميل الكل',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2C2C2C),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            state.isComplete
                                ? 'كل السور محمّلة'
                                : busy
                                    ? state.progressLabel
                                    : 'المصحف كامل للقارئ المختار · نحو ٥٠٠ م.ب',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7A6A55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _downloadAllAction(state, busy, anySurahDownloading),
                  ],
                ),
                if (busy) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: state.progressFraction > 0
                          ? state.progressFraction
                          : null,
                      backgroundColor:
                          const Color(0xFFE8DCC8).withValues(alpha: 0.5),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          SurahDownloadSheet._gold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _downloadAllAction(
      AudioDownloadState state, bool busy, bool anySurahDownloading) {
    if (state.isComplete) {
      return const Icon(Icons.check_circle_rounded,
          color: SurahDownloadSheet._green, size: 22);
    }
    if (busy) {
      return IconButton(
        icon: const Icon(Icons.cancel_rounded, color: Colors.red),
        onPressed: _service.cancelDownload,
        visualDensity: VisualDensity.compact,
      );
    }
    return FilledButton(
      onPressed: anySurahDownloading ? null : () => _service.downloadAll(),
      style: FilledButton.styleFrom(
        backgroundColor: SurahDownloadSheet._gold,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(state.downloadedFiles > 0 ? 'متابعة' : 'تحميل',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v),
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: 'ابحث عن سورة...',
            hintStyle: const TextStyle(color: Color(0xFFAFA48F), fontSize: 14),
            prefixIcon:
                const Icon(Icons.search_rounded, color: Color(0xFFB0956E)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8DCC8)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8DCC8)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: SurahDownloadSheet._gold),
            ),
          ),
        ),
      );

  Widget _surahList(ScrollController controller) {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(
        child: Text('لا توجد نتائج',
            style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
      );
    }
    return ValueListenableBuilder<SurahDownloadState>(
      valueListenable: _service.surahState,
      builder: (context, surahState, _) {
        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) => _surahRow(items[i], surahState),
        );
      },
    );
  }

  Widget _surahRow(Map<String, dynamic> surah, SurahDownloadState surahState) {
    final int number = surah['number'] as int;
    final String name = surah['name'] as String;
    final int ayahs = surah['ayahs'] as int;
    final SurahDownloadStatus? status =
        number - 1 < _statuses.length ? _statuses[number - 1] : null;

    final bool isThisDownloading =
        surahState.isDownloading && surahState.surah == number;
    final bool anyDownloadActive =
        surahState.surah != 0 || _service.state.value.isDownloading;
    final bool isComplete = status?.isComplete ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isComplete
              ? const Color(0xFFCDE3C2)
              : const Color(0xFFEDE4D3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete
                  ? const Color(0xFFE4F0DC)
                  : const Color(0xFFF2EADB),
            ),
            child: Text(
              _toArabic(number),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isComplete
                    ? SurahDownloadSheet._green
                    : SurahDownloadSheet._gold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isThisDownloading
                      ? 'جارٍ التحميل · ${(surahState.progressFraction * 100).round()}%'
                      : _ayahLabel(ayahs),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isThisDownloading
                        ? SurahDownloadSheet._gold
                        : const Color(0xFF9A8F7B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _surahTrailing(number, status, isThisDownloading, anyDownloadActive,
              surahState),
        ],
      ),
    );
  }

  Widget _surahTrailing(
    int number,
    SurahDownloadStatus? status,
    bool isThisDownloading,
    bool anyDownloadActive,
    SurahDownloadState surahState,
  ) {
    if (isThisDownloading) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              value: surahState.progressFraction > 0
                  ? surahState.progressFraction
                  : null,
              backgroundColor: const Color(0xFFEDE4D3),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  SurahDownloadSheet._gold),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 15, color: Color(0xFF888888)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _service.cancelDownload,
            ),
          ],
        ),
      );
    }

    if (status?.isComplete ?? false) {
      return const Icon(Icons.check_circle_rounded,
          color: SurahDownloadSheet._green, size: 24);
    }

    final bool partial = status?.isPartial ?? false;
    return OutlinedButton(
      onPressed:
          anyDownloadActive ? null : () => _service.downloadSurah(number),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: SurahDownloadSheet._gold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 34),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            partial ? Icons.download_for_offline_rounded : Icons.download_rounded,
            size: 15,
            color: SurahDownloadSheet._gold,
          ),
          const SizedBox(width: 4),
          Text(
            partial ? 'إكمال' : 'تحميل',
            style: const TextStyle(
                fontSize: 12, color: SurahDownloadSheet._gold),
          ),
        ],
      ),
    );
  }
}

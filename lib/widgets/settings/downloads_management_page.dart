import 'package:flutter/material.dart';
import '../../services/audio_download_service.dart';
import '../../services/margin_images_service.dart';
import '../../services/high_quality_images_service.dart';
class DownloadsManagementPage extends StatefulWidget {
  final AudioDownloadService audioDownloadService;
  final MarginImagesService marginImagesService;
  final HighQualityImagesService highQualityImagesService;

  const DownloadsManagementPage({super.key,
    required this.audioDownloadService,
    required this.marginImagesService,
    required this.highQualityImagesService,
  });

  @override
  State<DownloadsManagementPage> createState() => _DownloadsManagementPageState();
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
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, textDirection: TextDirection.rtl),
        content: Text(body, textDirection: TextDirection.rtl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
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
      body: 'سيتم حذف جميع ملفات الصوت المحملة من الجهاز. يمكنك إعادة تحميلها لاحقًا. هل تريد المتابعة؟',
    );
    if (!confirmed) return;
    await widget.audioDownloadService.deleteDownloads();
  }

  Future<void> _deleteMarginImages() async {
    final confirmed = await _confirmDelete(
      title: 'حذف عرض الهوامش',
      body: 'سيتم حذف ملفات عرض الهوامش من الجهاز وإيقاف هذا العرض حتى تعيد تنزيله لاحقًا. هل تريد المتابعة؟',
    );
    if (!confirmed) return;
    await widget.marginImagesService.deleteDownloadedImages();
  }

  Future<void> _deleteHighQualityImages() async {
    final confirmed = await _confirmDelete(
      title: 'حذف حزمة الجودة الفائقة',
      body: 'سيتم حذف صور الجودة الفائقة من الجهاز، وسيعود العرض إلى الصور الأساسية. يمكنك إعادة تنزيلها لاحقًا. هل تريد المتابعة؟',
    );
    if (!confirmed) return;
    await widget.highQualityImagesService.deleteDownloadedImages();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioDownloadState>(
      valueListenable: widget.audioDownloadService.state,
      builder: (context, audioState, _) {
        return ValueListenableBuilder<MarginImagesState>(
          valueListenable: widget.marginImagesService.state,
          builder: (context, marginState, _) {
            return ValueListenableBuilder<HighQualityImagesState>(
              valueListenable: widget.highQualityImagesService.state,
              builder: (context, hqState, _) {
            final totalBytes = audioState.installedBytes +
                marginState.installedBytes +
                hqState.installedBytes;

            return Scaffold(
              backgroundColor: const Color(0xFFF6F1E5),
              appBar: AppBar(
                centerTitle: true,
                elevation: 0,
                backgroundColor: const Color(0xFFF6F1E5),
                foregroundColor: const Color(0xFF3D3122),
                title: const Text(
                  'إدارة الملفات المحمّلة',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Color(0xFFF8F3E8),
                          Color(0xFFEADFC7),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0xFF8D6E3F).withValues(alpha: 0.22),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'المساحة المستخدمة الآن',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2F2418),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatBytes(totalBytes),
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF8D6E3F),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'تشمل الملفات الإضافية فقط، ولا تشمل الصور الأساسية المدمجة مع التطبيق.',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Color(0xFF6A5A45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const DownloadedPackageCard(
                    title: 'الصور الأساسية',
                    subtitle: 'مدمجة مع التطبيق وتعمل دائمًا كأساس للقراءة.',
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
                    actionLabel: audioState.downloadedFiles > 0 ? 'حذف' : null,
                    onAction: audioState.downloadedFiles > 0 && !audioState.isDownloading
                        ? _deleteAudioDownloads
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DownloadedPackageCard(
                    title: 'عرض الهوامش',
                    subtitle: marginState.isAvailable
                        ? (marginState.isEnabled
                              ? 'محمل ومفعّل الآن.'
                              : 'محمل على الجهاز ويمكن تفعيله من الإعدادات.')
                        : 'غير محمل حاليًا.',
                    sizeLabel: marginState.isAvailable
                        ? marginState.installedSizeLabel
                        : '0 MB',
                    statusLabel: marginState.isAvailable
                        ? (marginState.isEnabled ? 'مفعّل' : 'محمل')
                        : 'غير محمل',
                    icon: Icons.photo_size_select_large_rounded,
                    actionLabel: marginState.isAvailable ? 'حذف' : null,
                    onAction:
                        marginState.isAvailable && !marginState.isDownloading
                            ? _deleteMarginImages
                            : null,
                  ),
                  const SizedBox(height: 10),
                  DownloadedPackageCard(
                    title: 'حزمة الجودة الفائقة',
                    subtitle: hqState.isAvailable
                        ? 'محمّلة على الجهاز وتُستخدم عند اختيار الجودة الفائقة.'
                        : 'غير محمّلة حاليًا.',
                    sizeLabel: hqState.isAvailable
                        ? hqState.installedSizeLabel
                        : '0 MB',
                    statusLabel: hqState.isAvailable ? 'محمّلة' : 'غير محمّلة',
                    icon: Icons.hd_rounded,
                    actionLabel: hqState.isAvailable ? 'حذف' : null,
                    onAction: hqState.isAvailable && !hqState.isDownloading
                        ? _deleteHighQualityImages
                        : null,
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

  const DownloadedPackageCard({super.key,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EFE6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF8D6E3F).withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.rtl,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: const Color(0xFF5C4522)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2F2418),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Color(0xFF6A5A45),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3E8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF8D6E3F).withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5C4522),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_update_service.dart';

/// «شارك التطبيق». Both store links go out regardless of the sender's
/// platform: the recipients (often a whole group chat) may be on either, plus
/// the web version for anyone reading on a computer.
const String shareAppMessage =
    'المصحف الجامع\n'
    'تطبيق لقراءة القرآن الكريم، مع التلاوة والتفسير.\n\n'
    '📱 لأجهزة أندرويد:\n'
    '${AppUpdateService.playStoreUrl}\n\n'
    '🍏 لأجهزة آيفون:\n'
    '${AppUpdateService.appStoreUrl}\n\n'
    '🌐 من المتصفح:\n'
    'https://www.mushaf-qaloon.com/app/';

/// Opens the system share sheet with [shareAppMessage], anchored to
/// [anchorContext] (iPad presents it as a popover). Where sharing is not
/// available (e.g. a browser without Web Share) the links are copied instead.
Future<void> shareApp(BuildContext anchorContext) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  final messenger = ScaffoldMessenger.maybeOf(anchorContext);
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: shareAppMessage,
        subject: 'المصحف الجامع',
        sharePositionOrigin: origin,
      ),
    );
    if (result.status != ShareResultStatus.unavailable) return;
  } catch (_) {
    // Fall through to the clipboard.
  }
  await Clipboard.setData(const ClipboardData(text: shareAppMessage));
  messenger?.showSnackBar(
    const SnackBar(content: Text('تم نسخ روابط التطبيق، الصقها لمشاركتها')),
  );
}

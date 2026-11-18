import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';

/// App Store id of المصحف الجامع.
const String appStoreId = '6783147903';

/// «قيّم التطبيق» in one tap (owner, 2026-11-12): straight to the store, at
/// the stars. No store lets an app choose the stars for the reader, so this
/// is the shortest way there.
///
/// * iPhone and iPad: the App Store's write-a-review page.
/// * Android: the Play Store listing, where "Rate this app" is.
/// * Web and anything else: the Play Store page in the browser.
///
/// The in-app review prompt is not used here: both stores limit how often it
/// may show and say nothing when it doesn't, so a button that relied on it
/// would sometimes do nothing.
Future<void> rateApp() async {
  final isMobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  if (isMobile) {
    try {
      await InAppReview.instance.openStoreListing(appStoreId: appStoreId);
      return;
    } catch (_) {
      // fall through to the store's web page
    }
  }
  final url = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? 'https://apps.apple.com/app/id$appStoreId?action=write-review'
      : AppUpdateService.playStoreUrl;
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

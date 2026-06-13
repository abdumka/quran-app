import 'package:flutter/material.dart';

const Color settingsPrimaryTextColor = Color(0xFF241A10);
const Color settingsSecondaryTextColor = Color(0xFF4F4131);

const String readingSettingsTitle = 'إعدادات القراءة';
const String autoScrollTitle = 'التمرير التلقائي';
const String autoScrollSubtitle = 'يحرك الصفحات تلقائيًا في وضع التمرير ليساعدك على القراءة المتواصلة.';
const String autoScrollUnavailableNotice = 'التمرير التلقائي يعمل فقط داخل وضع التمرير';
const String tabletOnlyNotice = 'وضع التابلت يظهر فقط في أجهزة التابلت';
const String scrollUnavailableInTabletNotice = 'وضع التمرير غير متاح في وضع التابلت (الصفحتين)';
const String browseModeTitle = 'وضع التصفح';
const String browseModeSubtitle = 'اختر بين تقليب الصفحات صفحة صفحة أو القراءة المستمرة بالتمرير.';
const String pagesLabel = 'صفحات';
const String scrollLabel = 'تمرير';
const String tabletModeTitle = 'وضع التابلت';
const String tabletModeSubtitle = 'يجعل العرض صفحتين في العمودي والأفقي، ويوقف التمرير ليعطي شكل المصحف المفتوح.';

enum SettingsCoachStep {
  browseMode,
  autoScroll,
  marginImages,
  hideBar,
}

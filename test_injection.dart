import 'package:quran_app/services/quran_json_service.dart';

void main() async {
  final pages = await QuranJsonService.loadQuranPages();

  // Check pages 354, 355, 356 for injected ayahs
  final page354 = pages.firstWhere((p) => p.page == 354);
  final page355 = pages.firstWhere((p) => p.page == 355);
  final page356 = pages.firstWhere((p) => p.page == 356);

  print('Page 354 ayahs: ${page354.ayahs.length}');
  print('Page 355 ayahs: ${page355.ayahs.length}');
  print('Page 356 ayahs: ${page356.ayahs.length}');

  // Check if Surah 24 Ayah 36 is in page 354
  final ayah36In354 = page354.ayahs.any((a) => a.surah == 24 && a.ayah == 36);
  print('Ayah 36 in page 354: $ayah36In354');

  // Check if Surah 24 Ayah 42 is in page 355
  final ayah42In355 = page355.ayahs.any((a) => a.surah == 24 && a.ayah == 42);
  print('Ayah 42 in page 355: $ayah42In355');
}
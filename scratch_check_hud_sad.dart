import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('assets/data/output.json');
  final data = json.decode(file.readAsStringSync()) as List<dynamic>;
  final flattened = <dynamic>[];
  for (final item in data) {
    if (item is List) { flattened.addAll(item); } else { flattened.add(item); }
  }

  // Check Surah Hud (11) - first page and last page
  print('=== SURAH HUD (11) ===');
  for (final page in flattened) {
    final pNum = page['page'] as int;
    if (pNum >= 221 && pNum <= 223) {
      print('\n--- PAGE $pNum ---');
      for (final a in (page['ayahs'] as List)) {
        if (a['surah'] == 11) {
          final t = (a['text'] as String);
          final short = t.length > 60 ? '${t.substring(0, 30)}...${t.substring(t.length - 30)}' : t;
          print('  Ayah ${a['ayah']}: $short');
        }
      }
    }
    // Last page of Hud
    if (pNum >= 234 && pNum <= 236) {
      final ayahs = (page['ayahs'] as List).where((a) => a['surah'] == 11).toList();
      if (ayahs.isNotEmpty) {
        print('\n--- PAGE $pNum ---');
        for (final a in ayahs) {
          final t = (a['text'] as String);
          final short = t.length > 60 ? '${t.substring(0, 30)}...${t.substring(t.length - 30)}' : t;
          print('  Ayah ${a['ayah']}: $short');
        }
      }
    }
  }

  // Check Surah Sad (38)
  print('\n\n=== SURAH SAD (38) ===');
  for (final page in flattened) {
    final pNum = page['page'] as int;
    if (pNum == 452 || pNum == 453) {
      print('\n--- PAGE $pNum ---');
      for (final a in (page['ayahs'] as List)) {
        if (a['surah'] == 38) {
          final t = (a['text'] as String);
          final short = t.length > 60 ? '${t.substring(0, 30)}...${t.substring(t.length - 30)}' : t;
          print('  Ayah ${a['ayah']}: $short');
        }
      }
    }
  }
}

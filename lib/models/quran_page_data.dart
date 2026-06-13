class QuranAyahData {
  final int surah;
  final String surahName;
  final int ayah;
  final String text;

  const QuranAyahData({
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.text,
  });

  factory QuranAyahData.fromJson(Map<String, dynamic> json) {
    return QuranAyahData(
      surah: json['surah'] as int,
      surahName: json['surahName'] as String,
      ayah: json['ayah'] as int,
      text: json['text'] as String,
    );
  }
}

class QuranPageData {
  final int page;
  final List<QuranAyahData> ayahs;

  const QuranPageData({
    required this.page,
    required this.ayahs,
  });

  factory QuranPageData.fromJson(Map<String, dynamic> json) {
    return QuranPageData(
      page: json['page'] as int,
      ayahs: (json['ayahs'] as List)
          .map((e) => QuranAyahData.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
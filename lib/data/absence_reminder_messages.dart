// Generated from the owner's choices page (Del/reminder_messages_choices.html,
// 2026-11-12). Ayat are the app's own Qaloon text from assets/data/output.json
// with Madani numbering; the notification shows them through quranDisplayText.

enum AbsenceKind { ayah, hadith, line }

class AbsenceMessage {
  const AbsenceMessage(this.id, this.kind, this.text, this.source);
  final String id;
  final AbsenceKind kind;

  /// Ayat: raw output.json text. Lines: {N} is the day count, {P} the page.
  final String text;

  /// «الفرقان 30», «رواه مسلم»; empty for the app's own lines.
  final String source;
}

/// Every candidate on the choices page.
const List<AbsenceMessage> absenceMessageCandidates = [
  AbsenceMessage('Q1', AbsenceKind.ayah, 'وَقَالَ اَ۬لرَّسُولُ يَٰرَبِّ إِنَّ قَوْمِيَ اَ۪تَّخَذُواْ هَٰذَا اَ۬لْقُرْءَانَ مَهْجُوراٗ', 'الفرقان 30'),
  AbsenceMessage('Q2', AbsenceKind.ayah, 'وَلَقَدْ يَسَّرْنَا اَ۬لْقُرْءَانَ لِلذِّكْرِ فَهَلْ مِن مُّدَّكِرٖ', 'القمر 17'),
  AbsenceMessage('Q3', AbsenceKind.ayah, 'أَفَلَا يَتَدَبَّرُونَ اَ۬لْقُرْءَانَ أَمْ عَلَيٰ قُلُوبٍ أَقْفَالُهَا', 'محمد 25'),
  AbsenceMessage('Q4', AbsenceKind.ayah, 'أَلَمْ يَأْنِ لِلذِينَ ءَامَنُواْ أَن تَخْشَعَ قُلُوبُهُمْ لِذِكْرِ اِ۬للَّهِ وَمَا نَزَلَ مِنَ اَ۬لْحَقِّ', 'الحديد 15'),
  AbsenceMessage('Q5', AbsenceKind.ayah, 'أَلَا بِذِكْرِ اِ۬للَّهِ تَطْمَئِنُّ اُ۬لْقُلُوبُ', 'الرعد 29'),
  AbsenceMessage('Q6', AbsenceKind.ayah, 'كِتَٰبٌ أَنزَلْنَٰهُ إِلَيْكَ مُبَٰرَكٞ لِّيَدَّبَّرُواْ ءَايَٰتِهِۦ وَلِيَتَذَكَّرَ أُوْلُواْ اُ۬لْأَلْبَٰبِ', 'ص 28'),
  AbsenceMessage('Q7', AbsenceKind.ayah, 'إِنَّ هَٰذَا اَ۬لْقُرْءَانَ يَهْدِے لِلتِے هِيَ أَقْوَمُ', 'الإسراء 9'),
  AbsenceMessage('Q8', AbsenceKind.ayah, 'يَٰأَيُّهَا اَ۬لنَّاسُ قَدْ جَآءَتْكُم مَّوْعِظَةٞ مِّن رَّبِّكُمْ وَشِفَآءٞ لِّمَا فِے اِ۬لصُّدُورِ وَهُديٗ وَرَحْمَةٞ لِّلْمُؤْمِنِينَ', 'يونس 57'),
  AbsenceMessage('Q9', AbsenceKind.ayah, 'وَرَتِّلِ اِ۬لْقُرْءَانَ تَرْتِيلاً', 'المزمل 4'),
  AbsenceMessage('Q10', AbsenceKind.ayah, 'وَنُنَزِّلُ مِنَ اَ۬لْقُرْءَانِ مَا هُوَ شِفَآءٞ وَرَحْمَةٞ لِّلْمُؤْمِنِينَ', 'الإسراء 82'),
  AbsenceMessage('Q11', AbsenceKind.ayah, 'اِ۬لذِينَ ءَاتَيْنَٰهُمُ اُ۬لْكِتَٰبَ يَتْلُونَهُۥ حَقَّ تِلَٰوَتِهِۦ', 'البقرة 120'),
  AbsenceMessage('Q12', AbsenceKind.ayah, 'لَوْ أَنزَلْنَا هَٰذَا اَ۬لْقُرْءَانَ عَلَيٰ جَبَلٖ لَّرَأَيْتَهُۥ خَٰشِعاٗ مُّتَصَدِّعاٗ مِّنْ خَشْيَةِ اِ۬للَّهِ', 'الحشر 21'),
  AbsenceMessage('Q13', AbsenceKind.ayah, 'إِنَّ اَ۬لذِينَ يَتْلُونَ كِتَٰبَ اَ۬للَّهِ وَأَقَامُواْ اُ۬لصَّلَوٰةَ وَأَنفَقُواْ مِمَّا رَزَقْنَٰهُمْ سِرّاٗ وَعَلَٰنِيَةٗ يَرْجُونَ تِجَٰرَةٗ لَّن تَبُورَ', 'فاطر 29'),
  AbsenceMessage('Q14', AbsenceKind.ayah, 'وَإِذَا قُرِۓَ اَ۬لْقُرْءَانُ فَاسْتَمِعُواْ لَهُۥ وَأَنصِتُواْ لَعَلَّكُمْ تُرْحَمُونَ', 'الأعراف 204'),
  AbsenceMessage('Q15', AbsenceKind.ayah, 'وَمَنْ أَعْرَضَ عَن ذِكْرِے فَإِنَّ لَهُۥ مَعِيشَةٗ ضَنكاٗ', 'طه 122'),
  AbsenceMessage('H1', AbsenceKind.hadith, 'اقرؤوا القرآن، فإنه يأتي يوم القيامة شفيعًا لأصحابه', 'رواه مسلم'),
  AbsenceMessage('H2', AbsenceKind.hadith, 'تعاهدوا القرآن، فوالذي نفسي بيده لهو أشد تفصّيًا من الإبل في عُقُلها', 'رواه البخاري ومسلم'),
  AbsenceMessage('H3', AbsenceKind.hadith, 'إنما مثل صاحب القرآن كمثل صاحب الإبل المعقّلة، إن عاهد عليها أمسكها، وإن أطلقها ذهبت', 'رواه البخاري ومسلم'),
  AbsenceMessage('H4', AbsenceKind.hadith, 'أحب الأعمال إلى الله تعالى أدومها وإن قلّ', 'رواه مسلم'),
  AbsenceMessage('H5', AbsenceKind.hadith, 'خيركم من تعلّم القرآن وعلّمه', 'رواه البخاري'),
  AbsenceMessage('H6', AbsenceKind.hadith, 'من قرأ حرفًا من كتاب الله فله به حسنة، والحسنة بعشر أمثالها', 'رواه الترمذي'),
  AbsenceMessage('H7', AbsenceKind.hadith, 'الماهر بالقرآن مع السفرة الكرام البررة، والذي يقرأ القرآن ويتتعتع فيه وهو عليه شاق له أجران', 'رواه مسلم'),
  AbsenceMessage('H8', AbsenceKind.hadith, 'يقال لصاحب القرآن: اقرأ وارتق ورتّل كما كنت ترتّل في الدنيا، فإن منزلك عند آخر آية تقرؤها', 'رواه أبو داود والترمذي'),
  AbsenceMessage('H9', AbsenceKind.hadith, 'مثل المؤمن الذي يقرأ القرآن مثل الأترجّة، ريحها طيب وطعمها طيب', 'رواه مسلم'),
  AbsenceMessage('H10', AbsenceKind.hadith, 'إن الله يرفع بهذا الكتاب أقوامًا ويضع به آخرين', 'رواه مسلم'),
  AbsenceMessage('H11', AbsenceKind.hadith, 'من نام عن حزبه أو عن شيء منه، فقرأه فيما بين صلاة الفجر وصلاة الظهر، كُتب له كأنما قرأه من الليل', 'رواه مسلم'),
  AbsenceMessage('G1', AbsenceKind.line, 'مضت {N} أيام منذ آخر ورد، وصفحة واحدة اليوم تكفي للعودة', ''),
  AbsenceMessage('G2', AbsenceKind.line, 'مصحفك في انتظارك، ولو آية واحدة', ''),
  AbsenceMessage('G3', AbsenceKind.line, 'القليل الدائم خير من الكثير المنقطع، افتح صفحة اليوم', ''),
  AbsenceMessage('G4', AbsenceKind.line, 'دقيقتان مع كتاب الله تصنعان فرقًا في يومك', ''),
  AbsenceMessage('G5', AbsenceKind.line, 'تابع وردك من حيث توقفت: صفحة {P}', ''),
  AbsenceMessage('G6', AbsenceKind.line, 'لا تجعل يومك يخلو من القرآن', ''),
];

/// The ones the reminder picks from. The owner's two for now; the rest are
/// added when the owner ticks them on the choices page.
const List<String> absenceMessageIds = ['Q1', 'H1'];

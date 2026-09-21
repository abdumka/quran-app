import 'package:flutter/material.dart';

import '../../services/tasmee_report_store.dart';
import '../../services/tasmee_weak_point_store.dart';

const Color _gold = Color(0xFFD2B97E);
const Color _sheet = Color(0xFF1C1C1E);

String _kindLabel(String kind) => TasmeeError(
      surah: 0,
      ayah: 0,
      wordInAyah: 0,
      expected: '',
      kind: kind,
    ).kindLabel;

/// The "تقوية الحفظ" explanation: what it is, how the mistakes are collected,
/// how many are waiting. Returns true when the user chose to start the
/// drills (only offered once enough mistakes have been collected).
Future<bool> showTasmeeWeakPointsIntro(BuildContext context) async {
  final pool = await TasmeeWeakPointStore.load();
  if (!context.mounted) return false;
  final drills = TasmeeWeakPointStore.plan(pool);
  final ready = pool.length >= TasmeeWeakPointStore.minToStart;
  final missing = TasmeeWeakPointStore.minToStart - pool.length;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      Widget para(String text) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14.5,
                height: 1.6,
              ),
            ),
          );
      return SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تقوية الحفظ',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                  const SizedBox(height: 10),
                  para(
                    'كل خطأ يقع منك أثناء «التسميع» يُحفظ هنا تلقائيًا: كلمة '
                    'أخطأت فيها أو أبدلتها بغيرها، كلمة أو آية تجاوزتها، وكلمة '
                    'طلبت كشفها. لا يلزمك فعل شيء؛ سمِّع كعادتك والتطبيق يجمع.',
                  ),
                  para(
                    'عند بدء التقوية ينقلك التطبيق إلى موضع الخطأ، ويبدأ بك من '
                    'آية أو آيتين قبله، فتقرأ من حفظك حتى تتم الآية التي وقع '
                    'فيها الخطأ. إن قرأت موضع الخطأ صحيحًا حُذف من القائمة، '
                    'وإلا بقي لتعود إليه لاحقًا.',
                  ),
                  para(
                    'تبدأ التقوية بعد جمع ${TasmeeWeakPointStore.minToStart} '
                    'مواضع على الأقل، وتشمل الجولة الواحدة '
                    '${TasmeeWeakPointStore.maxDrillsPerRun} آيات على الأكثر، '
                    'يُقدَّم فيها الأكثر تكرارًا ثم الأقدم.',
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pool.isEmpty
                          ? 'لم تُجمع أخطاء بعد. ابدأ «التسميع» وستظهر هنا.'
                          : ready
                              ? 'المواضع المجموعة: ${pool.length} في '
                                  '${drills.length == TasmeeWeakPointStore.maxDrillsPerRun ? 'أكثر من ' : ''}'
                                  '${drills.length} آيات لهذه الجولة.'
                              : 'المواضع المجموعة: ${pool.length}. بقي '
                                  '$missing لتبدأ التقوية.',
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (pool.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final p in pool.take(8))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '• «${p.expected}» — سورة ${p.surah}، الآية ${p.ayah}'
                          ' (ص ${p.page}) — ${_kindLabel(p.kind)}'
                          '${p.count > 1 ? ' ×${p.count}' : ''}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    if (pool.length > 8)
                      Text(
                        '… و${pool.length - 8} مواضع أخرى',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor:
                                Colors.white.withValues(alpha: 0.12),
                            disabledForegroundColor:
                                Colors.white.withValues(alpha: 0.4),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: ready
                              ? () => Navigator.of(sheetContext).pop(true)
                              : null,
                          child: Text(
                            ready ? 'ابدأ التقوية' : 'تبدأ بعد جمع أخطاء كافية',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Tajawal',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text(
                          'إغلاق',
                          style: TextStyle(color: _gold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// What the user chose after a drill ended.
enum TasmeeDrillNext { next, stop }

/// The outcome of one drill, with the way on: the next drill or the end.
Future<TasmeeDrillNext> showTasmeeDrillResult(
  BuildContext context,
  TasmeeDrillResult result, {
  required bool hasNext,
}) async {
  final choice = await showModalBottomSheet<TasmeeDrillNext>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: _sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final allPassed = result.failed.isEmpty;
      return SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      allPassed
                          ? Icons.check_circle_rounded
                          : Icons.replay_circle_filled_rounded,
                      color: allPassed ? const Color(0xFF7BC67E) : _gold,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        allPassed
                            ? 'أحسنت — قرأتها صحيحة'
                            : 'ما زال هذا الموضع يحتاج مراجعة',
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ),
                    Text(
                      '${result.drill.index} / ${result.drill.total}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final p in result.passed)
                  Text(
                    '✓ «${p.expected}» — حُذفت من قائمة الأخطاء',
                    style: const TextStyle(
                      color: Color(0xFF9AD69C),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                for (final p in result.failed)
                  Text(
                    '✗ «${p.expected}» — بقيت في القائمة',
                    style: const TextStyle(
                      color: Color(0xFFF0A59A),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (hasNext)
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.of(sheetContext)
                              .pop(TasmeeDrillNext.next),
                          child: const Text(
                            'الموضع التالي',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Tajawal',
                            ),
                          ),
                        ),
                      ),
                    if (hasNext) const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gold,
                          side: const BorderSide(color: _gold),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.of(sheetContext)
                            .pop(TasmeeDrillNext.stop),
                        child: Text(
                          hasNext ? 'إنهاء' : 'تم',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return choice ?? TasmeeDrillNext.stop;
}

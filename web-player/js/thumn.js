function cmp(s1, a1, s2, a2) {
  return s1 !== s2 ? s1 - s2 : a1 - a2;
}

/** Last thumn whose start is at-or-before (surah, ayah). thumns must be
 * sorted ascending by number (== ascending by start position). */
export function findThumnFor(thumns, surah, ayah) {
  let found = null;
  for (const t of thumns) {
    if (cmp(t.startSurah, t.startAyah, surah, ayah) <= 0) found = t;
    else break;
  }
  return found;
}

/** Ordered (surah, ayah) pairs spanning a thumn, crossing surah boundaries
 * as needed (a thumn can cover multiple whole surahs). */
export function ayahsInThumn(surahMap, thumn) {
  const result = [];
  let s = thumn.startSurah;
  let a = thumn.startAyah;
  while (s <= 114) {
    if (thumn.endSurah != null && s === thumn.endSurah && a === thumn.endAyah) break;
    const surahData = surahMap.get(s);
    if (!surahData) break;
    if (a > surahData.ayahCount) {
      s += 1;
      a = 1;
      continue;
    }
    result.push({ surah: s, ayah: a });
    a += 1;
  }
  return result;
}

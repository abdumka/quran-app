/** Resolves a displayed (surah, ayah) to the audio clip(s) to play.
 *
 * Two storage shapes are supported and the caller does not care which:
 *
 *  - PER-AYAH mirrors (husary / naihi / qaniwah / hudaifi / doukali /
 *    abusenainah): a sparse override map over a `SSSAAA` default. A clip is a
 *    whole file, so `start`/`end` are null.
 *  - TIMED mirrors (alqryw): one `SSS.mp3` per surah plus a table of ayah spans.
 *    A clip is a slice of that file.
 *
 * Returning the same {stem, start, end} shape for both is what lets the player
 * engine — and every repeat mode built on it — stay ignorant of the difference.
 */

const pad3 = (n) => String(n).padStart(3, '0');

export function resolveAyah(overrides, surah, ayah, timings) {
  if (timings) {
    const table = timings[surah] || {};
    const span = table[ayah];
    // No span means this ayah has no audio of its own — the sheikh recites it
    // inside a neighbour's breath, or the source never published it. Same
    // signal as an empty file list: the engine advances past it.
    if (!span) return { clips: [], coveredBy: null };

    const clip = (s) => ({ stem: pad3(surah), start: s[0] / 1000, end: s[1] / 1000 });
    // Standard is a merged basmala: it lives inside ayah 1's own span, every
    // surah except At-Tawba (which has none), so the fallthrough below already
    // covers it and the build pipeline never emits a "0" key. This branch is
    // dead under that standard — kept only so a hand-edited or future-format
    // timings file that does carry a separate basmala span still plays it.
    if (ayah === 1 && table['0']) {
      return { clips: [clip(table['0']), clip(span)], coveredBy: null };
    }
    return { clips: [clip(span)], coveredBy: null };
  }

  const key = `${surah}-${ayah}`;
  const o = overrides[key];
  const stems = o ? o.f : [`${pad3(surah)}${pad3(ayah)}`];
  return {
    clips: stems.map((stem) => ({ stem, start: null, end: null })),
    coveredBy: o ? o.cov : null,
  };
}

export function fileUrl(baseUrl, stem) {
  return `${baseUrl}${stem}.mp3`;
}

/** Resolves a displayed (surah, ayah) to the file stem(s) to play, using a
 * sparse per-reciter override map with a `SSSAAA` default fallback. Scheme
 * (direct/native/covered) only matters to the build script that produced the
 * override map — this lookup is reciter-agnostic. */
export function resolveAyah(overrides, surah, ayah) {
  const key = `${surah}-${ayah}`;
  const o = overrides[key];
  if (o) return { files: o.f, coveredBy: o.cov };
  const stem = `${String(surah).padStart(3, '0')}${String(ayah).padStart(3, '0')}`;
  return { files: [stem], coveredBy: null };
}

export function fileUrl(baseUrl, stem) {
  return `${baseUrl}${stem}.mp3`;
}

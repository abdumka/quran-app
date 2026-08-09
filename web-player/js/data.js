const cache = {};

async function fetchJson(path) {
  if (cache[path]) return cache[path];
  const promise = fetch(path).then((res) => {
    if (!res.ok) throw new Error(`Failed to fetch ${path}: ${res.status}`);
    return res.json();
  });
  cache[path] = promise;
  return promise;
}

export function getReciters() {
  return fetchJson('data/reciters.json').then((d) => d.reciters);
}

export async function getReciter(id) {
  const list = await getReciters();
  return list.find((r) => r.id === id) || null;
}

export function getQuranText() {
  return fetchJson('data/quran_text.json').then((d) => d.surahs);
}

export async function getSurah(number) {
  const surahs = await getQuranText();
  return surahs.find((s) => s.number === number) || null;
}

export function getThumns() {
  return fetchJson('data/thumn_index.json').then((d) => d.thumns);
}

export function getOverrides(reciter) {
  return fetchJson('data/' + reciter.overridesFile).then((d) => d.overrides);
}

export function audioBaseUrl(reciter) {
  return `https://audio.mushaf-qaloon.com/${reciter.folder}/`;
}

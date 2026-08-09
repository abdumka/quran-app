import { getReciter, getQuranText } from './data.js';

const params = new URLSearchParams(location.search);
const reciterId = params.get('r');

const grid = document.getElementById('grid');
const reciterNameEl = document.getElementById('reciterName');
const reciterRiwayaEl = document.getElementById('reciterRiwaya');
const crumbEl = document.getElementById('crumbName');

async function main() {
  const [reciter, surahs] = await Promise.all([getReciter(reciterId), getQuranText()]);
  if (!reciter) {
    reciterNameEl.textContent = 'شيخ غير معروف';
    return;
  }

  reciterNameEl.textContent = reciter.name;
  reciterRiwayaEl.textContent = reciter.reviewNote
    ? `${reciter.riwaya} — ${reciter.reviewNote}`
    : reciter.riwaya;
  crumbEl.textContent = reciter.name;
  document.title = `السور — ${reciter.name}`;

  grid.innerHTML = '';
  for (const s of surahs) {
    const a = document.createElement('a');
    a.className = 'surah-tile';
    a.href = `player.html?r=${encodeURIComponent(reciter.id)}&s=${s.number}`;
    a.innerHTML = `<span class="num">${s.number}</span><span class="name">${s.name}</span><span class="count">${s.ayahCount} آية</span>`;
    grid.appendChild(a);
  }
}

main();

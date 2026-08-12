import { getReciters } from './data.js';

const grid = document.getElementById('grid');

getReciters().then((reciters) => {
  grid.innerHTML = '';
  for (const r of reciters) {
    const a = document.createElement('a');
    a.className = 'reciter-card';
    a.href = `surahs.html?r=${encodeURIComponent(r.id)}`;
    a.innerHTML =
      `<div class="name">${r.shortName || r.name}</div>` +
      `<div class="riwaya">${r.riwaya}</div>` +
      (r.reviewNote ? `<div class="review-badge">${r.reviewNote}</div>` : '');
    grid.appendChild(a);
  }
});

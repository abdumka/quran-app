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

// "ختمات تحت المراجعة" — a khatma appears here purely by having a reviewUrl in
// reciters.json (set from build_web_player_data.py), so adding the next one is
// a data change, not a code change. Hidden entirely when none are under review.
getReciters().then((reciters) => {
  const section = document.getElementById('reviewSection');
  const links = document.getElementById('reviewLinks');
  if (!section || !links) return;
  const underReview = reciters.filter((r) => r.reviewUrl);
  if (!underReview.length) return;
  links.innerHTML = '';
  for (const r of underReview) {
    const a = document.createElement('a');
    a.className = 'btn secondary';
    a.href = r.reviewUrl;
    a.textContent = `مراجعة مصحف ${r.shortName || r.name}`;
    links.appendChild(a);
  }
  section.hidden = false;
});

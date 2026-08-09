import { getReciter, getOverrides, getQuranText, getThumns, audioBaseUrl } from './data.js';
import { resolveAyah } from './audio-resolver.js';
import { PlayerEngine } from './player-engine.js';

const params = new URLSearchParams(location.search);
const reciterId = params.get('r');
const surahNumber = Number(params.get('s'));

const el = {
  reciterName: document.getElementById('reciterName'),
  reciterNote: document.getElementById('reciterNote'),
  surahsLink: document.getElementById('surahsLink'),
  stitle: document.getElementById('stitle'),
  list: document.getElementById('list'),
  playAll: document.getElementById('playAll'),
  stop: document.getElementById('stop'),
  speed: document.getElementById('speed'),
  follow: document.getElementById('follow'),
  status: document.getElementById('status'),
  ayahCycle: document.getElementById('ayahCycle'),
  surahCycle: document.getElementById('surahCycle'),
  thumnCycle: document.getElementById('thumnCycle'),
  rangeCycle: document.getElementById('rangeCycle'),
  fromAyah: document.getElementById('fromAyah'),
  toAyah: document.getElementById('toAyah'),
  prevSurah: document.getElementById('prevSurah'),
  nextSurah: document.getElementById('nextSurah'),
};

// off -> 2x -> 3x -> infinite -> off. Mirrors the mobile app's own repeat-cycle
// convention (1x is skipped — indistinguishable from off).
const REPEAT_STEPS = [
  { mode: 'off', label: 'إيقاف' },
  { mode: 'count', count: 2, label: '٢×' },
  { mode: 'count', count: 3, label: '٣×' },
  { mode: 'infinite', label: '∞' },
];

let ayahStepIdx = 0;
const structuralStepIdx = { surah: 0, thumn: 0, range: 0 };
const structuralButtons = {};

function resetStructuralButton(kind) {
  structuralStepIdx[kind] = 0;
  structuralButtons[kind].textContent = 'إيقاف';
  structuralButtons[kind].classList.remove('active-mode');
}

function clearOtherStructural(owner) {
  for (const kind of ['surah', 'thumn', 'range']) {
    if (kind !== owner) resetStructuralButton(kind);
  }
}

async function main() {
  const [reciter, surahs, thumns] = await Promise.all([
    getReciter(reciterId),
    getQuranText(),
    getThumns(),
  ]);
  if (!reciter) {
    el.reciterName.textContent = 'شيخ غير معروف';
    return;
  }
  const overrides = await getOverrides(reciter);
  const surah = surahs.find((s) => s.number === surahNumber);
  if (!surah) {
    el.reciterName.textContent = reciter.name;
    el.stitle.textContent = 'سورة غير موجودة';
    return;
  }

  structuralButtons.surah = el.surahCycle;
  structuralButtons.thumn = el.thumnCycle;
  structuralButtons.range = el.rangeCycle;

  el.reciterName.textContent = reciter.name;
  if (reciter.reviewNote) el.reciterNote.textContent = reciter.reviewNote;
  el.surahsLink.href = `surahs.html?r=${encodeURIComponent(reciter.id)}`;
  el.stitle.textContent = `سورة ${surah.number} — ${surah.name}`;
  document.title = `${surah.name} — ${reciter.name}`;

  if (surah.number > 1) {
    el.prevSurah.href = `player.html?r=${encodeURIComponent(reciter.id)}&s=${surah.number - 1}`;
  } else {
    el.prevSurah.style.visibility = 'hidden';
  }
  if (surah.number < 114) {
    el.nextSurah.href = `player.html?r=${encodeURIComponent(reciter.id)}&s=${surah.number + 1}`;
  } else {
    el.nextSurah.style.visibility = 'hidden';
  }

  for (let a = 1; a <= surah.ayahCount; a++) {
    const o1 = document.createElement('option');
    o1.value = String(a);
    o1.textContent = String(a);
    el.fromAyah.appendChild(o1);
    const o2 = document.createElement('option');
    o2.value = String(a);
    o2.textContent = String(a);
    el.toAyah.appendChild(o2);
  }
  el.toAyah.value = String(surah.ayahCount);

  const rows = new Map();
  surah.ayahs.forEach((text, i) => {
    const ayahNum = i + 1;
    const { coveredBy } = resolveAyah(overrides, surah.number, ayahNum);
    const row = document.createElement('div');
    row.className = 'ayah';
    row.dataset.ayah = String(ayahNum);
    let html = `<div class="num">${ayahNum}</div><div class="txt">${text}`;
    if (coveredBy) {
      const coveredAyah = coveredBy.split('-')[1];
      html += `<span class="covered">◂ تُتلى ضمن الآية ${coveredAyah}</span>`;
    }
    html += '</div>';
    row.innerHTML = html;
    row.onclick = () => onAyahClick(ayahNum);
    el.list.appendChild(row);
    rows.set(ayahNum, row);
  });

  const engine = new PlayerEngine({
    pageSurah: surah.number,
    surahs,
    overrides,
    baseUrl: audioBaseUrl(reciter),
    thumns,
    onAyahChange: ({ surah: s, ayah: a }) => {
      for (const r of rows.values()) r.classList.remove('playing');
      if (s === surah.number) {
        const row = rows.get(a);
        if (row) {
          row.classList.add('playing');
          if (el.follow.checked) row.scrollIntoView({ block: 'center', behavior: 'smooth' });
        }
        el.status.textContent = `${a} / ${surah.ayahCount}`;
      } else {
        el.status.textContent = `يُتلى الآن ضمن آية أخرى (${s}:${a})`;
      }
    },
    onStop: () => {
      for (const r of rows.values()) r.classList.remove('playing');
      el.status.textContent = '';
    },
    onError: () => {},
  });

  engine.setSpeed(parseFloat(el.speed.value));

  function onAyahClick(ayahNum) {
    const { coveredBy } = resolveAyah(overrides, surah.number, ayahNum);
    if (coveredBy) {
      const [cs, ca] = coveredBy.split('-').map(Number);
      engine.playFrom(cs, ca);
    } else {
      engine.playFrom(surah.number, ayahNum);
    }
  }

  el.playAll.onclick = () => engine.playFrom(surah.number, 1);
  el.stop.onclick = () => engine.stop();
  el.speed.onchange = () => engine.setSpeed(parseFloat(el.speed.value));

  el.ayahCycle.onclick = () => {
    ayahStepIdx = (ayahStepIdx + 1) % REPEAT_STEPS.length;
    const step = REPEAT_STEPS[ayahStepIdx];
    el.ayahCycle.textContent = step.label;
    el.ayahCycle.classList.toggle('active-mode', step.mode !== 'off');
    engine.setAyahRepeat(step.mode, step.count);
  };

  el.surahCycle.onclick = () => {
    structuralStepIdx.surah = (structuralStepIdx.surah + 1) % REPEAT_STEPS.length;
    const step = REPEAT_STEPS[structuralStepIdx.surah];
    el.surahCycle.textContent = step.label;
    el.surahCycle.classList.toggle('active-mode', step.mode !== 'off');
    if (step.mode === 'off') {
      engine.disengageStructural();
    } else {
      clearOtherStructural('surah');
      engine.engageSurah(surah.number, step.mode, step.count);
    }
  };

  el.thumnCycle.onclick = () => {
    structuralStepIdx.thumn = (structuralStepIdx.thumn + 1) % REPEAT_STEPS.length;
    const step = REPEAT_STEPS[structuralStepIdx.thumn];
    if (step.mode === 'off') {
      el.thumnCycle.textContent = step.label;
      el.thumnCycle.classList.remove('active-mode');
      engine.disengageStructural();
      return;
    }
    const anchor = engine.currentPos() || { surah: surah.number, ayah: 1 };
    const ok = engine.engageThumnAt(anchor.surah, anchor.ayah, step.mode, step.count);
    if (!ok) {
      resetStructuralButton('thumn');
      return;
    }
    clearOtherStructural('thumn');
    el.thumnCycle.textContent = step.label;
    el.thumnCycle.classList.add('active-mode');
  };

  function reEngageRangeIfActive() {
    const step = REPEAT_STEPS[structuralStepIdx.range];
    if (step.mode !== 'off') {
      const from = Number(el.fromAyah.value);
      const to = Number(el.toAyah.value);
      engine.engageRange(surah.number, Math.min(from, to), Math.max(from, to), step.mode, step.count);
    }
  }
  el.fromAyah.onchange = reEngageRangeIfActive;
  el.toAyah.onchange = reEngageRangeIfActive;

  el.rangeCycle.onclick = () => {
    structuralStepIdx.range = (structuralStepIdx.range + 1) % REPEAT_STEPS.length;
    const step = REPEAT_STEPS[structuralStepIdx.range];
    el.rangeCycle.textContent = step.label;
    el.rangeCycle.classList.toggle('active-mode', step.mode !== 'off');
    if (step.mode === 'off') {
      engine.disengageStructural();
    } else {
      const from = Number(el.fromAyah.value);
      const to = Number(el.toAyah.value);
      clearOtherStructural('range');
      engine.engageRange(surah.number, Math.min(from, to), Math.max(from, to), step.mode, step.count);
    }
  };
}

main();
